#requires -version 5.1
# SnapshotEngine.ps1 — hash-locked snapshot, diagnostics, and report export.
# Dotsourced by RepairCenter.ps1 after BuildInfo validation. Do not run directly.

function Get-ArmouryErrorCode([string]$Line) {
    $patterns = @(
        '(?i)(?:UI\s*code|uicode|error\s*code)\s*[:=]\s*(?<v>501|601|4\d{3})',
        '(?i)Optional\s+Hal\s+(?<v>4\d{3})',
        '(?i)\berror\s*(?<v>501)\b'
    )
    foreach ($p in $patterns) {
        if ($Line -match $p) { return [string]$matches['v'] }
    }
    if ($Line -match '(?i)FailedVersionMismatch') { return '4152' }
    return ''
}

function Get-ArmouryIncidentFromContext([string]$Line,[string]$Context,[datetime]$Observed,[string]$File) {
    $code = Get-ArmouryErrorCode $Line
    if (-not $code) { return $null }

    $profile = Get-ContextValue $Context @(
        '(?im)(?:ProfileID|Profile\s*ID)\s*[:=]\s*(?<v>\d{3,10})',
        '(?im)\bapid\s*[:=]\s*(?:AacSetup_)?(?<v>\d{3,10})'
    )
    $package = Get-ContextValue $Context @(
        '(?im)\bapn\s*[:=]\s*(?<v>[A-Za-z0-9_.+\- ]+)',
        '(?im)(?:Package|Component)\s*(?:Name)?\s*[:=]\s*(?<v>[A-Za-z0-9_.+\- ]+)'
    )
    $currentVersion = Get-ContextValue $Context @(
        '(?im)\bapcv\s*[:=]\s*(?<v>[0-9A-Za-z_.+\-]+)',
        '(?im)(?:current|installed)\s*(?:version)?\s*[:=]\s*(?<v>[0-9A-Za-z_.+\-]+)'
    )
    $targetVersion = Get-ContextValue $Context @(
        '(?im)\baptv\s*[:=]\s*(?<v>[0-9A-Za-z_.+\-]+)',
        '(?im)target\s*(?:version)?\s*[:=]\s*(?<v>[0-9A-Za-z_.+\-]+)'
    )
    $installerName = Get-ContextValue $Context @(
        '(?im)Install\s*filepath\s*[:=]\s*["'']?(?<v>[^\\/:*?"<>|\r\n]+?\.exe)',
        '(?im)\b(?<v>Aac[A-Za-z0-9_.+\-]+\.exe)\b'
    )
    $installerPath = Get-ContextValue $Context @(
        '(?im)(?:Install\s*filepath|CreateProcess(?:AsUserW)?(?:\s*path)?|FilePath)\s*[:=][^\r\n]*?["'']?(?<v>[A-Za-z]:\\[^\r\n"'']+?\.exe)',
        '(?im)["''](?<v>[A-Za-z]:\\[^\r\n"'']+?\.exe)["'']'
    )
    $exitCode = Get-ContextValue $Context @(
        '(?im)(?:Install\s*return\s*code|ExitCode)\s*[:=]\s*(?<v>-?\d+)'
    )

    $installer = [string]$installerName
    if ($installerPath) {
        try { $installer = [IO.Path]::GetFileName($installerPath) } catch {}
    }

    $matched = $null
    foreach ($d in $Known) {
        $stem = ([string]$d.Exe -replace '(?i)\.exe$','')
        if (($profile -and $profile -eq [string]$d.Profile) -or
            ($Context -match [regex]::Escape([string]$d.Profile)) -or
            ($Context -match [regex]::Escape([string]$d.Exe)) -or
            ($Context -match [regex]::Escape([string]$d.Name)) -or
            ($package -and $package -match [regex]::Escape($stem)) -or
            ($installer -and $installer -eq [string]$d.Exe)) {
            $matched = $d
            break
        }
    }

    $key = 'Unknown'
    $component = ''
    $group = 'DYNAMIC'
    $isKnown = $false
    if ($matched) {
        $key = [string]$matched.Key
        $component = [string]$matched.Name
        $group = [string]$matched.Group
        $isKnown = $true
    } else {
        if ($package) { $component = $package.Trim() }
        elseif ($installer) { $component = $installer }
        elseif ($profile) { $component = "Unknown HAL Profile $profile" }
        else { $component = 'Unknown Armoury HAL / Component' }

        if ($profile) { $key = "DynamicProfile_$profile" }
        elseif ($installer) { $key = "DynamicExe_$installer" }
        elseif ($package) { $key = "DynamicPackage_$($package.Trim())" }
    }

    return [PSCustomObject]@{
        ObservedAt=$Observed
        Code=$code
        Key=$key
        Profile=$profile
        Component=$component
        Package=$package
        Installer=$installer
        InstallerPath=$installerPath
        CurrentVersion=$currentVersion
        TargetVersion=$targetVersion
        ExitCode=$exitCode
        KnownComponent=$isKnown
        Group=$group
        File=$File
        Line=$Line.Trim()
        Context=$Context
    }
}

function Get-ArmouryErrorEvidence([int]$Minutes=180) {
    $hits = @()
    $seen = @{}
    $since = (Get-Date).AddMinutes(-1 * $Minutes)

    # v1.2.0 intentionally scans the broader ASUS log roots rather than only
    # today's known ROG Live Service subfolders. This keeps 4151/4152 detection
    # working if ASUS changes log layout in a future Armoury Crate release.
    $roots = @(
        "$env:ProgramData\ASUS",
        "$env:LOCALAPPDATA\ASUS"
    ) | Select-Object -Unique

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LastWriteTime -ge $since -and
                    $_.Length -lt 12MB -and
                    $_.Extension -match '^\.(log|txt)$'
                } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 220

            foreach ($f in $files) {
                $lines = @()
                try { $lines = @(Get-Content -LiteralPath $f.FullName -Tail 6500 -ErrorAction Stop) }
                catch { continue }

                for ($i=0; $i -lt $lines.Count; $i++) {
                    $line = [string]$lines[$i]
                    if ($line -notmatch '(?i)(UI\s*code\s*[:=]\s*(4\d{3}|501|601)|uicode\s*[:=]\s*(4\d{3}|501|601)|error\s*code\s*[:=]\s*(4\d{3}|501|601)|Optional\s+Hal\s+4\d{3}|FailedVersionMismatch|\berror\s*501\b)') {
                        continue
                    }

                    $observed = Get-LineObservedTime $line $f.LastWriteTime
                    if ($observed -lt $since) { continue }

                    $lo = [Math]::Max(0,$i-32)
                    $hi = [Math]::Min($lines.Count-1,$i+32)
                    $context = ''
                    if ($hi -ge $lo) { $context = (@($lines[$lo..$hi]) -join "`n") }

                    $incident = Get-ArmouryIncidentFromContext $line $context $observed $f.FullName
                    if (-not $incident) { continue }

                    $bucketMinute = [int]([Math]::Floor($observed.Minute / 5) * 5)
                    $bucket = '{0:yyyyMMddHH}{1:00}' -f $observed,$bucketMinute
                    $identity = [string]$incident.Key
                    if (-not $identity -or $identity -eq 'Unknown') {
                        if ($incident.Profile) { $identity = "P$($incident.Profile)" }
                        elseif ($incident.Installer) { $identity = [string]$incident.Installer }
                        else { $identity = 'Unknown' }
                    }
                    $dedupKey = $identity + '|' + [string]$incident.Code + '|' + $bucket
                    if ($seen.ContainsKey($dedupKey)) { continue }
                    $seen[$dedupKey] = $true

                    $incident | Add-Member -NotePropertyName DedupKey -NotePropertyValue $dedupKey
                    $hits += $incident
                }
            }
        } catch {}
    }
    return @($hits | Sort-Object ObservedAt -Descending)
}

