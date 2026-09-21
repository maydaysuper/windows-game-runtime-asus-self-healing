#requires -version 5.1
<#
ASUS Armoury Crate 4151 Targeted Fix v1.3.6

Targeted to the diagnosed update chain on this machine:
  Optional Hal / AacPatriotDRAMSetup: 1.0.9.8 -> 1.0.9.9 (Profile 44074)
  TUF-RTX5080 / AacVGASetup:         0.0.8.2 -> 0.0.8.3 (Profile 70216)

Safety principles:
  - Verify exact RLS profile path + target version evidence + Authenticode before uninstall.
  - Stage and hash target installers before changing installed components.
  - Never delete GPU drivers, DriverStore, BIOS, unknown MSI registry data, or unrelated ASUS HALs.
  - Do not edit PendingFileRenameOperations. Let Windows process it normally on reboot.
  - Require a real reboot between clean uninstall and fresh install.
  - Re-validate staged installer signature + SHA256 after reboot before execution.
  - Standard Burn/MSI uninstall only. If registration remains, stop instead of force-deleting it.
  - Preserve rollback installers when available.
#>

[CmdletBinding()]
param(
    [ValidateSet('Start','PostReboot','SelfTest','Diagnose')]
    [string]$Phase = 'Start',
    [switch]$NoRebootPrompt
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$ToolVersion = '1.3.6'
$TaskName = 'ASUS_4151_TargetedFix_PostReboot'
$BaseStageRoot = Join-Path $env:ProgramData 'ASUS4151TargetedFix'
$CurrentStatePath = Join-Path $BaseStageRoot 'CurrentStatePath.txt'
$Desktop = [Environment]::GetFolderPath('Desktop')

$Components = @(
    [PSCustomObject]@{
        Key='Patriot'
        DisplayName='Patriot Viper DRAM RGB'
        OldVersion='1.0.9.8'
        TargetVersion='1.0.9.9'
        ProductCode='{1F9C282E-CCB4-4D8E-A5CB-7B74DFCD8C95}'
        KnownOldBundle='{55993b50-5bec-47c8-8b2b-1aecad927e48}'
        ProfileId='44074'
        ExeName='AacPatriotDRAMSetup.exe'
        RlsSubPath='Optional Hal\4_HAL\44074'
        TargetPathVersionToken='1.0.9.9'
        InstallDir=(Join-Path $env:ProgramFiles 'Patriot\Aac_Patriot Viper DRAM RGB')
        TempDir=(Join-Path $env:LOCALAPPDATA 'Temp\Patriot\Aac_Patriot Viper DRAM RGB')
        FailedCacheName='{1F9C282E-CCB4-4D8E-A5CB-7B74DFCD8C95}v1.0.9.9'
        StageFile='AacPatriotDRAMSetup_1.0.9.9.exe'
        SignerRegex='(?i)(Patriot|CN="?Creative Technology Innovation Co\., Ltd\."?.*SERIALNUMBER=28212069)'
        LogPattern='Patriot Viper DRAM RGB*.log'
    },
    [PSCustomObject]@{
        Key='VGA'
        DisplayName='ASUS AURA VGA Component'
        OldVersion='0.0.8.2'
        TargetVersion='0.0.8.3'
        ProductCode='{71BB96A6-EAC4-45AE-A17D-D3ED43FF1D14}'
        KnownOldBundle='{8060d9de-27d3-4bb0-8ae0-4ad7bb5f44b0}'
        ProfileId='70216'
        ExeName='AacVGASetup.exe'
        RlsSubPath='TUF-RTX5080\4_HAL\70216'
        TargetPathVersionToken=''
        InstallDir=(Join-Path $env:ProgramFiles 'ASUS\AacVGAHal')
        TempDir=(Join-Path $env:windir 'Temp\ASUS\AacVGAHal')
        FailedCacheName='{71BB96A6-EAC4-45AE-A17D-D3ED43FF1D14}v0.0.8.3'
        StageFile='AacVGASetup_0.0.8.3.exe'
        SignerRegex='ASUS|ASUSTeK'
        LogPattern='ASUS AURA VGA Component*.log'
    }
)

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $id
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

if (-not (Test-Admin)) {
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Phase $Phase"
    if ($NoRebootPrompt) { $arg += ' -NoRebootPrompt' }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arg
    } catch {
        Write-Host '需要管理员权限。' -ForegroundColor Red
        Read-Host '按 Enter 退出'
    }
    exit
}

# Prevent overlapping repair instances.
$script:Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList @($false, 'Global\ASUS4151TargetedFix_v130')
if (-not $script:Mutex.WaitOne(0, $false)) {
    Write-Host '已有一个 ASUS 4151 修复实例正在运行。' -ForegroundColor Yellow
    return
}

function Release-Mutex {
    try { $script:Mutex.ReleaseMutex() | Out-Null } catch {}
    try { $script:Mutex.Dispose() } catch {}
}

function Get-BootTimeText {
    try { return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToString('o') }
    catch { return '' }
}

function Get-StatePath {
    if (-not (Test-Path -LiteralPath $CurrentStatePath)) { return $null }
    try {
        $p = (Get-Content -LiteralPath $CurrentStatePath -Raw -ErrorAction Stop).Trim()
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    } catch {}
    return $null
}

function Read-State {
    $p = Get-StatePath
    if (-not $p) { return $null }
    try { return (Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json) }
    catch { return $null }
}

function Write-State([object]$State) {
    $tmp = $script:StatePath + '.tmp'
    $State.UpdatedAt = (Get-Date).ToString('o')
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $script:StatePath -Force
    $script:StatePath | Set-Content -LiteralPath $CurrentStatePath -Encoding ASCII
}

function Set-StatePhase([string]$NewPhase) {
    $s = Read-State
    if ($s) {
        $s.Phase = $NewPhase
        Write-State $s
    }
}

function Step([string]$Text) {
    Write-Host ''
    Write-Host "==== $Text ====" -ForegroundColor Cyan
}

function Add-Result([string]$Text) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    Write-Host $line
    if ($script:RunRoot) {
        try { $line | Add-Content -LiteralPath (Join-Path $script:RunRoot 'RESULTS.txt') -Encoding UTF8 } catch {}
    }
}

function Initialize-RunContext {
    param([switch]$UseExisting)

    New-Item -ItemType Directory -Force -Path $BaseStageRoot | Out-Null
    Protect-BaseStageRoot

    if ($UseExisting) {
        $state = Read-State
        if (-not $state) { throw '找不到可继续的修复状态。' }
        $script:RunRoot = [string]$state.RunRoot
        $script:StageRun = [string]$state.StageRun
        $script:StatePath = Get-StatePath
        $script:RecoveryRoot = [string]$state.RecoveryRoot
    } else {
        $runId = Get-Date -Format 'yyyyMMdd_HHmmss'
        $script:RunRoot = Join-Path $Desktop "ASUS_4151_TargetedFix_$runId"
        $script:StageRun = Join-Path $BaseStageRoot $runId
        $script:StatePath = Join-Path $script:StageRun 'state.json'
        $script:RecoveryRoot = Join-Path $script:StageRun 'Recovery'
        New-Item -ItemType Directory -Force -Path $script:RunRoot,$script:StageRun,$script:RecoveryRoot | Out-Null
    }

    $script:Logs = Join-Path $script:RunRoot 'Logs'
    $script:BackupMeta = Join-Path $script:RunRoot 'BackupMetadata'
    New-Item -ItemType Directory -Force -Path $script:RunRoot,$script:Logs,$script:BackupMeta | Out-Null

    $script:TranscriptActive = $false
    try {
        Start-Transcript -Path (Join-Path $script:RunRoot 'TargetedFix.log') -Append -Force | Out-Null
        $script:TranscriptActive = $true
    } catch {}
}

