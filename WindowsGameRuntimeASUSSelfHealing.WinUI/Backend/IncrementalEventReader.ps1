#requires -version 5.1
<#
Read-only incremental Event Log adapter for WinUI 3.
This file is intentionally separated from RepairCenter.ps1 so crash/GPU telemetry can
run concurrently without importing or touching the hash-locked ASUS repair adapters.
It never repairs, uninstalls, edits drivers, or writes machine configuration.
#>

function Get-IncrementalEventProcessName([object]$Event) {
    $name=''
    try {
        if($Event.Properties -and $Event.Properties.Count -gt 0) {
            $candidate=[string]$Event.Properties[0].Value
            if($candidate -match '(?i)\.exe$') { $name=$candidate }
        }
    } catch {}
    if(-not $name) {
        $msg=''
        try { $msg=[string]$Event.Message } catch {}
        foreach($pattern in @(
            '(?im)(?:Faulting application name|Application Name|错误应用程序名称|故障应用程序名称)\s*[:：]\s*(?<v>[^,\r\n]+\.exe)',
            '(?im)(?:Hang application name|挂起应用程序名称)\s*[:：]\s*(?<v>[^,\r\n]+\.exe)'
        )) {
            if($msg -match $pattern) { $name=[string]$matches['v']; break }
        }
    }
    return $name.Trim()
}

function Get-IncrementalEventsBounded([hashtable]$Filter,[int]$Take) {
    try { return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Take -ErrorAction Stop) }
    catch {
        try { return @(Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue | Select-Object -First $Take) }
        catch { return @() }
    }
}

function Get-IncrementalCrashEvents([datetime]$SinceUtc,[int]$MaxEvents=500) {
    if($SinceUtc -eq [datetime]::MinValue) { $SinceUtc=(Get-Date).AddDays(-7) }
    $sinceLocal=$SinceUtc.ToLocalTime()
    $items=New-Object System.Collections.Generic.List[object]

    function Add-Event([object]$Event,[string]$Category,[string]$Severity) {
        if(-not $Event -or -not $Event.RecordId) { return }
        $msg=''
        try { $msg=[string]$Event.Message } catch {}
        if($msg.Length -gt 900) { $msg=$msg.Substring(0,900) }
        $logName=''
        try { $logName=[string]$Event.LogName } catch {}
        if(-not $logName) { return }
        $recordId=[int64]$Event.RecordId
        $when=$Event.TimeCreated
        if(-not $when) { $when=Get-Date }
        [void]$items.Add([PSCustomObject]@{
            EventKey=("{0}:{1}" -f $logName,$recordId)
            Time=([datetime]$when).ToUniversalTime().ToString('o')
            LogName=$logName
            RecordId=$recordId
            Category=$Category
            Severity=$Severity
            Provider=[string]$Event.ProviderName
            Id=[int]$Event.Id
            Process=(Get-IncrementalEventProcessName $Event)
            Message=($msg -replace '[\r\n]+',' ')
        })
    }

    foreach($e in @(Get-IncrementalEventsBounded @{LogName='Application';StartTime=$sinceLocal;Id=1000} 180)) { Add-Event $e 'Application Crash' 'WARN' }
    foreach($e in @(Get-IncrementalEventsBounded @{LogName='Application';StartTime=$sinceLocal;Id=1002} 120)) { Add-Event $e 'Application Hang' 'WARN' }
    foreach($e in @(Get-IncrementalEventsBounded @{LogName='Application';StartTime=$sinceLocal;Id=1001} 220)) {
        $m=''; try { $m=[string]$e.Message } catch {}
        if($m -match '(?i)LiveKernelEvent|APPCRASH|BEX64|RADAR_PRE_LEAK') { Add-Event $e 'Windows Error Reporting' 'WARN' }
    }
    foreach($e in @(Get-IncrementalEventsBounded @{LogName='System';ProviderName='Display';StartTime=$sinceLocal;Id=4101} 100)) { Add-Event $e 'GPU TDR / Display' 'WARN' }
    foreach($provider in @('nvlddmkm','amdkmdag','amdwddmg','igfx','Intel-GFX')) {
        foreach($e in @(Get-IncrementalEventsBounded @{LogName='System';ProviderName=$provider;StartTime=$sinceLocal} 100)) { Add-Event $e 'GPU Driver' 'WARN' }
    }
    foreach($e in @(Get-IncrementalEventsBounded @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$sinceLocal} 140)) {
        if($e.Id -in @(1,17,18,19,20,46,47)) {
            $sev='WARN'; if($e.Id -in @(18,46)) { $sev='FAIL' }
            Add-Event $e 'WHEA Hardware' $sev
        }
    }
    foreach($e in @(Get-IncrementalEventsBounded @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';StartTime=$sinceLocal;Id=41} 80)) { Add-Event $e 'Unexpected Restart' 'WARN' }

    return @($items | Sort-Object Time -Descending | Select-Object -First ([Math]::Max(1,[Math]::Min($MaxEvents,1000))))
}

function Get-IncrementalGPUHealthRows {
    $rows=@()
    try {
        foreach($g in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
            $status='PASS'
            if([string]$g.Status -and [string]$g.Status -ne 'OK') { $status='WARN' }
            $date=''
            try { $date=([Management.ManagementDateTimeConverter]::ToDateTime([string]$g.DriverDate)).ToString('yyyy-MM-dd') }
            catch { $date=[string]$g.DriverDate }
            $rows += [PSCustomObject]@{
                Category='GPU'
                Test=[string]$g.Name
                Status=$status
                Detail=("Driver={0}; DriverDate={1}; Status={2}; PNP={3}" -f $g.DriverVersion,$date,$g.Status,$g.PNPDeviceID)
            }
        }
    } catch {
        $rows += [PSCustomObject]@{Category='GPU';Test='Win32_VideoController';Status='WARN';Detail=$_.Exception.Message}
    }

    try {
        foreach($p in @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue)) {
            $problem=$null
            try {
                $prop=Get-PnpDeviceProperty -InstanceId ([string]$p.InstanceId) -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop
                if($null -ne $prop.Data) { $problem=[int]$prop.Data }
            } catch {}
            if($null -eq $problem) { $problem=if([string]$p.Status -eq 'OK'){0}else{-1} }
            $severity=if($problem -eq 0 -and [string]$p.Status -eq 'OK'){'PASS'}else{'WARN'}
            $rows += [PSCustomObject]@{
                Category='GPU PnP'
                Test=[string]$p.FriendlyName
                Status=$severity
                Detail=("Status={0}; ProblemCode={1}; InstanceId={2}" -f $p.Status,$problem,$p.InstanceId)
            }
        }
    } catch {}
    return $rows
}

function Get-IncrementalWerStatus {
    $root='HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
    $out=@()
    try {
        if(Test-Path -LiteralPath $root) {
            foreach($p in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                try {
                    $v=Get-ItemProperty -LiteralPath $p.PSPath -ErrorAction SilentlyContinue
                    $out += [PSCustomObject]@{
                        Exe=[string]$p.PSChildName
                        DumpFolder=[Environment]::ExpandEnvironmentVariables([string]$v.DumpFolder)
                        DumpCount=$v.DumpCount
                        DumpType=$v.DumpType
                    }
                } catch {}
            }
        }
    } catch {}
    return $out
}
