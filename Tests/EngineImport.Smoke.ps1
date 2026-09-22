#requires -version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Backend,
    [Parameter(Mandatory=$true)][string]$Scratch
)
$ErrorActionPreference = 'Stop'
$originalLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = [IO.Path]::GetFullPath($Scratch)
    . (Join-Path $Backend 'RepairCenter.ps1') -LibraryMode
    $ErrorActionPreference = 'Stop'
    foreach ($name in @('Get-SystemSnapshot','Export-DiagnosticReport','Compare-VersionSafe','Get-RuntimeDiagnosticRows')) {
        if (-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Engine function unavailable after import: $name"
        }
    }
    if ((Compare-VersionSafe '14.44.35211.0' '14.40.33810.0') -le 0) { throw 'Runtime function invocation failed' }
    # Exercise snapshot invocation without scanning or changing the host system.
    $script:SnapshotCache = [pscustomobject]@{ RegressionMarker = 'cached-snapshot' }
    $script:SnapshotCacheTime = Get-Date
    if ((Get-SystemSnapshot).RegressionMarker -ne 'cached-snapshot') { throw 'Snapshot invocation failed' }
    $engineRow = (Get-BuildConsistency).Rows | Where-Object Item -eq 'Engine SHA256'
    if ($engineRow.Status -ne 'PASS') { throw 'Engine integrity checked the wrong script' }
    $rejected = $false
    try { Resolve-HashLockedEngineModule 'SnapshotEngine.ps1' ('0' * 64) | Out-Null }
    catch { if ($_.Exception.Message -like '*SHA256 mismatch*') { $rejected = $true } else { throw } }
    if (-not $rejected) { throw 'Hash mismatch was accepted' }
    Write-Output 'PASS: functions survive import, runtime/snapshot invocation, hash mismatch rejected.'
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
}
