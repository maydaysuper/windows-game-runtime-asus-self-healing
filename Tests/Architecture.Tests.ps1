#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$ProjectRoot=Join-Path $Root 'WindowsGameRuntimeASUSSelfHealing.WinUI'
$Backend=Join-Path $ProjectRoot 'Backend'
$Failures=New-Object System.Collections.Generic.List[string]

function Pass([string]$Text){Write-Host ("[PASS] "+$Text) -ForegroundColor Green}
function Fail([string]$Text){$Failures.Add($Text);Write-Host ("[FAIL] "+$Text) -ForegroundColor Red}
function Hash([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop).Hash.ToLowerInvariant()}
$script:StrictUtf8 = New-Object System.Text.UTF8Encoding($false,$true)
function Read-Utf8Text([string]$Path){
    $text=[IO.File]::ReadAllText($Path,$script:StrictUtf8)
    if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
    return $text
}
function Read-Utf8Json([string]$Path){
    return ((Read-Utf8Text $Path)|ConvertFrom-Json)
}

trap {
    $line=0
    try{$line=[int]$_.InvocationInfo.ScriptLineNumber}catch{}
    Write-Host ("[FATAL] Architecture.Tests.ps1 line {0}: {1}" -f $line,$_.Exception.Message) -ForegroundColor Red
    exit 97
}

Write-Host '=== Architecture / Safety Static Tests ===' -ForegroundColor Cyan
Write-Host ("PowerShell={0}; Edition={1}; OS={2}" -f $PSVersionTable.PSVersion,$PSVersionTable.PSEdition,[Environment]::OSVersion.VersionString) -ForegroundColor DarkGray

