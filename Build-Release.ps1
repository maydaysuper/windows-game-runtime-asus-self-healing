#requires -version 5.1
[CmdletBinding()]
param(
    [string]$PublishRoot = (Join-Path $PSScriptRoot 'artifacts\publish'),
    [string]$ReleaseDir = (Join-Path $PSScriptRoot 'artifacts\release'),
    [switch]$SkipInstaller
)
$ErrorActionPreference='Stop'

function Read-Utf8Json([string]$Path) {
    $utf8=New-Object System.Text.UTF8Encoding($false,$true)
    return ([IO.File]::ReadAllText($Path,$utf8) | ConvertFrom-Json)
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
    if(-not (Test-Path -LiteralPath $csc)) { throw 'Cannot compile desktop launcher: dotnet net48 / csc.exe missing.' }
    $icon=Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Assets\app.ico'
    $src=Join-Path $PSScriptRoot 'Launcher\SelfHealingCenter.cs'
    $cscArgs=@('/nologo','/t:winexe','/platform:x64',"/win32icon:$icon","/out:$published",'/utf8output',$src)
    & $csc @cscArgs
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $published)) { throw 'csc launcher compile failed.' }
}

$build=Read-Utf8Json (Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\BuildInfo.json')
$verify=Join-Path $PSScriptRoot 'Installer\Verify-PublishPayload.ps1'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verify -PublishRoot $PublishRoot
if($LASTEXITCODE -ne 0){ throw "Publish payload verification failed: ExitCode=$LASTEXITCODE" }

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
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '使用说明.txt') -Destination (Join-Path $package '使用说明.txt') -Force

$rootDlls=@(Get-ChildItem -LiteralPath $package -Filter '*.dll' -File).Count
if($rootDlls -ne 0){ throw "User package root must not contain runtime DLLs (count=$rootDlls). Put them under App\." }
if(-not (Test-Path -LiteralPath (Join-Path $package 'SelfHealingCenter.exe'))){ throw 'User package missing SelfHealingCenter.exe' }
if(-not (Test-Path -LiteralPath (Join-Path $package 'App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe'))){ throw 'User package missing App inner EXE' }
if(-not (Test-Path -LiteralPath (Join-Path $package 'App\Backend\RepairCenter.ps1'))){ throw 'User package missing App\Backend' }
Write-Host "[PASS] User package is launcher + App folder"

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
$release=(Resolve-Path -LiteralPath $ReleaseDir).Path
$portable=Join-Path $release ("Windows_Game_Runtime_ASUS_SelfHealing_Portable_v{0}_win-x64.zip" -f $build.Version)
Remove-Item -LiteralPath $portable -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $portable -Force

if(-not $SkipInstaller) {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Installer\Build-Installer.ps1') -PublishRoot $PublishRoot -SourceRoot $package -OutputDir $release
    if($LASTEXITCODE -ne 0){ throw "Installer build failed: ExitCode=$LASTEXITCODE" }
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
    PackageLayout='SelfHealingCenter.exe + App\ + 使用说明.txt'
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

Write-Host "[PASS] Release directory: $release"
Write-Host "[PASS] Portable: $portable"
Write-Host "[PASS] Release hash list: $(Join-Path $release 'RELEASE_SHA256.txt')"
