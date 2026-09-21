#requires -version 5.1
<#
ASUS Armoury Crate 4152 - ENE M2 HAL Clean Fix v1.1

Diagnosed component:
  UI item: ASUS Core HAL
  ProfileID: 44066
  Package: AacSetup_ENE_EHD_M2.exe
  MSI Product: ENE_EHD_M2_HAL
  MSI ProductCode: {37A48B7F-D4EA-4863-844E-A284E2AA3C5D}
  UpgradeCode: {81613800-C5C6-4E2F-ACBD-5D8F169BC6D8}
  Current/desired bundle: 1.0.18.0
  Runtime HAL still reports: 1.0.17.0
  Current Burn provider: {04565624-f1c4-428e-80e8-0c3af195fb79}
  Previous Burn bundle: {6a0e18d7-c33b-4c8c-aa31-4beedf5956c6}

Observed reason for 4152:
  Burn/MSI returns success, MSI ProductVersion becomes 1.0.18.0,
  but maintenance-mode MSI planning leaves HAL components Action=Null.
  Actual ENE M2 runtime remains 1.0.17.0, so ROG Live Service reports
  FailedVersionMismatch -> Optional Hal 4152.

Repair:
  validate + stage target
  -> backup/restore-point
  -> standard uninstall current 1.0.18 bundle
  -> real reboot
  -> only after MSI is absent: move SourceHash/residual install dir to Backup
  -> fresh install 1.0.18.0
  -> verify MSI/bundle + installed file versions
  -> restore services
#>

[CmdletBinding()]
param(
    [ValidateSet('SelfTest','Start','PostReboot','Diagnose')]
    [string]$Phase = 'Start'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ToolVersion = '1.1'
$ProfileId = '44066'
$ProductName = 'ENE_EHD_M2_HAL'
$ExeName = 'AacSetup_ENE_EHD_M2.exe'
$TargetVersion = '1.0.18.0'
$StaleRuntimeVersion = '1.0.17.0'
$ProductCode = '{37A48B7F-D4EA-4863-844E-A284E2AA3C5D}'
$UpgradeCode = '{81613800-C5C6-4E2F-ACBD-5D8F169BC6D8}'
$CurrentBundleId = '{04565624-f1c4-428e-80e8-0c3af195fb79}'
$OldBundleId = '{6a0e18d7-c33b-4c8c-aa31-4beedf5956c6}'
$InstallDir = 'C:\Program Files\ENE\Aac_ENE_EHD_M2_HAL'
$RuntimeDllX64 = Join-Path $InstallDir 'AacHal_x64.dll'
$RuntimeDllX86 = Join-Path $InstallDir 'AacHal_x86.dll'
$SourceHashDir = "C:\Windows\Installer\SourceHash$ProductCode"
$TaskName = 'ASUS_ENE_M2_4152_PostReboot'
$BaseStageRoot = Join-Path $env:ProgramData 'ASUS_ENE_M2_4152_Fix'
$CurrentStatePath = Join-Path $BaseStageRoot 'CurrentStatePath.txt'
$Desktop = [Environment]::GetFolderPath('Desktop')

$script:RunRoot = $null
$script:Logs = $null
$script:Backup = $null
$script:StageRun = $null
$script:TranscriptActive = $false

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

if (-not (Test-Admin)) {
    throw 'Repair core must be launched elevated through Bootstrap_ENE_M2.ps1.'
}

function Initialize-Run {
    param([string]$ExistingRunRoot)

    if ($ExistingRunRoot) {
        $script:RunRoot = $ExistingRunRoot
    } else {
        $script:RunRoot = Join-Path $Desktop ("ASUS_ENE_M2_4152_Fix_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }

    $script:Logs = Join-Path $script:RunRoot 'Logs'
    $script:Backup = Join-Path $script:RunRoot 'Backup'
    New-Item -ItemType Directory -Force -Path $script:RunRoot,$script:Logs,$script:Backup,$BaseStageRoot | Out-Null

    try {
        Start-Transcript -Path (Join-Path $script:RunRoot 'ENE_M2_4152_Fix.log') -Append -Force | Out-Null
        $script:TranscriptActive = $true
    } catch {}
}

function Stop-RunTranscript {
    if ($script:TranscriptActive) {
        try { Stop-Transcript | Out-Null } catch {}
        $script:TranscriptActive = $false
    }
}

function Add-Result {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Text
    Write-Host $line
    try { $line | Add-Content -LiteralPath (Join-Path $script:RunRoot 'RESULTS.txt') -Encoding UTF8 } catch {}
}

function Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==== $Text ====" -ForegroundColor Cyan
}

function Get-UninstallEntry {
    param([string]$Code)
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Code",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$Code"
    )
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue
        }
    }
    return $null
}

