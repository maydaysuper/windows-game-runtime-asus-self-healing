#requires -version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Action,
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [Parameter(Mandatory=$true)][string]$EnginePath,
    [string]$Group='',
    [string]$ExeName='',
    [string]$SinceUtc='',
    [switch]$Force
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

function Write-BridgeResult([bool]$Success,[object]$Payload,[string]$Error='') {
    $o=[PSCustomObject]@{
        SchemaVersion=2
        Action=$Action
        Success=$Success
        Error=$Error
        CheckedAt=(Get-Date).ToString('o')
        Payload=$Payload
    }
    $tmp=$ResultPath+'.tmp'
    $o|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $ResultPath -Force
}

function Sync-BrokerFiles {
    $srcRoot=Split-Path -Parent $EnginePath
    $work=Join-Path $env:LOCALAPPDATA 'WindowsGameRuntimeASUSSelfHealing'
    New-Item -ItemType Directory -Force -Path $work|Out-Null
    foreach($n in @('RepairCenter.ps1','ElevatedBroker.ps1','BuildInfo.psd1','Bootstrap.ps1','AtomicPolicyExecutor.ps1','RecipeCatalog.psd1','GpuSafeRepair.ps1')){
        $src=Join-Path $srcRoot $n
        $dst=Join-Path $work $n
        if(-not(Test-Path -LiteralPath $src)){throw "Missing backend file: $src"}
        $copy=$true
        if(Test-Path -LiteralPath $dst){
            try{$copy=((Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash)}catch{}
        }
        if($copy){Copy-Item -LiteralPath $src -Destination $dst -Force}
    }
    return $work
}

try {
    # Crash/GPU telemetry is read-only and intentionally bypasses RepairCenter import.
    # This gives the WinUI crash page an independent async lane and prevents it from
    # contending with the hash-locked legacy adapter extraction performed by the engine.
    if($Action -eq 'CRASH_DELTA') {
        $srcRoot=Split-Path -Parent $EnginePath
        $reader=Join-Path $srcRoot 'IncrementalEventReader.ps1'
        $buildPath=Join-Path $srcRoot 'BuildInfo.psd1'
        if(-not(Test-Path -LiteralPath $reader)){throw "Incremental event reader missing: $reader"}
        if(-not(Test-Path -LiteralPath $buildPath)){throw "BuildInfo missing: $buildPath"}
        $build=Import-PowerShellDataFile -LiteralPath $buildPath
        $readerHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $reader -ErrorAction Stop).Hash.ToLowerInvariant()
        if($readerHash -ne [string]$build.EventReaderSHA256){throw 'IncrementalEventReader SHA256 mismatch vs BuildInfo'}
        . $reader
        $since=(Get-Date).AddDays(-7)
        if($SinceUtc){
            try{$since=[datetime]::Parse($SinceUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}catch{throw 'Invalid SinceUtc'}
        }
        # Capture a scan upper-bound before querying. On success the GUI advances its cursor to
        # this watermark (with a small overlap on the next run), even when zero events are found.
        # This prevents an idle machine from repeatedly rescanning the original 7-day seed window.
        $scanStarted=[DateTime]::UtcNow
        $events=@(Get-IncrementalCrashEvents $since 500)
        $payload=[PSCustomObject]@{
            SinceUtc=$since.ToUniversalTime().ToString('o')
            ScanStartedUtc=$scanStarted.ToString('o')
            ScanCompletedUtc=[DateTime]::UtcNow.ToString('o')
            Events=$events
            GPU=@(Get-IncrementalGPUHealthRows)
            WER=@(Get-IncrementalWerStatus)
        }
        Write-BridgeResult $true $payload
        exit 0
    }

    if($Action -eq 'GPU_DIAGNOSTICS') {
        $srcRoot=Split-Path -Parent $EnginePath
        $reader=Join-Path $srcRoot 'GpuDiagnosticsReader.ps1'
        $buildPath=Join-Path $srcRoot 'BuildInfo.psd1'
        if(-not(Test-Path -LiteralPath $reader)){throw "GPU diagnostics reader missing: $reader"}
        if(-not(Test-Path -LiteralPath $buildPath)){throw "BuildInfo missing: $buildPath"}
        $build=Import-PowerShellDataFile -LiteralPath $buildPath
        $readerHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $reader -ErrorAction Stop).Hash.ToLowerInvariant()
        if($readerHash -ne [string]$build.GpuDiagnosticsReaderSHA256){throw 'GpuDiagnosticsReader SHA256 mismatch vs BuildInfo'}
        . $reader
        $since=(Get-Date).AddDays(-7)
        if($SinceUtc){
            try{$since=[datetime]::Parse($SinceUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}catch{throw 'Invalid SinceUtc'}
        }
        Write-BridgeResult $true (Get-WgrGpuDiagnosticsSnapshot $since)
        exit 0
    }

    if(-not(Test-Path -LiteralPath $EnginePath)){throw "Engine missing: $EnginePath"}
    . $EnginePath -LibraryMode
    $work=Sync-BrokerFiles

    switch -Wildcard ($Action) {
        'DASHBOARD' {
            $snap=Get-SystemSnapshot -Force:$Force
            $pre=Get-EnvironmentPreflight 'Repair' ''
            $arch=Get-ArchitectureSecuritySummary
            $payload=[PSCustomObject]@{
                Version=$AppVersion
                BuildId=$BuildId
                Health=[string]$snap.Health
                HealthText=[string]$snap.HealthText
                RecommendedGroup=[string]$snap.RecommendedGroup
                ActiveErrorCodes=@($snap.ActiveErrorCodes)
                ActiveArmouryCount=@($snap.ActiveArmoury).Count
                ActiveMsiCount=@($snap.ActiveMsi).Count
                PendingReboot=@($snap.PendingReboot)
                ArmouryCrateNeedsRepair=[bool]$(if($snap.ArmouryCrate){$snap.ArmouryCrate.NeedsRepair}else{$false})
                ArmouryCrateIssue=[string]$(if($snap.ArmouryCrate){$snap.ArmouryCrate.Detail}else{''})
                ArmouryCrateChassis=[string]$(if($snap.ArmouryCrate){$snap.ArmouryCrate.Chassis}else{''})
                PendingRepair=$(if($snap.Pending){[string]$snap.Pending.Label}else{''})
                Components=@($snap.Rows|Select-Object Key,Name,Installed,Target,Runtime,ErrorCode,Status,Detail,Group)
                Preflight=@($pre.Rows|Select-Object Name,Status,Detail,Blocking)
                BrokerValid=[bool]$arch.BrokerValid
                BuildConsistency=[string]$arch.BuildConsistency
            }
            Write-BridgeResult $true $payload
        }
        'PREFLIGHT' {
            $mode=if($Group -eq 'RUNTIME'){'Runtime'}elseif($Group){'ASUS'}else{'Repair'}
            $pf=Get-EnvironmentPreflight $mode $(if($Group -in @('PV','HOLTEK','ENE')){$Group}else{''})
            Write-BridgeResult $true ([PSCustomObject]@{Rows=@($pf.Rows|Select-Object Name,Status,Detail,Blocking)})
        }
        'CRASH' {
            $payload=[PSCustomObject]@{
                Events=@(Get-GameCrashTelemetry 7 120)
                GPU=@(Get-GPUHealthRows)
                WER=@(Get-WerLocalDumpStatus)
            }
            Write-BridgeResult $true $payload
        }
        'IDENTITY' {
            $snap=Get-SystemSnapshot
            $fps=@()
            foreach($d in $Known){
                try{$fps += Get-ComponentFingerprint $d}catch{$fps += [PSCustomObject]@{Key=$d.Key;Error=$_.Exception.Message}}
            }
            Write-BridgeResult $true ([PSCustomObject]@{Incidents=@($snap.CorrelatedIncidents);Fingerprints=$fps})
        }
        'ARCH' {
            Write-BridgeResult $true ([PSCustomObject]@{Summary=(Get-ArchitectureSecuritySummary);RulePacks=@(Get-RulePackStatus);Build=(Get-BuildConsistency)})
        }
        'DEEP' {
            Write-BridgeResult $true ([PSCustomObject]@{Rows=@(Invoke-GamePlatformDeepTest)})
        }
        'TRANSACTIONS' {
            $list=@(Get-RecentTransactions 50)
            Write-BridgeResult $true ([PSCustomObject]@{Transactions=@($list|Select-Object TransactionId,Type,Group,Label,State,StartedAt,UpdatedAt,LastDetail);Open=(Get-LatestOpenTransaction)})
        }
        'RUNTIME_ONLINE' {
            $online=Update-RuntimeOnlineInfo -Force:$Force
            $snap=Get-SystemSnapshot -Force
            $elig=Get-RuntimeRepairEligibility $snap
            Write-BridgeResult $true ([PSCustomObject]@{Rows=@($snap.Rows|Where-Object{$_.Group -eq 'RUNTIME'}|Select-Object Key,Name,Installed,Target,Runtime,ErrorCode,Status,Detail,Group);Eligibility=$elig;OfficialVersion=[string]$script:RuntimeOfficialVC14;Compared=[bool]$online.Success;Message=[string]$script:RuntimeStatusMessage})
        }
        'PLAN_RUNTIME' {
            if(-not (Test-RuntimeOnlineInfoFresh 30) -or -not $script:RuntimeOfficialVC14){[void](Update-RuntimeOnlineInfo)}
            $snap=Get-SystemSnapshot -Force
            $plan=New-RepairPlan 'RUNTIME' '' $snap
            Write-BridgeResult $true ([PSCustomObject]@{Plan=$plan;Text=(Format-RepairPlan $plan)})
        }
        'PLAN_ASUS' {
            $snap=Get-SystemSnapshot -Force
            $crate=$snap.ArmouryCrate
            $has501=@($snap.ActiveErrorCodes) -contains '501' -or @($snap.ActiveErrorCodes) -contains '601'
            if($crate -and $has501 -and (-not [bool]$crate.Installed -or [bool]$crate.NeedsRepair)){
                try{$crate.NeedsRepair=$true;if(-not [string]$crate.Issue){$crate.Issue='安装奥创时出现 501 错误。';$crate.Detail=$crate.Issue}}catch{}
            }
            $g=$Group
            if(-not $g){$g=[string]$snap.RecommendedGroup}
            $plan=$null
            if($g -in @('PV','HOLTEK','ENE')){$plan=New-RepairPlan 'ASUS' $g $snap}
            $launch=[bool]($crate -and $crate.NeedsRepair)
            if($launch){
                $text=@('结论：可以全自动修复。')
                if($has501 -or ([string]$crate.Issue -match '501')){$text += '安装奥创时出现 501 错误。会清安装残留、检查 C++、拉起奥创服务，再尝试打开。'}
                else{$text += [string]$crate.Detail}
                $text += '笔记本和台式机都按这台电脑现有的奥创 / 奥创 Lite 来修。不会卸显卡驱动，也不会套未知新版本的旧方案。'
                if($plan -and [bool]$plan.Eligible){$text += '如果还有已验证的灯效更新错误，会在同一轮里一起修。'}
                Write-BridgeResult $true ([PSCustomObject]@{Plan=[PSCustomObject]@{Eligible=$true;PlanState='ELIGIBLE';Decision=($text -join ' ')};Text=($text -join ' ');RecommendedGroup=$(if($g){$g}else{'ASUS_CRATE'});LaunchEligible=$true;HalEligible=[bool]($plan -and $plan.Eligible)})
            }elseif($plan){
                Write-BridgeResult $true ([PSCustomObject]@{Plan=$plan;Text=(Format-RepairPlan $plan);RecommendedGroup=$g;LaunchEligible=$false;HalEligible=[bool]$plan.Eligible})
            }else{
                Write-BridgeResult $true ([PSCustomObject]@{Plan=$null;Text='结论：不必修复。现在没有 501、打不开或可自动修的奥创更新错误。';RecommendedGroup='';LaunchEligible=$false;HalEligible=$false})
            }
        }
        'VERIFY' {
            $path=Run-FinalVerification
            # Run-FinalVerification may transition the open transaction into Observing or
            # NeedsAttention. Return that state so the WinUI workflow does not incorrectly
            # label a just-started observation window as fully verified.
            Write-BridgeResult $true ([PSCustomObject]@{Path=$path;Open=(Get-LatestOpenTransaction)})
        }
        'EXPORT_REPORT' {
            $path=Export-DiagnosticReport
            Write-BridgeResult $true ([PSCustomObject]@{Path=$path})
        }
        'BROKER_PREPARE_*' {
            $brokerAction=$Action.Substring('BROKER_PREPARE_'.Length)
            $allowed=@('ASUS_REPAIR','RUNTIME_REPAIR','CONTINUE','WER_ENABLE','WER_DISABLE','GPU_SAFE_REPAIR','ASUS_CRATE_REPAIR')
            if($allowed -notcontains $brokerAction){throw "Invalid broker action: $brokerAction"}
            if($brokerAction -eq 'ASUS_REPAIR' -and $Group -notin @('PV','HOLTEK','ENE')){throw 'ASUS_REPAIR requires Group PV/HOLTEK/ENE'}
            if($brokerAction -in @('WER_ENABLE','WER_DISABLE') -and $ExeName -notmatch '^[A-Za-z0-9_.-]+\.exe$'){throw 'WER action requires a safe exe name'}

            $broker=Join-Path $work 'ElevatedBroker.ps1'
            $bi=Join-Path $work 'BuildInfo.psd1'
            $build=Import-PowerShellDataFile -LiteralPath $bi
            $stableEngine=Join-Path $work 'RepairCenter.ps1'
            $engineHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $stableEngine).Hash.ToLowerInvariant()
            if($engineHash -ne [string]$build.EngineSHA256){throw 'Engine SHA256 mismatch vs BuildInfo'}
            $brokerHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $broker).Hash.ToLowerInvariant()
            if($brokerHash -ne [string]$build.BrokerSHA256){throw 'Broker SHA256 mismatch vs BuildInfo'}
            $buildInfoHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $bi).Hash.ToLowerInvariant()

            $reqRoot=Join-Path $work 'BrokerRequests'
            New-Item -ItemType Directory -Force -Path $reqRoot|Out-Null
            $id='BR-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+([guid]::NewGuid().ToString('N').Substring(0,8))
            $reqPath=Join-Path $reqRoot ($id+'.request.json')
            $respPath=Join-Path $reqRoot ($id+'.response.json')
            $obj=[PSCustomObject]@{SchemaVersion=2;RequestId=$id;CreatedAt=(Get-Date).ToString('o');Action=$brokerAction;Group=$Group;ExeName=$ExeName;ResponsePath=$respPath;EngineVersion=$AppVersion;BuildId=$BuildId;EngineSHA256=$engineHash;BuildInfoSHA256=$buildInfoHash}
            $tmp=$reqPath+'.tmp';$obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $reqPath -Force
            Write-BridgeResult $true ([PSCustomObject]@{RequestPath=$reqPath;ResponsePath=$respPath;BrokerPath=$broker;EnginePath=$stableEngine;Action=$brokerAction})
        }
        default { throw "Unknown bridge action: $Action" }
    }
    exit 0
}catch{
    try{Write-BridgeResult $false $null $_.Exception.Message}catch{}
    exit 2
}
