#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReleaseDir)
$ErrorActionPreference = 'Stop'
# This test changes the current user's installed product. Run only on disposable CI workers.
if($env:GITHUB_ACTIONS -ne 'true') { throw 'Legacy installer E2E requires a disposable GitHub Actions worker.' }
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$build = Get-Content (Join-Path $repo 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\BuildInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$build.Version
$setup = (Resolve-Path (Join-Path $ReleaseDir "Windows_Game_Runtime_ASUS_SelfHealing_Setup_v${version}_x64.exe")).Path
$root = Join-Path $env:RUNNER_TEMP 'WGR upgrade 中文 path'
$state = Join-Path $env:LOCALAPPDATA 'WindowsGameRuntimeASUSSelfHealing\State'
$logs = Join-Path $repo 'BuildLogs\legacy-upgrade'
New-Item -ItemType Directory -Path $logs,$state,$root -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
function Put([string]$Path, [string]$Value = 'legacy fixture') {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Value)
}
function Link([string]$Path, [string]$Target) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $s = $shell.CreateShortcut($Path)
    $s.TargetPath = $Target
    $s.WorkingDirectory = Split-Path -Parent $Target
    $s.Save()
}
function Install([string]$Name, [bool]$Success = $true, [string]$Directory = $root) {
    $args = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',
        "/LOG=`"$(Join-Path $logs ($Name + '.log'))`"")
    if($Directory) { $args += "/DIR=`"$Directory`"" }
    $p = Start-Process -FilePath $setup -ArgumentList $args -PassThru
    if(-not $p.WaitForExit(180000)) { $p.Kill(); throw "Installer timed out: $Name" }
    if($Success -and $p.ExitCode -ne 0) { throw "Installer $Name exited $($p.ExitCode)" }
    if(-not $Success -and $p.ExitCode -eq 0) { throw "Unsafe upgrade unexpectedly succeeded: $Name" }
}
# Seed both the PyInstaller root layout and the App layout; keep nearby user files.
$legacy = @()
foreach($base in @($root, (Join-Path $root 'App'))) {
    foreach($rel in @('desktop_entry.exe','desktop_entry.py','desktop_entry.pyc','python3.dll','python312.dll',
        'Qt6Core.dll','Qt6Gui.dll','_internal\PySide6\Qt6Core.dll','_internal\base_library.zip',
        'PySide6\plugins\platforms\qwindows.dll','shiboken6\Shiboken.pyd')) {
        $path = Join-Path $base $rel
        Put $path
        $legacy += $path
    }
}
$preserve = @((Join-Path $state 'state-v1.db'), (Join-Path $state 'state-v1.db-wal'),
    (Join-Path $state 'state-v1.db-shm'), (Join-Path $state 'history\incident.json'),
    (Join-Path $root 'State\user-history.json'), (Join-Path $root 'history\report.txt'),
    (Join-Path $root 'other.dll'), (Join-Path $root 'notes.txt'),
    (Join-Path $env:RUNNER_TEMP 'unrelated-python\Qt6Core.dll'))
$hashes = @{}
foreach($p in $preserve) { Put $p ('preserve-' + [guid]::NewGuid()); $hashes[$p] = (Get-FileHash $p).Hash }
$desktop = [Environment]::GetFolderPath('Desktop')
$menu = [Environment]::GetFolderPath('StartMenu')
$pins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$owned = @((Join-Path $desktop '自愈中心.lnk'), (Join-Path $menu 'Programs\WGR Legacy\old.lnk'),
    (Join-Path $pins 'WGR legacy pin.lnk'))
foreach($p in $owned) { Link $p (Join-Path $root 'desktop_entry.exe') }
$unrelated = Join-Path $menu 'Programs\Unrelated\自愈中心.lnk'
Link $unrelated (Join-Path $env:WINDIR 'System32\notepad.exe')
$unrelatedHash = (Get-FileHash $unrelated).Hash
$collision = Join-Path $desktop '奥创修复中心.lnk'
Link $collision (Join-Path $env:WINDIR 'System32\notepad.exe')
$collisionHash = (Get-FileHash $collision).Hash