function Get-MsiVersion {
    $e = Get-UninstallEntry $ProductCode
    if ($e -and $e.DisplayVersion) { return [string]$e.DisplayVersion }
    return $null
}

function Test-MsiRegistered {
    return [bool](Get-UninstallEntry $ProductCode)
}

function Test-BundleRegistered {
    param([string]$Id)
    return [bool](Get-UninstallEntry $Id)
}

function Get-BundlePath {
    param([string]$Id)
    $e = Get-UninstallEntry $Id
    if (-not $e) { return $null }

    foreach ($prop in @('QuietUninstallString','UninstallString')) {
        $cmd = [string]$e.$prop
        if ($cmd -match '^"([^"]+)"') { return $matches[1] }
        if ($cmd -match '^(\S+\.exe)') { return $matches[1] }
    }
    return $null
}

function Get-BootStamp {
    try { return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToString('o') } catch { return $null }
}

function Get-FileVersionInfoSafe {
    param([string]$Path)
    try {
        $f = Get-Item -LiteralPath $Path -ErrorAction Stop
        return [PSCustomObject]@{
            FileVersion=[string]$f.VersionInfo.FileVersion
            ProductVersion=[string]$f.VersionInfo.ProductVersion
        }
    } catch {
        return [PSCustomObject]@{FileVersion='';ProductVersion=''}
    }
}

function Test-SignedPackage {
    param(
        [string]$Path,
        [string]$RequiredVersion
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{Valid=$false;Reason='FileMissing';Path=$Path}
    }

    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($fi.Length -lt 100KB) {
            return [PSCustomObject]@{Valid=$false;Reason='FileTooSmall';Path=$Path}
        }

        $v = Get-FileVersionInfoSafe $Path
        if ($RequiredVersion -and
            ($v.FileVersion -ne $RequiredVersion) -and
            ($v.ProductVersion -ne $RequiredVersion)) {
            return [PSCustomObject]@{
                Valid=$false
                Reason=("VersionMismatch file={0} product={1} wanted={2}" -f $v.FileVersion,$v.ProductVersion,$RequiredVersion)
                Path=$Path
            }
        }

        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        if (-not $sig -or $sig.Status -ne 'Valid') {
            return [PSCustomObject]@{Valid=$false;Reason=("Signature={0}" -f $sig.Status);Path=$Path}
        }

        $signer = ''
        try { $signer = [string]$sig.SignerCertificate.Subject } catch {}
        if ($signer -notmatch '(?i)(ENE|ASUS|ASUSTeK)') {
            return [PSCustomObject]@{Valid=$false;Reason=("UnexpectedSigner={0}" -f $signer);Path=$Path}
        }

        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop).Hash
        return [PSCustomObject]@{
            Valid=$true
            Reason='OK'
            Path=$Path
            SHA256=$hash
            FileVersion=$v.FileVersion
            ProductVersion=$v.ProductVersion
            Signer=$signer
        }
    } catch {
        return [PSCustomObject]@{Valid=$false;Reason=$_.Exception.Message;Path=$Path}
    }
}

function Find-TargetInstaller {
    $root = Join-Path $env:ProgramFiles "ASUS\RLSDownload\Optional Hal\4_HAL\AacSetup_$ProfileId"
    if (-not (Test-Path -LiteralPath $root)) { return $null }

    $items = Get-ChildItem -LiteralPath $root -Recurse -File -Filter $ExeName -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    foreach ($item in $items) {
        $t = Test-SignedPackage $item.FullName $TargetVersion
        if ($t.Valid) { return $t }
    }
    return $null
}

function Find-OldRollbackPackage {
    # Only trust the exact diagnosed old Burn bundle cache.
    # Do NOT scan unrelated Package Cache entries merely because they share version 1.0.17.0.
    $candidates = @(
        (Join-Path (Join-Path $env:ProgramData "Package Cache\$OldBundleId") 'AacSetup.exe'),
        (Join-Path (Join-Path $env:ProgramData "Package Cache\$OldBundleId") $ExeName)
    )

    foreach ($p in @($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        $t = Test-SignedPackage $p $StaleRuntimeVersion
        if ($t.Valid) { return $t }
    }
    return $null
}

function Get-ServiceSnapshot {
    $names = @(
        'ArmouryCrateService',
        'ROG Live Service',
        'LightingService',
        'AsusCertService',
        'asComSvc'
    )
    $r = @()
    foreach ($n in $names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) {
            $r += [PSCustomObject]@{Name=$svc.Name;WasRunning=($svc.Status -eq 'Running')}
        }
    }
    return $r
}

