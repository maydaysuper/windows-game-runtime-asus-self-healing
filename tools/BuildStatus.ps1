#requires -version 5.1
function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ('==> ' + $Text) -ForegroundColor Cyan
}
function Write-Ok {
    param([string]$Text)
    Write-Host ('[PASS] ' + $Text) -ForegroundColor Green
}
function Write-Warn {
    param([string]$Text)
    Write-Host ('[WARN] ' + $Text) -ForegroundColor Yellow
}
function Fail {
    param([string]$Text)
    Write-Host ('[FAIL] ' + $Text) -ForegroundColor Red
    throw $Text
}
