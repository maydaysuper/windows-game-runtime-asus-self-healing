#requires -version 5.1
<#
Read-only GPU / ReBAR / TDR / PCIe evidence collector.

Safety contract:
- No BIOS/UEFI writes.
- No display driver uninstall/restart.
- No TDR registry writes.
- No DDU / DriverStore deletion.
- No power-plan mutation.

This reader only collects evidence. Classification and user-facing confidence are performed
in the C# GpuDiagnosticsService so a single event never becomes a false root-cause verdict.
#>
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

function Get-WgrGpuEventsBounded([hashtable]$Filter,[int]$Take) {
    try { return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Take -ErrorAction Stop) }
    catch {
        try { return @(Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue | Select-Object -First $Take) }
        catch { return @() }
    }
}

function Convert-WgrSizeToBytes([string]$Text) {
    if(-not $Text){return [int64]0}
    if($Text -match '(?i)(?<n>[0-9]+(?:\.[0-9]+)?)\s*(?<u>KiB|MiB|GiB|KB|MB|GB|B)') {
        $n=[double]$matches['n']
        switch -Regex ($matches['u']) {
            '^(KiB|KB)$' { return [int64]($n*1024) }
            '^(MiB|MB)$' { return [int64]($n*1024*1024) }
            '^(GiB|GB)$' { return [int64]($n*1024*1024*1024) }
            default { return [int64]$n }
        }
    }
    return [int64]0
}

function Get-WgrNvidiaSmiEvidence {
    $result=@{}
    try {
        $cmd=Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
        if(-not $cmd){$cmd=Get-Command 'nvidia-smi' -ErrorAction SilentlyContinue}
        if(-not $cmd){return $result}
        $raw=& $cmd.Source -q -x 2>$null | Out-String
        if(-not $raw.Trim()){return $result}
        [xml]$xml=$raw
        foreach($g in @($xml.nvidia_smi_log.gpu)) {
            if(-not $g){continue}
            $name=[string]$g.product_name
            $uuid=[string]$g.uuid
            $fb=Convert-WgrSizeToBytes ([string]$g.fb_memory_usage.total)
            $bar=Convert-WgrSizeToBytes ([string]$g.bar1_memory_usage.total)
            $bus=''
            try{$bus=[string]$g.pci.pci_bus_id}catch{}
            $driver=[string]$xml.nvidia_smi_log.driver_version
            $key=if($bus){$bus}else{$name+'|'+$uuid}
            $result[$key]=[PSCustomObject]@{
                Name=$name
                Uuid=$uuid
                PciBusId=$bus
                FrameBufferBytes=[int64]$fb
                Bar1Bytes=[int64]$bar
                DriverVersion=$driver
            }
        }
    } catch {}
    return $result
}

function Get-WgrLargestGpuMemoryWindow([string]$PnpDeviceId) {
    if(-not $PnpDeviceId){return [int64]0}
    try {
        $device=Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { [string]$_.PNPDeviceID -eq $PnpDeviceId } | Select-Object -First 1
        if(-not $device){return [int64]0}
        $largest=[uint64]0
        foreach($r in @(Get-CimAssociatedInstance -InputObject $device -Association Win32_PNPAllocatedResource -ErrorAction SilentlyContinue)) {
            if([string]$r.CimClass.CimClassName -ne 'Win32_DeviceMemoryAddress'){continue}
            try {
                $start=[uint64]([string]$r.StartingAddress)
                $end=[uint64]([string]$r.EndingAddress)
                if($end -ge $start) {
                    $size=($end-$start)+1
                    if($size -gt $largest){$largest=$size}
                }
            } catch {}
        }
        return [int64]$largest
    } catch { return [int64]0 }
}

