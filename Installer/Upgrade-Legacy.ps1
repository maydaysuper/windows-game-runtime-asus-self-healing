#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [ValidateSet('Clean','Verify')][string]$Mode = 'Clean',
    [string]$ExpectedVersion = '4.6.3',
    [string]$LogPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Note([string]$Message) {
    Write-Host $Message
    if($LogPath) { Add-Content -LiteralPath $LogPath -Value $Message -Encoding UTF8 }
}
function FullPath([string]$Path) {
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}
function IsWithin([string]$Path, [string]$Parent) {
    return $Path.Equals($Parent, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($Parent + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-NoReparseAncestors([string]$Path) {
    $p = $Path
    while($p) {
        if(Test-Path -LiteralPath $p) {
            if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing reparse point: $p"
            }
        }
        $parent = Split-Path -Parent $p
        if($parent -eq $p) { break }
        $p = $parent
    }
}
# Explicit traversal checks links before descending, including nested junctions.
function Get-SafeTree([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing reparse point: $Path" }
    if($item.PSIsContainer) {
        foreach($child in Get-ChildItem -LiteralPath $Path -Force) { Get-SafeTree $child.FullName }
    }
    $item
}

try {
    if(-not [IO.Path]::IsPathRooted($InstallRoot) -or $InstallRoot.StartsWith('\\')) {
        throw 'InstallRoot must be a local absolute path.'
    }
    $root = FullPath $InstallRoot
    $dataRoot = FullPath (Join-Path $env:LOCALAPPDATA 'WindowsGameRuntimeASUSSelfHealing')
    # Never install into, clean, or contain the user data tree (State, history, logs).
    if((IsWithin $root $dataRoot) -or (IsWithin $dataRoot $root)) { throw 'Install directory overlaps user data.' }
    foreach($special in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA,
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'),
        [Environment]::GetFolderPath('Desktop'), [IO.Path]::GetPathRoot($root))) {
        if($special -and $root -eq (FullPath $special)) { throw "Unsafe install directory: $root" }
    }
    Assert-NoReparseAncestors $root
    $app = Join-Path $root 'App'
    Assert-NoReparseAncestors $app
    $launcher = Join-Path $root 'SelfHealingCenter.exe'
    $inner = Join-Path $app 'WindowsGameRuntimeASUSSelfHealing.WinUI.exe'
    if($Mode -eq 'Verify') {
        foreach($exe in @($launcher, $inner)) {
            if(-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing executable: $exe" }
            $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion
            if($version -ne "$ExpectedVersion.0") { throw "Version mismatch: $exe ($version)" }
        }
        foreach($name in @('coreclr.dll','hostfxr.dll','hostpolicy.dll','wpfgfx_cor3.dll',
            'PresentationNative_cor3.dll','e_sqlite3.dll','Backend\BuildInfo.json')) {
            if(-not (Test-Path -LiteralPath (Join-Path $app $name) -PathType Leaf)) { throw "Missing runtime: $name" }
        }
        $build = Get-Content -LiteralPath (Join-Path $app 'Backend\BuildInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if($build.Version -ne $ExpectedVersion) { throw 'Installed BuildInfo version mismatch.' }
        $output = & $launcher --version 2>&1 | Out-String
        if($LASTEXITCODE -ne 0 -or $output -notmatch ('\b' + [regex]::Escape($ExpectedVersion) + '(?:\.0)?\b')) {
            throw "Launcher --version failed: $output"
        }
        Note "[PASS] Installed launcher and WPF host $ExpectedVersion : $($output.Trim())"
        exit 0
    }

    # Only these runtime names at the installation root or its App subdirectory.
    # No recursive filename search through user folders; no broad *.exe / *.dll deletion.
    $files = @('desktop_entry.exe','desktop_entry.py','desktop_entry.pyc','python*.dll','Qt6*.dll')
    $dirs = @('_internal','PySide6','shiboken6')
    $remove = @()
    foreach($base in @($root, $app)) {
        if(-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        foreach($item in Get-ChildItem -LiteralPath $base -Force) {
            if(($item.PSIsContainer -and $item.Name -in $dirs) -or
                (-not $item.PSIsContainer -and @($files | Where-Object { $item.Name -like $_ }).Count -gt 0)) {
                Assert-NoReparseAncestors $item.FullName
                $remove += @(Get-SafeTree $item.FullName)
            }
        }
    }
    # Preflight the complete deletion set before deleting anything. Locked files fail closed.
    foreach($item in $remove) {
        if(-not $item.PSIsContainer) {
            $stream = [IO.File]::Open($item.FullName, 'Open', 'ReadWrite', 'None')
            $stream.Dispose()
        }
    }
    foreach($item in $remove) {
        Remove-Item -LiteralPath $item.FullName -Force
        Note "Removed legacy runtime: $($item.FullName)"
    }

    # Match shortcut TARGETS, never shortcut names. Do not touch other profiles or
    # taskbar registry/CloudStore state. Retarget existing pins to keep their identity.
    $shell = New-Object -ComObject WScript.Shell
    $targets = @()
    foreach($base in @($root, $app)) {
        $targets += Join-Path $base 'desktop_entry.exe'
        $targets += Join-Path $base 'desktop_entry.py'
        $targets += Join-Path $base 'WindowsGameRuntimeASUSSelfHealing.WinUI.exe'
    }
    $surfaces = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('StartMenu'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned')
    )
    # All-users links are inspected only when Setup is actually elevated.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $surfaces += [Environment]::GetFolderPath('CommonDesktopDirectory')
        $surfaces += [Environment]::GetFolderPath('CommonStartMenu')
    }
    function Find-Links([string]$Directory) {
        foreach($item in Get-ChildItem -LiteralPath $Directory -Force) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if($item.PSIsContainer) { Find-Links $item.FullName }
            elseif($item.Extension -eq '.lnk') { $item }
        }
    }
    foreach($surface in ($surfaces | Where-Object { $_ } | Select-Object -Unique)) {
        if(-not (Test-Path -LiteralPath $surface -PathType Container)) { continue }
        Assert-NoReparseAncestors $surface
        foreach($link in Find-Links $surface) {
            try {
                $shortcut = $shell.CreateShortcut($link.FullName)
                if(-not $shortcut.TargetPath) { continue }
                $target = FullPath $shortcut.TargetPath
                $owned = $target -in $targets
                # Python interpreter shortcuts are owned only for an exact, single script argument.
                if(-not $owned -and [IO.Path]::GetFileName($target) -in @('python.exe','pythonw.exe')) {
                    $arg = $shortcut.Arguments.Trim().Trim('"')
                    $owned = $arg -in @((Join-Path $root 'desktop_entry.py'), (Join-Path $app 'desktop_entry.py'))
                }
            } catch {
                Note "Skipped unreadable shortcut: $($link.FullName)"
                continue
            }
            if(-not $owned) { continue }
            # Preserve link name/location (including user pins); replace only the obsolete launch target.
            $shortcut.TargetPath = $launcher
            $shortcut.Arguments = ''
            $shortcut.WorkingDirectory = $root
            $shortcut.IconLocation = "$launcher,0"
            $shortcut.Save()
            Note "Retargeted legacy shortcut: $($link.FullName)"
        }
    }
    Note '[PASS] Legacy upgrade cleanup complete; user data preserved.'
    exit 0
} catch {
    Note "[FAIL] $($_.Exception.Message)"
    exit 1
}