function Get-DynamicIncidentRows([object[]]$ActiveArmoury) {
    $out = @()
    $unknown = @($ActiveArmoury | Where-Object { -not $_.KnownComponent })
    if ($unknown.Count -eq 0) { return $out }

    $groups = @($unknown | Group-Object Key)
    foreach ($g in $groups) {
        $items = @($g.Group | Sort-Object ObservedAt -Descending)
        if ($items.Count -eq 0) { continue }
        $x = $items[0]

        $codes = @($items | Select-Object -ExpandProperty Code -Unique)
        $name = [string]$x.Component
        if (-not $name) { $name = 'Unknown Armoury HAL / Component' }
        if ($x.Profile) { $name = "$name [Profile $($x.Profile)]" }

        $detail = "动态检测到当前 Armoury 错误 $($codes -join ',')"
        if ($x.ExitCode) { $detail += "，安装返回码=$($x.ExitCode)" }
        $detail += '；属于未来版本/未知组件，已完整记录但不会自动卸载或修复。'

        $out += [PSCustomObject]@{
            Key=[string]$x.Key
            Name=$name
            Installed=[string]$x.CurrentVersion
            Target=[string]$x.TargetVersion
            Runtime=''
            ErrorCode=($codes -join ',')
            Status='MANUAL'
            Detail=$detail
            Group='DYNAMIC'
        }
    }
    return $out
}

function Get-RlsRecentInstallers([int]$Days=7,[int]$MaxItems=300) {
    $root = Join-Path $env:ProgramFiles 'ASUS\RLSDownload'
    $out = @()
    if (-not (Test-Path -LiteralPath $root)) { return $out }
    $since = (Get-Date).AddDays(-1 * $Days)

    try {
        $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -ge $since -and
                $_.Extension -match '^\.(exe|msi)$'
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $MaxItems

        foreach ($f in $files) {
            $fileVersion = ''
            $productVersion = ''
            try {
                $fileVersion = [string]$f.VersionInfo.FileVersion
                $productVersion = [string]$f.VersionInfo.ProductVersion
            } catch {}

            $profile = ''
            if ($f.FullName -match '(?i)\\4_HAL\\(?:AacSetup_)?(?<p>\d{4,10})\\') {
                $profile = [string]$matches['p']
            } elseif ($f.FullName -match '(?i)\\(?<p>\d{5})\\[^\\]+$') {
                $profile = [string]$matches['p']
            }

            $sigStatus = ''
            $signer = ''
            if ($f.Extension -ieq '.exe') {
                try {
                    $sig = Get-AuthenticodeSignature -FilePath $f.FullName -ErrorAction SilentlyContinue
                    if ($sig) {
                        $sigStatus = [string]$sig.Status
                        if ($sig.SignerCertificate) { $signer = [string]$sig.SignerCertificate.Subject }
                    }
                } catch {}
            }

            $out += [PSCustomObject]@{
                LastWriteTime=$f.LastWriteTime
                Profile=$profile
                Name=$f.Name
                FileVersion=$fileVersion
                ProductVersion=$productVersion
                Signature=$sigStatus
                Signer=$signer
                FullName=$f.FullName
            }
        }
    } catch {}
    return $out
}

function Get-PendingRepair {
    $items = @(
        [PSCustomObject]@{Key='PV';State='C:\ProgramData\ASUS4151TargetedFix\CurrentStatePath.txt';Module=$PVModule;Label='Patriot / VGA 4151'},
        [PSCustomObject]@{Key='HOLTEK';State='C:\ProgramData\ASUSCoreHAL4151Fix\CurrentStatePath.txt';Module=$HoltekModule;Label='Holtek Core HAL 4151'},
        [PSCustomObject]@{Key='ENE';State='C:\ProgramData\ASUS_ENE_M2_4152_Fix\CurrentStatePath.txt';Module=$ENEModule;Label='ENE M2 4152'}
    )
    foreach ($i in $items) {
        if (Test-Path -LiteralPath $i.State) { return $i }
    }
    return $null
}

