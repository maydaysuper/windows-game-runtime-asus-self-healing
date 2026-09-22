#requires -version 5.1
[CmdletBinding()]
param([string]$Root = '.')
$ErrorActionPreference='Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
$Failures = New-Object System.Collections.Generic.List[string]

function AddFail([string]$Text){ [void]$Failures.Add($Text) }
function Exists([string]$Rel){
    $p = Join-Path $Root ($Rel -replace '/','\')
    return Test-Path -LiteralPath $p
}

# 1) Workflow / test scripts referenced with ./path must exist.
$refFiles = @()
$refFiles += Get-ChildItem -LiteralPath (Join-Path $Root '.github') -Recurse -File -ErrorAction SilentlyContinue
$refFiles += Get-ChildItem -LiteralPath (Join-Path $Root 'Tests') -Recurse -File -ErrorAction SilentlyContinue
$refFiles += Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -File -ErrorAction SilentlyContinue
foreach($file in $refFiles){
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach($m in [regex]::Matches($text, '(?m)(?:^|[\s"=])(\./(?:Tests|tools|Installer|scripts)/[A-Za-z0-9._\-]+(?:/[A-Za-z0-9._\-]+)*)')){
        $rel = $m.Groups[1].Value.TrimStart('.', '/', '\')
        if(-not (Exists $rel)){ AddFail ("{0} references missing {1}" -f $file.Name, $rel) }
    }
}

# 2) Hash-lock maps in Architecture.Tests and source_invariants must point at real Backend files.
$arch = Join-Path $Root 'Tests\Architecture.Tests.ps1'
if(Test-Path -LiteralPath $arch){
    $archText = [IO.File]::ReadAllText($arch)
    foreach($m in [regex]::Matches($archText, "SHA256='([A-Za-z0-9._\-]+\.(?:ps1|psd1))'")){
        $name = $m.Groups[1].Value
        $p = Join-Path $Root ('WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\' + $name)
        if(-not (Test-Path -LiteralPath $p)){ AddFail ("Architecture.Tests hashMap missing Backend\{0}" -f $name) }
    }
    foreach($m in [regex]::Matches($archText, "foreach\(\$launcherName in @\(([^)]+)\)\)")){
        $inner = $m.Groups[1].Value
        foreach($q in [regex]::Matches($inner, "'([^']+)'")){
            $name = $q.Groups[1].Value
            if(-not (Exists $name)){ AddFail ("Architecture.Tests launcher missing {0}" -f $name) }
        }
    }
}

$inv = Join-Path $Root 'Tests\source_invariants.py'
if(Test-Path -LiteralPath $inv){
    $invText = [IO.File]::ReadAllText($inv)
    foreach($m in [regex]::Matches($invText, "'([A-Za-z0-9]+)':'([A-Za-z0-9._\-]+\.(?:ps1|psd1))'")){
        $name = $m.Groups[2].Value
        $p = Join-Path $Root ('WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\' + $name)
        if(-not (Test-Path -LiteralPath $p)){ AddFail ("source_invariants expected_files missing Backend\{0}" -f $name) }
    }
}

# 3) Files deleted vs origin/main or HEAD~1 must not remain referenced by Tests/CI/tools.
$deleted = @()
try {
    git -C $Root rev-parse --verify origin/main 1>$null 2>$null
    if($LASTEXITCODE -eq 0){
        $deleted = @(git -C $Root diff --name-only --diff-filter=D origin/main...HEAD)
    } else {
        git -C $Root rev-parse --verify HEAD~1 1>$null 2>$null
        if($LASTEXITCODE -eq 0){
            $deleted = @(git -C $Root diff --name-only --diff-filter=D HEAD~1..HEAD)
        }
    }
} catch {}

$scan = @()
$scan += Get-ChildItem -LiteralPath (Join-Path $Root 'Tests') -Recurse -File -ErrorAction SilentlyContinue
$scan += Get-ChildItem -LiteralPath (Join-Path $Root '.github') -Recurse -File -ErrorAction SilentlyContinue
$scan += Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Recurse -File -ErrorAction SilentlyContinue
foreach($rel in $deleted){
    $leaf = Split-Path -Leaf $rel
    if(-not $leaf){ continue }
    foreach($file in $scan){
        if(Select-String -Path $file.FullName -Pattern ([regex]::Escape($leaf)) -SimpleMatch -Quiet -ErrorAction SilentlyContinue){
            AddFail ("deleted {0} still referenced in {1}" -f $rel, $file.Name)
        }
    }
}

if($Failures.Count -gt 0){
    Write-Host 'File reference check FAILED' -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host (" - " + $_) }
    exit 1
}
Write-Host 'File reference check passed.'
exit 0
