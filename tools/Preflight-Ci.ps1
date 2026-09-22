#requires -version 5.1
[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
Set-Location -LiteralPath $Root
. (Join-Path $Root 'tools\BuildStatus.ps1')

Write-Step 'file reference integrity'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $Root 'tools\Check-FileReferences.ps1') -Root $Root
if($LASTEXITCODE -ne 0){ Fail 'Check-FileReferences failed' }

Write-Step 'UTF-8 BOM'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $Root 'tools\Ensure-BOM.ps1') -Verify
if($LASTEXITCODE -ne 0){ Fail 'Ensure-BOM -Verify failed' }

Write-Step 'source invariants'
$python = Get-Command python -ErrorAction SilentlyContinue
if(-not $python){ $python = Get-Command python3 -ErrorAction SilentlyContinue }
if(-not $python){ Fail 'python is required to simulate CI source_invariants' }
& $python.Source (Join-Path $Root 'Tests\source_invariants.py')
if($LASTEXITCODE -ne 0){ Fail 'source_invariants failed' }

Write-Step 'Architecture / hash-lock'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $Root 'Tests\Architecture.Tests.ps1')
if($LASTEXITCODE -ne 0){ Fail 'Architecture.Tests failed' }

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
if($pester){
    Write-Step 'Pester unit tests'
    Import-Module Pester -MinimumVersion 5.0.0
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = (Join-Path $Root 'Tests\Unit')
    $cfg.Run.Exit = $true
    $cfg.Output.Verbosity = 'Normal'
    Invoke-Pester -Configuration $cfg
} else {
    Write-Warn 'Pester 5 not installed; skipped (CI will still run it)'
}

Write-Ok 'WhatIf / local CI preflight passed'
