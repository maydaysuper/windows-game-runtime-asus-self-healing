#requires -version 5.1
<#
ASUS Core HAL 4151 Targeted Fix v1.0
Target (from real Armoury Crate logs):
  UI: ASUS Core HAL / Optional HAL
  Component: Universal Holtek RGB DRAM
  EXE: AacUHDRAMSetup.exe
  ProfileID: 44075
  Current: 1.0.0.7
  Target: 1.0.0.8
  MSI ProductCode: {826388E4-E31F-4514-948B-3BB954FB3EAF}
  UpgradeCode: {BF3A35A7-E56A-4558-9BA6-EDA8CC21C261}
  Old Burn bundle: {9a732423-e2f4-47d0-87ab-ef745c7dba69}
  Target Burn provider: {28efb5e7-4406-4c29-925c-106483460038}

Observed failure chain:
  Setup64 MinorUpgrade
  -> SECREPAIR SourceHash mismatch
  -> AsusInstallVerifier verifyInstall
  -> MSI Error 1721
  -> 1603 / 0x80070643
  -> Armoury Crate UI 4151

Safety:
  - Does NOT touch VGA, Patriot, GPU drivers, DriverStore or BIOS.
  - Requires a signed 1.0.0.8 target EXE and a signed 1.0.0.7 rollback EXE before uninstall.
  - Uses standard Burn uninstall first.
  - Requires a real reboot before cleaning stale SourceHash/residual files.
  - Revalidates staged binaries by SHA256 + Authenticode after reboot.
  - On target install failure, attempts rollback to 1.0.0.7.
#>

[CmdletBinding()]
param(
    [ValidateSet('Start','SelfTest','PostReboot','Diagnose')]
    [string]$Phase = 'Start'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ToolVersion = '1.0'
$ProfileId = '44075'
$DisplayName = 'Universal Holtek RGB DRAM'
$ExeName = 'AacUHDRAMSetup.exe'
$CurrentVersionExpected = '1.0.0.7'
$TargetVersion = '1.0.0.8'
$ProductCode = '{826388E4-E31F-4514-948B-3BB954FB3EAF}'
$UpgradeCode = '{BF3A35A7-E56A-4558-9BA6-EDA8CC21C261}'
$OldBundleId = '{9a732423-e2f4-47d0-87ab-ef745c7dba69}'
$NewBundleId = '{28efb5e7-4406-4c29-925c-106483460038}'
$TaskName = 'ASUS_CoreHAL_4151_PostReboot'
$BaseStageRoot = Join-Path $env:ProgramData 'ASUSCoreHAL4151Fix'
$CurrentStatePath = Join-Path $BaseStageRoot 'CurrentStatePath.txt'
$Desktop = [Environment]::GetFolderPath('Desktop')

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

if (-not (Test-Admin)) {
    throw 'This repair core must be run elevated through Bootstrap_CoreHAL.ps1.'
}

$script:TranscriptActive = $false
$script:RunRoot = $null
$script:Logs = $null
$script:Backup = $null
$script:StageRun = $null

function Initialize-Run {
    param([string]$ExistingRunRoot)

    if ($ExistingRunRoot) {
        $script:RunRoot = $ExistingRunRoot
    } else {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $script:RunRoot = Join-Path $Desktop "ASUS_CoreHAL_4151_Fix_$stamp"
    }
    $script:Logs = Join-Path $script:RunRoot 'Logs'
    $script:Backup = Join-Path $script:RunRoot 'Backup'
    New-Item -ItemType Directory -Force -Path $script:RunRoot,$script:Logs,$script:Backup,$BaseStageRoot | Out-Null

    $log = Join-Path $script:RunRoot 'CoreHAL_Fix.log'
    try {
        Start-Transcript -Path $log -Append -Force | Out-Null
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
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
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
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Code",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$Code"
    )
    foreach ($p in $roots) {
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

function Get-BundleEntry {
    param([string]$BundleId)
    return Get-UninstallEntry $BundleId
}

function Test-BundleRegistered {
    param([string]$BundleId)
    return [bool](Get-BundleEntry $BundleId)
}

function Get-FileVersionText {
    param([string]$Path)
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        return [PSCustomObject]@{
            FileVersion = [string]$fi.VersionInfo.FileVersion
            ProductVersion = [string]$fi.VersionInfo.ProductVersion
        }
    } catch {
        return [PSCustomObject]@{FileVersion='';ProductVersion=''}
    }
}

function Test-VersionEvidence {
    param([string]$Path,[string]$Version)
    $v = Get-FileVersionText $Path
    return (($v.FileVersion -eq $Version) -or ($v.ProductVersion -eq $Version))
}

function Test-SignedFile {
    param([string]$Path,[string]$RequiredVersion)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{Valid=$false;Reason='FileMissing';Path=$Path}
    }
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($fi.Length -lt 100KB) {
            return [PSCustomObject]@{Valid=$false;Reason='FileTooSmall';Path=$Path}
        }

        if ($RequiredVersion -and -not (Test-VersionEvidence $Path $RequiredVersion)) {
            $v = Get-FileVersionText $Path
            return [PSCustomObject]@{
                Valid=$false
                Reason=("VersionMismatch file={0} product={1} required={2}" -f $v.FileVersion,$v.ProductVersion,$RequiredVersion)
                Path=$Path
            }
        }

        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        if (-not $sig -or $sig.Status -ne 'Valid') {
            return [PSCustomObject]@{Valid=$false;Reason=("Signature={0}" -f $sig.Status);Path=$Path}
        }

        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop).Hash
        if (-not $hash) {
            return [PSCustomObject]@{Valid=$false;Reason='NoSHA256';Path=$Path}
        }

        $v = Get-FileVersionText $Path
        $signer = ''
        try { $signer = [string]$sig.SignerCertificate.Subject } catch {}

        return [PSCustomObject]@{
            Valid=$true
            Reason='OK'
            Path=$Path
            SHA256=$hash
            Signer=$signer
            FileVersion=$v.FileVersion
            ProductVersion=$v.ProductVersion
        }
    } catch {
        return [PSCustomObject]@{Valid=$false;Reason=$_.Exception.Message;Path=$Path}
    }
}

