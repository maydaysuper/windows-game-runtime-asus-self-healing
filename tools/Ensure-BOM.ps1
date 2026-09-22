#requires -version 5.1
[CmdletBinding()]
param(
    [string]$Root = '.',
    [switch]$Verify,
    [switch]$Write
)
$ErrorActionPreference='Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
$utf8Bom = New-Object System.Text.UTF8Encoding $true
$targets = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -in '.ps1','.psm1' -and
        $_.FullName -notmatch '\\.git\\' -and
        $_.Name -ne 'Launch-Win11.cmd'
    }
$bad = New-Object System.Collections.Generic.List[string]
foreach($file in $targets){
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if($hasBom){ continue }
    if($Verify){ [void]$bad.Add($file.FullName); continue }
    if($Write){
        $text = [IO.File]::ReadAllText($file.FullName)
        [IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        Write-Host ("BOM written: " + $file.FullName)
    }
}
if($Verify -and $bad.Count -gt 0){
    Write-Host 'UTF-8 BOM check FAILED' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host (" - " + $_) }
    exit 1
}
if($Verify){ Write-Host ('UTF-8 BOM check passed ({0} scripts).' -f @($targets).Count) }
exit 0