# Junctions must fail before ANY runtime deletion and preserve the external target.
$outside = Join-Path $env:RUNNER_TEMP 'wgr-external-data'
Put (Join-Path $outside 'keep.txt') 'outside data'
$junction = Join-Path $root '_internal\outside'
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
try { Install 'reject-junction' $false } finally { [IO.Directory]::Delete($junction) }
if(-not (Test-Path (Join-Path $outside 'keep.txt')) -or -not (Test-Path $legacy[0])) { throw 'Junction preflight deleted files.' }
# A locked legacy executable must fail before the launcher can be replaced.
$lock = [IO.File]::Open($legacy[0], 'Open', 'Read', 'None')
try { Install 'reject-locked-runtime' $false } finally { $lock.Dispose() }
if(-not (Test-Path $legacy[0])) { throw 'Locked runtime disappeared.' }
# Explicitly reject State as an installation destination.
Install 'reject-state-destination' $false $state

foreach($pass in @('legacy-upgrade','idempotent-upgrade')) {
    if($pass -eq 'idempotent-upgrade') { Install $pass $true '' } else { Install $pass }
    foreach($p in $legacy) { if(Test-Path -LiteralPath $p) { throw "Legacy residue: $p" } }
    foreach($base in @($root, (Join-Path $root 'App'))) {
        foreach($dir in @('_internal','PySide6','shiboken6')) {
            if(Test-Path -LiteralPath (Join-Path $base $dir)) { throw "Legacy directory remains: $dir" }
        }
    }
    foreach($p in $preserve) { if((Get-FileHash -LiteralPath $p).Hash -ne $hashes[$p]) { throw "User data changed: $p" } }
    if((Get-FileHash $unrelated).Hash -ne $unrelatedHash) { throw 'Unrelated shortcut changed.' }
    $launcher = Join-Path $root 'SelfHealingCenter.exe'
    $checkLinks = $owned
    if($pass -eq 'legacy-upgrade') {
        if((Get-FileHash $collision).Hash -ne $collisionHash) { throw 'Same-name unrelated desktop shortcut changed.' }
        # Remove only our collision fixture; next pass must create the product shortcut.
        Remove-Item -LiteralPath $collision
    } else { $checkLinks += $collision }
    foreach($p in $checkLinks) {
        $s = $shell.CreateShortcut($p)
        if($s.TargetPath -ne $launcher -or $s.WorkingDirectory.TrimEnd('\') -ne $root -or $s.Arguments) {
            throw "Incorrect shortcut: $p"
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'Installer\Upgrade-Legacy.ps1') `
        -InstallRoot $root -Mode Verify -ExpectedVersion $version
    if($LASTEXITCODE -ne 0) { throw 'Installed payload validation failed.' }
    Write-Host "[PASS] $pass : legacy removed, State/history/unrelated files preserved, version $version"
}
# Verify the real desktop launch reaches the inner WPF process. Preserve fixture hashes
# above before launching: the app is expected to write its own state during normal use.
# The database sentinels are deliberately arbitrary bytes, so remove only those test
# files now to allow WPF to initialize a real SQLite database on this disposable worker.
foreach($p in $preserve | Where-Object { $_ -like "$state\state-v1.db*" }) { Remove-Item -LiteralPath $p }
Start-Process -FilePath (Join-Path $desktop '奥创修复中心.lnk')
$hostProcess = $null
$deadline = [DateTime]::UtcNow.AddSeconds(45)
while([DateTime]::UtcNow -lt $deadline) {
    $hostProcess = Get-Process -Name 'WindowsGameRuntimeASUSSelfHealing.WinUI' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq (Join-Path $root 'App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe') -and $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
    if($hostProcess) { break }
    Start-Sleep -Milliseconds 500
}
if(-not $hostProcess) { throw 'Desktop launcher did not open the installed WPF window.' }
try {
    if($hostProcess.WaitForExit(3000)) { throw 'WPF host exited immediately.' }
    Write-Host '[PASS] Desktop shortcut launches installed inner WPF window.'
} finally {
    [void]$hostProcess.CloseMainWindow()
    if(-not $hostProcess.WaitForExit(10000)) { $hostProcess.Kill() }
}
