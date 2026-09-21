#requires -version 5.1
[CmdletBinding()]
param(
    [string]$LogRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'BuildLogs')
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $LogRoot)) {
    Write-Host "No BuildLogs directory: $LogRoot"
    exit 0
}
$pattern = '\berror (CS|WMC|MSB|NETSDK|NU)\d+'
$hits = @()
Get-ChildItem -LiteralPath $LogRoot -File -Recurse -Include *.log,*.txt | ForEach-Object {
    $hits += @(Select-String -LiteralPath $_.FullName -Pattern $pattern -ErrorAction SilentlyContinue)
}
if ($hits.Count -eq 0) {
    Write-Host 'No CS/WMC/MSB/NETSDK/NU error tokens found in BuildLogs.'
    exit 0
}
Write-Host "==== Compiler/SDK errors ({0}) ====" -f $hits.Count
$hits | Select-Object -First 80 | ForEach-Object {
    Write-Host ("{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim())
}
exit 0