# 1) Parse every PowerShell file with the Windows PowerShell parser.
$parseErrors=@()
foreach($file in @(Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.ps1' -File)){
    $tokens=$null;$errors=$null
    $raw=Read-Utf8Text $file.FullName
    [void][System.Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
    foreach($e in @($errors)){$parseErrors += ("{0}:{1}:{2} {3}" -f $file.FullName,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)}
}
if($parseErrors.Count -eq 0){Pass 'PowerShell parser: all .ps1 files'}else{foreach($e in $parseErrors){Fail $e}}

# 2) Validate XAML/project XML well-formedness.
foreach($file in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File | Where-Object{$_.Extension -in @('.xaml','.csproj')})){
    try{[xml](Read-Utf8Text $file.FullName)|Out-Null;Pass ("XML: "+$file.Name)}catch{Fail ("XML invalid: {0}: {1}" -f $file.FullName,$_.Exception.Message)}
}

# 2b) WinUI 3 XAML member compatibility guards discovered by the real XAML compiler.
$invalidScrollMembers=@()
foreach($file in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.xaml' -File)){
    $raw=Read-Utf8Text $file.FullName
    if($raw -match '(?<!ScrollViewer\.)(?:Horizontal|Vertical)ScrollBarVisibility\s*='){
        $invalidScrollMembers += $file.FullName
    }
}
if($invalidScrollMembers.Count -eq 0){Pass 'WinUI XAML: TextBox scrollbars use ScrollViewer attached properties'}else{foreach($x in $invalidScrollMembers){Fail ('Invalid direct TextBox ScrollBarVisibility member: '+$x)}}

$installerPath=Join-Path $Root 'Installer\WindowsGameRuntimeASUSSelfHealing.iss'
if(Test-Path -LiteralPath $installerPath){
    $installerRaw=Read-Utf8Text $installerPath
    if($installerRaw -match 'PrivilegesRequired=lowest' -and $installerRaw -match 'recursesubdirs' -and $installerRaw -match 'WindowsGameRuntimeASUSSelfHealing\.WinUI\.exe'){
        Pass 'Installer contract: per-user Setup packages complete published runtime'
    }else{Fail 'Installer contract drift'}
}else{Fail 'Installer definition missing'}

# 3) BuildInfo integrity chain.
$buildJson=Read-Utf8Json (Join-Path $Backend 'BuildInfo.json')
$buildPsd=Import-PowerShellDataFile -LiteralPath (Join-Path $Backend 'BuildInfo.psd1')
$hashMap=@{
    EngineSHA256='RepairCenter.ps1'
    BrokerSHA256='ElevatedBroker.ps1'
    BootstrapSHA256='Bootstrap.ps1'
    UiBridgeSHA256='UiBridge.ps1'
    EventReaderSHA256='IncrementalEventReader.ps1'
    GpuDiagnosticsReaderSHA256='GpuDiagnosticsReader.ps1'
    GpuSafeRepairSHA256='GpuSafeRepair.ps1'
    AtomicPolicyExecutorSHA256='AtomicPolicyExecutor.ps1'
    RecipeCatalogSHA256='RecipeCatalog.psd1'
}
foreach($key in $hashMap.Keys){
    $actual=Hash (Join-Path $Backend $hashMap[$key])
    $expected=[string]$buildJson.$key
    $expectedPsd=[string]$buildPsd[$key]
    if($actual -eq $expected -and $actual -eq $expectedPsd){Pass ("BuildInfo hash-lock: "+$hashMap[$key])}else{Fail ("BuildInfo hash mismatch {0}: actual={1} json={2} psd1={3}" -f $hashMap[$key],$actual,$expected,$expectedPsd)}
}
$psdHash=Hash (Join-Path $Backend 'BuildInfo.psd1')
if($psdHash -eq [string]$buildJson.BuildInfoSHA256){Pass 'BuildInfo.psd1 hash-lock'}else{Fail 'BuildInfo.psd1 hash mismatch'}
if([string]$buildJson.Version -eq [string]$buildPsd.Version){Pass ("Version consistency: "+$buildJson.Version)}else{Fail 'BuildInfo version mismatch'}

# 4) Immutable legacy adapter lock: external source files + embedded payloads + engine constants.
$lock=Read-Utf8Json (Join-Path $Root 'LEGACY_ADAPTER_LOCK.json')
$engineRaw=Read-Utf8Text (Join-Path $Backend 'RepairCenter.ps1')
foreach($key in @('PV','HOLTEK','ENE')){
    $entry=$lock.Modules.$key
    $file=Join-Path $Root ([string]$entry.File)
    $expected=([string]$entry.SHA256).ToLowerInvariant()
    if((Hash $file) -eq $expected){Pass ("Legacy source hash: "+$key)}else{Fail ("Legacy source hash changed: "+$key)}
    if($engineRaw -match ("(?m)^\s*"+[regex]::Escape($key)+"='(?<h>[0-9a-f]{64})'")){
        if(([string]$matches['h']).ToLowerInvariant() -eq $expected){Pass ("Engine expected hash constant: "+$key)}else{Fail ("Engine expected hash constant changed: "+$key)}
    }else{Fail ("Engine expected hash constant missing: "+$key)}
    $varName=if($key -eq 'PV'){'EmbeddedPV'}elseif($key -eq 'HOLTEK'){'EmbeddedHoltek'}else{'EmbeddedENE'}
    $pattern=('(?s)\$'+[regex]::Escape($varName)+"\s*=\s*'(?<b64>[^']+)'" )
    if($engineRaw -match $pattern){
        try{
            $bytes=[Convert]::FromBase64String([string]$matches['b64'])
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$embedded=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            if($embedded -eq $expected){Pass ("Embedded legacy payload hash: "+$key)}else{Fail ("Embedded legacy payload changed: "+$key)}
        }catch{Fail ("Embedded legacy payload invalid: {0}: {1}" -f $key,$_.Exception.Message)}
    }else{Fail ("Embedded legacy payload missing: "+$key)}
}

# 5) Structured Recipe / Atomic Policy envelope.
$recipePath=Join-Path $Backend 'RecipeCatalog.psd1'
try{
    $catalog=Import-PowerShellDataFile -LiteralPath $recipePath
    if([int]$catalog.SchemaVersion -eq 1){Pass 'RecipeCatalog schema v1'}else{Fail 'RecipeCatalog schema unexpected'}
    if([string]$catalog.Policy.UnknownAsusVersionBehavior -eq 'DIAGNOSE_ONLY'){Pass 'Unknown ASUS versions remain diagnose-only'}else{Fail 'Unknown ASUS version policy drift'}
    if(-not [bool]$catalog.Policy.AutomaticDDU){Pass 'Recipe policy: automatic DDU disabled'}else{Fail 'Recipe policy enables automatic DDU'}
    if(-not [bool]$catalog.Policy.BlindDriverRemoval){Pass 'Recipe policy: blind driver removal disabled'}else{Fail 'Recipe policy enables blind driver removal'}
    foreach($key in @('PV','HOLTEK','ENE')){
        $recipe=$catalog.Recipes[$key]
        $lockHash=([string]$lock.Modules.$key.SHA256).ToLowerInvariant()
        if(([string]$recipe.AdapterSHA256).ToLowerInvariant() -eq $lockHash){Pass ("Recipe legacy adapter lock: "+$key)}else{Fail ("Recipe adapter hash drift: "+$key)}
        if([string]$recipe.UnknownVersionBehavior -eq 'DIAGNOSE_ONLY'){Pass ("Recipe unknown-version safety: "+$key)}else{Fail ("Recipe unknown-version safety drift: "+$key)}
        if(([string]$buildPsd.LegacyAdapterHashes[$key]).ToLowerInvariant() -eq $lockHash){Pass ("BuildInfo legacy adapter lock: "+$key)}else{Fail ("BuildInfo legacy adapter hash drift: "+$key)}
    }
}catch{Fail ("RecipeCatalog validation failed: "+$_.Exception.Message)}

# 6) UI async discipline: no sync-over-async in C# source.
$badAsync=@()
foreach($file in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.cs' -File)){
    $raw=Read-Utf8Text $file.FullName
    if($raw -match '\.Result\b|\.Wait\s*\(|GetAwaiter\(\)\.GetResult\(\)'){$badAsync += $file.FullName}
}
if($badAsync.Count -eq 0){Pass 'C# async discipline: no .Result/.Wait/GetResult'}else{foreach($x in $badAsync){Fail ("sync-over-async found: "+$x)}}

# 7) Read-only Event Log and GPU telemetry lanes must stay outside RepairCenter.
$uiBridgeRaw=Read-Utf8Text (Join-Path $Backend 'UiBridge.ps1')
$engineMarker='. $EnginePath -LibraryMode'
foreach($telemetryMarker in @("if(`$Action -eq 'CRASH_DELTA')","if(`$Action -eq 'GPU_DIAGNOSTICS')")){
    if($uiBridgeRaw.Contains($telemetryMarker) -and $uiBridgeRaw.IndexOf($telemetryMarker) -lt $uiBridgeRaw.IndexOf($engineMarker)){Pass ($telemetryMarker+' bypasses RepairCenter import')}else{Fail ($telemetryMarker+' is no longer isolated from RepairCenter import')}
}

# 8) Incremental telemetry must advance by scan watermark and Broker must enforce Recipe envelope.
$telemetryRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\CrashTelemetryService.cs')
if($telemetryRaw -match 'ScanStartedUtc' -and $telemetryRaw -match 'SetEventCursorAsync\(CursorName, scanStarted'){Pass 'Event cursor advances to successful scan watermark'}else{Fail 'Incremental event cursor watermark logic missing'}
$workflowRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\RepairWorkflowCoordinator.cs')
if($workflowRaw -match 'BROKER_STILL_RUNNING' -and $workflowRaw -match 'BROKER_WAIT_CANCELLED' -and $workflowRaw -match 'RepairWorkflowPhase\.BrokerRunning'){Pass 'Broker wait timeout/cancel preserves active repair state'}else{Fail 'Broker wait timeout is incorrectly treated as repair failure'}
$brokerRaw=Read-Utf8Text (Join-Path $Backend 'ElevatedBroker.ps1')
if($brokerRaw -match 'Assert-WgrRecipeEnvelope' -and $brokerRaw -match 'AtomicPolicyExecutorSHA256'){Pass 'Elevated Broker enforces structured Recipe/Atomic Policy envelope'}else{Fail 'Broker structured Recipe gate missing'}

# 9) Explicitly reject dangerous automation drift.
$recipeFiles=@(Get-ChildItem -LiteralPath $Backend -Filter '*.ps1' -File | Where-Object{$_.Name -notmatch '^module_'})
foreach($file in $recipeFiles){
    $raw=Read-Utf8Text $file.FullName
    if($raw -match '(?i)\bDDU\b.*(?:Start-Process|&\s|Invoke-Expression)' ){Fail ("Automated DDU pattern found: "+$file.Name)}
}
Pass 'Dangerous-operation scan completed'


# 10) Publish/runtime + current stable technology invariants.
$csprojRaw=Read-Utf8Text (Join-Path $ProjectRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI.csproj')
$packagesRaw=Read-Utf8Text (Join-Path $Root 'Directory.Packages.props')
$buildPropsRaw=Read-Utf8Text (Join-Path $Root 'Directory.Build.props')
foreach($required in @(
    '<TargetFramework>net10.0-windows10.0.26100.0</TargetFramework>',
    '<Platform>x64</Platform>',
    '<PlatformTarget>x64</PlatformTarget>',
    '<WindowsPackageType>None</WindowsPackageType>',
    '<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>',
    '<SelfContained>true</SelfContained>',
    '<PublishSingleFile>true</PublishSingleFile>',
    '<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>'
)){
    if($csprojRaw.Contains($required)){Pass ("Publish invariant: "+$required)}else{Fail ("Missing publish invariant: "+$required)}
}
foreach($required in @(
    '<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>',
    'Microsoft.WindowsAppSDK" Version="2.5.1',
    'Microsoft.Windows.SDK.BuildTools.WinApp" Version="0.6.1',
    'Microsoft.Data.Sqlite" Version="10.0.12'
)){
    if($packagesRaw.Contains($required)){Pass ("Central package invariant: "+$required)}else{Fail ("Missing central package invariant: "+$required)}
}
foreach($required in @('<LangVersion>14.0</LangVersion>','<NuGetAudit>true</NuGetAudit>','<NuGetAuditMode>all</NuGetAuditMode>','<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>')){
    if($buildPropsRaw.Contains($required)){Pass ("Modern build invariant: "+$required)}else{Fail ("Missing modern build invariant: "+$required)}
}
if([string]$buildJson.WindowsAppSDK -eq '2.5.1' -and [string]$buildJson.DotNet -eq '10.0' -and [string]$buildJson.Language -eq 'C# 14'){Pass 'BuildInfo current stable technology metadata'}else{Fail 'BuildInfo technology metadata mismatch'}

# 11) One-click package version must match BuildInfo.
$oneClickRaw=Read-Utf8Text (Join-Path $Root 'OneClick-Win11.ps1')
if($oneClickRaw -match 'publish 目录缺少 Backend' -and $oneClickRaw -match '孤立 EXE' -and $oneClickRaw -notmatch '\$DesktopExe'){Pass 'OneClick never ships bare EXE without Backend'}else{Fail 'OneClick bare-EXE delivery regression'}
$versionPattern=("(?m)^\s*"+[regex]::Escape('$Version')+"\s*=\s*'"+[regex]::Escape([string]$buildJson.Version)+"'\s*$")
if($oneClickRaw -match $versionPattern){Pass 'OneClick version matches BuildInfo'}else{Fail 'OneClick version does not match BuildInfo'}
if($oneClickRaw -match 'Architecture\.Tests\.ps1'){Pass 'OneClick runs architecture static tests before publish'}else{Fail 'OneClick no longer runs architecture static tests'}
if($oneClickRaw -match 'https://dot\.net/v1/dotnet-install\.ps1' -and $oneClickRaw -match "Install-DotNet10SdkLocal" -and $oneClickRaw -match "'-Channel','10\.0'" -and $oneClickRaw -match "'-Quality','GA'"){Pass 'OneClick has Microsoft dotnet-install local SDK fallback'}else{Fail 'OneClick local .NET 10 SDK fallback missing'}
if($oneClickRaw -match 'source update --name winget' -and $oneClickRaw -match '0x8A15000F'){Pass 'OneClick handles missing WinGet source data'}else{Fail 'OneClick WinGet source recovery missing'}
if($oneClickRaw -notmatch 'source reset'){Pass 'OneClick does not destructively reset WinGet sources'}else{Fail 'OneClick must not automatically reset WinGet sources'}
if($oneClickRaw -match "'-p:Platform=x64'" -and $oneClickRaw -match 'Publish_\{0\}\.log' -and $oneClickRaw -match '-bl:'){Pass 'OneClick pins MSBuild Platform=x64 and emits publish diagnostics'}else{Fail 'OneClick x64 publish/logging contract missing'}

# 11b) Windows cmd launchers must be code-page independent: ASCII-only, no UTF-8 BOM, strict CRLF.
foreach($launcherName in @('一键构建并启动_Win11.cmd','Launch-Win11.cmd','Build-WinUI3.cmd')){
    $launcherPath=Join-Path $Root $launcherName
    if(-not (Test-Path -LiteralPath $launcherPath)){Fail ('Launcher missing: '+$launcherName);continue}
    $bytes=[IO.File]::ReadAllBytes($launcherPath)
    $hasBom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if(-not $hasBom){Pass ('Launcher BOM-free: '+$launcherName)}else{Fail ('Launcher UTF-8 BOM forbidden: '+$launcherName)}
    $hasNonAscii=@($bytes|Where-Object{$_ -gt 0x7F}).Count -gt 0
    if(-not $hasNonAscii){Pass ('Launcher ASCII-only: '+$launcherName)}else{Fail ('Launcher contains non-ASCII bytes: '+$launcherName)}
    $badLf=$false
    for($i=0;$i -lt $bytes.Length;$i++){if($bytes[$i] -eq 0x0A -and ($i -eq 0 -or $bytes[$i-1] -ne 0x0D)){$badLf=$true;break}}
    if(-not $badLf -and ([Text.Encoding]::ASCII.GetString($bytes)).Contains("`r`n")){Pass ('Launcher strict CRLF: '+$launcherName)}else{Fail ('Launcher line endings are not strict CRLF: '+$launcherName)}
    $launcherText=[Text.Encoding]::ASCII.GetString($bytes)
    $expectedScript=if($launcherName -eq 'Build-WinUI3.cmd'){'Build-WinUI3.ps1'}else{'OneClick-Win11.ps1'}
    if($launcherText.StartsWith("@echo off`r`n") -and $launcherText -notmatch '(?i)chcp\s+65001' -and $launcherText.Contains($expectedScript)){Pass ('Launcher command contract: '+$launcherName)}else{Fail ('Launcher command contract drift: '+$launcherName)}
}

# 12) v3.4 simplified information architecture, Dump and GPU/ReBAR analysis.
$mainWindowRaw=Read-Utf8Text (Join-Path $ProjectRoot 'MainWindow.xaml')
foreach($tag in @('overview','asus','runtime','crash','reports')){
    if($mainWindowRaw -match ('Tag="'+$tag+'"')){Pass ("Main navigation contains: "+$tag)}else{Fail ("Main navigation missing: "+$tag)}
}
if($mainWindowRaw -notmatch 'Tag="transactions"' -and $mainWindowRaw -notmatch 'Tag="settings"'){Pass 'Developer/history pages removed from primary navigation'}else{Fail 'Primary navigation regressed to developer-oriented pages'}
$dumpRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\DumpAnalysisService.cs')
if($dumpRaw -match 'MiniDumpReadDumpStream' -and $dumpRaw -match 'MemoryMappedFile'){Pass 'Dump analyzer uses bounded local memory mapping + DbgHelp'}else{Fail 'Local Dump analyzer core missing'}
$reportRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\ReportService.cs')
if($reportRaw -match 'GenerateSystemHealthReportAsync' -and $reportRaw -match 'GenerateRepairReportAsync' -and $reportRaw -match 'CreateDumpAnalysisReportAsync' -and $reportRaw -match 'CreateGpuDiagnosisReportAsync'){Pass 'Unified report service covers system/repair/dump/GPU'}else{Fail 'Unified report service incomplete'}

# 13) Adaptive low-resource policy and state schema v3.
$resourceRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\AdaptiveResourceGovernor.cs')
if($resourceRaw -match 'Environment\.ProcessorCount' -and $resourceRaw -match 'TotalAvailableMemoryBytes' -and $resourceRaw -match 'SemaphoreSlim'){Pass 'Adaptive resource governor is CPU/memory aware'}else{Fail 'Adaptive resource governor missing hardware-aware concurrency'}
$stateRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\StateStoreService.cs')
if($stateRaw -match 'SchemaVersion = 3' -and $stateRaw -match 'CREATE TABLE IF NOT EXISTS dump_analyses' -and $stateRaw -match 'journal_size_limit=4194304'){Pass 'SQLite schema v3 stores dump analyses and bounds WAL/journal growth'}else{Fail 'SQLite v3 dump/resource policy missing'}
if([int]$buildJson.StateSchemaVersion -eq 3 -and [int]$buildPsd.StateSchemaVersion -eq 3){Pass 'BuildInfo state schema v3'}else{Fail 'BuildInfo state schema mismatch'}


# 14) No-feature-reduction baseline. ASUS repair is the protected core capability.
$capabilityPath=Join-Path $Backend 'CapabilityBaseline.json'
try{$capability=Read-Utf8Json $capabilityPath}catch{$capability=$null;Fail ('Capability baseline parse failed: '+$_.Exception.Message)}
if($capability){
    $capHash=Hash $capabilityPath
    if($capHash -eq [string]$buildJson.CapabilityBaselineSHA256 -and $capHash -eq [string]$buildPsd.CapabilityBaselineSHA256){Pass 'Capability baseline hash-lock'}else{Fail 'Capability baseline SHA256 mismatch'}
    if([string]$capability.Policy -eq 'NO_FEATURE_REDUCTION' -and [string]$capability.AsusCore.Priority -eq 'CORE'){Pass 'ASUS marked as non-reducible core capability'}else{Fail 'ASUS no-feature-reduction policy missing'}
    $bridgeRaw=Read-Utf8Text (Join-Path $Backend 'UiBridge.ps1')
    foreach($action in @('DASHBOARD','PREFLIGHT','PLAN_ASUS','PLAN_RUNTIME','RUNTIME_ONLINE','TRANSACTIONS','VERIFY','EXPORT_REPORT')){
        if($bridgeRaw -match [regex]::Escape("'$action'")){Pass ('Bridge action retained: '+$action)}else{Fail ('Bridge action missing: '+$action)}
    }
    foreach($action in @('ASUS_REPAIR','RUNTIME_REPAIR','CONTINUE','WER_ENABLE','WER_DISABLE','GPU_SAFE_REPAIR')){
        if($brokerRaw -match [regex]::Escape("'$action'")){Pass ('Broker action retained: '+$action)}else{Fail ('Broker action missing: '+$action)}
    }
    $engineRaw=Read-Utf8Text (Join-Path $Backend 'RepairCenter.ps1')
    foreach($fn in @('Get-ASUSRepairEligibility','Invoke-ASUSRepairHeadless','Invoke-RuntimeRepairHeadless','Continue-PendingRepair','Run-FinalVerification','Start-TransactionObservation','Get-GameCrashTelemetry','Set-WerLocalDumpConfiguration')){
        if($engineRaw -match ('(?m)^function\s+'+[regex]::Escape($fn)+'\b')){Pass ('Engine capability retained: '+$fn)}else{Fail ('Engine capability missing: '+$fn)}
    }
    $reportsXaml=Read-Utf8Text (Join-Path $ProjectRoot 'Pages\ReportsPage.xaml')
    if($reportsXaml -match 'TransactionId' -and $reportsXaml -match '重启后续跑'){Pass 'Transaction history details retained inside report center'}else{Fail 'Transaction history detail was reduced'}
    $reportsCode=Read-Utf8Text (Join-Path $ProjectRoot 'Pages\ReportsPage.xaml.cs')
    if($reportsCode -match 'RunAsync\("VERIFY"' -and $reportsCode -match 'RunAsync\("EXPORT_REPORT"' -and $reportsCode -match 'CONTINUE'){Pass 'Final verification/export/reboot-continuation remain user accessible'}else{Fail 'Report center lost verification/export/continuation capability'}
}

# 15) GPU/ReBAR classifier and remediation safety invariants.
$gpuDiagRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\GpuDiagnosticsService.cs')
$gpuMemRaw=Read-Utf8Text (Join-Path $ProjectRoot 'Services\GpuMemoryTelemetryService.cs')
$gpuReaderRaw=Read-Utf8Text (Join-Path $Backend 'GpuDiagnosticsReader.ps1')
$gpuRepairRaw=Read-Utf8Text (Join-Path $Backend 'GpuSafeRepair.ps1')
foreach($category in @('REBAR_COMPATIBILITY_SUSPECTED','TRUE_VRAM_PRESSURE','DRIVER_TDR','PCIE_LINK','POWER_DELIVERY_SUSPECTED','EVIDENCE_INSUFFICIENT')){
    if($gpuDiagRaw -match [regex]::Escape($category)){Pass ('GPU classifier retained: '+$category)}else{Fail ('GPU classifier missing: '+$category)}
}
if($gpuMemRaw -match 'PdhAddEnglishCounterW' -and $gpuMemRaw -match 'Dedicated Usage' -and $gpuMemRaw -match 'Shared Usage' -and $gpuMemRaw -match 'CreateDXGIFactory1'){Pass 'GPU memory telemetry uses PDH English counters + DXGI'}else{Fail 'GPU memory telemetry path incomplete'}
if($gpuMemRaw -match 'PdhGetFormattedCounterArrayW\([^;]*out uint itemCount' -and $gpuMemRaw -notmatch 'PdhGetFormattedCounterArrayW\([^;]*ref itemCount'){Pass 'PDH formatted counter array uses out itemCount (CS1620-safe)'}else{Fail 'PdhGetFormattedCounterArrayW call-site/DllImport out/ref mismatch'}
if($gpuMemRaw -match 'StructLayout\(LayoutKind.Explicit, Size = 16\)' -and $gpuMemRaw -match 'FieldOffset\(8\)\]\s*public double DoubleValue'){Pass 'PDH_FMT_COUNTERVALUE uses explicit x64 union layout'}else{Fail 'PDH_FMT_COUNTERVALUE layout is not CS/x64-safe'}
if($gpuReaderRaw -match 'nvlddmkm' -and $gpuReaderRaw -match 'WHEA-Logger' -and $gpuReaderRaw -match 'Kernel-Power' -and $gpuReaderRaw -match 'LiveKernelReports' -and $gpuReaderRaw -match 'TdrOverrides'){Pass 'GPU reader covers TDR/WHEA/power/livekernel evidence'}else{Fail 'GPU reader evidence coverage incomplete'}
if($gpuReaderRaw -match 'DisplayTdrTimesUtc' -and $gpuReaderRaw -match 'WheaPcieTimesUtc' -and $gpuReaderRaw -match 'AbruptPowerLossTimesUtc' -and $gpuDiagRaw -match 'CountNearPairs' -and $gpuDiagRaw -match 'TimeSpan.FromMinutes\(10\)' -and $gpuDiagRaw -match 'TimeSpan.FromMinutes\(30\)'){Pass 'GPU root-cause classifier uses bounded temporal correlation'}else{Fail 'GPU temporal-correlation guard missing'}
if($gpuRepairRaw -match 'GpuCacheBackups' -and $gpuRepairRaw -match '/scan-devices' -and $gpuRepairRaw -match 'AutomaticDDU=\$false' -and $gpuRepairRaw -match 'DriverRemoval=\$false' -and $gpuRepairRaw -match 'TdrRegistryWrites=\$false' -and $gpuRepairRaw -match 'BiosWrites=\$false'){Pass 'GPU safe repair remains non-destructive'}else{Fail 'GPU safe repair safety boundary drift'}
$crashCode=Read-Utf8Text (Join-Path $ProjectRoot 'Pages\CrashPage.xaml.cs')
if($crashCode -match 'RunGpuDiagnosisAsync' -and $crashCode -match 'GPU_SAFE_REPAIR'){Pass 'GPU diagnosis and safe repair are user accessible'}else{Fail 'GPU diagnosis UI path missing'}
if($gpuDiagRaw -match 'LiveKernelReports' -and $gpuDiagRaw -match '_dumpAnalysis\.AnalyzeAsync' -and $gpuDiagRaw -match 'SaveDumpAnalysisAsync'){Pass 'GPU diagnosis auto-analyzes newest local LiveKernel dump best-effort'}else{Fail 'GPU LiveKernel dump auto-analysis path missing'}

if($Failures.Count -gt 0){
    Write-Host ''
    Write-Host ("FAILED: {0} static test(s)" -f $Failures.Count) -ForegroundColor Red
    $Failures|ForEach-Object{Write-Host (" - "+$_) -ForegroundColor Red}
    exit 1
}
Write-Host ''
Write-Host 'ALL STATIC TESTS PASSED' -ForegroundColor Green
exit 0