function Stop-ASUSStack {
    param([object[]]$Snapshot)
    Step '停止使用 ENE HAL 的 ASUS/Armoury 服务'
    foreach ($s in $Snapshot) {
        try { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue } catch {}
    }

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match '(Armoury|ROG|LightingService|AacSetup_ENE|EneHal|Aura)'
        } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 3
}

function Restore-ASUSStack {
    param([object[]]$Snapshot)
    foreach ($s in $Snapshot) {
        if ($s.WasRunning) {
            try { Start-Service -Name $s.Name -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Get-CurrentUserSidText {
    try { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { return $null }
}

function Protect-StageDirectory {
    param([string]$Path)
    $sid = Get-CurrentUserSidText
    if (-not $sid) { throw '无法获取当前用户 SID。' }

    $rootGrants = @(
        '*S-1-5-18:(OI)(CI)F',
        '*S-1-5-32-544:(OI)(CI)F',
        ("*{0}:(OI)(CI)F" -f $sid)
    )
    & icacls.exe $Path /inheritance:r /grant:r $rootGrants /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Stage root ACL failed=$LASTEXITCODE" }

    $fileGrants = @(
        '*S-1-5-18:F',
        '*S-1-5-32-544:F',
        ("*{0}:F" -f $sid)
    )
    & icacls.exe $Path /grant $fileGrants /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Stage child ACL failed=$LASTEXITCODE" }
}

function Copy-StageVerified {
    param([object]$Package,[string]$Name)
    $dst = Join-Path $script:StageRun $Name
    Copy-Item -LiteralPath $Package.Path -Destination $dst -Force
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst -ErrorAction Stop).Hash
    if ($hash -ne $Package.SHA256) { throw "Staging SHA256 mismatch: $Name" }
    return $dst
}

function Revalidate-Staged {
    param([string]$Path,[string]$Hash,[string]$Version)
    try {
        $t = Test-SignedPackage $Path $Version
        if (-not $t.Valid) {
            Add-Result "重启后二次验证失败：$($t.Reason)"
            return $false
        }
        if ($t.SHA256 -ne $Hash) {
            Add-Result '重启后 SHA256 与阶段1不一致。'
            return $false
        }
        Add-Result "重启后二次验证 PASS：$Path"
        return $true
    } catch {
        Add-Result "重启后二次验证异常：$($_.Exception.Message)"
        return $false
    }
}

function Invoke-Exe {
    param([string]$File,[string]$Arguments,[string]$Label)
    $stdout = Join-Path $script:Logs "$Label.stdout.txt"
    $stderr = Join-Path $script:Logs "$Label.stderr.txt"

    try {
        $p = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Add-Result "$Label ExitCode=$($p.ExitCode)"
        return $p.ExitCode
    } catch {
        Add-Result "$Label 启动失败：$($_.Exception.Message)"
        return 99999
    }
}

function Export-RegistryBackup {
    try {
        & reg.exe export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode" `
            (Join-Path $script:Backup 'MSI_Uninstall.reg') /y | Out-Null
    } catch {}
    try {
        & reg.exe export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$CurrentBundleId" `
            (Join-Path $script:Backup 'Burn_Uninstall.reg') /y | Out-Null
    } catch {}
}

function Save-InstalledFileVersions {
    param([string]$Label)
    $dest = Join-Path $script:Logs "$Label.txt"
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        "InstallDir missing: $InstallDir" | Set-Content -LiteralPath $dest -Encoding UTF8
        return
    }

    $rows = @()
    Get-ChildItem -LiteralPath $InstallDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $rows += [PSCustomObject]@{
                FullName=$_.FullName
                Length=$_.Length
                FileVersion=[string]$_.VersionInfo.FileVersion
                ProductVersion=[string]$_.VersionInfo.ProductVersion
                LastWriteTime=$_.LastWriteTime
            }
        } catch {}
    }

    $rows | Sort-Object FullName | Format-Table -AutoSize |
        Out-String -Width 500 | Set-Content -LiteralPath $dest -Encoding UTF8
}

function Find-ActualHALVersionSummary {
    $versions = @()
    if (Test-Path -LiteralPath $InstallDir) {
        Get-ChildItem -LiteralPath $InstallDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $fv = [string]$_.VersionInfo.FileVersion
                $pv = [string]$_.VersionInfo.ProductVersion
                if ($fv) { $versions += $fv }
                if ($pv) { $versions += $pv }
            } catch {}
        }
    }
    return @($versions | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-ExactRuntimeDllState {
    $rows = @()
    foreach ($path in @($RuntimeDllX64,$RuntimeDllX86)) {
        if (Test-Path -LiteralPath $path) {
            try {
                $f = Get-Item -LiteralPath $path -ErrorAction Stop
                $rows += [PSCustomObject]@{
                    Path=$path
                    Exists=$true
                    FileVersion=[string]$f.VersionInfo.FileVersion
                    ProductVersion=[string]$f.VersionInfo.ProductVersion
                    SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path -ErrorAction Stop).Hash
                }
            } catch {
                $rows += [PSCustomObject]@{
                    Path=$path;Exists=$true;FileVersion='';ProductVersion='';SHA256=''
                }
            }
        } else {
            $rows += [PSCustomObject]@{
                Path=$path;Exists=$false;FileVersion='';ProductVersion='';SHA256=''
            }
        }
    }
    return $rows
}

