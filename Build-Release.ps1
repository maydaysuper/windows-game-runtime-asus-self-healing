#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$PublishRoot = (Join-Path $PSScriptRoot 'artifacts\publish'),
    [string]$ReleaseDir = (Join-Path $PSScriptRoot 'artifacts\release'),
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64',
    [switch]$SkipInstaller,
    [switch]$BuildProject
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'tools\BuildStatus.ps1')

if($WhatIfPreference) {
    Write-Step 'WhatIf: simulate CI gates, skip publish/package'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'tools\Preflight-Ci.ps1') -Root $PSScriptRoot
    if($LASTEXITCODE -ne 0){ Fail 'WhatIf preflight failed' }
    Write-Ok 'WhatIf preflight matched CI static/Pester gates'
    return
}

function Read-Utf8Json([string]$Path) {
    $utf8=New-Object System.Text.UTF8Encoding($false,$true)
    return ([IO.File]::ReadAllText($Path,$utf8) | ConvertFrom-Json)
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Title,
        [string]$DiagnosticLog
    )
    Write-Step $Title
    Write-Host ($FilePath + ' ' + ($Arguments -join ' '))
    if($DiagnosticLog) { Write-Host ("MSBuild log: {0}" -f $DiagnosticLog) -ForegroundColor DarkGray }
    & $FilePath @Arguments
    if($LASTEXITCODE -ne 0) {
        if($DiagnosticLog) { Fail ("{0} failed, ExitCode={1}. log={2}" -f $Title,$LASTEXITCODE,$DiagnosticLog) }
        Fail ("{0} failed, ExitCode={1}" -f $Title,$LASTEXITCODE)
    }
}

function Build-DesktopLauncher([string]$OutDir) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $proj=Join-Path $PSScriptRoot 'Launcher\SelfHealingCenter.csproj'
    $published=Join-Path $OutDir 'SelfHealingCenter.exe'
    if(Get-Command dotnet -ErrorAction SilentlyContinue) {
        & dotnet publish $proj -c Release -o $OutDir --nologo
        if($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $published)) { return }
    }
    $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if(-not (Test-Path -LiteralPath $csc)) { Fail 'Cannot compile desktop launcher: dotnet net48 / csc.exe missing.' }
    $icon=Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Assets\app.ico'
    $src=Join-Path $PSScriptRoot 'Launcher\SelfHealingCenter.cs'
    $cscArgs=@('/nologo','/t:winexe','/platform:x64',"/win32icon:$icon","/out:$published",'/utf8output',$src)
    & $csc @cscArgs
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $published)) { Fail 'csc launcher compile failed.' }
}

function Publish-WpfProject {
    $Project = Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\WindowsGameRuntimeASUSSelfHealing.WinUI.csproj'
    if(-not (Test-Path -LiteralPath $Project)) { Fail ("project missing: {0}" -f $Project) }
    $dotnet = (Get-Command dotnet.exe -ErrorAction Stop).Source
    $LogRoot = Join-Path $PSScriptRoot 'BuildLogs'
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $RestoreLog = Join-Path $LogRoot ("Restore_{0}.log" -f $stamp)
    $RestoreBinLog = Join-Path $LogRoot ("Restore_{0}.binlog" -f $stamp)
    $PublishLog = Join-Path $LogRoot ("Publish_{0}.log" -f $stamp)
    $PublishBinLog = Join-Path $LogRoot ("Publish_{0}.binlog" -f $stamp)

    $projectDir = Split-Path -Parent $Project
    foreach($name in @('bin','obj')) {
        Remove-Item -LiteralPath (Join-Path $projectDir $name) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PublishRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $PublishRoot -Force | Out-Null

    Invoke-LoggedCommand -FilePath $dotnet -Title 'restore WPF / Sqlite' -DiagnosticLog $RestoreLog -Arguments @(
        'restore',$Project,'-r',$Runtime,'--nologo','-p:Platform=x64','-v:minimal',
        ("-flp:logfile={0};verbosity=normal" -f $RestoreLog),("-bl:{0}" -f $RestoreBinLog)
    )
    Invoke-LoggedCommand -FilePath $dotnet -Title 'publish self-contained WPF' -DiagnosticLog $PublishLog -Arguments @(
        'publish',$Project,'-c',$Configuration,'-r',$Runtime,'-o',$PublishRoot,
        '--self-contained','true','--no-restore','--nologo',
        '-p:Platform=x64','-p:SelfContained=true','-p:PublishSingleFile=false',
        '-p:PublishTrimmed=false','-p:PublishReadyToRun=false','-v:minimal',
        ("-flp:logfile={0};verbosity=normal" -f $PublishLog),("-bl:{0}" -f $PublishBinLog)
    )

    $sourceBackend = Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend'
    $backendDir = Join-Path $PublishRoot 'Backend'
    if(-not (Test-Path -LiteralPath $sourceBackend)) { Fail 'source Backend missing' }
    New-Item -ItemType Directory -Path $backendDir -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceBackend -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $backendDir $_.Name) -Force
    }
    Write-Ok ("materialized {0} hash-lock Backend files" -f @(Get-ChildItem -LiteralPath $backendDir -File).Count)
}