function Find-TargetInstaller {
    $profileRoot = Join-Path $env:ProgramFiles "ASUS\RLSDownload\Optional Hal\4_HAL\$ProfileId"
    if (-not (Test-Path -LiteralPath $profileRoot)) { return $null }

    $items = Get-ChildItem -LiteralPath $profileRoot -Recurse -File -Filter $ExeName -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    foreach ($item in $items) {
        $test = Test-SignedFile $item.FullName $TargetVersion
        if ($test.Valid) { return $test }
    }
    return $null
}

function Find-RollbackInstaller {
    $candidates = @()

    $bundle = Get-BundleEntry $OldBundleId
    if ($bundle) {
        foreach ($field in @('QuietUninstallString','UninstallString')) {
            $cmd = [string]$bundle.$field
            if ($cmd -match '^"([^"]+)"') { $candidates += $matches[1] }
            elseif ($cmd -match '^(\S+\.exe)') { $candidates += $matches[1] }
        }
    }

    $candidates += (Join-Path (Join-Path $env:ProgramData "Package Cache\$OldBundleId") $ExeName)
    $candidates = @($candidates | Where-Object { $_ } | Select-Object -Unique)

    foreach ($path in $candidates) {
        $test = Test-SignedFile $path $CurrentVersionExpected
        if ($test.Valid) { return $test }
    }
    return $null
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
        Where-Object { $_.Message -match 'AacUHDRAMSetup|AsusInstallVerifier|Universal Holtek' } |
        Select-Object TimeCreated,Id,Message
    } catch {}

    try {
        $hits += Get-WinEvent -FilterHashtable @{
            LogName='Microsoft-Windows-AppLocker/EXE and DLL'
            Id=8004
            StartTime=$since
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'AacUHDRAMSetup|AsusInstallVerifier|Universal Holtek' } |
        Select-Object TimeCreated,Id,Message
    } catch {}

    return $hits
}

function Get-BootStamp {
    try {
        return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToString('o')
    } catch { return $null }
}