function Get-WgrRebarState([string]$Vendor,[int64]$DedicatedBytes,[int64]$LargestWindow,[int64]$Bar1Bytes) {
    # NVIDIA BAR1 is the strongest local evidence available without vendor SDK/BIOS writes.
    # A generic PCI allocation >256 MiB is useful evidence, but not treated as absolute truth.
    if($Vendor -eq 'NVIDIA' -and $Bar1Bytes -gt 0) {
        if($Bar1Bytes -gt (512MB)) {
            return [PSCustomObject]@{State='LIKELY_ENABLED';Confidence='HIGH';Evidence=("NVIDIA BAR1={0:N0} MiB" -f ($Bar1Bytes/1MB))}
        }
        if($Bar1Bytes -le (256MB)) {
            return [PSCustomObject]@{State='LIKELY_DISABLED';Confidence='HIGH';Evidence=("NVIDIA BAR1={0:N0} MiB (small BAR)" -f ($Bar1Bytes/1MB))}
        }
    }
    if($LargestWindow -gt (256MB)) {
        return [PSCustomObject]@{State='LIKELY_ENABLED';Confidence='MEDIUM';Evidence=("Largest assigned PCI memory window={0:N0} MiB" -f ($LargestWindow/1MB))}
    }
    if($LargestWindow -gt 0 -and $LargestWindow -le (256MB) -and $DedicatedBytes -gt (1GB)) {
        return [PSCustomObject]@{State='LIKELY_DISABLED';Confidence='MEDIUM';Evidence=("Largest assigned PCI memory window={0:N0} MiB" -f ($LargestWindow/1MB))}
    }
    return [PSCustomObject]@{State='UNKNOWN';Confidence='LOW';Evidence='Windows did not expose a reliable large-BAR signal for this adapter.'}
}

function Get-WgrGpuAdapters {
    $nvidia=Get-WgrNvidiaSmiEvidence
    $rows=@()
    foreach($g in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
        $name=[string]$g.Name
        $pnp=[string]$g.PNPDeviceID
        $vendor='OTHER'
        if($pnp -match '(?i)VEN_10DE' -or $name -match '(?i)NVIDIA'){$vendor='NVIDIA'}
        elseif($pnp -match '(?i)VEN_1002' -or $name -match '(?i)AMD|Radeon'){$vendor='AMD'}
        elseif($pnp -match '(?i)VEN_8086' -or $name -match '(?i)Intel'){$vendor='INTEL'}

        $dedicated=[int64]0
        try{$dedicated=[int64][uint32]$g.AdapterRAM}catch{}
        $bar1=[int64]0
        $smiMatch=$null
        if($vendor -eq 'NVIDIA' -and $nvidia.Count -gt 0) {
            $smiMatch=@($nvidia.Values | Where-Object { [string]$_.Name -eq $name } | Select-Object -First 1)
            if(-not $smiMatch){$smiMatch=@($nvidia.Values | Select-Object -First 1)}
            if($smiMatch) {
                if([int64]$smiMatch.FrameBufferBytes -gt 0){$dedicated=[int64]$smiMatch.FrameBufferBytes}
                $bar1=[int64]$smiMatch.Bar1Bytes
            }
        }
        $largest=Get-WgrLargestGpuMemoryWindow $pnp
        $rebar=Get-WgrRebarState $vendor $dedicated $largest $bar1
        $driverDate=''
        try{$driverDate=([Management.ManagementDateTimeConverter]::ToDateTime([string]$g.DriverDate)).ToString('yyyy-MM-dd')}catch{$driverDate=[string]$g.DriverDate}
        $rows += [PSCustomObject]@{
            Name=$name
            Vendor=$vendor
            PnpDeviceId=$pnp
            DriverVersion=[string]$g.DriverVersion
            DriverDate=$driverDate
            Status=[string]$g.Status
            DedicatedBytes=[int64]$dedicated
            LargestPciMemoryWindowBytes=[int64]$largest
            Bar1Bytes=[int64]$bar1
            RebarState=[string]$rebar.State
            RebarConfidence=[string]$rebar.Confidence
            RebarEvidence=[string]$rebar.Evidence
        }
    }
    return @($rows)
}