function Get-DiagnosticRows([object[]]$ActiveArmoury=@()) {
    $rows = @()

    foreach ($d in $Known) {
        $installed = Get-InstalledVersion $d.ProductCode
        $target = Get-RlsTargetVersion $d
        $runtime = ''
        $status = 'INFO'
        $detail = ''
        $currentError = ''

        $incidents = @($ActiveArmoury | Where-Object { $_.Key -eq $d.Key })
        $latestIncident = $null
        if ($incidents.Count -gt 0) {
            $latestIncident = $incidents | Sort-Object ObservedAt -Descending | Select-Object -First 1
            $currentError = (@($incidents | Select-Object -ExpandProperty Code -Unique) -join ',')
            if (-not $target -and $latestIncident.TargetVersion) {
                $target = [string]$latestIncident.TargetVersion
            }
        }

        $hasActiveError = ($incidents.Count -gt 0)
        $expectedActive = $false
        if ($hasActiveError) {
            $expectedActive = (@($incidents | Where-Object { $_.Code -eq [string]$d.ExpectedCode }).Count -gt 0)
        }

        if ($d.Key -eq 'ENE') {
            $x64 = Get-FileVersionSafe 'C:\Program Files\ENE\Aac_ENE_EHD_M2_HAL\AacHal_x64.dll'
            $x86 = Get-FileVersionSafe 'C:\Program Files\ENE\Aac_ENE_EHD_M2_HAL\AacHal_x86.dll'
            $runtime = "x64=$x64; x86=$x86"

            $exactVerified4152 = (
                $hasActiveError -and
                $expectedActive -and
                $installed -eq $d.VerifiedGood -and
                $x64 -eq $d.VerifiedOld -and
                $x86 -eq $d.VerifiedOld -and
                ((-not $target) -or $target -eq $d.VerifiedGood)
            )

            if ($exactVerified4152) {
                $status = 'REPAIR'
                $detail = '命中已验证 4152 假成功：MSI 已升级，但两个实际 HAL DLL 仍为旧版'
            } elseif ($hasActiveError) {
                $status = 'MANUAL'
                if ($currentError -match '4152' -and $installed -and $x64 -and $x86 -and ($x64 -ne $installed -or $x86 -ne $installed)) {
                    $detail = "检测到当前 4152 且真实 DLL 与 MSI 不一致：MSI=$installed，$runtime；版本组合属于未来/未验证范围，仅诊断不自动修复"
                } else {
                    $detail = "检测到当前 Armoury 错误 $currentError；当前/目标版本属于未来或未验证组合，仅诊断不自动修复"
                }
            } elseif (-not $installed) {
                if ($target) {
                    $status = 'UPDATE'
                    $detail = "检测到 RLS 目标版本 $target，但当前 MSI 未注册；没有当前 4152，暂不自动操作"
                } else {
                    $status = 'N/A'
                    $detail = '本机未检测到该组件；不参与健康评分'
                }
            } elseif ($x64 -and $x86 -and ($x64 -ne $installed -or $x86 -ne $installed)) {
                $status = 'MANUAL'
                $detail = "没有新的 4152，但 MSI 与真实 DLL 版本不一致：MSI=$installed，$runtime；建议导出诊断报告"
            } elseif ($target -and (Compare-VersionSafe $target $installed) -gt 0) {
                $status = 'UPDATE'
                $detail = "存在正常新版本 $installed -> $target；当前未检测到 4152"
            } elseif ($x64 -eq $installed -and $x86 -eq $installed) {
                $status = 'PASS'
                $detail = 'MSI 与真实 DLL 一致；诊断不依赖固定目标版本'
            } else {
                $status = 'INFO'
                $detail = '版本状态可读取，但无法完成双 DLL 一致性确认'
            }
        } else {
            $exactVerifiedFault = (
                $hasActiveError -and
                $expectedActive -and
                $installed -eq $d.VerifiedOld -and
                $target -eq $d.VerifiedGood
            )

            if ($exactVerifiedFault) {
                $status = 'REPAIR'
                $detail = "命中已验证故障链 $installed -> $target，且当前日志出现 $($d.ExpectedCode)，可安全进入现有修复模块"
            } elseif ($hasActiveError) {
                $status = 'MANUAL'
                $observedCurrent = ''
                $observedTarget = ''
                if ($latestIncident) {
                    $observedCurrent = [string]$latestIncident.CurrentVersion
                    $observedTarget = [string]$latestIncident.TargetVersion
                }
                if (-not $observedCurrent) { $observedCurrent = $installed }
                if (-not $observedTarget) { $observedTarget = $target }
                $detail = "动态捕获当前错误 $currentError：current=$observedCurrent target=$observedTarget；属于未来/未验证版本组合，仅诊断不自动修复"
            } elseif (-not $installed) {
                if ($target) {
                    $status = 'UPDATE'
                    $detail = "发现 RLS 目标 $target，但没有当前 4151/4152 错误；不自动修复"
                } else {
                    $status = 'N/A'
                    $detail = '本机未检测到该组件；不参与健康评分'
                }
            } elseif ($target -and (Compare-VersionSafe $target $installed) -gt 0) {
                $status = 'UPDATE'
                $detail = "存在正常新版本 $installed -> $target；当前没有安装失败证据"
            } elseif ((Compare-VersionSafe $installed $d.VerifiedGood) -ge 0) {
                $status = 'PASS'
                $detail = '当前版本正常；未来更高版本同样按错误日志动态判断，不要求等于旧固定版本'
            } else {
                $status = 'INFO'
                $detail = '当前没有 4151/4152；版本低于历史验证基线，但不会仅因版本号自动修复'
            }
        }

        $rows += [PSCustomObject]@{
            Key=$d.Key
            Name=$d.Name
            Installed=$installed
            Target=$target
            Runtime=$runtime
            ErrorCode=$currentError
            Status=$status
            Detail=$detail
            Group=$d.Group
        }
    }

    # Unknown/new ASUS HAL profiles and future component names are appended dynamically.
    $rows += @(Get-DynamicIncidentRows $ActiveArmoury)
    return $rows
}

function Get-VersionDiff([object[]]$Rows) {
    if (-not (Test-Path -LiteralPath $BaselinePath)) { return @() }
    try {
        $b = Get-Content -LiteralPath $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Json
        $out = @()
        foreach ($old in @($b.Rows)) {
            $now = $Rows | Where-Object { $_.Key -eq $old.Key } | Select-Object -First 1
            if (-not $now) { continue }
            $parts = @()
            if ([string]$old.Installed -ne [string]$now.Installed) {
                $parts += ("MSI {0} -> {1}" -f [string]$old.Installed,[string]$now.Installed)
            }
            if ([string]$old.Runtime -ne [string]$now.Runtime -and ([string]$old.Runtime -or [string]$now.Runtime)) {
                $parts += ("Runtime {0} -> {1}" -f [string]$old.Runtime,[string]$now.Runtime)
            }
            if ($parts.Count -gt 0) {
                $out += ("{0}: {1}" -f [string]$now.Name,($parts -join '; '))
            }
        }
        return $out
    } catch {
        return @()
    }
}

function Save-RepairBaseline([string]$Group,[object[]]$Rows) {
    try {
        $obj = [PSCustomObject]@{
            Version=$AppVersion
            Group=$Group
            Created=(Get-Date).ToString('o')
            Rows=@($Rows | Select-Object Key,Name,Installed,Target,Runtime,Status)
        }
        $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8
    } catch {}
}

function Get-RecommendedRepairGroup([object[]]$Rows,[object[]]$ActiveArmoury) {
    $repairRows = @($Rows | Where-Object { $_.Status -eq 'REPAIR' })
    if ($repairRows.Count -eq 0) { return $null }
    $activeKeys = @($ActiveArmoury | Select-Object -ExpandProperty Key -Unique)
    foreach ($group in @('PV','HOLTEK','ENE')) {
        $candidates = @($repairRows | Where-Object { $_.Group -eq $group })
        if ($candidates.Count -eq 0) { continue }
        foreach ($c in $candidates) {
            if ($activeKeys -contains $c.Key) { return $group }
        }
    }
    foreach ($group in @('PV','HOLTEK','ENE')) {
        if (@($repairRows | Where-Object { $_.Group -eq $group }).Count -gt 0) { return $group }
    }
    return $null
}