function Test-ExactRuntimeVersion {
    param([string]$ExpectedVersion)
    $rows = @(Get-ExactRuntimeDllState)
    if ($rows.Count -ne 2) { return $false }
    foreach ($r in $rows) {
        if (-not $r.Exists) { return $false }
        if (($r.FileVersion -ne $ExpectedVersion) -and ($r.ProductVersion -ne $ExpectedVersion)) {
            return $false
        }
    }
    return $true
}

function Save-ExactRuntimeDllState {
    param([string]$Name)
    @(Get-ExactRuntimeDllState) |
        Format-List | Out-String -Width 500 |
        Set-Content -LiteralPath (Join-Path $script:Logs $Name) -Encoding UTF8
}

function Get-RecentRestorePoint {
    param([int]$MaxAgeHours=6)
    try {
        $cutoff = (Get-Date).AddHours(-1 * $MaxAgeHours)
        $points = Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending
        foreach ($rp in $points) {
            try {
                $dt = [Management.ManagementDateTimeConverter]::ToDateTime([string]$rp.CreationTime)
                if ($dt -ge $cutoff) {
                    return [PSCustomObject]@{
                        SequenceNumber=$rp.SequenceNumber
                        Description=[string]$rp.Description
                        CreationTime=$dt
                    }
                }
            } catch {}
        }
    } catch {}
    return $null
}