function Get-WgrEventSummary([datetime]$SinceLocal) {
    $display=@(Get-WgrGpuEventsBounded @{LogName='System';ProviderName='Display';StartTime=$SinceLocal;Id=4101} 120)
    $nvidia=@(Get-WgrGpuEventsBounded @{LogName='System';ProviderName='nvlddmkm';StartTime=$SinceLocal} 160)
    $amd=@()
    foreach($provider in @('amdkmdag','amdwddmg')){$amd += @(Get-WgrGpuEventsBounded @{LogName='System';ProviderName=$provider;StartTime=$SinceLocal} 100)}
    $intel=@()
    foreach($provider in @('igfx','Intel-GFX','igfxCUIService2.0.0.0')){$intel += @(Get-WgrGpuEventsBounded @{LogName='System';ProviderName=$provider;StartTime=$SinceLocal} 80)}
    $whea=@(Get-WgrGpuEventsBounded @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$SinceLocal} 180)
    $kp=@(Get-WgrGpuEventsBounded @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';StartTime=$SinceLocal;Id=41} 100)
    $wer=@(Get-WgrGpuEventsBounded @{LogName='Application';StartTime=$SinceLocal;Id=1001} 260)

    $wheaPcie=0;$wheaFatal=0;$wheaCorrected=0
    $wheaPcieTimes=New-Object System.Collections.Generic.List[string]
    foreach($e in $whea) {
        $msg='';try{$msg=[string]$e.Message}catch{}
        if($e.Id -eq 17){$wheaCorrected++}
        if($e.Id -in @(18,46)){$wheaFatal++}
        if($msg -match '(?i)PCI\s*Express|PCIe|Root\s*Port|根端口|PCI Express 根端口'){
            $wheaPcie++
            try{$wheaPcieTimes.Add(([datetime]$e.TimeCreated).ToUniversalTime().ToString('o'))}catch{}
        }
    }

    $abrupt=0;$kpDetails=@();$abruptTimes=New-Object System.Collections.Generic.List[string]
    foreach($e in $kp) {
        $bug=0;$button=[int64]0;$sleep=0
        try {
            [xml]$xml=$e.ToXml();$map=@{}
            foreach($d in @($xml.Event.EventData.Data)){$map[[string]$d.Name]=[string]$d.'#text'}
            if($map.ContainsKey('BugcheckCode')){[void][int]::TryParse($map['BugcheckCode'],[ref]$bug)}
            if($map.ContainsKey('PowerButtonTimestamp')){[void][int64]::TryParse($map['PowerButtonTimestamp'],[ref]$button)}
            if($map.ContainsKey('SleepInProgress')){[void][int]::TryParse($map['SleepInProgress'],[ref]$sleep)}
        } catch {}
        if($bug -eq 0 -and $button -eq 0){
            $abrupt++
            try{$abruptTimes.Add(([datetime]$e.TimeCreated).ToUniversalTime().ToString('o'))}catch{}
        }
        $kpDetails += [PSCustomObject]@{Time=([datetime]$e.TimeCreated).ToUniversalTime().ToString('o');BugcheckCode=$bug;PowerButtonTimestamp=$button;SleepInProgress=$sleep}
    }

    $liveKernel=0;$liveCodes=New-Object System.Collections.Generic.List[string];$liveKernelTimes=New-Object System.Collections.Generic.List[string]
    foreach($e in $wer) {
        $blob=''
        try{$blob=([string]$e.Message)+' '+((@($e.Properties)|ForEach-Object{[string]$_.Value}) -join ' ')}catch{}
        if($blob -match '(?i)LiveKernelEvent') {
            $liveKernel++
            try{$liveKernelTimes.Add(([datetime]$e.TimeCreated).ToUniversalTime().ToString('o'))}catch{}
            foreach($code in @('141','117','193','1a8','1b0')){if($blob -match ('(?i)(^|\D)'+[regex]::Escape($code)+'(\D|$)')){if(-not $liveCodes.Contains($code)){$liveCodes.Add($code)}}}
        }
    }

    $displayTimes=@($display | ForEach-Object { try { ([datetime]$_.TimeCreated).ToUniversalTime().ToString('o') } catch {} })
    $vendorTimes=@((@($nvidia)+@($amd)+@($intel)) | ForEach-Object { try { ([datetime]$_.TimeCreated).ToUniversalTime().ToString('o') } catch {} })

    return [PSCustomObject]@{
        DisplayTdrCount=$display.Count
        NvidiaDriverEventCount=$nvidia.Count
        AmdDriverEventCount=$amd.Count
        IntelDriverEventCount=$intel.Count
        WheaCorrectedCount=$wheaCorrected
        WheaFatalCount=$wheaFatal
        WheaPcieCount=$wheaPcie
        KernelPower41Count=$kp.Count
        AbruptPowerLossLikeCount=$abrupt
        LiveKernelGpuCount=$liveKernel
        LiveKernelCodes=@($liveCodes)
        DisplayTdrTimesUtc=@($displayTimes | Select-Object -First 80)
        VendorDriverTimesUtc=@($vendorTimes | Select-Object -First 120)
        LiveKernelTimesUtc=@($liveKernelTimes | Select-Object -First 80)
        WheaPcieTimesUtc=@($wheaPcieTimes | Select-Object -First 120)
        AbruptPowerLossTimesUtc=@($abruptTimes | Select-Object -First 80)
        KernelPowerDetails=@($kpDetails | Select-Object -First 20)
    }
}