function Get-SystemSnapshot([switch]$Force) {
    $now = Get-Date
    if (-not $Force -and $script:SnapshotCache -and (($now - $script:SnapshotCacheTime).TotalSeconds -lt 15)) {
        return $script:SnapshotCache
    }
    try { [void](Update-RuntimeOnlineInfo -Force:$Force) } catch {}

    $activeWindow = 15
    $historyWindow = 180
    $armAll = @(Get-ArmouryErrorEvidence $historyWindow)
    Save-IncidentHistory $armAll
    $msiAll = @(Get-RecentMsiErrors $historyWindow)
    $cut = $now.AddMinutes(-1 * $activeWindow)
    $activeArmoury = @($armAll | Where-Object { $_.ObservedAt -ge $cut })
    $historyArmoury = @($armAll | Where-Object { $_.ObservedAt -lt $cut })
    $activeMsi = @($msiAll | Where-Object { $_.ObservedAt -ge $cut })
    $historyMsi = @($msiAll | Where-Object { $_.ObservedAt -lt $cut })
    # Correlation is computed only after the active windows are materialized.
    # Scores group evidence for display/incident management only; they never grant repair permission.
    $correlated = @(Get-CorrelatedIncidents $activeArmoury $activeMsi)
    $rows = @(Get-DiagnosticRows $activeArmoury)
    $rows += @(Get-RuntimeDiagnosticRows)
    $pending = Get-PendingRepair
    $repair = @($rows | Where-Object { $_.Status -eq 'REPAIR' })
    $runtimeUpdate = @($rows | Where-Object { $_.Group -eq 'RUNTIME' -and $_.Status -eq 'UPDATE' })
    $manual = @($rows | Where-Object { $_.Status -eq 'MANUAL' })

    $health = 'HEALTHY'
    $healthText = '健康'
    if ($pending) {
        $health = 'WAIT_REBOOT'
        $healthText = '等待重启 / 续跑'
    } elseif ($repair.Count -gt 0 -or $runtimeUpdate.Count -gt 0) {
        $health = 'NEEDS_REPAIR'
        if ($repair.Count -gt 0) { $healthText = '需要修复' } else { $healthText = '系统运行库可更新' }
    } elseif ($manual.Count -gt 0 -or @($activeArmoury).Count -gt 0) {
        $health = 'MANUAL'
        $healthText = '检测到故障 / 需要人工确认'
    }

    $recommended = Get-RecommendedRepairGroup $rows $activeArmoury
    $diff = @(Get-VersionDiff $rows)
    $codes = @($activeArmoury | Select-Object -ExpandProperty Code -Unique | Sort-Object)

    $crate = $null
    try { $crate = Get-ArmouryCrateLaunchHealth } catch { $crate = [PSCustomObject]@{NeedsRepair=$false;Issue='';Detail='';Has501=$false;Chassis='';Installed=$false} }
    if ($codes -contains '501') {
        try {
            $crate.Has501 = $true
            if (-not [bool]$crate.Installed -or [bool]$crate.NeedsRepair) {
                $crate.NeedsRepair = $true
                if (-not [string]$crate.Issue) { $crate.Issue = '安装奥创时出现 501 错误。'; $crate.Detail = $crate.Issue }
            }
        } catch {}
    }
    if ($crate -and [bool]$crate.Has501 -and ($codes -notcontains '501')) { $codes = @($codes + '501') }
    $obj = [PSCustomObject]@{
        CapturedAt=$now
        Rows=$rows
        Pending=$pending
        ActiveArmoury=$activeArmoury
        HistoryArmoury=$historyArmoury
        ActiveMsi=$activeMsi
        HistoryMsi=$historyMsi
        ActiveErrorCodes=$codes
        CorrelatedIncidents=$correlated
        Health=$health
        HealthText=$healthText
        RecommendedGroup=$recommended
        VersionDiff=$diff
        PendingReboot=@(Get-PendingRebootReasons)
        ArmouryCrate=$crate
    }
    $script:SnapshotCache = $obj
    $script:SnapshotCacheTime = $now
    return $obj
}

