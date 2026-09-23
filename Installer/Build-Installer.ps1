#requires -version 5.1
[CmdletBinding()]
param(
    [string]$PublishRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\publish'),
    [string]$SourceRoot = '',
    [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\installer')
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot

function Read-Utf8Json([string]$Path) {
    $utf8=New-Object System.Text.UTF8Encoding($false,$true)
    return ([IO.File]::ReadAllText($Path,$utf8) | ConvertFrom-Json)
}

$build=Read-Utf8Json (Join-Path $root 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\BuildInfo.json')
$verify=Join-Path $PSScriptRoot 'Verify-PublishPayload.ps1'
if(-not (Test-Path -LiteralPath $PublishRoot)){ throw "Publish root not found: $PublishRoot" }
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verify -PublishRoot $PublishRoot
if($LASTEXITCODE -ne 0){ throw "Publish payload verification failed: ExitCode=$LASTEXITCODE" }

if([string]::IsNullOrWhiteSpace($SourceRoot)){ $SourceRoot = $PublishRoot }
if(-not (Test-Path -LiteralPath $SourceRoot)){ throw "Installer source root not found: $SourceRoot" }
$launcher=Join-Path $SourceRoot 'SelfHealingCenter.exe'
$inner=Join-Path $SourceRoot 'App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe'
if(-not (Test-Path -LiteralPath $launcher)){ throw "Desktop launcher missing from installer source: $launcher" }
if(-not (Test-Path -LiteralPath $inner)){ throw "Inner WPF EXE missing from installer source: $inner" }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Upgrade-Legacy.ps1') -Mode Verify -InstallRoot (Resolve-Path $SourceRoot).Path -ExpectedVersion $build.Version
if($LASTEXITCODE -ne 0) { throw 'Installer source version/layout validation failed.' }
$iscc = @(
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if(-not $iscc){ throw 'Inno Setup 7/6 (ISCC.exe) not found.' }
Write-Host "ISCC: $iscc"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$source=(Resolve-Path -LiteralPath $SourceRoot).Path
$out=(Resolve-Path -LiteralPath $OutputDir).Path
$iss=Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.iss'
$isccArgs=@(
    "/DMyAppVersion=$($build.Version)",
    "/DSourceRoot=$source",
    "/DOutputDir=$out",
    $iss
)
& $iscc @isccArgs
if($LASTEXITCODE -ne 0){ throw "Inno Setup failed, ExitCode=$LASTEXITCODE" }
$setup=Get-Item -LiteralPath (Join-Path $OutputDir ("Windows_Game_Runtime_ASUS_SelfHealing_Setup_v{0}_x64.exe" -f $build.Version))
$setupVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($setup.FullName)
$numericVersion = '{0}.{1}.{2}.{3}' -f $setupVersion.FileMajorPart, $setupVersion.FileMinorPart, $setupVersion.FileBuildPart, $setupVersion.FilePrivatePart
Write-Host "Setup version: numeric=$numericVersion text=$($setupVersion.FileVersion) expected=$($build.Version).0"
if($numericVersion -ne "$($build.Version).0") { throw "Setup FileVersion mismatch: $numericVersion" }
if(-not $setup){ throw 'Setup EXE was not created.' }
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $setup.FullName).Hash.ToLowerInvariant()
$hashPath=$setup.FullName+'.sha256.txt'
[IO.File]::WriteAllText($hashPath,"$hash  $($setup.Name)`r`n",[Text.Encoding]::ASCII)
Write-Host "[PASS] Setup: $($setup.FullName)"
Write-Host "[PASS] SHA256: $hash"
Write-Host "[PASS] SHA256 file: $hashPath"
