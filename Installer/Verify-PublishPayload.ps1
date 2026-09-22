#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PublishRoot,
    [string]$ManifestPath
)
$ErrorActionPreference='Stop'

function Read-Utf8Json([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)) { throw "Missing JSON: $Path" }
    $utf8 = New-Object System.Text.UTF8Encoding($false,$true)
    $text = [IO.File]::ReadAllText($Path,$utf8)
    return ($text | ConvertFrom-Json)
}


function Assert-PeX64([string]$Path) {
    $fs=[IO.File]::OpenRead($Path)
    try {
        $br=New-Object IO.BinaryReader($fs)
        if($br.ReadUInt16() -ne 0x5A4D) { throw "Not a PE/MZ executable: $Path" }
        $fs.Seek(0x3C,[IO.SeekOrigin]::Begin) | Out-Null
        $peOffset=$br.ReadInt32()
        $fs.Seek($peOffset,[IO.SeekOrigin]::Begin) | Out-Null
        if($br.ReadUInt32() -ne 0x00004550) { throw "Invalid PE signature: $Path" }
        $machine=$br.ReadUInt16()
        if($machine -ne 0x8664) { throw ("Expected x64 PE machine 0x8664, actual=0x{0:X4}: {1}" -f $machine,$Path) }
    } finally { $fs.Dispose() }
    Write-Host "[PASS] PE machine x64: $Path"
}

function Assert-Hash([string]$Path,[string]$Expected,[string]$Label) {
    if(-not (Test-Path -LiteralPath $Path)) { throw "$Label missing: $Path" }
    if([string]::IsNullOrWhiteSpace($Expected)) { throw "$Label expected SHA256 missing" }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if($actual -ne $Expected.ToLowerInvariant()) {
        throw "$Label SHA256 mismatch. expected=$Expected actual=$actual path=$Path"
    }
    Write-Host "[PASS] $Label $actual"
}

$root=(Resolve-Path -LiteralPath $PublishRoot).Path
$backend=Join-Path $root 'Backend'
$exe=Join-Path $root 'WindowsGameRuntimeASUSSelfHealing.WinUI.exe'
$buildInfoPath=Join-Path $backend 'BuildInfo.json'
$buildInfoPsd1=Join-Path $backend 'BuildInfo.psd1'

if(-not (Test-Path -LiteralPath $exe)) { throw "Published EXE missing: $exe" }
Assert-PeX64 $exe
if(-not (Test-Path -LiteralPath $backend)) { throw "Published Backend directory missing: $backend" }

$runtimeFiles=@(
    'wpfgfx_cor3.dll',
    'PresentationNative_cor3.dll',
    'e_sqlite3.dll'
)
foreach($name in $runtimeFiles) {
    $runtimePath=Join-Path $root $name
    if(-not (Test-Path -LiteralPath $runtimePath)) {
        throw "Self-contained WPF runtime file missing (PublishSingleFile is forbidden): $runtimePath"
    }
    Assert-PeX64 $runtimePath
}
$dllCount=@(Get-ChildItem -LiteralPath $root -Filter '*.dll' -File).Count
if($dllCount -lt 8) {
    throw "Published payload looks like PublishSingleFile (dllCount=$dllCount). WPF native DLLs must sit next to the EXE or Setup will not launch."
}
Write-Host "[PASS] Self-contained WPF runtime beside EXE (dllCount=$dllCount)"

$build=Read-Utf8Json $buildInfoPath
$required=@{
    'RepairCenter.ps1'=[string]$build.EngineSHA256
    'ElevatedBroker.ps1'=[string]$build.BrokerSHA256
    'Bootstrap.ps1'=[string]$build.BootstrapSHA256
    'UiBridge.ps1'=[string]$build.UiBridgeSHA256
    'IncrementalEventReader.ps1'=[string]$build.EventReaderSHA256
    'GpuDiagnosticsReader.ps1'=[string]$build.GpuDiagnosticsReaderSHA256
    'GpuSafeRepair.ps1'=[string]$build.GpuSafeRepairSHA256
    'ArmouryCrateSafeRepair.ps1'=[string]$build.ArmouryCrateSafeRepairSHA256
    'AtomicPolicyExecutor.ps1'=[string]$build.AtomicPolicyExecutorSHA256
    'RecipeCatalog.psd1'=[string]$build.RecipeCatalogSHA256
    'BuildInfo.psd1'=[string]$build.BuildInfoSHA256
    'CapabilityBaseline.json'=[string]$build.CapabilityBaselineSHA256
}
foreach($name in ($required.Keys | Sort-Object)) {
    Assert-Hash (Join-Path $backend $name) $required[$name] "Backend/$name"
}

$legacy=@{
    'module_pv.ps1'=[string]$build.LegacyAdapterHashes.PV
    'module_holtek.ps1'=[string]$build.LegacyAdapterHashes.HOLTEK
    'module_ene.ps1'=[string]$build.LegacyAdapterHashes.ENE
}
foreach($name in ($legacy.Keys | Sort-Object)) {
    Assert-Hash (Join-Path $backend $name) $legacy[$name] "Legacy/$name"
}

$versionInfo=(Get-Item -LiteralPath $exe).VersionInfo
if($versionInfo.FileVersion -and -not $versionInfo.FileVersion.StartsWith([string]$build.Version)) { throw ("EXE FileVersion mismatch. BuildInfo={0} FileVersion={1}" -f $build.Version,$versionInfo.FileVersion) }
Write-Host ("[PASS] EXE {0} ProductVersion={1} FileVersion={2}" -f $exe,$versionInfo.ProductVersion,$versionInfo.FileVersion)

if(-not $ManifestPath) { $ManifestPath=Join-Path $root 'PAYLOAD_SHA256.txt' }
$lines=New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.FullName -ne $ManifestPath } | Sort-Object FullName | ForEach-Object {
    $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    $rel=$_.FullName.Substring($root.Length).TrimStart('\')
    [void]$lines.Add("$h  $rel")
}
[IO.File]::WriteAllLines($ManifestPath,$lines,(New-Object System.Text.UTF8Encoding($false)))
Write-Host "[PASS] Payload manifest: $ManifestPath ($($lines.Count) files)"
Write-Host "[PASS] Publish payload trust chain verified for v$($build.Version) / $($build.BuildId)"