function Get-BuildConsistency {
    $rows=@();function AddC([string]$Item,[string]$Status,[string]$Expected,[string]$Actual,[string]$Detail=''){$script:__bc += [PSCustomObject]@{Item=$Item;Status=$Status;Expected=$Expected;Actual=$Actual;Detail=$Detail}};$script:__bc=@()
    try{$a=(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();AddC 'Engine SHA256' $(if($a -eq [string]$BuildInfo.EngineSHA256){'PASS'}else{'FAIL'}) ([string]$BuildInfo.EngineSHA256) $a ''}catch{AddC 'Engine SHA256' 'FAIL' ([string]$BuildInfo.EngineSHA256) '' $_.Exception.Message}
    try{$a=(Get-FileHash -Algorithm SHA256 -LiteralPath $BrokerPath).Hash.ToLowerInvariant();AddC 'Broker SHA256' $(if($a -eq [string]$BuildInfo.BrokerSHA256){'PASS'}else{'FAIL'}) ([string]$BuildInfo.BrokerSHA256) $a ''}catch{AddC 'Broker SHA256' 'FAIL' ([string]$BuildInfo.BrokerSHA256) '' $_.Exception.Message}
    $bp=Join-Path $PSScriptRoot 'Bootstrap.ps1';try{$a=(Get-FileHash -Algorithm SHA256 -LiteralPath $bp).Hash.ToLowerInvariant();AddC 'Bootstrap SHA256' $(if($a -eq [string]$BuildInfo.BootstrapSHA256){'PASS'}else{'FAIL'}) ([string]$BuildInfo.BootstrapSHA256) $a ''}catch{AddC 'Bootstrap SHA256' 'FAIL' ([string]$BuildInfo.BootstrapSHA256) '' $_.Exception.Message}
    AddC 'Engine Version' $(if($AppVersion -eq [string]$BuildInfo.Version){'PASS'}else{'FAIL'}) ([string]$BuildInfo.Version) $AppVersion '';AddC 'Build ID' $(if($BuildId -eq [string]$BuildInfo.BuildId){'PASS'}else{'FAIL'}) ([string]$BuildInfo.BuildId) $BuildId ''
    if($script:CurrentPlan){$ok=([string]$script:CurrentPlan.AppVersion -eq $AppVersion -and [string]$script:CurrentPlan.BuildId -eq $BuildId);AddC 'Current Plan Build' $(if($ok){'PASS'}else{'WARN'}) "$AppVersion/$BuildId" "$($script:CurrentPlan.AppVersion)/$($script:CurrentPlan.BuildId)" $(if($ok){''}else{'当前 Dry Run 来自旧 Engine；应重新生成计划'})}
    $legacy=Join-Path $LegacyWorkRoot 'RepairCenter.ps1';if(Test-Path -LiteralPath $legacy){AddC 'Legacy ProgramData Runtime' 'INFO' 'not used by current v2.3.2' $legacy '检测到旧版 ProgramData 运行文件；当前 Engine 使用 LocalAppData，不会调用旧文件'}
    $rows=@($script:__bc);Remove-Variable __bc -Scope Script -ErrorAction SilentlyContinue;$fatal=@($rows|Where-Object{$_.Status -eq 'FAIL'});return [PSCustomObject]@{Status=$(if($fatal.Count -eq 0){'PASS'}else{'BUILD_MISMATCH'});Rows=$rows;EngineVersion=$AppVersion;BuildId=$BuildId;EngineSHA256=$script:EngineSHA256;BuildInfoSHA256=$script:BuildInfoSHA256}
}
function Write-ReportIntegrityManifest([string]$ReportRoot){$files=@();foreach($f in @(Get-ChildItem -LiteralPath $ReportRoot -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -notin @('report_manifest.json','report_manifest.sha256')}|Sort-Object FullName)){try{$rel=$f.FullName.Substring($ReportRoot.Length).TrimStart('\');$files += [PSCustomObject]@{Path=$rel;Bytes=[int64]$f.Length;SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()}}catch{}};$bc=Get-BuildConsistency;$m=[PSCustomObject]@{SchemaVersion=2;Product=[string]$BuildInfo.Product;Version=$AppVersion;BuildId=$BuildId;GeneratedAt=(Get-Date).ToString('o');EngineSHA256=$script:EngineSHA256;BrokerSHA256=[string]$BuildInfo.BrokerSHA256;BuildConsistency=$bc.Status;FileCount=$files.Count;Files=$files};$mp=Join-Path $ReportRoot 'report_manifest.json';[void](Write-JsonAtomic $mp $m 16);$mh=(Get-FileHash -Algorithm SHA256 -LiteralPath $mp).Hash.ToLowerInvariant();$mh|Set-Content -LiteralPath (Join-Path $ReportRoot 'report_manifest.sha256') -Encoding ASCII;return $m}

function New-ReportFolder([string]$Prefix) {
    $p = Join-Path $Desktop ($Prefix + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    return $p
}

function Export-DiagnosticReport {
    $snap = Get-SystemSnapshot -Force
    try{[void](Invoke-GamePlatformDeepTest)}catch{}
    $consistency=Get-BuildConsistency
    $out = New-ReportFolder 'GameRuntime_ASUS_SelfHealing_Report'
    $snap.Rows | Format-Table -AutoSize | Out-String -Width 600 | Set-Content (Join-Path $out 'Component_Status.txt') -Encoding UTF8

    @(
        "Windows Game Runtime / ASUS Self-Healing Center v$AppVersion",
        "BuildId=$BuildId",
        "ReportSchema=$ReportSchemaVersion",
        "EngineSHA256=$script:EngineSHA256",
        "BrokerSHA256=$ExpectedBrokerSHA256",
        "BuildConsistency=$($consistency.Status)",
        "CapturedAt=$($snap.CapturedAt)",
        "Health=$($snap.HealthText)",
        "RecommendedGroup=$($snap.RecommendedGroup)",
        "ActiveArmoury=$(@($snap.ActiveArmoury).Count)",
        "ActiveMSI=$(@($snap.ActiveMsi).Count)",
        "ActiveErrorCodes=$(@($snap.ActiveErrorCodes) -join ',')",
        "HistoryArmoury3h=$(@($snap.HistoryArmoury).Count)",
        "HistoryMSI3h=$(@($snap.HistoryMsi).Count)",
        "PendingReboot=$(@($snap.PendingReboot) -join ',')",
        "VersionDiff=$(@($snap.VersionDiff) -join ' | ')"
    ) | Set-Content (Join-Path $out 'Health_Summary.txt') -Encoding UTF8

    @($snap.ActiveArmoury) | Select-Object ObservedAt,Code,Key,Profile,Component,Package,Installer,CurrentVersion,TargetVersion,ExitCode,KnownComponent,File,Line |
        Format-List | Out-String -Width 900 | Set-Content (Join-Path $out 'Armoury_Active_15min.txt') -Encoding UTF8
    @($snap.HistoryArmoury) | Select-Object ObservedAt,Code,Key,Profile,Component,Package,Installer,CurrentVersion,TargetVersion,ExitCode,KnownComponent,File,Line |
        Format-List | Out-String -Width 900 | Set-Content (Join-Path $out 'Armoury_History_3h.txt') -Encoding UTF8

    @($snap.CorrelatedIncidents) | Format-Table -AutoSize | Out-String -Width 1000 | Set-Content (Join-Path $out 'Correlated_Incidents.txt') -Encoding UTF8

    @($snap.ActiveArmoury | Where-Object { -not $_.KnownComponent }) |
        Select-Object ObservedAt,Code,Profile,Component,Package,Installer,InstallerPath,CurrentVersion,TargetVersion,ExitCode,File |
        Format-List | Out-String -Width 900 |
        Set-Content (Join-Path $out 'Dynamic_Unknown_or_Future_Incidents.txt') -Encoding UTF8

    @(Get-RlsRecentInstallers -Days 7 -MaxItems 350) |
        Format-Table -AutoSize | Out-String -Width 1000 |
        Set-Content (Join-Path $out 'RLS_Recent_Installers_7days.txt') -Encoding UTF8
    @($snap.ActiveMsi) | Select-Object ObservedAt,Id,Message | Format-List | Out-String -Width 700 | Set-Content (Join-Path $out 'MSI_Active_15min.txt') -Encoding UTF8
    @($snap.HistoryMsi) | Select-Object ObservedAt,Id,Message | Format-List | Out-String -Width 700 | Set-Content (Join-Path $out 'MSI_History_3h.txt') -Encoding UTF8

    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'ASUS|Armoury|ROG|Aura|Lighting|ENE|Aac' } |
        Sort-Object Name | Format-Table -AutoSize | Out-String -Width 500 |
        Set-Content (Join-Path $out 'ASUS_Services.txt') -Encoding UTF8

    @($snap.PendingReboot) | Set-Content (Join-Path $out 'PendingReboot.txt') -Encoding UTF8
    @(Get-PendingFileRenameDetails)|Format-Table -AutoSize|Out-String -Width 1400|Set-Content (Join-Path $out 'PendingFileRenameOperations_Details.txt') -Encoding UTF8
    $installerState=Get-InstallerBusyState;@($installerState.All)|Format-Table -AutoSize|Out-String -Width 1600|Set-Content (Join-Path $out 'WindowsInstaller_Process_Details.txt') -Encoding UTF8

    $pf=Get-EnvironmentPreflight 'Report'
    @($pf.Rows) | Format-Table -AutoSize | Out-String -Width 900 |
        Set-Content (Join-Path $out 'Safety_Preflight.txt') -Encoding UTF8
    @(Get-RecentTransactions 50) | Select-Object TransactionId,Type,Group,Label,State,StartedAt,UpdatedAt,LastDetail |
        Format-Table -AutoSize | Out-String -Width 1200 |
        Set-Content (Join-Path $out 'Repair_Transactions.txt') -Encoding UTF8
    if($script:CurrentPlan){
        (Format-RepairPlan $script:CurrentPlan) | Set-Content (Join-Path $out 'Current_DryRun_Plan.txt') -Encoding UTF8
    }
    if(Test-Path -LiteralPath $IncidentDbPath){
        Get-Content -LiteralPath $IncidentDbPath -Tail 4000 -ErrorAction SilentlyContinue |
            Set-Content (Join-Path $out 'IncidentHistory_tail.jsonl') -Encoding UTF8
    }
    if(Test-Path -LiteralPath $DeepTestLastPath){
        Copy-Item -LiteralPath $DeepTestLastPath -Destination (Join-Path $out 'Last_GameRuntime_DeepTest.json') -Force -ErrorAction SilentlyContinue
    }

    try{@(Get-GPUHealthRows)|Format-Table -AutoSize|Out-String -Width 1200|Set-Content (Join-Path $out 'GPU_Health.txt') -Encoding UTF8}catch{}
    try{@(Get-GameCrashTelemetry 7 250 -Raw)|Format-List|Out-String -Width 1400|Set-Content (Join-Path $out 'Game_Crash_Telemetry_7days.txt') -Encoding UTF8}catch{}
    try{@(Get-AdditionalGameRuntimeRows)|Format-Table -AutoSize|Out-String -Width 1200|Set-Content (Join-Path $out 'Additional_Game_Runtimes.txt') -Encoding UTF8}catch{}
    try{@(Get-WerLocalDumpStatus)|Format-Table -AutoSize|Out-String -Width 1000|Set-Content (Join-Path $out 'WER_LocalDumps.txt') -Encoding UTF8}catch{}
    try{@(Get-RulePackStatus)|Format-List|Out-String -Width 1200|Set-Content (Join-Path $out 'RulePack_Trust.txt') -Encoding UTF8}catch{}
    try{Get-ArchitectureSecuritySummary|Format-List|Out-String -Width 1200|Set-Content (Join-Path $out 'Broker_Policy_Architecture.txt') -Encoding UTF8}catch{}
    $newDeep=Join-Path $DeepTestRoot 'LastGamePlatformDeepTest.json';if(Test-Path -LiteralPath $newDeep){Copy-Item -LiteralPath $newDeep -Destination (Join-Path $out 'Last_GamePlatform_DeepTest.json') -Force -ErrorAction SilentlyContinue}


    @(Get-RuntimeDiagnosticRows) | Format-Table -AutoSize | Out-String -Width 900 |
        Set-Content (Join-Path $out 'VCpp_DirectX_Status.txt') -Encoding UTF8
    @(Get-VCRuntimeErrorEvidence 168) | Format-List | Out-String -Width 900 |
        Set-Content (Join-Path $out 'VCpp_Runtime_Error_Evidence_7days.txt') -Encoding UTF8
    @(Get-LegacyVCRedistInventory) | Format-Table -AutoSize | Out-String -Width 900 |
        Set-Content (Join-Path $out 'VCpp_Legacy_2005_2013_Inventory.txt') -Encoding UTF8
    try {
        $dxp = Invoke-DxDiagCapture
        if ($dxp -and (Test-Path -LiteralPath $dxp)) { Copy-Item -LiteralPath $dxp -Destination (Join-Path $out 'DxDiag.txt') -Force }
    } catch {}
    if ($script:RuntimeOnlineInfo) {
        $script:RuntimeOnlineInfo.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{Key=$_.Key;Success=$_.Value.Success;TrustComplete=$_.Value.TrustComplete;Version=$_.Value.Version;Path=$_.Value.Path;SHA256=$_.Value.SHA256;SignatureStatus=$_.Value.SignatureStatus;Signer=$_.Value.Signer;Thumbprint=$_.Value.Thumbprint;Issuer=$_.Value.Issuer;Source=$_.Value.Source;OriginalUri=$_.Value.OriginalUri;FinalUri=$_.Value.FinalUri;FinalHost=$_.Value.FinalHost;VerifiedAt=$_.Value.VerifiedAt;Error=$_.Value.Error}
        } | Format-Table -AutoSize | Out-String -Width 1000 |
            Set-Content (Join-Path $out 'Runtime_Online_Microsoft_Packages.txt') -Encoding UTF8
    }

    try{@(Get-PnpRelatedInventory)|Format-Table Status,Severity,Class,FriendlyName,ProblemCode,ProblemText,InstanceId -AutoSize|Out-String -Width 1800|Set-Content (Join-Path $out 'PnP_Related.txt') -Encoding UTF8}catch{}

    @($consistency.Rows)|Format-Table -AutoSize|Out-String -Width 1600|Set-Content (Join-Path $out 'Build_SelfConsistency.txt') -Encoding UTF8
    $logdir = Join-Path $out 'Recent_ASUS_Logs'
    New-Item -ItemType Directory -Force -Path $logdir | Out-Null
    foreach ($root in @("$env:ProgramData\ASUS","$env:LOCALAPPDATA\ASUS")) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-3) -and $_.Length -lt 5MB -and $_.Extension -match '^\.(log|txt|json|xml)$' } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 250 | ForEach-Object {
                    $name = ($_.FullName -replace '[:\\/ ]','_')
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $logdir $name) -Force -ErrorAction SilentlyContinue
                }
        } catch {}
    }

    if (Test-Path -LiteralPath $LauncherLog) {
        Copy-Item -LiteralPath $LauncherLog -Destination (Join-Path $out 'Launcher.log') -Force -ErrorAction SilentlyContinue
    }

    [void](Write-ReportIntegrityManifest $out)
    $zip = "$out.zip"
    try { Compress-Archive -Path "$out\*" -DestinationPath $zip -Force -ErrorAction Stop }
    catch { return $out }
    return $zip
}

