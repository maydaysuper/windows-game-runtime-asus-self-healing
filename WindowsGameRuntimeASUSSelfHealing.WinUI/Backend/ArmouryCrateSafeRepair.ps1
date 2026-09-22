#requires -version 5.1
<#
Safe Armoury Crate launch / install-501 repair.

This does NOT:
- run DDU or uninstall GPU drivers;
- write BIOS / ReBAR / TDR;
- delete Program Files HAL modules;
- download unofficial Armoury Crate packages;
- kill running games.

It restarts missing ASUS services, re-registers already-installed AppX packages,
cleans allow-listed installer leftovers, and tries to start Armoury Crate / Lite.
#>
$ErrorActionPreference='Continue'

function Test-WgrArmouryTempPath([string]$Path) {
    if(-not $Path){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')+'\'
        $n=$full.ToLowerInvariant()
        if($n -match 'windowsruntimeasusselfhealing|asus4151|asuscorehal4151|asus_ene_m2_4152|driverstore|windows\\system32|windows\\syswow64'){return $false}
        $roots=@()
        foreach($raw in @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'), (Join-Path $env:ProgramData 'ASUS'), (Join-Path $env:LOCALAPPDATA 'ASUS'), (Join-Path $env:WINDIR 'Temp'))) {
            if(-not $raw){continue}
            try{$roots += ([IO.Path]::GetFullPath($raw).TrimEnd('\')+'\')}catch{}
        }
        $under=$false
        foreach($root in $roots){if($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){$under=$true;break}}
        if(-not $under){return $false}
        return $n -match 'armoury|aacsetup|crateinstaller|asus.*install'
    } catch { return $false }
}

function Get-WgrArmouryChassisKind {
    $laptopTypes=@(8,9,10,11,12,14,18,21,30,31,32)
    try {
        foreach($e in @(Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue)) {
            foreach($t in @($e.ChassisTypes)) {
                try{if($laptopTypes -contains [int]$t){return 'Laptop'}}catch{}
            }
        }
    } catch {}
    return 'Desktop'
}

function Get-WgrArmouryServiceNames {
    return @(
        'ArmouryCrateService',
        'ROG Live Service',
        'LightingService',
        'asComSvc',
        'AsusAppService',
        'AsusSystemAnalysis',
        'AsusSystemDiagnosis'
    )
}

function Get-WgrArmouryAppxPackages {
    $out=@()
    try {
        $pkgs=@(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            [string]$_.Name -match '(?i)ArmouryCrate'
        })
        foreach($p in $pkgs){
            $out += [PSCustomObject]@{
                Name=[string]$p.Name
                Status=[string]$p.Status
                Location=[string]$p.InstallLocation
                Lite=$([string]$p.Name -match '(?i)Lite')
            }
        }
    } catch {}
    return $out
}

function Get-WgrArmouryExecutables {
    $names=@('ArmouryCrate.exe','ArmouryCrate.UserSessionHelper.exe','Armoury Crate.exe','AacApp.exe')
    $roots=@(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
        (Join-Path $env:LOCALAPPDATA 'ASUS'),
        (Join-Path $env:ProgramData 'ASUS')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $found=@()
    $seen=@{}
    foreach($root in $roots){
        try {
            $hits=@(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $names -contains $_.Name } |
                Select-Object -First 12)
            foreach($h in $hits){
                $p=[string]$h.FullName
                if($seen.ContainsKey($p.ToLowerInvariant())){continue}
                $seen[$p.ToLowerInvariant()]=$true
                $found += $p
            }
        } catch {}
    }
    return $found
}

function Test-WgrArmouryError501 {
    $since=(Get-Date).AddHours(-6)
    $roots=@("$env:ProgramData\ASUS","$env:LOCALAPPDATA\ASUS") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach($root in $roots){
        try {
            $files=@(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $since -and $_.Length -lt 8MB -and $_.Extension -match '^\.(log|txt)$' } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 80)
            foreach($f in $files){
                try {
                    $tail=@(Get-Content -LiteralPath $f.FullName -Tail 800 -ErrorAction Stop)
                    foreach($line in $tail){
                        if([string]$line -match '(?i)(?:UI\s*code|uicode|error\s*code)\s*[:=]\s*501|\berror\s*501\b'){return $true}
                    }
                } catch {}
            }
        } catch {}
    }
    return $false
}

function Get-WgrArmouryCrateLaunchHealth([switch]$SkipLogScan) {
    $kind=Get-WgrArmouryChassisKind
    $svc=@()
    foreach($n in @(Get-WgrArmouryServiceNames)){
        try {
            $s=Get-Service -Name $n -ErrorAction Stop
            $svc += [PSCustomObject]@{Name=$n;Exists=$true;Status=[string]$s.Status;StartType=[string]$s.StartType}
        } catch {
            $svc += [PSCustomObject]@{Name=$n;Exists=$false;Status='Missing';StartType=''}
        }
    }
    $core=@($svc | Where-Object { $_.Name -in @('ArmouryCrateService','ROG Live Service','LightingService') -and $_.Exists })
    $stopped=@($core | Where-Object { $_.Status -ne 'Running' })
    $appx=@(Get-WgrArmouryAppxPackages)
    $exes=@(Get-WgrArmouryExecutables)
    $installed=($core.Count -gt 0 -or $appx.Count -gt 0 -or $exes.Count -gt 0)
    $brokenAppx=@($appx | Where-Object { $_.Status -and $_.Status -ne 'Ok' })
    $runningProc=$false
    try { $runningProc = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)ArmouryCrate' }).Count -gt 0 } catch {}

    $needsRepair=$false
    $issue=''
    $has501=$false
    if(-not $SkipLogScan){
        try { $has501=[bool](Test-WgrArmouryError501) } catch {}
    }
    if($has501 -and ((-not $installed) -or $stopped.Count -gt 0)){
        $needsRepair=$true
        $issue='安装奥创时出现 501 错误。'
    }
    if($stopped.Count -gt 0){
        $needsRepair=$true
        if(-not $issue){$issue='奥创服务没有在运行，所以软件打不开。'}
    }
    if($installed -and $appx.Count -gt 0 -and $brokenAppx.Count -gt 0){
        $needsRepair=$true
        if(-not $issue){$issue='奥创应用包损坏，所以打不开。'}
    }
    if($installed -and $core.Count -eq 0 -and $exes.Count -gt 0){
        $needsRepair=$true
        if(-not $issue){$issue='奥创文件还在，但服务没装好，所以打不开。'}
    }

    $detail=if($needsRepair){$issue}elseif(-not $installed){'这台电脑还没装奥创，或者已经卸干净了。'}else{'奥创服务正常。'}
    if($kind -eq 'Laptop' -and $needsRepair){$detail += ' 这是笔记本，会按奥创 / 奥创 Lite 现有安装来修。'}

    return [PSCustomObject]@{
        Chassis=$kind
        Installed=$installed
        NeedsRepair=$needsRepair
        Issue=$issue
        Detail=$detail
        Services=$svc
        Appx=$appx
        Executables=$exes
        ProcessRunning=$runningProc
        Has501=$has501
    }
}

function Invoke-WgrArmouryLaunchAttempt {
    [CmdletBinding()]
    param(
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5,
        [string[]]$Executables,
        [switch]$SkipProcessCheck
    )
    if(-not $SkipProcessCheck){
        try {
            $running=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)ArmouryCrate' })
            if($running.Count -gt 0){
                return [PSCustomObject]@{Success=$true;Attempts=0;ErrorCode=$null;Error=$null;Path='';AlreadyRunning=$true;ErrorHistory=@()}
            }
        } catch {}
    }
    if($null -eq $Executables){ $Executables = @(Get-WgrArmouryExecutables) }
    $list=@($Executables | Where-Object { $_ })
    if($list.Count -eq 0){
        return [PSCustomObject]@{Success=$false;Attempts=0;ErrorCode=$null;Error='没有找到奥创程序';Path='';AlreadyRunning=$false;ErrorHistory=@()}
    }

    $attempts=0
    $lastError=$null
    $lastCode=$null
    $path=$list[0]
    $exeIndex=0
    $history=New-Object System.Collections.Generic.List[object]
    while($attempts -lt $MaxRetries){
        $attempts++
        if($exeIndex -ge $list.Count){ $exeIndex = 0 }
        $path=$list[$exeIndex]
        try {
            Start-Process -FilePath $path -ErrorAction Stop | Out-Null
            return [PSCustomObject]@{Success=$true;Attempts=$attempts;ErrorCode=$null;Error=$null;Path=$path;AlreadyRunning=$false;ErrorHistory=@($history)}
        } catch {
            $lastError=[string]$_.Exception.Message
            $lastCode=$null
            if($_.Exception -is [ComponentModel.Win32Exception]){
                $lastCode = [int]$_.Exception.NativeErrorCode
            } elseif($_.Exception.InnerException -is [ComponentModel.Win32Exception]){
                $lastCode = [int]$_.Exception.InnerException.NativeErrorCode
            } else {
                try { $lastCode = [int]$_.Exception.HResult } catch { $lastCode = $null }
            }
            [void]$history.Add([PSCustomObject]@{Attempt=$attempts;Path=$path;ErrorCode=$lastCode;Error=$lastError})
            $exeIndex++
            if($attempts -lt $MaxRetries -and $DelaySeconds -gt 0){ Start-Sleep -Seconds $DelaySeconds }
        }
    }
    return [PSCustomObject]@{Success=$false;Attempts=$attempts;ErrorCode=$lastCode;Error=$lastError;Path=$path;AlreadyRunning=$false;ErrorHistory=@($history)}
}

