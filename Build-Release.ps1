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

$build=Read-Utf8Json (Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\BuildInfo.json')
$verify=Join-Path $PSScriptRoot 'Installer\Verify-PublishPayload.ps1'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verify -PublishRoot $PublishRoot
if($LASTEXITCODE -ne 0){ throw "Publish payload verification failed: ExitCode=$LASTEXITCODE" }

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
$release=(Resolve-Path -LiteralPath $ReleaseDir).Path
$portable=Join-Path $release ("Windows_Game_Runtime_ASUS_SelfHealing_Portable_v{0}_win-x64.zip" -f $build.Version)
Remove-Item -LiteralPath $portable -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $PublishRoot '*') -DestinationPath $portable -Force

if(-not $SkipInstaller) {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Installer\Build-Installer.ps1') -PublishRoot $PublishRoot -OutputDir $release
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