function Stop-TranscriptSafe {
    if ($script:TranscriptActive) {
        try { Stop-Transcript | Out-Null } catch {}
        $script:TranscriptActive = $false
    }
}

function Get-CurrentUserSidText {
    try { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { return $null }
}

function Protect-BaseStageRoot {
    try {
        New-Item -ItemType Directory -Force -Path $BaseStageRoot | Out-Null
        $userSid = Get-CurrentUserSidText
        $grants = @(
            '*S-1-5-18:(OI)(CI)F',
            '*S-1-5-32-544:(OI)(CI)F'
        )
        if ($userSid) { $grants += ("*{0}:(OI)(CI)F" -f $userSid) }

        & icacls.exe $BaseStageRoot /inheritance:r /grant:r $grants /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls BaseStageRoot exit=$LASTEXITCODE" }
    } catch {
        # Do not stop here; StageRun gets its own explicit ACL and signature/hash gates remain.
    }
}

function Protect-StageDirectory {
    # v1.3.6:
    # Never apply (OI)(CI) inheritance flags directly to every existing file with /T.
    # That pattern caused already-staged EXEs to become unreadable after reboot on this machine.
    # The root directory gets inheritable ACEs; existing descendants get explicit F ACEs without
    # inheritance flags, including the exact interactive administrator SID.
    try {
        $userSid = Get-CurrentUserSidText
        if (-not $userSid) { throw '无法获取当前用户 SID。' }

        $rootGrants = @(
            '*S-1-5-18:(OI)(CI)F',
            '*S-1-5-32-544:(OI)(CI)F',
            ("*{0}:(OI)(CI)F" -f $userSid)
        )
        & icacls.exe $script:StageRun /inheritance:r /grant:r $rootGrants /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls StageRun root exit=$LASTEXITCODE" }

        # Existing files/directories: explicit Full Control, no OI/CI flags on file ACEs.
        $directGrants = @(
            '*S-1-5-18:F',
            '*S-1-5-32-544:F',
            ("*{0}:F" -f $userSid)
        )
        & icacls.exe $script:StageRun /grant $directGrants /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls StageRun descendants exit=$LASTEXITCODE" }

        Add-Result "暂存目录 ACL 已修正：SYSTEM / Administrators / 当前用户 SID=$userSid 可访问；文件 ACE 不再错误套用 OI/CI。"
    } catch {
        Add-Result "暂存目录 ACL 修复失败：$($_.Exception.Message)"
        throw
    }
}

function Get-UninstallEntriesExact([string]$DisplayName) {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $all = @()
    foreach ($root in $roots) {
        $all += Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $DisplayName } |
            Select-Object DisplayName,DisplayVersion,Publisher,InstallDate,UninstallString,QuietUninstallString,PSChildName,PSPath
    }
    return @($all | Sort-Object PSPath -Unique)
}

function Get-MSIProductVersion([string]$ProductCode) {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode"
    )
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            return [string](Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue).DisplayVersion
        }
    }
    return $null
}

function Test-MSIProductRegistered([string]$ProductCode) {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode"
    )
    foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { return $true } }
    return $false
}

function Get-BundleEntries([object]$Component, [string]$Version) {
    return @(Get-UninstallEntriesExact $Component.DisplayName |
        Where-Object {
            $_.UninstallString -and
            $_.UninstallString -notmatch '(?i)msiexec' -and
            ((-not $Version) -or ([string]$_.DisplayVersion -eq $Version) -or ([string]$_.PSChildName -eq [string]$Component.KnownOldBundle))
        })
}

function Get-ExeAndArgsFromCommand([string]$CommandLine) {
    if (-not $CommandLine) { return $null }
    $exe = $null
    $args = ''
    if ($CommandLine -match '^\s*"([^"]+\.exe)"\s*(.*)$') {
        $exe = $matches[1]; $args = $matches[2]
    } elseif ($CommandLine -match '^\s*([^\s]+\.exe)\s*(.*)$') {
        $exe = $matches[1]; $args = $matches[2]
    }
    if (-not $exe) { return $null }
    return [PSCustomObject]@{ Exe=$exe; Args=$args }
}

function Export-RegKey([string]$NativeKey, [string]$Name) {
    try { & reg.exe export $NativeKey (Join-Path $script:BackupMeta "$Name.reg") /y | Out-Null } catch {}
}

function Save-PreflightState {
    Step '保存修复前状态'
    Export-RegKey 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' 'SessionManager'
    foreach ($c in $Components) {
        Export-RegKey "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($c.ProductCode)" "$($c.Key)_MSI64"
        Export-RegKey "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($c.ProductCode)" "$($c.Key)_MSI32"
        Get-UninstallEntriesExact $c.DisplayName | Format-List * | Out-String -Width 360 |
            Set-Content -LiteralPath (Join-Path $script:BackupMeta "$($c.Key)_UninstallEntries.txt") -Encoding UTF8
    }
    try {
        $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        $pending | Set-Content -LiteralPath (Join-Path $script:BackupMeta 'PendingFileRenameOperations_BEFORE.txt') -Encoding UTF8
    } catch {}
}