function Invoke-WgrArmouryCrateSafeRepair {
    $before=Get-WgrArmouryCrateLaunchHealth
    $messages=New-Object System.Collections.Generic.List[string]
    $cleaned=0
    $started=0
    $registered=0

    if(Get-Command Invoke-RuntimeAutoRepair -ErrorAction SilentlyContinue){
        try {
            if(Get-Command Update-RuntimeOnlineInfo -ErrorAction SilentlyContinue){try{[void](Update-RuntimeOnlineInfo)}catch{}}
            $snap=$null
            if(Get-Command Get-SystemSnapshot -ErrorAction SilentlyContinue){$snap=Get-SystemSnapshot -Force}
            $elig=$null
            if($snap -and (Get-Command Get-RuntimeRepairEligibility -ErrorAction SilentlyContinue)){$elig=Get-RuntimeRepairEligibility $snap}
            if($elig -and [bool]$elig.Eligible){
                $vr=Invoke-RuntimeAutoRepair
                if($vr.Success){[void]$messages.Add('C++ 运行库已检查并修好。')}
                else{[void]$messages.Add('C++ 运行库已尝试修复。')}
            } else {
                [void]$messages.Add('C++ 运行库本机可用。')
            }
        } catch {
            [void]$messages.Add('C++ 运行库检查已跳过。')
        }
    }

    $tempRoots=@($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'), (Join-Path $env:WINDIR 'Temp'), (Join-Path $env:ProgramData 'ASUS'), (Join-Path $env:LOCALAPPDATA 'ASUS')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach($root in $tempRoots){
        try {
            $items=@(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '(?i)(Armoury|AacSetup|CrateInstaller|ASUS.*Install)'
            } | Select-Object -First 40)
            foreach($item in $items){
                if(-not (Test-WgrArmouryTempPath $item.FullName)){continue}
                try {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                    $cleaned++
                } catch {}
            }
        } catch {}
    }
    if($cleaned -gt 0){[void]$messages.Add("已清理 $cleaned 处奥创安装残留。")}

    foreach($n in @(Get-WgrArmouryServiceNames)){
        try {
            $s=Get-Service -Name $n -ErrorAction Stop
            if([string]$s.StartType -eq 'Disabled'){
                try { Set-Service -Name $n -StartupType Automatic -ErrorAction Stop } catch {}
            }
            if([string]$s.Status -ne 'Running'){
                Start-Service -Name $n -ErrorAction Stop
                $started++
            }
        } catch {}
    }
    if($started -gt 0){[void]$messages.Add("已启动 $started 个奥创相关服务。")}

    try {
        $pkgs=@(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match '(?i)ArmouryCrate' })
        try { $pkgs += @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match '(?i)ArmouryCrate' }) } catch {}
        $seen=@{}
        foreach($p in $pkgs){
            $key=[string]$p.PackageFullName
            if(-not $key -or $seen.ContainsKey($key)){continue}
            $seen[$key]=$true
            $manifest=Join-Path ([string]$p.InstallLocation) 'AppxManifest.xml'
            if(Test-Path -LiteralPath $manifest){
                try { Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop; $registered++ } catch {}
            }
            if(Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue){
                try { Reset-AppxPackage -Package $p -ErrorAction SilentlyContinue | Out-Null } catch {}
            }
        }
    } catch {}
    if($registered -gt 0){[void]$messages.Add("已重新注册 $registered 个奥创应用。")}

    $launch=Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 5
    if($launch.AlreadyRunning){[void]$messages.Add('奥创已经在运行。')}
    elseif($launch.Success){[void]$messages.Add("已打开奥创（第 $($launch.Attempts) 次成功）。")}
    elseif($launch.ErrorCode){[void]$messages.Add("打开奥创失败，错误码 $($launch.ErrorCode)。")}
    elseif($launch.Error){[void]$messages.Add('打开奥创失败。')}

    Start-Sleep -Seconds 2
    $after=Get-WgrArmouryCrateLaunchHealth
    $ok=(-not [bool]$after.NeedsRepair)
    if($ok){[void]$messages.Add('奥创现在可以打开。')}
    elseif(-not $after.Installed){[void]$messages.Add('安装残留已处理。请再运行一次奥创官方安装包。')}
    else{[void]$messages.Add('还没有完全恢复。请再点一次全自动修复，或再运行奥创官方安装包。')}

    $detail=($messages | Where-Object { $_ }) -join ' '
    if(-not $detail){$detail='奥创安装/启动修复已跑完。'}
    $launched=[bool]$launch.Success
    return [PSCustomObject]@{
        Success=$ok -or $cleaned -gt 0 -or $started -gt 0 -or $registered -gt 0 -or $launched
        Detail=$detail
        State=$(if($ok){'COMPLETED'}else{'NEEDS_ATTENTION'})
        Before=$before
        After=$after
        LaunchAttempt=$launch
        Safety=[PSCustomObject]@{AutomaticDDU=$false;DriverRemoval=$false;BiosWrites=$false;HalDeletion=$false}
    }
}
