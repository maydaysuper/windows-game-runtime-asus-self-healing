#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SetupPath,
    [Parameter(Mandatory=$true)][ValidateSet('Win10','Win11')][string]$ExpectedOS,
    [switch]$DisposableClient
)
$ErrorActionPreference = 'Stop'
if(-not $DisposableClient) { throw 'Run only on a disposable Windows client VM: pass -DisposableClient.' }
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if($os.ProductType -ne 1) { throw 'This gate requires Windows client, not Windows Server.' }
if(-not [Environment]::Is64BitOperatingSystem) { throw 'This gate requires x64 Windows.' }
if($ExpectedOS -eq 'Win10' -and ($build -lt 19044 -or $build -ge 22000)) {
    throw "Expected Windows 10 build 19044–21999; found $build."
}
if($ExpectedOS -eq 'Win11' -and $build -lt 22000) { throw "Expected Windows 11; found build $build." }
$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if($dotnet -and (& $dotnet.Source --list-sdks 2>$null)) {
    throw 'This is not a clean client: .NET SDK is installed.'
}
$setup = (Resolve-Path -LiteralPath $SetupPath).Path
$version = [regex]::Match([IO.Path]::GetFileName($setup), 'Setup_v(\d+\.\d+\.\d+)_x64\.exe$').Groups[1].Value
if(-not $version) { throw "Cannot read expected version from $setup" }
$root = Join-Path $env:LOCALAPPDATA ('Programs\WGR-CleanClient-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $env:LOCALAPPDATA 'WindowsGameRuntimeASUSSelfHealing\State'
$sentinel = Join-Path $state ('clean-client-' + [guid]::NewGuid().ToString('N') + '.txt')
New-Item -ItemType Directory -Path $state -Force | Out-Null
[IO.File]::WriteAllText($sentinel, 'preserve-this-user-data')
try {
    $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',"/DIR=`"$root`"")
    $installer = Start-Process -FilePath $setup -ArgumentList $arguments -PassThru
    if(-not $installer.WaitForExit(180000)) { $installer.Kill(); throw 'Installer timed out.' }
    if($installer.ExitCode -ne 0) { throw "Installer exited $($installer.ExitCode)." }
    if([IO.File]::ReadAllText($sentinel) -ne 'preserve-this-user-data') { throw 'State was modified.' }
    $launcher = Join-Path $root 'SelfHealingCenter.exe'
    $inner = Join-Path $root 'App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe'
    if(-not (Test-Path -LiteralPath $launcher) -or -not (Test-Path -LiteralPath $inner)) { throw 'Installed EXEs missing.' }
    $output = & $launcher --diagnose-install 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape($version) -or
       $output -notmatch [regex]::Escape($launcher) -or
       $output -notmatch [regex]::Escape($inner)) { throw "Installed launcher diagnostics failed: $output" }
    $innerVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($inner).FileVersion
    if($innerVersion -ne "$version.0") { throw "Inner version mismatch: $innerVersion" }
    $before = @(Get-CimInstance Win32_Process -Filter "Name='WindowsGameRuntimeASUSSelfHealing.WinUI.exe'" | Select-Object -ExpandProperty ProcessId)
    Start-Process -FilePath $launcher -WorkingDirectory $root
    $launched = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while([DateTime]::UtcNow -lt $deadline) {
        $launched = Get-CimInstance Win32_Process -Filter "Name='WindowsGameRuntimeASUSSelfHealing.WinUI.exe'" |
            Where-Object { $_.ProcessId -notin $before -and $_.ExecutablePath -eq $inner } | Select-Object -First 1
        if($launched) { break }
        Start-Sleep -Milliseconds 500
    }
    if(-not $launched) { throw 'Launcher did not start the installed inner WPF EXE.' }
    Start-Sleep -Seconds 3
    $window = Get-Process -Id $launched.ProcessId -ErrorAction SilentlyContinue
    if(-not $window -or $window.MainWindowHandle -eq 0) { throw 'WPF window did not remain open.' }
    Write-Host "[PASS] $ExpectedOS build $build: clean install, launcher v$version, WPF started, State preserved"
} finally {
    if($launched) { Stop-Process -Id $launched.ProcessId -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
    # Leave the installed app and its logs in this disposable VM for failure diagnosis.
}