function Get-WgrLiveKernelReports([datetime]$SinceLocal) {
    $root=Join-Path $env:SystemRoot 'LiveKernelReports'
    if(-not(Test-Path -LiteralPath $root)){return @()}
    try {
        return @(Get-ChildItem -LiteralPath $root -Filter '*.dmp' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {$_.LastWriteTime -ge $SinceLocal} |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 40 |
            ForEach-Object {[PSCustomObject]@{Name=$_.Name;Path=$_.FullName;Folder=$_.Directory.Name;Length=[int64]$_.Length;LastWriteUtc=$_.LastWriteTimeUtc.ToString('o')}})
    } catch { return @() }
}

function Get-WgrTdrOverrides {
    $path='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    $names=@('TdrLevel','TdrDelay','TdrDdiDelay','TdrDebugMode','TdrLimitTime','TdrLimitCount')
    $out=@()
    try {
        $v=Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        foreach($name in $names) {
            if($null -ne $v -and $v.PSObject.Properties.Name -contains $name) {
                $out += [PSCustomObject]@{Name=$name;Value=[string]$v.$name}
            }
        }
    } catch {}
    return @($out)
}

function Get-WgrGpuDiagnosticsSnapshot([datetime]$SinceUtc) {
    if($SinceUtc -eq [datetime]::MinValue){$SinceUtc=(Get-Date).AddDays(-7).ToUniversalTime()}
    $sinceLocal=$SinceUtc.ToLocalTime()
    $started=[DateTime]::UtcNow
    return [PSCustomObject]@{
        ScanStartedUtc=$started.ToString('o')
        SinceUtc=$SinceUtc.ToUniversalTime().ToString('o')
        Adapters=@(Get-WgrGpuAdapters)
        Events=(Get-WgrEventSummary $sinceLocal)
        LiveKernelReports=@(Get-WgrLiveKernelReports $sinceLocal)
        TdrOverrides=@(Get-WgrTdrOverrides)
        Safety=[PSCustomObject]@{
            BiosWrites=$false
            DriverRemoval=$false
            AutomaticDdu=$false
            TdrRegistryWrites=$false
            PowerPlanWrites=$false
        }
        ScanCompletedUtc=[DateTime]::UtcNow.ToString('o')
    }
}
