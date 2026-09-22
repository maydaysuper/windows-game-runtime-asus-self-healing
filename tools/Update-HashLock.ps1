#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Root = '.',
    [string]$Version
)
$ErrorActionPreference='Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
$Backend = Join-Path $Root 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend'
$psdPath = Join-Path $Backend 'BuildInfo.psd1'
$jsonPath = Join-Path $Backend 'BuildInfo.json'
$map = [ordered]@{
    EngineSHA256 = 'RepairCenter.ps1'
    BrokerSHA256 = 'ElevatedBroker.ps1'
    BootstrapSHA256 = 'Bootstrap.ps1'
    UiBridgeSHA256 = 'UiBridge.ps1'
    EventReaderSHA256 = 'IncrementalEventReader.ps1'
    GpuDiagnosticsReaderSHA256 = 'GpuDiagnosticsReader.ps1'
    GpuSafeRepairSHA256 = 'GpuSafeRepair.ps1'
    ArmouryCrateSafeRepairSHA256 = 'ArmouryCrateSafeRepair.ps1'
    AtomicPolicyExecutorSHA256 = 'AtomicPolicyExecutor.ps1'
    RecipeCatalogSHA256 = 'RecipeCatalog.psd1'
}

function Hash([string]$Path){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$utf8Bom = New-Object System.Text.UTF8Encoding $true
$psd = [IO.File]::ReadAllText($psdPath)
$json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
foreach($key in $map.Keys){
    $file = Join-Path $Backend $map[$key]
    if(-not (Test-Path -LiteralPath $file)){ throw "missing $file" }
    $h = Hash $file
    if($psd -notmatch [regex]::Escape($key)){ throw "BuildInfo.psd1 missing $key" }
    $psd = [regex]::Replace($psd, "$key = '[0-9a-f]{64}'", "$key = '$h'")
    $json.$key = $h
    Write-Host ("{0} {1}" -f $key, $h)
}
$cap = Join-Path $Backend 'CapabilityBaseline.json'
if(Test-Path -LiteralPath $cap){
    $ch = Hash $cap
    $psd = [regex]::Replace($psd, "CapabilityBaselineSHA256 = '[0-9a-f]{64}'", "CapabilityBaselineSHA256 = '$ch'")
    $json.CapabilityBaselineSHA256 = $ch
}
if($Version){
    $psd = [regex]::Replace($psd, "Version = '[^']+'", "Version = '$Version'")
    $json.Version = $Version
}
[IO.File]::WriteAllText($psdPath, $psd, $utf8Bom)
$json.BuildInfoSHA256 = Hash $psdPath
$jsonText = $json | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($jsonPath, $jsonText + "`n", (New-Object System.Text.UTF8Encoding $false))
Write-Host ("BuildInfoSHA256 {0}" -f $json.BuildInfoSHA256)
Write-Host 'Hash lock updated.'