function Get-PnpProblemText([int]$Code){$m=@{0='设备正常';1='设备配置不正确';3='驱动可能损坏或系统资源不足';10='设备无法启动';12='没有足够的可用资源';14='需要重启计算机';18='需要重新安装驱动';19='注册表中的设备配置信息不完整或损坏';22='设备已被禁用';24='设备不存在/工作异常或驱动未完整安装';28='设备驱动未安装';31='Windows 无法加载此设备所需驱动';32='该设备的驱动服务已被禁用';37='Windows 无法初始化此设备驱动';39='驱动损坏或缺失';43='设备报告问题，Windows 已停止设备';45='设备当前未连接';48='驱动软件被阻止启动';52='Windows 无法验证驱动数字签名'};if($m.ContainsKey($Code)){return [string]$m[$Code]};return "ConfigManager ProblemCode=$Code"}
function Get-PnpRelatedInventory {
    $rows=@();$cim=@{};try{foreach($c in @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)){if($c.PNPDeviceID){$cim[[string]$c.PNPDeviceID.ToUpperInvariant()]=$c}}}catch{}
    try{foreach($p in @(Get-PnpDevice -ErrorAction SilentlyContinue|Where-Object{$_.FriendlyName -match 'ASUS|ROG|ENE|NVIDIA|AMD|Display|VGA|High Definition Audio|ULTRAGEAR'})){$code=$null;try{$pr=Get-PnpDeviceProperty -InstanceId ([string]$p.InstanceId) -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop;if($null -ne $pr.Data){$code=[int]$pr.Data}}catch{};if($null -eq $code -and $cim.ContainsKey(([string]$p.InstanceId).ToUpperInvariant())){try{$code=[int]$cim[([string]$p.InstanceId).ToUpperInvariant()].ConfigManagerErrorCode}catch{}};if($null -eq $code){$code=if([string]$p.Status -eq 'OK'){0}else{-1}};$txt=if($code -ge 0){Get-PnpProblemText $code}else{'无法读取 ConfigManager ProblemCode'};$sev=if($code -eq 0 -and [string]$p.Status -eq 'OK'){'PASS'}elseif($code -in @(22,45) -and [string]$p.Class -in @('MEDIA','AudioEndpoint')){'INFO'}else{'WARN'};if([string]$p.FriendlyName -match '(?i)(NVIDIA|AMD).*(High Definition Audio|Display Audio)' -and $code -eq 22){$txt += '；如果不使用 HDMI/DisplayPort 显示器音频，主动禁用通常无需修复'};$rows += [PSCustomObject]@{Status=[string]$p.Status;Severity=$sev;Class=[string]$p.Class;FriendlyName=[string]$p.FriendlyName;InstanceId=[string]$p.InstanceId;ProblemCode=$code;ProblemText=$txt}}}catch{};return $rows
}
function Get-GPUHealthRows {
    $rows=@();try{foreach($g in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)){$st='PASS';if([string]$g.Status -and [string]$g.Status -ne 'OK'){$st='WARN'};$date='';try{$date=([Management.ManagementDateTimeConverter]::ToDateTime([string]$g.DriverDate)).ToString('yyyy-MM-dd')}catch{$date=[string]$g.DriverDate};$rows += [PSCustomObject]@{Category='GPU';Test=[string]$g.Name;Status=$st;Detail=("Driver={0}; DriverDate={1}; Status={2}; PNP={3}" -f $g.DriverVersion,$date,$g.Status,$g.PNPDeviceID)}}}catch{$rows += [PSCustomObject]@{Category='GPU';Test='Win32_VideoController';Status='WARN';Detail=$_.Exception.Message}};foreach($p in @(Get-PnpRelatedInventory|Where-Object{$_.Class -eq 'Display' -or $_.FriendlyName -match '(?i)(NVIDIA|AMD).*(High Definition Audio|Display Audio)'})){$rows += [PSCustomObject]@{Category=$(if($p.Class -eq 'Display'){'GPU PnP'}else{'Display Audio PnP'});Test=[string]$p.FriendlyName;Status=[string]$p.Severity;Detail=("Status={0}; ProblemCode={1} ({2}); InstanceId={3}" -f $p.Status,$p.ProblemCode,$p.ProblemText,$p.InstanceId)}};return $rows
}