if($BuildProject) { Publish-WpfProject }

$build=Read-Utf8Json (Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\BuildInfo.json')
$verify=Join-Path $PSScriptRoot 'Installer\Verify-PublishPayload.ps1'
Write-Step 'verify publish payload'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File $verify -PublishRoot $PublishRoot
if($LASTEXITCODE -ne 0){ Fail ("Publish payload verification failed: ExitCode={0}" -f $LASTEXITCODE) }

$package=Join-Path $PSScriptRoot 'artifacts\package'
if(Test-Path -LiteralPath $package){ Remove-Item -LiteralPath $package -Recurse -Force }
New-Item -ItemType Directory -Path $package -Force | Out-Null
$app=Join-Path $package App
New-Item -ItemType Directory -Path $app -Force | Out-Null
Copy-Item -Path (Join-Path $PublishRoot '*') -Destination $app -Recurse -Force
Get-ChildItem -LiteralPath $app -Filter '*.pdb' -File -Recurse | Remove-Item -Force
Get-ChildItem -LiteralPath $app -Filter '*.xml' -File | Where-Object { $_.Name -ne 'BuildInfo.json' } | Remove-Item -Force -ErrorAction SilentlyContinue

$launcherOut=Join-Path $PSScriptRoot 'artifacts\launcher'
Build-DesktopLauncher $launcherOut
Copy-Item -LiteralPath (Join-Path $launcherOut 'SelfHealingCenter.exe') -Destination (Join-Path $package 'SelfHealingCenter.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.txt') -Destination (Join-Path $package 'README.txt') -Force

$rootDlls=@(Get-ChildItem -LiteralPath $package -Filter '*.dll' -File).Count
if($rootDlls -ne 0){ Fail ("User package root must not contain runtime DLLs (count={0}). Put them under App\." -f $rootDlls) }
if(-not (Test-Path -LiteralPath (Join-Path $package 'SelfHealingCenter.exe'))){ Fail 'User package missing SelfHealingCenter.exe' }
if(-not (Test-Path -LiteralPath (Join-Path $package 'App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe'))){ Fail 'User package missing App inner EXE' }
if(-not (Test-Path -LiteralPath (Join-Path $package 'App\Backend\RepairCenter.ps1'))){ Fail 'User package missing App\Backend' }
if(-not (Test-Path -LiteralPath (Join-Path $package 'App\Backend\RuntimeEngine.ps1'))){ Fail 'User package missing RuntimeEngine.ps1' }
if(-not (Test-Path -LiteralPath (Join-Path $package 'App\Backend\SnapshotEngine.ps1'))){ Fail 'User package missing SnapshotEngine.ps1' }
Write-Ok 'User package is launcher + App folder'

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
$release=(Resolve-Path -LiteralPath $ReleaseDir).Path
$portable=Join-Path $release ("Windows_Game_Runtime_ASUS_SelfHealing_Portable_v{0}_win-x64.zip" -f $build.Version)
Remove-Item -LiteralPath $portable -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $portable -Force

if(-not $SkipInstaller) {
    Write-Step 'build Setup EXE'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Installer\Build-Installer.ps1') -PublishRoot $PublishRoot -SourceRoot $package -OutputDir $release
    if($LASTEXITCODE -ne 0){ Fail ("Installer build failed: ExitCode={0}" -f $LASTEXITCODE) }
}

$setup=Get-ChildItem -LiteralPath $release -Filter 'Windows_Game_Runtime_ASUS_SelfHealing_Setup_*.exe' -File | Select-Object -First 1
$setupName=$null
if($setup){ $setupName=$setup.Name }
$manifest=[ordered]@{
    Product=[string]$build.Product
    Version=[string]$build.Version
    BuildId=[string]$build.BuildId
    Runtime='win-x64'
    Platform='x64'
    WindowsAppSDK=[string]$build.WindowsAppSDK
    DotNet=[string]$build.DotNet
    Launch='desktop-shortcut-or-portable-exe'
    StartMenu=$false
    PackageLayout='SelfHealingCenter.exe + App\ + README.txt'
    GeneratedUtc=[DateTime]::UtcNow.ToString('o')
    Portable=[IO.Path]::GetFileName($portable)
    Setup=$setupName
}
$manifestPath=Join-Path $release 'RELEASE_MANIFEST.json'
$manifestJson=$manifest | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($manifestPath,$manifestJson,(New-Object System.Text.UTF8Encoding($false)))

$hashLines=New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Name -ne 'RELEASE_SHA256.txt' } | Sort-Object Name | ForEach-Object {
    $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    [void]$hashLines.Add("$h  $($_.Name)")
}
[IO.File]::WriteAllLines((Join-Path $release 'RELEASE_SHA256.txt'),$hashLines,[Text.Encoding]::ASCII)

Write-Ok ("Release directory: {0}" -f $release)
Write-Ok ("Portable: {0}" -f $portable)
Write-Ok ("Release hash list: {0}" -f (Join-Path $release 'RELEASE_SHA256.txt'))