function Test-TargetVersionEvidence([object]$Component, [System.IO.FileInfo]$Item) {
    $target = [string]$Component.TargetVersion

    # 1) Preferred: Windows version resource embedded in the signed EXE.
    try {
        $vi = $Item.VersionInfo
        $vtext = @([string]$vi.ProductVersion,[string]$vi.FileVersion) -join ' | '
        if ($vtext -match [regex]::Escape($target)) {
            return [PSCustomObject]@{ Valid=$true; Method='VersionInfo'; Detail=$vtext }
        }
    } catch {}

    # 2) Recent ASUS/WiX Burn log that names this exact installer path and target bundle version.
    $roots = @(
        (Join-Path $env:ProgramData 'ASUS\ROG Live Service\InstallLog\MsiInstallLog'),
        (Join-Path $env:ProgramData 'ASUS\ARMOURY CRATE Diagnosis\ROG Live Service\InstallLog\MsiInstallLog')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    foreach ($root in $roots) {
        $logs = Get-ChildItem -LiteralPath $root -File -Filter $Component.LogPattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 30
        foreach ($log in $logs) {
            try {
                if ($log.LastWriteTime -lt $Item.LastWriteTime.AddMinutes(-10)) { continue }
                $raw = Get-Content -LiteralPath $log.FullName -Raw -ErrorAction Stop
                $escapedPath = [regex]::Escape($Item.FullName)
                if (($raw -match $escapedPath) -and ($raw -match ('WixBundleVersion\s*=\s*' + [regex]::Escape($target)))) {
                    return [PSCustomObject]@{ Valid=$true; Method='BurnLog'; Detail=$log.FullName }
                }
            } catch {}
        }
    }

    # 3) ASUS RLS metadata in the exact Profile subtree. Some ASUS Burn launchers carry
    # generic FileVersion values while JSON/XML/TXT metadata carries the package version.
    try {
        $profileRoot = Join-Path (Join-Path $env:ProgramFiles 'ASUS\RLSDownload') $Component.RlsSubPath
        if (Test-Path -LiteralPath $profileRoot) {
            $metaFiles = Get-ChildItem -LiteralPath $profileRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Length -le 4MB -and
                    $_.Extension -match '^\.(json|xml|txt|ini|config|manifest)$'
                } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 120

            foreach ($mf in $metaFiles) {
                try {
                    $raw = Get-Content -LiteralPath $mf.FullName -Raw -ErrorAction Stop
                    $hasTarget = $raw -match [regex]::Escape($target)
                    $hasIdentity = (
                        ($raw -match [regex]::Escape([string]$Component.ProfileId)) -or
                        ($raw -match [regex]::Escape([string]$Component.ExeName)) -or
                        ($raw -match [regex]::Escape([string]$Component.DisplayName))
                    )
                    if ($hasTarget -and $hasIdentity) {
                        return [PSCustomObject]@{ Valid=$true; Method='RLSMetadata'; Detail=$mf.FullName }
                    }
                } catch {}
            }
        }
    } catch {}

    # 4) Signed-binary content evidence. WiX Burn manifests frequently contain the bundle
    # version as ASCII/UTF-16 even when VersionInfo is generic. This reads but never executes.
    try {
        if ($Item.Length -le 100MB) {
            $bytes = [System.IO.File]::ReadAllBytes($Item.FullName)
            $asciiText = [System.Text.Encoding]::ASCII.GetString($bytes)
            if ($asciiText.IndexOf($target,[System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return [PSCustomObject]@{ Valid=$true; Method='BinaryASCII'; Detail="signed EXE contains $target" }
            }
            $unicodeText = [System.Text.Encoding]::Unicode.GetString($bytes)
            if ($unicodeText.IndexOf($target,[System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return [PSCustomObject]@{ Valid=$true; Method='BinaryUnicode'; Detail="signed EXE contains $target" }
            }
        }
    } catch {}

    # 5) Controlled fallback for ASUS RLS packages whose Burn stub exposes no usable version
    # resource/manifest text. This fallback is intentionally available only when the component
    # definition includes a target-version path token (currently Patriot only). The caller has
    # already required: exact Profile subtree, exact EXE name, valid Authenticode signature,
    # approved signer, and later records SHA256. Post-install must still equal TargetVersion;
    # otherwise the tool invokes the staged old-version rollback package.
    if ([string]$Component.TargetPathVersionToken) {
        try {
            $token = [string]$Component.TargetPathVersionToken
            $pathRegex = '(?i)(?:^|[\\/_\.-])' + [regex]::Escape($token) + '(?:[\\/_\.-]|$)'
            if ($Item.FullName -match $pathRegex) {
                return [PSCustomObject]@{
                    Valid=$true
                    Method='SignedExactProfilePathFallback'
                    Detail="exact profile path contains target token $token; strict post-install MSI version verification + rollback remain enabled"
                }
            }
        } catch {}
    }

    return [PSCustomObject]@{
        Valid=$false
        Method='None'
        Detail='无法从 VersionInfo、BurnLog、RLSMetadata、signed-binary content 或受控精确路径 fallback 证明目标版本。'
    }
}

function Find-And-ValidateTargetInstaller([object]$Component, [switch]$NoCopy) {
    $profileRoot = Join-Path (Join-Path $env:ProgramFiles 'ASUS\RLSDownload') $Component.RlsSubPath
    if (-not (Test-Path -LiteralPath $profileRoot)) {
        Add-Result "$($Component.Key): 找不到精确 Profile 目录：$profileRoot"
        return $null
    }

    $items = @(Get-ChildItem -LiteralPath $profileRoot -Recurse -File -Filter $Component.ExeName -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($Component.TargetPathVersionToken) {
        $items = @($items | Where-Object { $_.FullName -match [regex]::Escape($Component.TargetPathVersionToken) })
    }
    if ($items.Count -eq 0) {
        Add-Result "$($Component.Key): Profile $($Component.ProfileId) 中没有找到目标安装器。"
        return $null
    }

    $candidateAudit = @()
    foreach ($item in $items) {
        $viText = ''
        try { $viText = "ProductVersion=$($item.VersionInfo.ProductVersion); FileVersion=$($item.VersionInfo.FileVersion)" } catch {}

        if ($item.Length -lt 100KB) {
            $candidateAudit += "REJECT size<100KB | $($item.FullName) | $viText"
            continue
        }

        $sig = Get-AuthenticodeSignature -FilePath $item.FullName -ErrorAction SilentlyContinue
        if (-not $sig -or $sig.Status -ne 'Valid') {
            $candidateAudit += "REJECT signature=$($sig.Status) | $($item.FullName) | $viText"
            continue
        }

        $signer = ''
        try { $signer = [string]$sig.SignerCertificate.Subject } catch {}
        if (-not $signer -or $signer -notmatch [string]$Component.SignerRegex) {
            $candidateAudit += "REJECT signer=$signer | $($item.FullName) | $viText"
            continue
        }

        $ev = Test-TargetVersionEvidence $Component $item
        if (-not $ev.Valid) {
            $candidateAudit += "REJECT versionEvidence=$($ev.Method) detail=$($ev.Detail) | $($item.FullName) | $viText"
            continue
        }

        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName -ErrorAction SilentlyContinue
        if (-not $hash.Hash) {
            $candidateAudit += "REJECT no-SHA256 | $($item.FullName) | $viText"
            continue
        }

        $candidateAudit += "ACCEPT evidence=$($ev.Method) sha256=$($hash.Hash) signer=$signer | $($item.FullName) | $viText"
        $candidateAudit | Set-Content -LiteralPath (Join-Path $script:Logs "$($Component.Key)_CandidateAudit.txt") -Encoding UTF8

        @(
            "Key=$($Component.Key)",
            "Path=$($item.FullName)",
            "Length=$($item.Length)",
            "Signature=$($sig.Status)",
            "Signer=$signer",
            "SHA256=$($hash.Hash)",
            "VersionEvidence=$($ev.Method)",
            "VersionEvidenceDetail=$($ev.Detail)",
            $viText
        ) | Set-Content -LiteralPath (Join-Path $script:Logs "$($Component.Key)_TargetInstaller.txt") -Encoding UTF8

        $stagePath = Join-Path $script:StageRun $Component.StageFile
        if (-not $NoCopy) {
            Copy-Item -LiteralPath $item.FullName -Destination $stagePath -Force
            $stageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagePath -ErrorAction Stop).Hash
            if ($stageHash -ne $hash.Hash) {
                Add-Result "$($Component.Key): 暂存后 SHA256 不一致，停止。"
                return $null
            }
        }

        Add-Result "$($Component.Key): 已确认 Profile=$($Component.ProfileId)、目标=$($Component.TargetVersion)、签名 Valid、SHA256=$($hash.Hash.Substring(0,12))..."
        return [PSCustomObject]@{
            Key=$Component.Key
            SourcePath=$item.FullName
            StagePath=$stagePath
            SHA256=$hash.Hash
            Signer=$signer
            Evidence=$ev.Method
            TargetVersion=$Component.TargetVersion
        }
    }

    if ($candidateAudit.Count -gt 0) {
        $candidateAudit | Set-Content -LiteralPath (Join-Path $script:Logs "$($Component.Key)_CandidateAudit.txt") -Encoding UTF8
    }
    Add-Result "$($Component.Key): 找到安装器，但没有任何一个同时通过精确 Profile、目标版本证据、数字签名和哈希校验。"
    return $null
}

function Revalidate-StagedInstaller([object]$Component, [object]$StateComponent) {
    $path = [string]$StateComponent.StagePath
    if (-not (Test-Path -LiteralPath $path)) { Add-Result "$($Component.Key): 暂存安装器丢失。"; return $false }
    try {
        # Explicit read probe gives a precise ACL error before signature parsing.
        $fs = New-Object System.IO.FileStream(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try { [void]$fs.Length } finally { $fs.Dispose() }

        $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
        if (-not $sig -or $sig.Status -ne 'Valid') {
            Add-Result "$($Component.Key): 重启后数字签名不再是 Valid。"
            return $false
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path -ErrorAction Stop).Hash
        if (-not $hash -or $hash -ne [string]$StateComponent.SHA256) {
            Add-Result "$($Component.Key): 重启后 SHA256 与阶段1不一致。"
            return $false
        }
        Add-Result "$($Component.Key): 重启后暂存包可读，签名 Valid，SHA256 与阶段1一致。"
        return $true
    } catch {
        Add-Result "$($Component.Key): 重启后暂存包验证失败：$($_.Exception.Message)"
        return $false
    }
}

function Stage-RollbackInstaller([object]$Component, [string]$OriginalVersion) {
    $entries = @(Get-BundleEntries $Component $OriginalVersion)
    foreach ($e in $entries) {
        $cmd = if ($e.QuietUninstallString) { [string]$e.QuietUninstallString } else { [string]$e.UninstallString }
        $parsed = Get-ExeAndArgsFromCommand $cmd
        if (-not $parsed -or -not (Test-Path -LiteralPath $parsed.Exe)) { continue }
        $sig = Get-AuthenticodeSignature -FilePath $parsed.Exe -ErrorAction SilentlyContinue
        if (-not $sig -or $sig.Status -ne 'Valid') { continue }
        $rollbackSigner = ''
        try { $rollbackSigner = [string]$sig.SignerCertificate.Subject } catch {}
        if (-not $rollbackSigner -or $rollbackSigner -notmatch [string]$Component.SignerRegex) { continue }
        $dest = Join-Path $script:StageRun ("Rollback_{0}_{1}.exe" -f $Component.Key,$OriginalVersion)
        Copy-Item -LiteralPath $parsed.Exe -Destination $dest -Force
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest -ErrorAction SilentlyContinue).Hash
        Add-Result "$($Component.Key): 已保存旧版回滚安装器 $OriginalVersion。"
        return [PSCustomObject]@{ Path=$dest; SHA256=$hash; Version=$OriginalVersion; OriginalBundleKey=[string]$e.PSChildName }
    }
    Add-Result "$($Component.Key): 未找到可验证的旧版 Burn 回滚安装器；目标新版仍已完整暂存。"
    return $null
}

function Get-ServiceSnapshot {
    $names = @('ArmouryCrateService','ROG Live Service','LightingService','AsusCertService','asComSvc','AsusFanControlService','AsusROGLSLService')
    $out = @()
    foreach ($n in $names) {
        try {
            $s = Get-Service -Name $n -ErrorAction Stop
            $c = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $n.Replace("'","''")) -ErrorAction SilentlyContinue
            $out += [PSCustomObject]@{ Name=$n; WasRunning=($s.Status -eq 'Running'); StartMode=[string]$c.StartMode }
        } catch {}
    }
    return @($out)
}

function Stop-TargetProcessesAndServices {
    Step '停止 Armoury / Aura / HAL 相关进程与服务'
    $names = @('ArmouryCrateService','ROG Live Service','LightingService','AsusCertService','asComSvc','AsusFanControlService','AsusROGLSLService')
    foreach ($n in $names) { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue }
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^(ArmouryCrate|ArmouryCrate\.UserSessionHelper|ROGLiveService|LightingService|Aac.*VGA.*|Aac.*Patriot.*)$'
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Restore-ServiceSnapshot([object[]]$Snapshot) {
    foreach ($s in @($Snapshot)) {
        if ($s.WasRunning -and $s.StartMode -ne 'Disabled') {
            Start-Service -Name ([string]$s.Name) -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ProcessLogged {
    param([string]$File,[string]$Arguments,[string]$Name,[int]$Retry1618=2)
    $out = Join-Path $script:Logs "$Name.stdout.txt"
    $err = Join-Path $script:Logs "$Name.stderr.txt"
    $attempt = 0
    do {
        $attempt++
        try {
            $p = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput $out -RedirectStandardError $err
            $rc = [int]$p.ExitCode
        } catch {
            Add-Result "$Name 启动失败: $($_.Exception.Message)"
            return 99999
        }
        Add-Result "$Name attempt=$attempt ExitCode=$rc"
        if ($rc -ne 1618 -or $attempt -gt $Retry1618) { return $rc }
        Start-Sleep -Seconds 20
    } while ($true)
}

function Invoke-BundleUninstallEntry([object]$Entry,[string]$Label) {
    $cmd = if ($Entry.QuietUninstallString) { [string]$Entry.QuietUninstallString } else { [string]$Entry.UninstallString }
    $parsed = Get-ExeAndArgsFromCommand $cmd
    if (-not $parsed -or -not (Test-Path -LiteralPath $parsed.Exe)) {
        Add-Result "${Label}: Burn 卸载器路径无效：$cmd"
        return 1619
    }
    $args = [string]$parsed.Args
    if ($args -notmatch '(?i)(/|-)uninstall') { $args += ' /uninstall' }
    if ($args -notmatch '(?i)(/|-)quiet') { $args += ' /quiet' }
    if ($args -notmatch '(?i)(/|-)norestart') { $args += ' /norestart' }
    return Invoke-ProcessLogged $parsed.Exe $args ("{0}_BundleUninstall" -f $Label)
}

function Invoke-MSIUninstall([object]$Component) {
    if (-not (Test-MSIProductRegistered $Component.ProductCode)) { return 0 }
    $log = Join-Path $script:Logs "$($Component.Key)_MSI_Uninstall.log"
    $attempt = 0
    do {
        $attempt++
        try {
            $p = Start-Process msiexec.exe -ArgumentList "/x $($Component.ProductCode) /qn /norestart /L*v `"$log`"" -Wait -PassThru
            $rc = [int]$p.ExitCode
        } catch { return 99999 }
        Add-Result "$($Component.Key) MSI uninstall attempt=$attempt ExitCode=$rc"
        if ($rc -ne 1618 -or $attempt -ge 3) { return $rc }
        Start-Sleep -Seconds 20
    } while ($true)
}

function Uninstall-ComponentCleanly([object]$Component,[string]$OriginalVersion) {
    Step "标准卸载 $($Component.DisplayName) $OriginalVersion"
    $bundleEntries = @(Get-BundleEntries $Component $OriginalVersion)
    foreach ($entry in $bundleEntries) {
        [void](Invoke-BundleUninstallEntry $entry $Component.Key)
        Start-Sleep -Seconds 2
    }

    if (Test-MSIProductRegistered $Component.ProductCode) {
        [void](Invoke-MSIUninstall $Component)
        Start-Sleep -Seconds 2
    }

    # One more standard Burn attempt can clean stale bundle registration after MSI removal.
    $remainingBundles = @(Get-BundleEntries $Component $OriginalVersion)
    foreach ($entry in $remainingBundles) {
        [void](Invoke-BundleUninstallEntry $entry ($Component.Key + '_Retry'))
        Start-Sleep -Seconds 2
    }

    $msiRemains = Test-MSIProductRegistered $Component.ProductCode
    $bundleRemains = @((Get-BundleEntries $Component $OriginalVersion)).Count -gt 0
    Add-Result "$($Component.Key) 卸载后：MSI remains=$msiRemains; old Burn bundle remains=$bundleRemains"
    return (-not $msiRemains -and -not $bundleRemains)
}

function Move-ResidualToRecovery([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $safe = $Label + '_' + (Get-Date -Format 'HHmmss')
    $dest = Join-Path $script:RecoveryRoot $safe
    try {
        Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Path) {
            Add-Result "残留移动后原路径仍存在：$Path"
            return $false
        }
        Add-Result "残留已移动到 Recovery：$Path -> $dest"
        return $true
    } catch {
        Add-Result "无法移动残留 $Path：$($_.Exception.Message)"
        return $false
    }
}

function Cleanup-ResidualAfterReboot([object]$Component) {
    # At this point product and old bundle registration were already verified absent before reboot.
    if (Test-MSIProductRegistered $Component.ProductCode) {
        Add-Result "$($Component.Key): 重启后 MSI 注册意外恢复，拒绝清理残留。"
        return $false
    }
    if (@(Get-BundleEntries $Component $Component.OldVersion).Count -gt 0) {
        Add-Result "$($Component.Key): 重启后旧 Burn 注册仍存在，拒绝清理残留。"
        return $false
    }

    $sourceHash = Join-Path (Join-Path $env:windir 'Installer') ("SourceHash{0}" -f $Component.ProductCode)
    $failedCache = Join-Path (Join-Path $env:ProgramData 'Package Cache') $Component.FailedCacheName
    $okInstall = Move-ResidualToRecovery $Component.InstallDir ($Component.Key + '_InstallDir')
    $okHash = Move-ResidualToRecovery $sourceHash ($Component.Key + '_SourceHash')
    # Failed target cache is safe to preserve if move fails; Burn can normally replace/re-cache it.
    [void](Move-ResidualToRecovery $failedCache ($Component.Key + '_FailedTargetCache'))

    $okTemp = $true
    if (Test-Path -LiteralPath $Component.TempDir) {
        try {
            Remove-Item -LiteralPath $Component.TempDir -Recurse -Force -ErrorAction Stop
            $okTemp = -not (Test-Path -LiteralPath $Component.TempDir)
            Add-Result "$($Component.Key): 已清除验证器临时目录。"
        } catch {
            $okTemp = $false
            Add-Result "$($Component.Key): 临时目录清理失败：$($_.Exception.Message)"
        }
    }

    if (-not $okInstall -or -not $okHash -or -not $okTemp) {
        Add-Result "$($Component.Key): 关键残留未能安全移除，拒绝继续安装，避免重复 1721/1603。"
        return $false
    }
    return $true
}

function Save-PendingRenameAfterReboot {
    try {
        $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        $pending | Set-Content -LiteralPath (Join-Path $script:BackupMeta 'PendingFileRenameOperations_AFTER_REBOOT.txt') -Encoding UTF8
    } catch {}
}

function Create-ResumeInfrastructure([object]$State) {
    try {
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $script:StageRun 'ASUS_4151_TargetedFix.ps1') -Force
        $resumePs1 = Join-Path $script:StageRun 'ASUS_4151_TargetedFix.ps1'
        $manualCmd = Join-Path $script:RunRoot 'Continue_After_Reboot.cmd'
        $cmdText = "@echo off`r`nchcp 65001 >nul`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$resumePs1`" -Phase PostReboot`r`n"
        [IO.File]::WriteAllText($manualCmd,$cmdText,[Text.Encoding]::ASCII)

        Import-Module ScheduledTasks -ErrorAction Stop
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$resumePs1`" -Phase PostReboot -NoRebootPrompt"
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Add-Result "已创建重启续跑任务，并生成手动备用入口：$manualCmd"
        return $true
    } catch {
        Add-Result "创建重启续跑基础设施失败：$($_.Exception.Message)"
        return $false
    }
}

function Remove-ResumeInfrastructure {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

function Collect-FailureEvidence([datetime]$Since) {
    Step '收集本次安装失败证据'
    try {
        Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='MsiInstaller';StartTime=$Since} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'Patriot|AURA VGA|AacVGA|1721|1603' } |
            Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String -Width 360 |
            Set-Content -LiteralPath (Join-Path $script:Logs 'Fresh_MsiInstaller_Events.txt') -Encoding UTF8
    } catch {}
    foreach ($logName in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-AppLocker/EXE and DLL','Microsoft-Windows-AppLocker/MSI and Script')) {
        try {
            $safe = ($logName -replace '[\\/:*?"<>| ]','_')
            Get-WinEvent -FilterHashtable @{LogName=$logName;StartTime=$Since} -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match 'AsusInstallVerifier|AacVGA|Patriot|AacPatriot' } |
                Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String -Width 360 |
                Set-Content -LiteralPath (Join-Path $script:Logs "Fresh_$safe.txt") -Encoding UTF8
        } catch {}
    }
}

function Install-TargetComponent([object]$Component,[object]$StateComponent) {
    if (-not (Revalidate-StagedInstaller $Component $StateComponent)) { return [PSCustomObject]@{Success=$false;ExitCode=99998;Version=(Get-MSIProductVersion $Component.ProductCode)} }
    $start = Get-Date
    $rc = Invoke-ProcessLogged ([string]$StateComponent.StagePath) '/quiet /norestart' ("{0}_{1}_Install" -f $Component.Key,$Component.TargetVersion) 0
    Start-Sleep -Seconds 3
    $v = Get-MSIProductVersion $Component.ProductCode
    $success = (($rc -in 0,3010,1641) -and ($v -eq $Component.TargetVersion))
    Add-Result "$($Component.Key): target install ExitCode=$rc; detected version=$v; success=$success"
    return [PSCustomObject]@{Success=$success;ExitCode=$rc;Version=$v;StartTime=$start}
}

function Try-RollbackComponent([object]$Component,[object]$StateComponent) {
    if (-not $StateComponent.RollbackPath) { Add-Result "$($Component.Key): 无可用回滚安装器。"; return $false }
    if (Test-MSIProductRegistered $Component.ProductCode) {
        $current = Get-MSIProductVersion $Component.ProductCode
        if ($current -eq [string]$StateComponent.OriginalVersion) {
            Add-Result "$($Component.Key): 目标安装失败后 Burn 已自动回滚到原版本 $current，无需再次回滚。"
            return $true
        }
        Add-Result "$($Component.Key): 目标安装失败后仍有 MSI 注册（version=$current），为避免覆盖半安装状态，不自动回滚。"
        return $false
    }
    $path = [string]$StateComponent.RollbackPath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction SilentlyContinue
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path -ErrorAction SilentlyContinue).Hash
    if (-not $sig -or $sig.Status -ne 'Valid' -or $hash -ne [string]$StateComponent.RollbackSHA256) {
        Add-Result "$($Component.Key): 回滚包签名/哈希校验失败，不执行。"
        return $false
    }
    $rc = Invoke-ProcessLogged $path '/quiet /norestart' ("{0}_Rollback_{1}" -f $Component.Key,$StateComponent.OriginalVersion) 0
    Start-Sleep -Seconds 3
    $v = Get-MSIProductVersion $Component.ProductCode
    $ok = (($rc -in 0,3010,1641) -and ($v -eq [string]$StateComponent.OriginalVersion))
    Add-Result "$($Component.Key): rollback ExitCode=$rc; version=$v; success=$ok"
    return $ok
}

function Pack-Report {
    Stop-TranscriptSafe
    Start-Sleep -Milliseconds 500
    $zip = "$($script:RunRoot).zip"
    try {
        Compress-Archive -Path (Join-Path $script:RunRoot '*') -DestinationPath $zip -Force -ErrorAction Stop
        Write-Host "报告 ZIP: $zip" -ForegroundColor Green
        return
    } catch {
        Add-Result "主 ZIP 打包失败，启用兼容打包：$($_.Exception.Message)"
    }

    $stage = Join-Path $env:TEMP ('ASUS4151Pack_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        Get-ChildItem -LiteralPath $script:RunRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $rel = $_.FullName.Substring($script:RunRoot.Length).TrimStart('\')
                $dst = Join-Path $stage $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                $srcStream = [IO.File]::Open($_.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try {
                    $dstStream = [IO.File]::Open($dst,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
                    try { $srcStream.CopyTo($dstStream) } finally { $dstStream.Dispose() }
                } finally { $srcStream.Dispose() }
            } catch {
                "Skipped: $($_.FullName) :: $($_.Exception.Message)" | Add-Content -LiteralPath (Join-Path $stage 'PACKING_SKIPPED_FILES.txt') -Encoding UTF8
            }
        }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force -ErrorAction Stop
        Write-Host "报告 ZIP: $zip" -ForegroundColor Green
    } catch {
        Write-Host "ZIP 仍失败；未压缩报告保留在：$($script:RunRoot)" -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ComponentPlan([object]$Component) {
    $v = Get-MSIProductVersion $Component.ProductCode
    $bundles = @(Get-BundleEntries $Component $null)
    if ($v -eq $Component.TargetVersion) {
        return [PSCustomObject]@{Action='AlreadyTarget';CurrentVersion=$v;Reason='目标版本已安装'}
    }
    if ($v) {
        try {
            if ([version]$v -gt [version]$Component.TargetVersion) {
                return [PSCustomObject]@{Action='SkipNewer';CurrentVersion=$v;Reason='当前版本高于本工具目标，禁止降级'}
            }
        } catch {}
        if ($v -ne $Component.OldVersion) {
            return [PSCustomObject]@{Action='StopUnexpected';CurrentVersion=$v;Reason='当前 MSI 版本不等于已诊断旧版本'}
        }
        return [PSCustomObject]@{Action='UninstallThenInstall';CurrentVersion=$v;Reason='命中已诊断旧版本'}
    }
    $oldBundle = @($bundles | Where-Object { $_.DisplayVersion -eq $Component.OldVersion }).Count -gt 0
    if ($oldBundle) {
        return [PSCustomObject]@{Action='UninstallThenInstall';CurrentVersion='MSI missing';Reason='旧 Burn bundle 仍注册'}
    }
    return [PSCustomObject]@{Action='InstallOnly';CurrentVersion='Not installed';Reason='没有旧 MSI/Burn 注册，可直接干净安装'}
}


function Get-ApplicationControlBlockEvidence {
    $hits = @()
    $since = (Get-Date).AddDays(-2)

    # Microsoft Code Integrity: 3077 = enforcement-mode block.
    try {
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational';Id=3077;StartTime=$since} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match '(?i)AsusInstallVerifier|AacVGASetup|AacPatriotDRAMSetup' } |
            ForEach-Object {
                $hits += [PSCustomObject]@{Log='CodeIntegrity';Id=$_.Id;TimeCreated=$_.TimeCreated;Message=$_.Message}
            }
    } catch {}

    # AppLocker: 8004 = EXE/DLL blocked, 8007 = MSI/Script blocked.
    try {
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppLocker/EXE and DLL';Id=8004;StartTime=$since} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match '(?i)AsusInstallVerifier|AacVGASetup|AacPatriotDRAMSetup' } |
            ForEach-Object {
                $hits += [PSCustomObject]@{Log='AppLocker EXE/DLL';Id=$_.Id;TimeCreated=$_.TimeCreated;Message=$_.Message}
            }
    } catch {}
    try {
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppLocker/MSI and Script';Id=8007;StartTime=$since} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match '(?i)AsusInstallVerifier|AacVGASetup|AacPatriotDRAMSetup|Patriot Viper DRAM RGB|ASUS AURA VGA Component' } |
            ForEach-Object {
                $hits += [PSCustomObject]@{Log='AppLocker MSI/Script';Id=$_.Id;TimeCreated=$_.TimeCreated;Message=$_.Message}
            }
    } catch {}

    if ($script:Logs) {
        if ($hits.Count -gt 0) {
            $hits | Sort-Object TimeCreated | Format-List * | Out-String -Width 420 |
                Set-Content -LiteralPath (Join-Path $script:Logs 'Preflight_ApplicationControlBlocks.txt') -Encoding UTF8
        } else {
            'No explicit Code Integrity 3077 / AppLocker 8004 or 8007 block matching the target ASUS installers was found in the last 48 hours.' |
                Set-Content -LiteralPath (Join-Path $script:Logs 'Preflight_ApplicationControlBlocks.txt') -Encoding UTF8
        }
    }
    return $hits
}

function Invoke-SelfTest([switch]$ForRepair) {
    Step '自检 PowerShell / 系统 / 安装器'
    $errors = @()
    $warnings = @()

    if ($PSVersionTable.PSVersion -lt [version]'5.1') { $errors += '需要 Windows PowerShell 5.1 或更高的 Windows PowerShell。' }
    foreach ($cmd in @('Get-AuthenticodeSignature','Get-FileHash','Get-CimInstance','Register-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskPrincipal')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { $errors += "缺少命令：$cmd" }
    }
    try {
        $systemDriveName = $env:SystemDrive.Substring(0,1)
        $free = (Get-PSDrive -Name $systemDriveName -ErrorAction Stop).Free
        if ($free -lt 2GB) { $errors += '系统盘剩余空间低于 2 GB。' }
    } catch { $warnings += '无法读取系统盘剩余空间。' }

    # Armoury Crate/ROG Live Service launches HAL installers in the interactive user's context.
    # If UAC elevation switched to a different administrator account, HKCU and logon-task context
    # would no longer match the desktop user; stop before touching installed components.
    try {
        $activeUser = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        $currentUser = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        if (-not $activeUser) {
            $warnings += '无法确认当前交互式登录用户；如果你是通过“其他管理员账号”输入 UAC 凭据启动，请不要继续修复。'
        } elseif (-not [string]::Equals($activeUser,$currentUser,[System.StringComparison]::OrdinalIgnoreCase)) {
            $errors += "当前提升身份 $currentUser 与桌面登录用户 $activeUser 不一致。请使用当前登录、且本身属于 Administrators 组的账户运行，避免 HAL 安装进入错误的 HKCU/登录上下文。"
        }
    } catch {
        $warnings += '无法核对交互式登录用户与提升身份。'
    }

    $appControlBlocks = @(Get-ApplicationControlBlockEvidence)
    if ($appControlBlocks.Count -gt 0) {
        $errors += "检测到 $($appControlBlocks.Count) 条明确的 Code Integrity/AppLocker 阻断记录，命中了 AsusInstallVerifier 或目标 HAL 安装器。为避免先卸载后仍被策略阻断，本工具不会执行修复。详见 Preflight_ApplicationControlBlocks.txt。"
    }

    $plans = @()
    $targets = @()
    foreach ($c in $Components) {
        $plan = Get-ComponentPlan $c
        $plans += [PSCustomObject]@{Key=$c.Key;Action=$plan.Action;CurrentVersion=$plan.CurrentVersion;Reason=$plan.Reason}
        Add-Result "$($c.Key) plan=$($plan.Action); current=$($plan.CurrentVersion); $($plan.Reason)"
        if ($plan.Action -eq 'StopUnexpected') { $errors += "$($c.Key) 当前版本 $($plan.CurrentVersion) 与已诊断版本不一致。" }
        if ($plan.Action -eq 'SkipNewer') { $warnings += "$($c.Key) 已是比目标更高的版本，将跳过。" }
        if ($plan.Action -in @('UninstallThenInstall','InstallOnly')) {
            if ($ForRepair) { $target = Find-And-ValidateTargetInstaller $c }
            else { $target = Find-And-ValidateTargetInstaller $c -NoCopy }
            if (-not $target) { $errors += "$($c.Key) 无法确认安全且版本正确的目标安装器。" }
            else { $targets += $target }
        }
    }

    $plans | Format-Table -AutoSize | Out-String -Width 240 | Set-Content -LiteralPath (Join-Path $script:Logs 'SelfTest_Plans.txt') -Encoding UTF8
    $errors | Set-Content -LiteralPath (Join-Path $script:Logs 'SelfTest_Errors.txt') -Encoding UTF8
    $warnings | Set-Content -LiteralPath (Join-Path $script:Logs 'SelfTest_Warnings.txt') -Encoding UTF8
    Add-Result "SelfTest: errors=$($errors.Count), warnings=$($warnings.Count)"
    return [PSCustomObject]@{ Passed=($errors.Count -eq 0); Errors=@($errors); Warnings=@($warnings); Plans=@($plans); Targets=@($targets) }
}

function Run-SelfTestOnly {
    Initialize-RunContext
    $r = Invoke-SelfTest
    if ($r.Passed) {
        'PASS' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'SELFTEST_STATUS.txt') -Encoding ASCII
        Write-Host '自检通过：未执行卸载或安装。' -ForegroundColor Green
    } else {
        'FAIL' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'SELFTEST_STATUS.txt') -Encoding ASCII
        Write-Host '自检未通过：未执行任何卸载或安装。' -ForegroundColor Yellow
    }
    Pack-Report
    if (-not $NoRebootPrompt) { Read-Host '按 Enter 关闭' }
}

function Run-DiagnoseOnly {
    Initialize-RunContext
    Save-PreflightState
    [void](Invoke-SelfTest)
    try {
        Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='MsiInstaller';StartTime=(Get-Date).AddDays(-14)} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'Patriot|AURA VGA|1721|1603' } |
            Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String -Width 360 |
            Set-Content -LiteralPath (Join-Path $script:Logs 'MsiInstaller_14days.txt') -Encoding UTF8
    } catch {}
    Pack-Report
    if (-not $NoRebootPrompt) { Read-Host '按 Enter 关闭' }
}

function Abort-Repair([string]$Reason,[object[]]$ServiceSnapshot) {
    Add-Result "ABORTED: $Reason"
    'ABORTED' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
    Set-StatePhase 'Aborted'
    Restore-ServiceSnapshot $ServiceSnapshot
    Remove-ResumeInfrastructure
    Pack-Report
}

function Run-Start {
    # Do not start a second repair if a previous one awaits reboot.
    $existing = Read-State
    if ($existing) {
        if ([string]$existing.Phase -eq 'AwaitingReboot') {
            $before = [string]$existing.PreRebootBootTime
            $now = Get-BootTimeText
            if ($before -and $now -and $before -ne $now) {
                Add-Result '检测到上一阶段已完成且系统已重启，转入 PostReboot。'
                Run-PostReboot
                return
            }
            Write-Host '已有一次修复正在等待重启。请先重启 Windows；不要重复执行阶段1。' -ForegroundColor Yellow
            return
        }
        if ([string]$existing.Phase -in @('Prepared','Uninstalling')) {
            Write-Host "检测到未完成的旧状态：$($existing.Phase)。为避免重复卸载，本次不会继续自动修改。请运行 Diagnose 或把现有报告发回。" -ForegroundColor Yellow
            return
        }
        # Terminal state: clear pointer; old run files remain for audit.
        if ([string]$existing.Phase -in @('Completed','Failed','Aborted')) {
            Remove-Item -LiteralPath $CurrentStatePath -Force -ErrorAction SilentlyContinue
        }
    }

    Initialize-RunContext
    Write-Host "ASUS Armoury Crate 4151 Targeted Fix v$ToolVersion" -ForegroundColor Green
    Write-Host "工作目录：$($script:RunRoot)"

    Save-PreflightState
    $self = Invoke-SelfTest -ForRepair
    if (-not $self.Passed) {
        'SELFTEST_FAILED' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Write-Host '安全自检未通过，因此没有卸载任何组件。' -ForegroundColor Yellow
        Pack-Report
        return
    }

    # If nothing needs repair, finish without touching installed components.
    $repairPlans = @($self.Plans | Where-Object { $_.Action -in @('UninstallThenInstall','InstallOnly') })
    if ($repairPlans.Count -eq 0) {
        'ALREADY_OK' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result '两个目标组件均无需降级/修复。'
        Pack-Report
        return
    }

    Protect-StageDirectory

    $stateComponents = @()
    $missingRollback = @()
    foreach ($c in $Components) {
        $plan = $self.Plans | Where-Object { $_.Key -eq $c.Key } | Select-Object -First 1
        if (-not $plan) { continue }
        $target = $self.Targets | Where-Object { $_.Key -eq $c.Key } | Select-Object -First 1
        $rollback = $null
        if ($plan.Action -eq 'UninstallThenInstall') {
            $rollbackVersion = [string]$plan.CurrentVersion
            if ($rollbackVersion -eq 'MSI missing') { $rollbackVersion = [string]$c.OldVersion }
            $rollback = Stage-RollbackInstaller $c $rollbackVersion
            if (-not $rollback) { $missingRollback += [string]$c.Key }
        }
        $stagePath = ''
        $stageHash = ''
        $rollbackPath = ''
        $rollbackHash = ''
        if ($target) { $stagePath = [string]$target.StagePath; $stageHash = [string]$target.SHA256 }
        if ($rollback) { $rollbackPath = [string]$rollback.Path; $rollbackHash = [string]$rollback.SHA256 }
        $originalVersionForState = [string]$plan.CurrentVersion
        if ($originalVersionForState -eq 'MSI missing') { $originalVersionForState = [string]$c.OldVersion }
        $stateComponents += [PSCustomObject]@{
            Key=$c.Key
            Action=[string]$plan.Action
            OriginalVersion=$originalVersionForState
            TargetVersion=[string]$c.TargetVersion
            StagePath=$stagePath
            SHA256=$stageHash
            RollbackPath=$rollbackPath
            RollbackSHA256=$rollbackHash
            Result='Pending'
        }
    }

    if ($missingRollback.Count -gt 0) {
        $msg = '安全前置条件未满足：以下待卸载组件没有找到可验证、可暂存的旧版 Burn 回滚包：' + ($missingRollback -join ', ')
        Add-Result $msg
        'PRECONDITION_FAILED_NO_ROLLBACK' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Write-Host '为避免“第一个组件已卸载、第二个组件失败”时无法恢复，本工具没有卸载任何 HAL。' -ForegroundColor Yellow
        Pack-Report
        return
    }

    try {
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Before ASUS 4151 Targeted Fix v1.3.6' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Add-Result '系统还原点已创建。'
    } catch { Add-Result "系统还原点未创建：$($_.Exception.Message)" }

    $serviceSnapshot = Get-ServiceSnapshot
    $state = [PSCustomObject]@{
        ToolVersion=$ToolVersion
        Phase='Prepared'
        RunRoot=$script:RunRoot
        StageRun=$script:StageRun
        RecoveryRoot=$script:RecoveryRoot
        StatePath=$script:StatePath
        CreatedAt=(Get-Date).ToString('o')
        UpdatedAt=(Get-Date).ToString('o')
        PreRebootBootTime=Get-BootTimeText
        ServiceSnapshot=$serviceSnapshot
        Components=$stateComponents
    }
    Write-State $state

    if (-not (Create-ResumeInfrastructure $state)) {
        Set-StatePhase 'Aborted'
        Remove-ResumeInfrastructure
        'ABORTED_RESUME_SETUP' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Pack-Report
        return
    }

    Stop-TargetProcessesAndServices
    Set-StatePhase 'Uninstalling'

    $allClean = $true
    foreach ($c in $Components) {
        $sc = $stateComponents | Where-Object { $_.Key -eq $c.Key } | Select-Object -First 1
        if (-not $sc) { continue }
        if ([string]$sc.Action -eq 'UninstallThenInstall') {
            $orig = [string]$sc.OriginalVersion
            if ($orig -eq 'MSI missing') { $orig = $c.OldVersion }
            if (-not (Uninstall-ComponentCleanly $c $orig)) { $allClean = $false }
        }
    }

    if (-not $allClean) {
        Step '部分卸载失败：尝试恢复已成功卸载的旧组件'
        foreach ($c in $Components) {
            $sc = $stateComponents | Where-Object { $_.Key -eq $c.Key } | Select-Object -First 1
            if (-not $sc -or [string]$sc.Action -ne 'UninstallThenInstall') { continue }
            [void](Try-RollbackComponent $c $sc)
        }
        Abort-Repair '至少一个旧 HAL 无法通过标准 Burn/MSI 卸载完全移除；已尝试恢复任何已卸载组件，且未进行暴力注册表删除。' $serviceSnapshot
        return
    }

    # Important: DO NOT edit PendingFileRenameOperations or move install folders here.
    # Windows must be allowed to finish its normal pending file operations during reboot.
    $state = Read-State
    $state.Phase = 'AwaitingReboot'
    $state.PreRebootBootTime = Get-BootTimeText
    Write-State $state
    'AWAITING_REBOOT' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
    Add-Result '阶段1完成：旧组件已标准卸载。未修改 PendingFileRenameOperations。必须完成一次真实重启后才能安装新版。'

    # If the user postpones reboot, restore previously running infrastructure/fan services.
    Restore-ServiceSnapshot $serviceSnapshot
    Stop-TranscriptSafe

    Write-Host ''
    Write-Host '阶段1完成。现在必须重启 Windows。登录原账户后会自动继续；桌面报告目录内也有 Continue_After_Reboot.cmd 备用入口。' -ForegroundColor Yellow
    if ($NoRebootPrompt) { return }
    $ans = Read-Host '输入 R 立即重启；直接按 Enter 则稍后手动重启'
    if ($ans -match '^[Rr]$') { shutdown.exe /r /t 5 /c 'ASUS 4151 Targeted Fix: continue after reboot' }
}

function Run-PostReboot {
    Initialize-RunContext -UseExisting
    $state = Read-State
    if (-not $state) { throw '找不到 PostReboot 状态。' }
    Write-Host "ASUS 4151 Targeted Fix v$ToolVersion - PostReboot" -ForegroundColor Green

    if ([string]$state.Phase -ne 'AwaitingReboot') {
        Add-Result "PostReboot 拒绝执行：当前状态是 $($state.Phase)，不是 AwaitingReboot。"
        Pack-Report
        return
    }
    $before = [string]$state.PreRebootBootTime
    $after = Get-BootTimeText
    if (-not $before -or -not $after -or $before -eq $after) {
        Add-Result '没有检测到阶段1之后的真实 Windows 重启，因此拒绝安装新版。'
        Write-Host '必须先真正重启 Windows，不能只注销或直接再次运行脚本。' -ForegroundColor Yellow
        Pack-Report
        return
    }
    Add-Result "已确认真实重启：before=$before ; after=$after"

    # Repair/normalize staging ACL before touching residuals or reading staged EXEs.
    # Safe to run repeatedly and required for recovery from the v1.3.5 ACL bug.
    Protect-StageDirectory
    Save-PendingRenameAfterReboot

    $serviceSnapshot = @($state.ServiceSnapshot)
    Stop-TargetProcessesAndServices
    $installStart = Get-Date
    $overall = $true
    $needsSecondReboot = $false

    foreach ($c in $Components) {
        $sc = $state.Components | Where-Object { $_.Key -eq $c.Key } | Select-Object -First 1
        if (-not $sc) { continue }
        if ([string]$sc.Action -notin @('UninstallThenInstall','InstallOnly')) { continue }

        if (-not (Cleanup-ResidualAfterReboot $c)) {
            $overall = $false
            $sc.Result = 'ResidualCleanupBlocked'
            continue
        }
        $r = Install-TargetComponent $c $sc
        if ($r.ExitCode -in 3010,1641) { $needsSecondReboot = $true }
        if ($r.Success) {
            $sc.Result = 'TargetInstalled'
        } else {
            $overall = $false
            $rolled = Try-RollbackComponent $c $sc
            if ($rolled) { $sc.Result = 'TargetFailed_RolledBack' } else { $sc.Result = 'TargetFailed' }
        }
    }

    Collect-FailureEvidence $installStart
    Restore-ServiceSnapshot $serviceSnapshot

    # Keep the in-memory state so per-component Result updates are preserved.
    # Re-read actual versions into result text.
    foreach ($c in $Components) {
        $v = Get-MSIProductVersion $c.ProductCode
        Add-Result "$($c.Key) final version=$v; target=$($c.TargetVersion)"
    }

    if ($overall) {
        $state.Phase = 'Completed'
        Write-State $state
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FINAL_STATE.json') -Encoding UTF8
        'SUCCESS' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result 'SUCCESS: 所有需要修复的目标 HAL 均已安装到目标版本。'
    } else {
        $state.Phase = 'Failed'
        Write-State $state
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FINAL_STATE.json') -Encoding UTF8
        'FAILED' | Set-Content -LiteralPath (Join-Path $script:RunRoot 'FIX_STATUS.txt') -Encoding ASCII
        Add-Result 'FAILED: 至少一个目标 HAL 仍失败；已尽量保留/回滚原版本并收集本次 CodeIntegrity/AppLocker/MSI 证据。'
    }

    Remove-ResumeInfrastructure
    Remove-Item -LiteralPath $CurrentStatePath -Force -ErrorAction SilentlyContinue
    Pack-Report

    Write-Host ''
    if ($overall) {
        Write-Host '修复完成。现在打开 Armoury Crate > 设置 > 更新中心刷新状态。' -ForegroundColor Green
        if ($needsSecondReboot) { Write-Host '安装器返回了“需要重启”，建议再重启一次 Windows 后再打开 Armoury Crate。' -ForegroundColor Yellow }
    } else {
        Write-Host '有组件仍未通过。请把桌面新生成的 ASUS_4151_TargetedFix_*.zip 发回分析。' -ForegroundColor Yellow
    }
    if (-not $NoRebootPrompt) { Read-Host '按 Enter 关闭' }
}

try {
    switch ($Phase) {
        'Start'      { Run-Start }
        'PostReboot' { Run-PostReboot }
        'SelfTest'   { Run-SelfTestOnly }
        'Diagnose'   { Run-DiagnoseOnly }
    }
} catch {
    try { Add-Result "UNHANDLED: $($_.Exception.Message)`r`n$($_.ScriptStackTrace)" } catch {}
    try { Pack-Report } catch {}
    throw
} finally {
    Stop-TranscriptSafe
    Release-Mutex
}
