#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReleaseDir)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = (Resolve-Path -LiteralPath $ReleaseDir).Path
$list = Join-Path $root 'RELEASE_SHA256.txt'
if(-not (Test-Path -LiteralPath $list)) { throw 'RELEASE_SHA256.txt missing' }
Get-Content -LiteralPath $list | Where-Object { $_ -match '^[0-9a-f]{64}\s+\S+' } | ForEach-Object {
    $hash, $name = $_ -split '\s+', 2
    $path = Join-Path $root $name.Trim()
    if(-not (Test-Path -LiteralPath $path)) { throw "Release file missing: $name" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if($actual -ne $hash.ToLowerInvariant()) { throw "SHA256 mismatch for $name" }
    Write-Host "[PASS] hash $name"
}
$zip = Get-Item (Join-Path $root 'Windows_Game_Runtime_ASUS_SelfHealing_Portable_v*_win-x64.zip') | Select-Object -First 1
if(-not $zip) { throw 'Portable ZIP missing' }
$archive = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
try {
    $names = @($archive.Entries | ForEach-Object { ($_.FullName -replace '\\','/').TrimStart('/') })
    foreach($need in @(
        'SelfHealingCenter.exe',
        'README.txt',
        'App/WindowsGameRuntimeASUSSelfHealing.WinUI.exe',
        'App/Backend/RepairCenter.ps1',
        'App/Backend/RuntimeEngine.ps1',
        'App/Backend/SnapshotEngine.ps1',
        'App/Backend/ArmouryCrateSafeRepair.ps1',
        'App/wpfgfx_cor3.dll'
    )) {
        if($names -notcontains $need) { throw "ZIP missing $need" }
        Write-Host "[PASS] zip $need"
    }
} finally { $archive.Dispose() }

$buildJson = Join-Path $PSScriptRoot '..\..\WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\BuildInfo.json'
$expected = $null
if(Test-Path -LiteralPath $buildJson){
    $utf8 = New-Object System.Text.UTF8Encoding($false,$true)
    $expected = ([IO.File]::ReadAllText((Resolve-Path $buildJson), $utf8) | ConvertFrom-Json).Version
}
$extract = Join-Path ([IO.Path]::GetTempPath()) ('wgr-e2e-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $extract -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extract -Force
    $launcher = Join-Path $extract 'SelfHealingCenter.exe'
    if(-not (Test-Path -LiteralPath $launcher)) { throw 'extracted launcher missing' }
    $inner = Join-Path $extract 'App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe'
    $innerVer = [Diagnostics.FileVersionInfo]::GetVersionInfo($inner).FileVersion
    if($expected -and $innerVer -notlike "$expected*") { throw "inner FileVersion=$innerVer expected $expected" }
    Write-Host ("[PASS] inner FileVersion=$innerVer")
    $output = & $launcher --version 2>&1 | Out-String
    if($LASTEXITCODE -ne 0) { throw ("launcher --version exit {0}: {1}" -f $LASTEXITCODE,$output) }
    if($expected -and $output -notmatch [regex]::Escape([string]$expected)) { throw "launcher --version missing $expected : $output" }
    Write-Host ("[PASS] launcher --version {0}" -f $output.Trim())
    $diagnostics = & $launcher --diagnose-install 2>&1 | Out-String
    if($LASTEXITCODE -ne 0) { throw "launcher --diagnose-install failed: $diagnostics" }
    if($diagnostics -notmatch [regex]::Escape($launcher) -or
       $diagnostics -notmatch [regex]::Escape($inner) -or
       $diagnostics -notmatch 'OS version:' -or
       $diagnostics -notmatch 'State:') { throw "Install diagnostics incomplete: $diagnostics" }
    Write-Host '[PASS] launcher reports actual install paths and OS version'
} finally {
    try { Remove-Item -LiteralPath $extract -Recurse -Force } catch {}
}
Write-Host '[PASS] release layout'
