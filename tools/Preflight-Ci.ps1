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

Write-Step 'Engine import regression'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $Root 'Tests\EngineImport.Smoke.ps1') -Backend (Join-Path $Root 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend') -Scratch (Join-Path $env:TEMP ('WgrImportSmoke-' + [guid]::NewGuid()))
if($LASTEXITCODE -ne 0){ Fail 'Engine import regression failed' }

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

$onWindows = $env:OS -eq 'Windows_NT'
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if($onWindows -and $dotnet){
    Write-Step '.NET unit tests (WGR.Tests)'
    $testProj = Join-Path $Root 'Tests\WGR.Tests\WGR.Tests.csproj'
    & $dotnet.Source test $testProj -c Release --nologo -p:Platform=x64 --runtime win-x64
    if($LASTEXITCODE -ne 0){ Fail 'WGR.Tests failed' }
} elseif(-not $onWindows) {
    Write-Warn 'Non-Windows host; skipped WGR.Tests'
} else {
    Write-Warn 'dotnet not found; skipped WGR.Tests (CI will still run it)'
}

Write-Ok 'WhatIf / local CI preflight passed'