function Ensure-RecoveryPoint {
    # Prefer creating a fresh point. Windows may refuse when another point was created recently.
    # If so, accept only a restore point from the last 6 hours; never silently proceed with none.
    try {
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Before ASUS ENE M2 HAL 4152 Clean Fix v1.1' `
            -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Add-Result '系统还原点已创建。'
        return [PSCustomObject]@{Valid=$true;Fresh=$true;Detail='Fresh restore point created'}
    } catch {
        Add-Result "新系统还原点创建失败：$($_.Exception.Message)"
        $recent = Get-RecentRestorePoint -MaxAgeHours 6
        if ($recent) {
            Add-Result ("发现可用的最近系统还原点：Sequence={0}; Time={1}; Description={2}" -f `
                $recent.SequenceNumber,$recent.CreationTime,$recent.Description)
            return [PSCustomObject]@{
                Valid=$true
                Fresh=$false
                Detail=("Recent restore point #{0} at {1}" -f $recent.SequenceNumber,$recent.CreationTime)
            }
        }
        return [PSCustomObject]@{Valid=$false;Fresh=$false;Detail='No fresh/recent restore point'}
    }
}

function Move-ToBackup {
    param([string]$Path,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $dst = Join-Path $script:Backup ($Label + '_' + (Get-Date -Format 'HHmmss'))
    Move-Item -LiteralPath $Path -Destination $dst -Force -ErrorAction Stop
    Add-Result "已备份并移走：$Path -> $dst"
}

function Get-ExplicitBlockEvidence {
    $hits = @()
    $since = (Get-Date).AddDays(-7)

    try {
        $hits += Get-WinEvent -FilterHashtable @{
            LogName='Microsoft-Windows-CodeIntegrity/Operational'
            Id=3077
            StartTime=$since
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'AacSetup_ENE_EHD_M2|AsusInstallVerifier|Aac_ENE_EHD_M2_HAL' } |
        Select-Object TimeCreated,Id,Message
    } catch {}

    try {
        $hits += Get-WinEvent -FilterHashtable @{
            LogName='Microsoft-Windows-AppLocker/EXE and DLL'
            Id=8004
            StartTime=$since
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'AacSetup_ENE_EHD_M2|AsusInstallVerifier|Aac_ENE_EHD_M2_HAL' } |
        Select-Object TimeCreated,Id,Message
    } catch {}

    return $hits
}

function Save-Preflight {
    Save-InstalledFileVersions 'InstalledFiles_BEFORE.txt'
    Save-ExactRuntimeDllState 'ExactRuntimeDLLs_BEFORE.txt'

    $stateText = @"
Product=$ProductName
ProfileID=$ProfileId
MSI ProductCode=$ProductCode
MSI DisplayVersion=$(Get-MsiVersion)
CurrentBundleRegistered=$(Test-BundleRegistered $CurrentBundleId)
OldBundleRegistered=$(Test-BundleRegistered $OldBundleId)
InstallDirExists=$(Test-Path -LiteralPath $InstallDir)
SourceHashExists=$(Test-Path -LiteralPath $SourceHashDir)
BootStamp=$(Get-BootStamp)
"@
    $stateText | Set-Content -LiteralPath (Join-Path $script:Logs 'Preflight_State.txt') -Encoding UTF8
}

function Pack-Report {
    Stop-RunTranscript
    Start-Sleep -Milliseconds 500
    if (-not $script:RunRoot -or -not (Test-Path -LiteralPath $script:RunRoot)) { return }

    $zip = "$($script:RunRoot).zip"
    try {
        Compress-Archive -Path "$($script:RunRoot)\*" -DestinationPath $zip -Force -ErrorAction Stop
        Write-Host "报告 ZIP：$zip" -ForegroundColor Green
    } catch {
        Write-Host "ZIP 创建失败；报告目录仍在：$($script:RunRoot)" -ForegroundColor Yellow
    }
}

function Run-SelfTest {
    Initialize-Run
    Add-Result "ASUS ENE M2 HAL 4152 Clean Fix v$ToolVersion - SelfTest"

    $errors = @()
    $warnings = @()

    Save-Preflight

    $msiVersion = Get-MsiVersion
    if ($msiVersion -ne $TargetVersion) {
        $errors += "当前 MSI DisplayVersion 应为 $TargetVersion，实际=$msiVersion。"
    }

    if (-not (Test-BundleRegistered $CurrentBundleId)) {
        $errors += "当前 1.0.18 Burn Bundle $CurrentBundleId 未注册。"
    }

    $target = Find-TargetInstaller
    if (-not $target) {
        $errors += "找不到 Profile $ProfileId 下有效签名的 $TargetVersion 目标安装器。"
    } else {
        Add-Result "目标包 PASS：$($target.Path)"
        Add-Result "target file=$($target.FileVersion) product=$($target.ProductVersion) SHA256=$($target.SHA256.Substring(0,12))..."
    }

    $currentBundlePath = Get-BundlePath $CurrentBundleId
    $currentBundle = Test-SignedPackage $currentBundlePath $TargetVersion
    if (-not $currentBundle.Valid) {
        $errors += "当前已注册 Burn Bundle 无法验证：$($currentBundle.Reason)"
    } else {
        Add-Result "当前 Bundle PASS：$($currentBundle.Path)"
    }

    $rollback = Find-OldRollbackPackage
    if ($rollback) {
        Add-Result "发现旧版 1.0.17.0 回滚包：$($rollback.Path)"
    } else {
        $warnings += '未找到 1.0.17.0 Burn 回滚包；正式修复必须成功创建系统还原点才会允许卸载。'
    }

    $blocks = @(Get-ExplicitBlockEvidence)
    if ($blocks.Count -gt 0) {
        $blocks | Format-List | Out-String -Width 500 |
            Set-Content -LiteralPath (Join-Path $script:Logs 'ApplicationControlBlocks.txt') -Encoding UTF8
        $errors += "发现 $($blocks.Count) 条 Code Integrity/AppLocker 明确阻断。"
    }

    $actualVersions = @(Find-ActualHALVersionSummary)
    Add-Result ("当前安装目录内版本资源：" + ($actualVersions -join ', '))

    $exactRuntime = @(Get-ExactRuntimeDllState)
    foreach ($r in $exactRuntime) {
        Add-Result ("RuntimeDLL {0} exists={1} file={2} product={3}" -f `
            $r.Path,$r.Exists,$r.FileVersion,$r.ProductVersion)
    }

    if (Test-ExactRuntimeVersion $StaleRuntimeVersion) {
        Add-Result "CONFIRMED：AacHal_x64.dll 与 AacHal_x86.dll 都仍是 $StaleRuntimeVersion，与 4152 完全一致。"
    } elseif ($actualVersions -contains $StaleRuntimeVersion) {
        Add-Result "CONFIRMED：安装目录仍含 $StaleRuntimeVersion 文件，与 4152 的 FailedVersionMismatch 一致。"
    } else {
        $warnings += "安装目录版本资源未直接找到 $StaleRuntimeVersion；仍以 ROG Live Service/EneHal 的实际运行版本日志为准。"
    }

    foreach ($w in $warnings) { Add-Result "WARNING: $w" }
    foreach ($e in $errors) { Add-Result "ERROR: $e" }

    if ($errors.Count -eq 0) {
        'PASS' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'SELFTEST_STATUS.txt') -Encoding ASCII
        Add-Result 'SelfTest PASS：没有卸载或安装任何组件。'
    } else {
        'FAIL' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'SELFTEST_STATUS.txt') -Encoding ASCII
        Add-Result "SelfTest FAIL：errors=$($errors.Count)，没有执行修复。"
    }

    Pack-Report
}