function Get-GameCrashTelemetry([int]$Days=7,[int]$MaxEvents=120,[switch]$Raw) {
    $since=(Get-Date).AddDays(-1*$Days)
    $items=@()

    function Get-EventProcessName([object]$e) {
        $name=''
        try {
            if($e.Properties -and $e.Properties.Count -gt 0) {
                $candidate=[string]$e.Properties[0].Value
                if($candidate -match '(?i)\.exe$') { $name=$candidate }
            }
        } catch {}
        if(-not $name) {
            $msg=''
            try{$msg=[string]$e.Message}catch{}
            foreach($p in @(
                '(?im)(?:Faulting application name|Application Name|错误应用程序名称|故障应用程序名称)\s*[:：]\s*(?<v>[^,\r\n]+\.exe)',
                '(?im)(?:Hang application name|挂起应用程序名称)\s*[:：]\s*(?<v>[^,\r\n]+\.exe)'
            )){
                if($msg -match $p){$name=[string]$matches['v'];break}
            }
        }
        return $name.Trim()
    }

    function AddCrashEvent([object]$e,[string]$Category,[string]$Severity){
        if(-not $e){return}
        $msg=''
        try{$msg=[string]$e.Message}catch{}
        if($msg.Length -gt 700){$msg=$msg.Substring(0,700)}
        $proc=Get-EventProcessName $e
        $script:__crashItems += [PSCustomObject]@{
            Time=$e.TimeCreated
            Category=$Category
            Severity=$Severity
            Provider=[string]$e.ProviderName
            Id=[int]$e.Id
            Process=$proc
            Count=1
            Message=($msg -replace '[\r\n]+',' ')
        }
    }

    function Get-EventsBounded([hashtable]$Filter,[int]$Take) {
        try {
            return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Take -ErrorAction Stop)
        } catch {
            try { return @(Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue | Select-Object -First $Take) }
            catch { return @() }
        }
    }

    $script:__crashItems=@()

    foreach($e in @(Get-EventsBounded @{LogName='Application';StartTime=$since;Id=1000} 50)){AddCrashEvent $e 'Application Crash' 'WARN'}
    foreach($e in @(Get-EventsBounded @{LogName='Application';StartTime=$since;Id=1002} 40)){AddCrashEvent $e 'Application Hang' 'WARN'}
    foreach($e in @(Get-EventsBounded @{LogName='Application';StartTime=$since;Id=1001} 60)){
        $m='';try{$m=[string]$e.Message}catch{}
        if($m -match '(?i)LiveKernelEvent|APPCRASH|BEX64|RADAR_PRE_LEAK'){AddCrashEvent $e 'Windows Error Reporting' 'WARN'}
    }
    foreach($e in @(Get-EventsBounded @{LogName='System';ProviderName='Display';StartTime=$since;Id=4101} 35)){AddCrashEvent $e 'GPU TDR / Display' 'WARN'}
    foreach($e in @(Get-EventsBounded @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$since} 45)){
        if($e.Id -in @(1,17,18,19,20,46,47)){AddCrashEvent $e 'WHEA Hardware' $(if($e.Id -in @(18,46)){'FAIL'}else{'WARN'})}
    }
    foreach($e in @(Get-EventsBounded @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';StartTime=$since;Id=41} 25)){AddCrashEvent $e 'Unexpected Restart' 'WARN'}

    $items=@($script:__crashItems|Sort-Object Time -Descending)
    $script:__crashItems=$null

    if($Raw){
        return @($items|Select-Object -First $MaxEvents)
    }

    # UI view: collapse repeated identical app/provider events so one noisy service
    # does not occupy the entire page. Raw evidence is still exported separately.
    $grouped=@()
    foreach($g in @($items|Group-Object {
        $p=[string]$_.Process
        if(-not $p){$p='(unknown)'}
        "{0}|{1}|{2}|{3}" -f $_.Category,$_.Provider,$_.Id,$p
    })){
        $latest=@($g.Group|Sort-Object Time -Descending|Select-Object -First 1)[0]
        if(-not $latest){continue}
        $sev='WARN'
        if(@($g.Group|Where-Object{$_.Severity -eq 'FAIL'}).Count -gt 0){$sev='FAIL'}
        $grouped += [PSCustomObject]@{
            Time=$latest.Time
            Category=$latest.Category
            Severity=$sev
            Provider=$latest.Provider
            Id=$latest.Id
            Process=$latest.Process
            Count=$g.Count
            Message=$latest.Message
        }
    }
    return @($grouped|Sort-Object Time -Descending|Select-Object -First $MaxEvents)
}

function Get-CrashHealthRows([int]$Days=7) {
    $events=@(Get-GameCrashTelemetry $Days 180 -Raw);$rows=@()
    foreach($g in @($events|Group-Object Category)){
        $sev='PASS';if(@($g.Group|Where-Object{$_.Severity -eq 'FAIL'}).Count -gt 0){$sev='FAIL'}elseif($g.Count -gt 0){$sev='WARN'}
        $latest='';if($g.Group[0].Time){$latest=([datetime]$g.Group[0].Time).ToString('yyyy-MM-dd HH:mm:ss')}
        $rows += [PSCustomObject]@{Category='Crash';Test=[string]$g.Name;Status=$sev;Detail=("Last {0} days count={1}; latest={2}" -f $Days,$g.Count,$latest)}
    }
    if($rows.Count -eq 0){$rows += [PSCustomObject]@{Category='Crash';Test='Windows crash/event evidence';Status='PASS';Detail="最近 $Days 天未发现已监控的 Application Crash/Hang、LiveKernelEvent、Display 4101、WHEA 或 Kernel-Power 41 证据"}}
    return $rows
}

function Invoke-DllLoadTest([string]$Arch,[string[]]$Dlls) {
    $ps=Join-Path $env:WINDIR $(if($Arch -eq 'x86' -and [Environment]::Is64BitOperatingSystem){'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'}else{'System32\WindowsPowerShell\v1.0\powershell.exe'})
    if(-not (Test-Path -LiteralPath $ps)){return [PSCustomObject]@{Success=$false;Detail='PowerShell arch host missing'}}
    $worker=Join-Path $DeepTestRoot ('dll_load_'+$Arch+'_'+[guid]::NewGuid().ToString('N')+'.ps1');$result=$worker+'.json'
    $list=($Dlls|ForEach-Object{"'"+($_ -replace "'","''")+"'"}) -join ','
    $code=@"
param([string]`$Result)
`$ErrorActionPreference='SilentlyContinue'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; public static class DllSmoke230 { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryW(string n); [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr h); }
'@
`$out=@();foreach(`$n in @($list)){`$h=[DllSmoke230]::LoadLibraryW(`$n);`$ok=(`$h -ne [IntPtr]::Zero);if(`$ok){[DllSmoke230]::FreeLibrary(`$h)|Out-Null};`$out += [PSCustomObject]@{Dll=`$n;Loaded=`$ok}}
[PSCustomObject]@{Success=(@(`$out|Where-Object{-not `$_.Loaded}).Count -eq 0);Items=`$out}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath `$Result -Encoding UTF8
"@
    try{$code|Set-Content -LiteralPath $worker -Encoding UTF8;$p=Start-Process -FilePath $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$worker`" -Result `"$result`"" -PassThru -WindowStyle Hidden;$p.WaitForExit();if(Test-Path -LiteralPath $result){$o=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json;return [PSCustomObject]@{Success=[bool]$o.Success;Detail=(@($o.Items|ForEach-Object{"$($_.Dll)=$($_.Loaded)"}) -join '; ')}}}catch{}finally{Remove-Item -LiteralPath $worker,$result -Force -ErrorAction SilentlyContinue}
    return [PSCustomObject]@{Success=$false;Detail='DLL load worker failed'}
}

function Get-AdditionalGameRuntimeRows {
    $rows=@()
    # .NET Framework 4.x
    try{$rel=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release;$rows += [PSCustomObject]@{Category='.NET';Test='.NET Framework 4.x';Status='PASS';Detail="Release=$rel"}}catch{$rows += [PSCustomObject]@{Category='.NET';Test='.NET Framework 4.x';Status='INFO';Detail='未读取到 v4 Full Release；仅作为兼容信息，不自动安装'}}
    # Modern .NET Desktop runtimes
    $dotnetRows=@();foreach($root in @("$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App","${env:ProgramFiles(x86)}\dotnet\shared\Microsoft.WindowsDesktop.App")){if($root -and (Test-Path -LiteralPath $root)){try{$dotnetRows += Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name}catch{}}}
    if($dotnetRows.Count -gt 0){$rows += [PSCustomObject]@{Category='.NET';Test='.NET Desktop Runtime';Status='PASS';Detail=('Installed: '+(@($dotnetRows|Sort-Object -Unique)-join ', '))}}else{$rows += [PSCustomObject]@{Category='.NET';Test='.NET Desktop Runtime';Status='INFO';Detail='未发现 Microsoft.WindowsDesktop.App；不是所有游戏都需要，因此不视为故障'}}
    # WebView2 runtime, discovered by product name rather than hard-coded GUID.
    $wv=@();foreach($root in @('HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\*','HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\*')){try{$wv += Get-ItemProperty $root -ErrorAction SilentlyContinue|Where-Object{([string]$_.name -match '(?i)WebView2') -or ([string]$_.pv -and [string]$_.name -match '(?i)Microsoft Edge WebView')}}catch{}}
    if($wv.Count -gt 0){$rows += [PSCustomObject]@{Category='WebView2';Test='Microsoft Edge WebView2 Runtime';Status='PASS';Detail=('Versions: '+(@($wv|ForEach-Object{$_.pv}|Where-Object{$_}|Sort-Object -Unique)-join ', '))}}else{$rows += [PSCustomObject]@{Category='WebView2';Test='Microsoft Edge WebView2 Runtime';Status='INFO';Detail='未发现 WebView2；仅在游戏启动器明确依赖时才需要安装'}}
    # Vulkan/OpenAL loaders: absence alone is not a Windows fault.
    foreach($a in @('x64','x86')){
        $v=Invoke-DllLoadTest $a @('vulkan-1.dll');$rows += [PSCustomObject]@{Category='Vulkan';Test=("Vulkan loader $a");Status=$(if($v.Success){'PASS'}else{'INFO'});Detail=$v.Detail}
        $o=Invoke-DllLoadTest $a @('OpenAL32.dll');$rows += [PSCustomObject]@{Category='OpenAL';Test=("OpenAL loader $a");Status=$(if($o.Success){'PASS'}else{'INFO'});Detail=$o.Detail}
    }
    # XNA side-by-side inventory; missing is informational.
    $xna=@();foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')){try{$xna += Get-ItemProperty $root -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName -match '(?i)Microsoft XNA Framework'}}catch{}}
    $rows += [PSCustomObject]@{Category='XNA';Test='Microsoft XNA Framework';Status=$(if($xna.Count -gt 0){'PASS'}else{'INFO'});Detail=$(if($xna.Count -gt 0){(@($xna|ForEach-Object{"$($_.DisplayName) $($_.DisplayVersion)"}) -join '; ')}else{'未安装；只有明确依赖 XNA 的旧游戏才需要'})}
    return $rows
}

function Invoke-GamePlatformDeepTest {
    $rows=@();try{$rows += @(Invoke-GameRuntimeDeepTest)}catch{$rows += [PSCustomObject]@{Category='Runtime';Test='Existing deep test';Status='WARN';Detail=$_.Exception.Message}}
    $rows += @(Get-GPUHealthRows)
    $rows += @(Get-CrashHealthRows 7)
    $rows += @(Get-AdditionalGameRuntimeRows)
    $obj=[PSCustomObject]@{Version=$AppVersion;CheckedAt=(Get-Date).ToString('o');Rows=$rows};try{Write-JsonAtomic (Join-Path $DeepTestRoot 'LastGamePlatformDeepTest.json') $obj 12|Out-Null}catch{}
    return $rows
}

