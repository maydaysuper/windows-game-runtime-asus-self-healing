#requires -version 5.1
<#
Safe GPU remediation recipe.

This deliberately does NOT:
- write BIOS/UEFI or ReBAR settings;
- modify TdrDelay/TdrDdiDelay/TdrLevel;
- uninstall/restart display adapters;
- run DDU or delete DriverStore packages;
- change clocks, voltages or power plans.

The recipe only rotates user-level shader caches into a rollback folder and asks Windows to
rescan Plug and Play devices. Cache rotation is a metadata move on the same volume when possible.
Locked/in-use caches are skipped rather than force-deleted.
#>
$ErrorActionPreference='Stop'

function Get-WgrGpuVendors {
    $vendors=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        foreach($g in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
            $name=[string]$g.Name;$pnp=[string]$g.PNPDeviceID
            if($pnp -match '(?i)VEN_10DE' -or $name -match '(?i)NVIDIA'){[void]$vendors.Add('NVIDIA')}
            if($pnp -match '(?i)VEN_1002' -or $name -match '(?i)AMD|Radeon'){[void]$vendors.Add('AMD')}
            if($pnp -match '(?i)VEN_8086' -or $name -match '(?i)Intel'){[void]$vendors.Add('INTEL')}
        }
    } catch {}
    return @($vendors)
}

function Test-WgrGpuCachePath([string]$Path) {
    if(-not $Path){return $false}
    try {
        $local=[IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')+'\'
        $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')+'\'
        if(-not $full.StartsWith($local,[StringComparison]::OrdinalIgnoreCase)){return $false}
        $normalized=$full.ToLowerInvariant()
        return $normalized.Contains('\d3dscache\') -or
               $normalized.Contains('\nvidia\dxcache\') -or
               $normalized.Contains('\nvidia\glcache\') -or
               $normalized.Contains('\nvidia corporation\nv_cache\') -or
               $normalized.Contains('\amd\dxcache\') -or
               $normalized.Contains('\amd\glcache\')
    } catch { return $false }
}

function Invoke-WgrGpuSafeRepair {
    $vendors=@(Get-WgrGpuVendors)
    $targets=New-Object System.Collections.Generic.List[string]
    [void]$targets.Add((Join-Path $env:LOCALAPPDATA 'D3DSCache'))
    if($vendors -contains 'NVIDIA') {
        [void]$targets.Add((Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'))
        [void]$targets.Add((Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'))
        [void]$targets.Add((Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NV_Cache'))
    }
    if($vendors -contains 'AMD') {
        [void]$targets.Add((Join-Path $env:LOCALAPPDATA 'AMD\DxCache'))
        [void]$targets.Add((Join-Path $env:LOCALAPPDATA 'AMD\GLCache'))
    }

    $backupRoot=Join-Path $env:LOCALAPPDATA ('WindowsGameRuntimeASUSSelfHealing\GpuCacheBackups\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $backupRoot|Out-Null
    $moved=New-Object System.Collections.Generic.List[object]
    $skipped=New-Object System.Collections.Generic.List[object]
    $index=0
    foreach($path in @($targets | Select-Object -Unique)) {
        if(-not(Test-WgrGpuCachePath $path)) { [void]$skipped.Add([PSCustomObject]@{Path=$path;Reason='Policy denied path'}); continue }
        if(-not(Test-Path -LiteralPath $path)) { continue }
        $index++
        $leaf=Split-Path -Leaf $path
        $dest=Join-Path $backupRoot (('{0:D2}-{1}' -f $index,$leaf))
        try {
            Move-Item -LiteralPath $path -Destination $dest -ErrorAction Stop
            New-Item -ItemType Directory -Force -Path $path|Out-Null
            [void]$moved.Add([PSCustomObject]@{Source=$path;Backup=$dest})
        } catch {
            [void]$skipped.Add([PSCustomObject]@{Path=$path;Reason=$_.Exception.Message})
        }
    }

    $rescanExit=$null
    try {
        $pnputil=Join-Path $env:SystemRoot 'System32\pnputil.exe'
        if(Test-Path -LiteralPath $pnputil) {
            $p=Start-Process -FilePath $pnputil -ArgumentList '/scan-devices' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            $rescanExit=[int]$p.ExitCode
        }
    } catch { $rescanExit=-1 }

    $detail=('安全 GPU 修复完成：已轮换 {0} 个 Shader Cache，跳过 {1} 个；PnP rescan={2}。备份：{3}' -f $moved.Count,$skipped.Count,$rescanExit,$backupRoot)
    return [PSCustomObject]@{
        Success=$true
        Detail=$detail
        State='COMPLETED'
        BackupPath=$backupRoot
        MovedCaches=@($moved)
        SkippedCaches=@($skipped)
        PnpRescanExitCode=$rescanExit
        Safety=[PSCustomObject]@{AutomaticDDU=$false;DriverRemoval=$false;TdrRegistryWrites=$false;BiosWrites=$false;AdapterRestart=$false}
    }
}