function Save-PreflightEvidence {
    Step '保存 Core HAL 诊断证据'
    try {
        Get-WinEvent -FilterHashtable @{
            LogName='Application'
            ProviderName='MsiInstaller'
            StartTime=(Get-Date).AddDays(-2)
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Universal Holtek|AacUHDRAM|1721|1603' } |
        Select-Object TimeCreated,Id,LevelDisplayName,Message |
        Format-List | Out-String -Width 420 |
        Set-Content -LiteralPath (Join-Path $script:Logs 'MsiInstaller_CoreHAL.txt') -Encoding UTF8
    } catch {}

    try {
        $srcHash = "C:\Windows\Installer\SourceHash$ProductCode"
        "ProductCode=$ProductCode`nProductVersion=$(Get-MsiVersion)`nOldBundleRegistered=$(Test-BundleRegistered $OldBundleId)`nNewBundleRegistered=$(Test-BundleRegistered $NewBundleId)`nSourceHashExists=$(Test-Path -LiteralPath $srcHash)" |
            Set-Content -LiteralPath (Join-Path $script:Logs 'CoreHAL_State.txt') -Encoding UTF8
    } catch {}
}

function Invoke-SelfTest {
    Initialize-Run
    Add-Result "ASUS Core HAL 4151 Targeted Fix v$ToolVersion SelfTest"
    Add-Result "目标：Profile=$ProfileId, $CurrentVersionExpected -> $TargetVersion, ProductCode=$ProductCode"

    Save-PreflightEvidence

    $errors = @()
    $warnings = @()

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $errors += '需要 Windows PowerShell 5.1。'
    }

    try {
        if ((Get-PSDrive C).Free -lt 2GB) { $errors += 'C: 剩余空间低于 2 GB。' }
    } catch { $warnings += '无法读取 C: 剩余空间。' }

    $current = Get-MsiVersion
    if (-not $current) {
        $errors += "无法从 MSI ProductCode $ProductCode 读取当前 Core HAL 版本。"
    } elseif ($current -ne $CurrentVersionExpected -and $current -ne $TargetVersion) {
        $errors += "当前 Core HAL MSI 版本为 $current，不是已诊断的 $CurrentVersionExpected 或目标 $TargetVersion。"
    }

    if ($current -eq $TargetVersion) {
        $warnings += "MSI 已显示目标版本 $TargetVersion；可能只需刷新 Armoury Crate。"
    }

    $target = Find-TargetInstaller
    if (-not $target) {
        $errors += "找不到同时满足 Profile $ProfileId + $TargetVersion + Valid Authenticode 的 $ExeName。"
    } else {
        Add-Result "目标安装器 PASS：$($target.Path)"
        Add-Result "目标版本 file=$($target.FileVersion) product=$($target.ProductVersion) SHA256=$($target.SHA256.Substring(0,12))..."
    }

    $rollback = Find-RollbackInstaller
    if (-not $rollback) {
        $errors += "找不到可验证的旧版 $CurrentVersionExpected Burn 回滚包；为避免卸载后无法恢复，禁止继续。"
    } else {
        Add-Result "回滚包 PASS：$($rollback.Path)"
        Add-Result "回滚版本 file=$($rollback.FileVersion) product=$($rollback.ProductVersion) SHA256=$($rollback.SHA256.Substring(0,12))..."
    }

    $blocks = @(Get-ExplicitBlockEvidence)
    if ($blocks.Count -gt 0) {
        $blocks | Format-List | Out-String -Width 420 |
            Set-Content -LiteralPath (Join-Path $script:Logs 'ApplicationControlBlocks.txt') -Encoding UTF8
        $errors += "检测到 $($blocks.Count) 条明确的 Code Integrity/AppLocker 阻断记录。"
    }

    if (-not (Test-BundleRegistered $OldBundleId) -and $current -eq $CurrentVersionExpected) {
        $warnings += "旧 MSI 为 $CurrentVersionExpected，但旧 Burn Bundle $OldBundleId 未注册；修复阶段仍可使用缓存回滚 EXE，但卸载后会严格验证 MSI 是否消失。"
    }

    foreach ($w in $warnings) { Add-Result "WARNING: $w" }
    foreach ($e in $errors) { Add-Result "ERROR: $e" }

    if ($errors.Count -eq 0) {
        'PASS' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'SELFTEST_STATUS.txt') -Encoding ASCII
        Add-Result 'SelfTest PASS：没有执行卸载/安装。'
    } else {
        'FAIL' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'SELFTEST_STATUS.txt') -Encoding ASCII
        Add-Result "SelfTest FAIL：errors=$($errors.Count)，没有执行卸载/安装。"
    }

    Pack-Report
    return ($errors.Count -eq 0)
}