function Create-ResumeTask {
    $stagedScript = Join-Path $script:StageRun 'ASUS_ENE_M2_4152_Fix.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $stagedScript -Force

    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        "-NoProfile -ExecutionPolicy Bypass -File `"$stagedScript`" -Phase PostReboot"
    )
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    @"
@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$stagedScript" -Phase PostReboot
pause
"@ | Set-Content -LiteralPath (Join-Path $script:RunRoot 'Continue_After_Reboot.cmd') -Encoding ASCII
}

function Remove-ResumeTask {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

function Run-Start {
    Initialize-Run
    Add-Result "ASUS ENE M2 HAL 4152 Clean Fix v$ToolVersion"
    Add-Result "只处理 Profile $ProfileId / $ProductName；不会修改其他 HAL。"

    Save-Preflight

    if ((Get-MsiVersion) -ne $TargetVersion) {
        throw "正式修复前 MSI DisplayVersion 必须是 $TargetVersion。"
    }
    if (-not (Test-BundleRegistered $CurrentBundleId)) {
        throw '当前 1.0.18 Burn Bundle 未注册，停止。'
    }

    $target = Find-TargetInstaller
    if (-not $target) { throw '目标 1.0.18 安装器验证失败。' }

    $currentBundle = Test-SignedPackage (Get-BundlePath $CurrentBundleId) $TargetVersion
    if (-not $currentBundle.Valid) { throw "当前 Bundle 验证失败：$($currentBundle.Reason)" }

    $rollback = Find-OldRollbackPackage
    $blocks = @(Get-ExplicitBlockEvidence)
    if ($blocks.Count -gt 0) { throw '发现 Code Integrity/AppLocker 阻断，停止。' }

    # Recovery path is mandatory if an exact 1.0.17 rollback bundle is unavailable.
    $recoveryPoint = Ensure-RecoveryPoint
    $restoreOK = [bool]$recoveryPoint.Valid

    if (-not $rollback -and -not $restoreOK) {
        throw '没有精确 1.0.17 回滚包，也没有 6 小时内可用系统还原点；为避免无回滚路径，不执行卸载。'
    }

    Export-RegistryBackup

    # Backup current runtime files before uninstall for forensic/recovery use.
    if (Test-Path -LiteralPath $InstallDir) {
        $runtimeBackup = Join-Path $script:Backup 'InstalledRuntime_BEFORE'
        Copy-Item -LiteralPath $InstallDir -Destination $runtimeBackup -Recurse -Force -ErrorAction Stop
        Add-Result "当前 ENE M2 运行目录已备份：$runtimeBackup"
    }

    $runId = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:StageRun = Join-Path $BaseStageRoot $runId
    New-Item -ItemType Directory -Force -Path $script:StageRun | Out-Null

    $targetStage = Copy-StageVerified $target 'AacSetup_ENE_EHD_M2_1.0.18.0.exe'
    $bundleStage = Copy-StageVerified $currentBundle 'AacSetup_CurrentBundle_1.0.18.0.exe'

    $rollbackStage = $null
    $rollbackHash = $null
    if ($rollback) {
        $rollbackStage = Copy-StageVerified $rollback 'AacSetup_ENE_EHD_M2_1.0.17.0_ROLLBACK.exe'
        $rollbackHash = $rollback.SHA256
    }

    Protect-StageDirectory $script:StageRun

    $snapshot = @(Get-ServiceSnapshot)
    $state = [PSCustomObject]@{
        ToolVersion=$ToolVersion
        Phase='Prepared'
        RunRoot=$script:RunRoot
        StageRun=$script:StageRun
        BootBefore=Get-BootStamp
        TargetPath=$targetStage
        TargetSHA256=$target.SHA256
        BundlePath=$bundleStage
        BundleSHA256=$currentBundle.SHA256
        RollbackPath=$rollbackStage
        RollbackSHA256=$rollbackHash
        RestorePointCreated=$restoreOK
        RestorePointDetail=[string]$recoveryPoint.Detail
        ServiceSnapshot=$snapshot
        Created=(Get-Date).ToString('o')
    }

    $statePath = Join-Path $script:StageRun 'state.json'
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $statePath | Set-Content -LiteralPath $CurrentStatePath -Encoding UTF8

    Create-ResumeTask
    Protect-StageDirectory $script:StageRun

    Stop-ASUSStack $snapshot

    Step '标准卸载当前 ENE_EHD_M2_HAL 1.0.18.0'
    $rc = Invoke-Exe $bundleStage '/uninstall /quiet /norestart' 'ENE_M2_1.0.18_Uninstall'
    Start-Sleep -Seconds 4

    $msiRemains = Test-MsiRegistered
    $bundleRemains = Test-BundleRegistered $CurrentBundleId
    Add-Result "卸载后：MSI remains=$msiRemains ; Burn remains=$bundleRemains"

    if (($rc -notin 0,3010,1641) -or $msiRemains -or $bundleRemains) {
        Restore-ASUSStack $snapshot
        Remove-ResumeTask
        Add-Result '标准卸载没有完全完成；没有清理 SourceHash/安装目录，也没有安装新版。'
        Pack-Report
        throw '当前 ENE M2 HAL 标准卸载失败。'
    }

    $state.Phase='AwaitingReboot'
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    'AWAITING_REBOOT' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
    Add-Result '阶段1成功：当前 MSI/Burn 已完整卸载。必须真实重启后才能进行干净安装。'

    Stop-RunTranscript
    Write-Host ""
    Write-Host "阶段1完成。现在必须重启 Windows。" -ForegroundColor Yellow
    $ans = Read-Host '输入 R 立即重启；直接回车稍后手动重启'
    if ($ans -match '^[Rr]$') {
        shutdown.exe /r /t 5 /c "ASUS ENE M2 4152 Clean Fix continuing after reboot"
    }
}

function Try-OldRollback {
    param([object]$State)
    if (-not $State.RollbackPath) { return $false }

    Add-Result '目标安装失败；尝试恢复旧版 1.0.17.0。'
    if (-not (Revalidate-Staged ([string]$State.RollbackPath) ([string]$State.RollbackSHA256) $StaleRuntimeVersion)) {
        Add-Result '旧版回滚包二次验证失败，不能执行回滚。'
        return $false
    }

    $rc = Invoke-Exe ([string]$State.RollbackPath) '/quiet /norestart' 'ENE_M2_1.0.17_Rollback'
    Start-Sleep -Seconds 4
    $v = Get-MsiVersion
    Add-Result "旧版回滚后 MSI version=$v"
    return (($rc -in 0,3010,1641) -and ($v -eq $StaleRuntimeVersion))
}

function Run-PostReboot {
    if (-not (Test-Path -LiteralPath $CurrentStatePath)) {
        throw '找不到 CurrentStatePath；没有可续跑修复。'
    }

    $statePath = (Get-Content -LiteralPath $CurrentStatePath -Raw).Trim()
    if (-not (Test-Path -LiteralPath $statePath)) { throw "state.json 不存在：$statePath" }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

    Initialize-Run ([string]$state.RunRoot)
    $script:StageRun = [string]$state.StageRun
    Protect-StageDirectory $script:StageRun

    if ([string]$state.Phase -ne 'AwaitingReboot') {
        throw "状态不是 AwaitingReboot：$($state.Phase)"
    }

    $before = [string]$state.BootBefore
    $after = Get-BootStamp
    if (-not $before -or -not $after -or $before -eq $after) {
        Add-Result '真实重启门禁失败：LastBootUpTime 没有变化。'
        Pack-Report
        throw '请真正“重启”Windows 后再运行 Continue_After_Reboot.cmd。'
    }
    Add-Result "真实重启确认：before=$before ; after=$after"

    if (Test-MsiRegistered) {
        throw '重启后 MSI ProductCode 仍然注册；拒绝清理。'
    }
    if (Test-BundleRegistered $CurrentBundleId) {
        throw '重启后当前 Burn Bundle 仍然注册；拒绝清理。'
    }

    if (-not (Revalidate-Staged ([string]$state.TargetPath) ([string]$state.TargetSHA256) $TargetVersion)) {
        throw '1.0.18.0 目标包重启后二次校验失败。'
    }

    Step '清理导致 maintenance-mode 文件不刷新的旧安装状态'
    Move-ToBackup $SourceHashDir 'SourceHash_STALE'
    Move-ToBackup $InstallDir 'InstallDir_STALE_1.0.17'

    try {
        $temp = Join-Path $env:LOCALAPPDATA 'Temp\ENE\Aac_ENE_EHD_M2_HAL'
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            Add-Result "已清理临时目录：$temp"
        }
    } catch {}

    Step '全新安装 ENE_EHD_M2_HAL 1.0.18.0'
    $rc = Invoke-Exe ([string]$state.TargetPath) '/quiet /norestart' 'ENE_M2_1.0.18_FreshInstall'
    Start-Sleep -Seconds 5

    $finalMsi = Get-MsiVersion
    $finalBundle = Test-BundleRegistered $CurrentBundleId
    Save-InstalledFileVersions 'InstalledFiles_AFTER.txt'
    Save-ExactRuntimeDllState 'ExactRuntimeDLLs_AFTER.txt'
    $actualVersions = @(Find-ActualHALVersionSummary)
    $exactRuntimeOK = Test-ExactRuntimeVersion $TargetVersion

    Add-Result "安装后 MSI version=$finalMsi ; Burn registered=$finalBundle ; ExactRuntimeDLLs=$exactRuntimeOK"
    Add-Result ("安装目录版本资源：" + ($actualVersions -join ', '))

    foreach ($r in @(Get-ExactRuntimeDllState)) {
        Add-Result ("POST RuntimeDLL {0} exists={1} file={2} product={3}" -f `
            $r.Path,$r.Exists,$r.FileVersion,$r.ProductVersion)
    }

    $snapshot = @($state.ServiceSnapshot)

    if (($rc -in 0,3010,1641) -and
        ($finalMsi -eq $TargetVersion) -and
        $finalBundle -and
        $exactRuntimeOK) {
        Restore-ASUSStack $snapshot
        Start-Sleep -Seconds 8

        # Capture ENE runtime log after services reload. Do not require this log to exist.
        try {
            $eneLog = Join-Path $env:ProgramData 'ASUS\ARMOURY CRATE Diagnosis\OptionHAL\EneHal.log'
            if (Test-Path -LiteralPath $eneLog) {
                Get-Content -LiteralPath $eneLog -Tail 500 -ErrorAction SilentlyContinue |
                    Select-String -Pattern '\[ENE M2\].*Ver:' |
                    ForEach-Object { $_.Line } |
                    Set-Content -LiteralPath (Join-Path $script:Logs 'EneM2_RuntimeVersion_AFTER.txt') -Encoding UTF8
            }
        } catch {}

        'SUCCESS' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        $state.Phase='Success'
        $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
        Add-Result 'SUCCESS：MSI/Burn 均为 1.0.18.0，且 AacHal_x64.dll / AacHal_x86.dll 实际文件版本也严格为 1.0.18.0。'
        Add-Result '现在先重启一次/等待服务加载，再打开 Armoury Crate 检查 4152。'

        Remove-ResumeTask
        Remove-Item -LiteralPath $CurrentStatePath -Force -ErrorAction SilentlyContinue
        Pack-Report
        return
    }

    Add-Result '1.0.18.0 干净安装没有通过严格最终验证（MSI/Burn/两个实际 AacHal DLL 必须全部为目标状态）。'
    $rolledBack = Try-OldRollback $state
    Restore-ASUSStack $snapshot
    Remove-ResumeTask

    if ($rolledBack) {
        'FAILED_ROLLED_BACK' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result '目标安装失败，但旧版 1.0.17.0 已成功恢复。'
    } else {
        'FAILED_NEEDS_ATTENTION' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result '目标安装失败，且没有确认旧版回滚。不要继续点 Armoury Crate 更新；请上传报告。'
    }

    Pack-Report
}

function Run-Diagnose {
    Initialize-Run
    Save-Preflight
    $target = Find-TargetInstaller
    $rollback = Find-OldRollbackPackage
    Add-Result "MSI=$(Get-MsiVersion)"
    Add-Result "CurrentBundle=$(Test-BundleRegistered $CurrentBundleId)"
    Add-Result "TargetFound=$([bool]$target)"
    Add-Result "OldRollbackFound=$([bool]$rollback)"
    Add-Result ("InstalledVersions=" + ((Find-ActualHALVersionSummary) -join ', '))
    Pack-Report
}

try {
    switch ($Phase) {
        'SelfTest'   { Run-SelfTest }
        'Start'      { Run-Start }
        'PostReboot' { Run-PostReboot }
        'Diagnose'   { Run-Diagnose }
    }
} catch {
    if ($script:RunRoot) {
        Add-Result "FATAL: $($_.Exception.Message)"
        try { Pack-Report } catch {}
    }
    throw
} finally {
    Stop-RunTranscript
}
