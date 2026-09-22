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
Write-Host '[PASS] release layout'