function Get-ServiceSnapshot {
    $names = @('ArmouryCrateService','ROG Live Service','LightingService','AsusCertService','asComSvc')
    $result = @()
    foreach ($n in $names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) {
            $result += [PSCustomObject]@{Name=$svc.Name;WasRunning=($svc.Status -eq 'Running')}
        }
    }
    return $result
}

function Stop-ASUSServices {
    param([object[]]$Snapshot)
    Step '停止 Armoury/ASUS 相关服务'
    foreach ($s in $Snapshot) {
        try { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue } catch {}
    }
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match 'Armoury|ROG|LightingService|AacUHDRAM|AsusInstallVerifier'
        } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Restore-ASUSServices {
    param([object[]]$Snapshot)
    foreach ($s in $Snapshot) {
        if ($s.WasRunning) {
            try { Start-Service -Name $s.Name -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Stage-File {
    param([object]$Validated,[string]$Name)
    $dst = Join-Path $script:StageRun $Name
    Copy-Item -LiteralPath $Validated.Path -Destination $dst -Force
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst -ErrorAction Stop).Hash
    if ($hash -ne $Validated.SHA256) { throw "Stage SHA256 mismatch: $Name" }
    return $dst
}

function Create-ResumeTask {
    $stagedScript = Join-Path $script:StageRun 'ASUS_CoreHAL_4151_Fix.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $stagedScript -Force

    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        "-NoProfile -ExecutionPolicy Bypass -File `"$stagedScript`" -Phase PostReboot"
    )
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    $continueCmd = Join-Path $script:RunRoot 'Continue_After_Reboot.cmd'
    @"
@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$stagedScript" -Phase PostReboot
pause
"@ | Set-Content -LiteralPath $continueCmd -Encoding ASCII
}

function Remove-ResumeTask {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
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

function Try-RollbackOldVersion {
    param([string]$RollbackPath)
    Add-Result "开始尝试回滚 Core HAL 到 $CurrentVersionExpected。"
    $rc = Invoke-Exe $RollbackPath '/quiet /norestart' 'Rollback_1.0.0.7'
    Start-Sleep -Seconds 3
    $v = Get-MsiVersion
    Add-Result "回滚后 MSI version=$v"
    return (($rc -in 0,3010,1641) -and ($v -eq $CurrentVersionExpected))
}

function Run-Start {
    Initialize-Run

    Add-Result "ASUS Core HAL 4151 Targeted Fix v$ToolVersion"
    Add-Result '此阶段只处理 Universal Holtek RGB DRAM / Profile 44075。'

    # Repeat all important preflight checks inside repair mode.
    $current = Get-MsiVersion
    if ($current -ne $CurrentVersionExpected) {
        throw "修复前 MSI 版本必须是 $CurrentVersionExpected，实际=$current。请先运行 SelfTest。"
    }

    $target = Find-TargetInstaller
    if (-not $target) { throw '目标 1.0.0.8 安装器验证失败，停止。' }

    $rollback = Find-RollbackInstaller
    if (-not $rollback) { throw '旧版 1.0.0.7 回滚安装器验证失败，停止。' }

    $blocks = @(Get-ExplicitBlockEvidence)
    if ($blocks.Count -gt 0) { throw '检测到 Code Integrity/AppLocker 阻断，停止。' }

    try {
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Before ASUS Core HAL 4151 Fix' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Add-Result '系统还原点已创建。'
    } catch {
        Add-Result "系统还原点未创建：$($_.Exception.Message)"
    }

    Save-PreflightEvidence

    $runId = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:StageRun = Join-Path $BaseStageRoot $runId
    New-Item -ItemType Directory -Force -Path $script:StageRun | Out-Null

    $targetStage = Stage-File $target 'AacUHDRAMSetup_1.0.0.8.exe'
    $rollbackStage = Stage-File $rollback 'AacUHDRAMSetup_1.0.0.7_ROLLBACK.exe'

    $snapshot = @(Get-ServiceSnapshot)
    $bootBefore = Get-BootStamp

    $state = [PSCustomObject]@{
        ToolVersion=$ToolVersion
        Phase='Prepared'
        RunRoot=$script:RunRoot
        StageRun=$script:StageRun
        BootBefore=$bootBefore
        ProductCode=$ProductCode
        OldBundleId=$OldBundleId
        NewBundleId=$NewBundleId
        TargetPath=$targetStage
        TargetSHA256=$target.SHA256
        RollbackPath=$rollbackStage
        RollbackSHA256=$rollback.SHA256
        ServiceSnapshot=$snapshot
        Created=(Get-Date).ToString('o')
    }
    $statePath = Join-Path $script:StageRun 'state.json'
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $statePath | Set-Content -LiteralPath $CurrentStatePath -Encoding UTF8

    Create-ResumeTask
    Stop-ASUSServices $snapshot

    Step '标准卸载 Core HAL 1.0.0.7'
    $rc = Invoke-Exe $rollbackStage '/uninstall /quiet /norestart' 'CoreHAL_1.0.0.7_Uninstall'
    Start-Sleep -Seconds 3

    $msiRemains = Test-MsiRegistered
    $bundleRemains = Test-BundleRegistered $OldBundleId
    Add-Result "卸载后：MSI remains=$msiRemains ; old Burn remains=$bundleRemains"

    if (($rc -notin 0,3010,1641) -or $msiRemains) {
        Add-Result '旧 Core HAL 标准卸载没有完全成功，停止。'
        if (-not $msiRemains) {
            [void](Try-RollbackOldVersion $rollbackStage)
        }
        Restore-ASUSServices $snapshot
        Remove-ResumeTask
        Pack-Report
        throw 'Core HAL 旧版卸载失败；未执行 SourceHash 清理或新版安装。'
    }

    $state.Phase = 'AwaitingReboot'
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    'AWAITING_REBOOT' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
    Add-Result '阶段1成功：旧 Core HAL 已卸载。必须真实重启后再继续，当前未清理 SourceHash。'

    Stop-RunTranscript

    Write-Host ""
    Write-Host "阶段1完成。请现在重启 Windows。" -ForegroundColor Yellow
    $ans = Read-Host '输入 R 立即重启；直接回车稍后手动重启'
    if ($ans -match '^[Rr]$') {
        shutdown.exe /r /t 5 /c "ASUS Core HAL 4151 Fix continuing after reboot"
    }
}

function Move-ToBackup {
    param([string]$Path,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $dst = Join-Path $script:Backup ($Label + '_' + (Get-Date -Format 'HHmmss'))
    try {
        Move-Item -LiteralPath $Path -Destination $dst -Force -ErrorAction Stop
        Add-Result "已备份并移走：$Path -> $dst"
    } catch {
        Add-Result "无法移动 $Path：$($_.Exception.Message)"
        throw
    }
}

function Revalidate-Staged {
    param([string]$Path,[string]$ExpectedHash,[string]$Version)
    try {
        $test = Test-SignedFile $Path $Version
        if (-not $test.Valid) {
            Add-Result "重启后暂存包验证失败：$($test.Reason)"
            return $false
        }
        if ($test.SHA256 -ne $ExpectedHash) {
            Add-Result '重启后 SHA256 与阶段1不一致。'
            return $false
        }
        return $true
    } catch {
        Add-Result "重启后验证异常：$($_.Exception.Message)"
        return $false
    }
}

function Run-PostReboot {
    if (-not (Test-Path -LiteralPath $CurrentStatePath)) {
        throw '找不到 CurrentStatePath.txt；没有可续跑状态。'
    }

    $statePath = (Get-Content -LiteralPath $CurrentStatePath -Raw).Trim()
    if (-not (Test-Path -LiteralPath $statePath)) { throw "state.json 不存在：$statePath" }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

    Initialize-Run ([string]$state.RunRoot)
    $script:StageRun = [string]$state.StageRun

    if ([string]$state.Phase -ne 'AwaitingReboot') {
        throw "状态不是 AwaitingReboot：$($state.Phase)"
    }

    $before = [string]$state.BootBefore
    $after = Get-BootStamp
    if (-not $before -or -not $after -or $before -eq $after) {
        Add-Result '真实重启门禁失败：LastBootUpTime 没有变化。'
        Pack-Report
        throw '请真正重启 Windows 后再运行 Continue_After_Reboot.cmd。'
    }
    Add-Result "已确认真实重启：before=$before ; after=$after"

    if (Test-MsiRegistered) {
        Add-Result "重启后旧 MSI $ProductCode 仍然注册，拒绝继续清理。"
        Pack-Report
        throw '旧 MSI 仍注册。'
    }

    if (-not (Revalidate-Staged ([string]$state.TargetPath) ([string]$state.TargetSHA256) $TargetVersion)) {
        Pack-Report
        throw '目标暂存包重启后二次校验失败。'
    }
    if (-not (Revalidate-Staged ([string]$state.RollbackPath) ([string]$state.RollbackSHA256) $CurrentVersionExpected)) {
        Pack-Report
        throw '回滚暂存包重启后二次校验失败。'
    }

    Step '清理已确认卸载后的 Core HAL 残留'
    $sourceHash = "C:\Windows\Installer\SourceHash$ProductCode"
    Move-ToBackup $sourceHash 'SourceHash_OLD'

    $installDir = 'C:\Program Files\PD\Aac_Universal Holtek RGB DRAM'
    Move-ToBackup $installDir 'InstallDir_OLD'

    try {
        $tempDir = Join-Path $env:LOCALAPPDATA 'Temp\PD\Aac_Universal Holtek RGB DRAM'
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Add-Result "已清理临时验证目录：$tempDir"
        }
    } catch {}

    Step '安装 Core HAL 1.0.0.8'
    $rc = Invoke-Exe ([string]$state.TargetPath) '/quiet /norestart' 'CoreHAL_1.0.0.8_Install'
    Start-Sleep -Seconds 4

    $finalVersion = Get-MsiVersion
    $newBundle = Test-BundleRegistered $NewBundleId
    Add-Result "安装后：MSI version=$finalVersion ; target Burn registered=$newBundle"

    $snapshot = @($state.ServiceSnapshot)

    if (($rc -in 0,3010,1641) -and ($finalVersion -eq $TargetVersion)) {
        'SUCCESS' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        $state.Phase = 'Success'
        $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
        Add-Result 'SUCCESS：Core HAL 已从 1.0.0.7 更新到 1.0.0.8。'
        Restore-ASUSServices $snapshot
        Remove-ResumeTask
        Remove-Item -LiteralPath $CurrentStatePath -Force -ErrorAction SilentlyContinue
        Pack-Report
        return
    }

    Add-Result '目标 1.0.0.8 安装失败，开始回滚 1.0.0.7。'
    $rollbackOK = Try-RollbackOldVersion ([string]$state.RollbackPath)
    Restore-ASUSServices $snapshot
    Remove-ResumeTask

    if ($rollbackOK) {
        'FAILED_ROLLED_BACK' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result '目标安装失败，但旧版 1.0.0.7 已成功恢复。'
    } else {
        'FAILED_NEEDS_ATTENTION' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result '目标安装失败，且自动回滚未确认成功。请不要继续点 Armoury Crate 更新，上传报告。'
    }

    Pack-Report
}

function Run-Diagnose {
    Initialize-Run
    Save-PreflightEvidence
    $target = Find-TargetInstaller
    $rollback = Find-RollbackInstaller
    Add-Result "CurrentVersion=$(Get-MsiVersion)"
    Add-Result "OldBundleRegistered=$(Test-BundleRegistered $OldBundleId)"
    Add-Result "TargetFound=$([bool]$target)"
    Add-Result "RollbackFound=$([bool]$rollback)"
    Pack-Report
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
        Write-Host "ZIP 创建失败，但报告目录仍保留：$($script:RunRoot)" -ForegroundColor Yellow
    }
}

try {
    switch ($Phase) {
        'SelfTest'   { [void](Invoke-SelfTest) }
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
