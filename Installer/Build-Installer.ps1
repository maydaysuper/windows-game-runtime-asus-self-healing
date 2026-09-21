#requires -version 5.1
[CmdletBinding()]
param(
    [string]$PublishRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\publish'),
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
$source=(Resolve-Path -LiteralPath $PublishRoot).Path
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
$setup=Get-ChildItem -LiteralPath $OutputDir -Filter '*.exe' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
if(-not $setup){ throw 'Setup EXE was not created.' }
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $setup.FullName).Hash.ToLowerInvariant()
$hashPath=$setup.FullName+'.sha256.txt'
[IO.File]::WriteAllText($hashPath,"$hash  $($setup.Name)`r`n",[Text.Encoding]::ASCII)
Write-Host "[PASS] Setup: $($setup.FullName)"
Write-Host "[PASS] SHA256: $hash"
Write-Host "[PASS] SHA256 file: $hashPath"
