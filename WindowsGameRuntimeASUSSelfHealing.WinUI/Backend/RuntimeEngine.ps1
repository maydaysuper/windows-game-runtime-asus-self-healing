#requires -version 5.1
# RuntimeEngine.ps1 — hash-locked VC++ / DirectX detect, compare, repair.
# Dotsourced by RepairCenter.ps1 after BuildInfo validation. Do not run directly.

function Get-FileVersionSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $f = Get-Item -LiteralPath $Path -ErrorAction Stop
        $v = [string]$f.VersionInfo.FileVersion
        if (-not $v) { $v = [string]$f.VersionInfo.ProductVersion }
        return $v
    } catch {
        return ''
    }
}

function Get-RlsTargetVersion([object]$Def) {
    $root = Join-Path $env:ProgramFiles ("ASUS\RLSDownload\" + $Def.Rls)
    if (-not (Test-Path -LiteralPath $root)) { return '' }
    try {
        $items = Get-ChildItem -LiteralPath $root -Recurse -File -Filter $Def.Exe -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        foreach ($i in $items) {
            try {
                $v = [string]$i.VersionInfo.ProductVersion
                if (-not $v) { $v = [string]$i.VersionInfo.FileVersion }
                $sig = Get-AuthenticodeSignature -FilePath $i.FullName -ErrorAction SilentlyContinue
                if ($v -and $sig -and $sig.Status -eq 'Valid') { return $v }
            } catch {}
        }
    } catch {}
    return ''
}

function Compare-VersionSafe([string]$A,[string]$B) {
    $na = Normalize-VersionText $A
    $nb = Normalize-VersionText $B
    if (-not $na -and -not $nb) { return 0 }
    if (-not $na) { return -1 }
    if (-not $nb) { return 1 }
    try {
        $pa = [System.Collections.Generic.List[string]]::new()
        $pb = [System.Collections.Generic.List[string]]::new()
        foreach ($x in @($na.Split('.'))) { if ($pa.Count -lt 4) { [void]$pa.Add($x) } }
        foreach ($x in @($nb.Split('.'))) { if ($pb.Count -lt 4) { [void]$pb.Add($x) } }
        while ($pa.Count -lt 4) { [void]$pa.Add('0') }
        while ($pb.Count -lt 4) { [void]$pb.Add('0') }
        return ([version]($pa -join '.')).CompareTo([version]($pb -join '.'))
    } catch {
        return [string]::Compare($na,$nb,$true)
    }
}

function Normalize-VersionText([string]$VersionText) {
    if (-not $VersionText) { return '' }
    $v = $VersionText.Trim()
    if ($v.StartsWith('v',[System.StringComparison]::OrdinalIgnoreCase)) { $v = $v.Substring(1) }
    if ($v -match '(?<v>\d+\.\d+\.\d+(?:\.\d+)?)') { return [string]$matches['v'] }
    return $v
}

function Test-MicrosoftSignedFile([string]$Path,[switch]$Fast) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{Valid=$false;Status='Missing';SignatureStatus='Missing';Signer='';Thumbprint='';Issuer='';NotBefore='';NotAfter='';SHA256='';Version='';FileVersion='';ProductVersion='';Company=''}
    }
    try {
        $f=Get-Item -LiteralPath $Path -ErrorAction Stop
        $fileVersion=[string]$f.VersionInfo.FileVersion
        $productVersion=[string]$f.VersionInfo.ProductVersion
        $ver=Normalize-VersionText $productVersion;if(-not $ver){$ver=Normalize-VersionText $fileVersion}
        $company=[string]$f.VersionInfo.CompanyName
        if($Fast){
            $valid=($f.Length -gt 0 -and $company -match '(?i)Microsoft')
            $st=if($valid){'FastMetadataOK'}else{'FastMetadataMismatch'}
            return [PSCustomObject]@{Valid=$valid;Status=$st;SignatureStatus=$st;Signer=$company;Thumbprint='';Issuer='';NotBefore='';NotAfter='';SHA256='';Version=$ver;FileVersion=$fileVersion;ProductVersion=$productVersion;Company=$company}
        }
        $sig=Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        $signer='';$thumb='';$issuer='';$nb='';$na=''
        if($sig.SignerCertificate){$signer=[string]$sig.SignerCertificate.Subject;$thumb=[string]$sig.SignerCertificate.Thumbprint;$issuer=[string]$sig.SignerCertificate.Issuer;$nb=$sig.SignerCertificate.NotBefore.ToString('o');$na=$sig.SignerCertificate.NotAfter.ToString('o')}
        $valid=($sig.Status -eq 'Valid' -and $signer -match '(?i)Microsoft')
        $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop).Hash
        return [PSCustomObject]@{Valid=$valid;Status=[string]$sig.Status;SignatureStatus=[string]$sig.Status;Signer=$signer;Thumbprint=$thumb;Issuer=$issuer;NotBefore=$nb;NotAfter=$na;SHA256=$hash;Version=$ver;FileVersion=$fileVersion;ProductVersion=$productVersion;Company=$company}
    } catch {
        return [PSCustomObject]@{Valid=$false;Status=$_.Exception.Message;SignatureStatus=$_.Exception.Message;Signer='';Thumbprint='';Issuer='';NotBefore='';NotAfter='';SHA256='';Version='';FileVersion='';ProductVersion='';Company=''}
    }
}

function Get-RequiredVCRedistArchitectures {
    if ($env:PROCESSOR_ARCHITECTURE -match '(?i)ARM64') { return @('arm64','x64','x86') }
    if ([Environment]::Is64BitOperatingSystem) { return @('x64','x86') }
    return @('x86')
}

function Get-VCRuntimeRegistryState([string]$Arch) {
    $paths = @(
        "HKLM:\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\$Arch",
        "HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\$Arch"
    )
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $e = Get-ItemProperty -LiteralPath $p -ErrorAction Stop
            $version = Normalize-VersionText ([string]$e.Version)
            if (-not $version -and $null -ne $e.Major) {
                $version = '{0}.{1}.{2}.{3}' -f $e.Major,$e.Minor,$e.Bld,$e.Rbld
            }
            return [PSCustomObject]@{
                Arch=$Arch
                Installed=([int]$e.Installed -eq 1)
                Version=$version
                Path=$p
                Source='Runtimes'
            }
        } catch {}
    }
    $label = switch ($Arch) { 'x86' { 'x86' } 'arm64' { 'ARM64' } default { 'x64' } }
    foreach ($root in @(
        'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
        'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
    )) {
        try {
            $hits = @(Get-ItemProperty $root -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -match '(?i)Microsoft Visual C\+\+ 2015-\d+ Redistributable' -and
                    $_.DisplayName -match [regex]::Escape('(' + $label + ')')
                })
            foreach ($h in $hits) {
                $version = Normalize-VersionText ([string]$h.DisplayVersion)
                if ($version) {
                    return [PSCustomObject]@{
                        Arch=$Arch
                        Installed=$true
                        Version=$version
                        Path=[string]$h.PSPath
                        Source='Uninstall'
                    }
                }
            }
        } catch {}
    }
    return [PSCustomObject]@{Arch=$Arch;Installed=$false;Version='';Path='';Source=''}
}

function Get-VCRuntimeFileRoot([string]$Arch) {
    if ($Arch -eq 'x86' -and [Environment]::Is64BitOperatingSystem) { return (Join-Path $env:WINDIR 'SysWOW64') }
    return (Join-Path $env:WINDIR 'System32')
}

function Get-VCRuntimeDllNames([string]$Arch) {
    $names = @(
        'vcruntime140.dll',
        'msvcp140.dll',
        'msvcp140_1.dll',
        'msvcp140_2.dll',
        'msvcp140_atomic_wait.dll',
        'msvcp140_codecvt_ids.dll',
        'concrt140.dll',
        'vccorlib140.dll'
    )
    if ($Arch -ne 'x86') { $names += 'vcruntime140_1.dll' }
    return $names
}

function Get-VCRuntimeFileState([string]$Arch,[switch]$Deep) {
    $root = Get-VCRuntimeFileRoot $Arch
    $names = @(Get-VCRuntimeDllNames $Arch)
    $rows = @()
    foreach ($n in $names) {
        $p = Join-Path $root $n
        $t = Test-MicrosoftSignedFile $p -Fast:(-not $Deep)
        $rows += [PSCustomObject]@{
            Arch=$Arch;Name=$n;Path=$p;Exists=(Test-Path -LiteralPath $p);SignatureOK=[bool]$t.Valid;Version=[string]$t.Version;Signer=[string]$t.Signer
        }
    }
    return $rows
}

function Initialize-VCLoadType {
    if ($script:VCLoadTypeReady) { return $true }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VCLoad {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryW(string p);
    [DllImport("kernel32.dll")]
    public static extern bool FreeLibrary(IntPtr h);
}
'@ -ErrorAction Stop | Out-Null
        $script:VCLoadTypeReady = $true
        return $true
    } catch {
        return $false
    }
}

function Test-VCRuntimeInProcessLoad([string]$Arch,[object[]]$Files) {
    $result = [PSCustomObject]@{Ran=$false;Success=$true;Failed=@()}
    if ($Arch -eq 'x86' -and [Environment]::Is64BitOperatingSystem) { return $result }
    if ($Arch -eq 'arm64' -and $env:PROCESSOR_ARCHITECTURE -notmatch '(?i)ARM64') { return $result }
    if (-not (Initialize-VCLoadType)) { return $result }
    $core = @('vcruntime140.dll','msvcp140.dll','vcruntime140_1.dll')
    $result.Ran = $true
    foreach ($f in @($Files)) {
        $name = [string]$f.Name
        if ($core -notcontains $name) { continue }
        if (-not $f.Exists) { $result.Success = $false; $result.Failed += $name; continue }
        try {
            $h = [VCLoad]::LoadLibraryW([string]$f.Path)
            if ($h -eq [IntPtr]::Zero) {
                $result.Success = $false
                $result.Failed += $name
            } else {
                [void][VCLoad]::FreeLibrary($h)
            }
        } catch {
            $result.Success = $false
            $result.Failed += $name
        }
    }
    return $result
}

function Get-VCRuntimeLocalState([string]$Arch,[switch]$Deep) {
    $reg = Get-VCRuntimeRegistryState $Arch
    $files = @(Get-VCRuntimeFileState $Arch -Deep:$Deep)
    $missing = @($files | Where-Object { -not $_.Exists })
    $bad = @($files | Where-Object { $_.Exists -and -not $_.SignatureOK })
    $ok = @($files | Where-Object { $_.Exists -and $_.SignatureOK })
    $versions = @($ok | ForEach-Object { Normalize-VersionText ([string]$_.Version) } | Where-Object { $_ })
    $fileVersion = ''
    $inconsistent = $false
    if ($versions.Count -gt 0) {
        $fileVersion = $versions[0]
        foreach ($v in $versions) {
            if ((Compare-VersionSafe $v $fileVersion) -lt 0) { $fileVersion = $v }
        }
        foreach ($v in $versions) {
            if ((Compare-VersionSafe $v $fileVersion) -ne 0) { $inconsistent = $true; break }
        }
    }
    $effective = $fileVersion
    if (-not $effective) { $effective = [string]$reg.Version }
    $complete = ($missing.Count -eq 0 -and $bad.Count -eq 0 -and $ok.Count -eq $files.Count)
    $load = Test-VCRuntimeInProcessLoad $Arch $files
    $healthy = $complete -and -not $inconsistent -and (-not $load.Ran -or $load.Success)
    return [PSCustomObject]@{
        Arch=$Arch
        Registry=$reg
        Files=$files
        MissingCount=$missing.Count
        BadCount=$bad.Count
        FileVersion=$fileVersion
        EffectiveVersion=$effective
        Inconsistent=$inconsistent
        Complete=$complete
        LoadRan=[bool]$load.Ran
        LoadOk=[bool]$load.Success
        Healthy=$healthy
        InstalledFlag=[bool]$reg.Installed
    }
}

function Get-VCRuntimeErrorEvidence([int]$Hours=24) {
    $out = @()
    $since = (Get-Date).AddHours(-1 * $Hours)
    try {
        if (Test-Path -LiteralPath $RuntimeRepairStampPath) {
            $stampText = (Get-Content -LiteralPath $RuntimeRepairStampPath -Raw -ErrorAction Stop).Trim()
            $stamp = [datetime]::MinValue
            if ([datetime]::TryParse($stampText,[ref]$stamp) -and $stamp -gt $since) { $since = $stamp }
        }
    } catch {}
    try {
        $events = @()
        try { $events += Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='SideBySide';StartTime=$since} -ErrorAction SilentlyContinue } catch {}
        try { $events += Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';StartTime=$since} -ErrorAction SilentlyContinue } catch {}
        foreach ($e in $events) {
            $msg = [string]$e.Message
            if (-not $msg) { continue }
            $provider = [string]$e.ProviderName
            $hit = $false
            if ($provider -match '(?i)SideBySide' -and $msg -match '(?i)(Microsoft\.VC|VC\+\+|CRT|VCRUNTIME|MSVCP)') { $hit = $true }
            if ($msg -match '(?i)(VCRUNTIME14\d*\.dll|MSVCP14\d*\.dll).*(?:not found|missing|找不到|缺少)') { $hit = $true }
            if ($hit) {
                $out += [PSCustomObject]@{Time=$e.TimeCreated;Id=$e.Id;Provider=$provider;Message=($msg -replace '\s+',' ').Trim()}
            }
        }
    } catch {}
    return @($out | Sort-Object Time -Descending | Select-Object -First 50)
}

function Test-MicrosoftTrustedUri([string]$UriText) {
    try{$u=[uri]$UriText;if($u.Scheme -ne 'https'){return $false};return ($u.Host -match '(?i)(^|\.)microsoft\.com$|(^|\.)visualstudio\.microsoft\.com$|(^|\.)aka\.ms$')}catch{return $false}
}

function Resolve-MicrosoftRedirectChain([string]$Url,[int]$MaxRedirects=10) {
    if(-not (Test-MicrosoftTrustedUri $Url)){throw "Untrusted Microsoft HTTPS source: $Url"}
    $current=[uri]$Url;$chain=@()
    for($i=0;$i -le $MaxRedirects;$i++){
        if(-not (Test-MicrosoftTrustedUri $current.AbsoluteUri)){throw "Redirect left Microsoft trust boundary: $($current.AbsoluteUri)"}
        $req=[System.Net.HttpWebRequest]::Create($current);$req.Method='GET';$req.AllowAutoRedirect=$false;$req.Timeout=15000;$req.ReadWriteTimeout=15000;$req.UserAgent='WindowsGameRuntimeASUSSelfHealing/2.3.2';try{$req.AddRange(0,0)}catch{}
        $resp=$null
        try{$resp=$req.GetResponse()}catch [System.Net.WebException] {if($_.Exception.Response){$resp=$_.Exception.Response}else{throw}}
        try{
            $code=[int]$resp.StatusCode;$loc=[string]$resp.Headers['Location']
            if($code -ge 300 -and $code -lt 400 -and $loc){$next=New-Object System.Uri($current,$loc);if(-not (Test-MicrosoftTrustedUri $next.AbsoluteUri)){throw "Redirect left Microsoft HTTPS trust boundary: $($next.Host)"};$chain += [PSCustomObject]@{Hop=$chain.Count+1;StatusCode=$code;From=$current.AbsoluteUri;To=$next.AbsoluteUri;Host=$next.Host};$current=$next;continue}
            return [PSCustomObject]@{Success=$true;OriginalUri=$Url;RedirectChain=@($chain);FinalUri=$current.AbsoluteUri;FinalHost=$current.Host;Error=''}
        } finally {if($resp){try{$resp.Close()}catch{}}}
    }
    throw "Too many redirects (>$MaxRedirects)"
}

function Get-MicrosoftTrustSidecarPath([string]$Destination){return ($Destination+'.trust.json')}
function Read-MicrosoftTrustSidecar([string]$Destination,[string]$OriginalUri,[string]$SHA256) {
    $p = Get-MicrosoftTrustSidecarPath $Destination
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $o = Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json
        if ([string]$o.OriginalUri -ne $OriginalUri) { return $null }
        if ($SHA256 -and ([string]$o.SHA256 -ne $SHA256)) { return $null }
        if (-not ([bool]$o.TrustComplete)) { return $null }
        if (-not (Test-MicrosoftTrustedUri ([string]$o.FinalUri))) { return $null }
        return $o
    } catch {
        return $null
    }
}
function Write-MicrosoftTrustSidecar([string]$Destination,[object]$Result){try{$p=Get-MicrosoftTrustSidecarPath $Destination;$tmp=$p+'.tmp';$Result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $p -Force}catch{}}
function New-MicrosoftTrustResult([bool]$Success,[string]$Path,[object]$Check,[string]$Source,[string]$OriginalUri,[object]$Redirect,[string]$Error=''){
    $final='';$finalHost='';$chain=@();$redirErr='';if($Redirect){try{$final=[string]$Redirect.FinalUri}catch{};try{$finalHost=[string]$Redirect.FinalHost}catch{};try{$chain=@($Redirect.RedirectChain)}catch{};try{$redirErr=[string]$Redirect.Error}catch{}}
    $complete=($Success -and $Check -and [bool]$Check.Valid -and $final -and (Test-MicrosoftTrustedUri $final))
    return [PSCustomObject]@{SchemaVersion=2;Success=$Success;Path=$Path;Version=$(if($Check){[string]$Check.Version}else{''});FileVersion=$(if($Check){[string]$Check.FileVersion}else{''});ProductVersion=$(if($Check){[string]$Check.ProductVersion}else{''});SHA256=$(if($Check){[string]$Check.SHA256}else{''});SignatureStatus=$(if($Check){[string]$Check.SignatureStatus}else{''});Signer=$(if($Check){[string]$Check.Signer}else{''});Thumbprint=$(if($Check){[string]$Check.Thumbprint}else{''});Issuer=$(if($Check){[string]$Check.Issuer}else{''});NotBefore=$(if($Check){[string]$Check.NotBefore}else{''});NotAfter=$(if($Check){[string]$Check.NotAfter}else{''});Source=$Source;OriginalUri=$OriginalUri;RedirectChain=@($chain);FinalUri=$final;FinalHost=$finalHost;VerifiedAt=(Get-Date).ToString('o');TrustComplete=[bool]$complete;RedirectError=$redirErr;Error=$Error}
}

function Invoke-OfficialMicrosoftDownload([string]$Url,[string]$Destination,[int]$MaxAgeHours=24) {
    try{
        if(-not (Test-MicrosoftTrustedUri $Url)){throw "Non-Microsoft HTTPS source blocked: $Url"}
        if(Test-Path -LiteralPath $Destination){$age=((Get-Date)-(Get-Item -LiteralPath $Destination).LastWriteTime).TotalHours;if($age -le $MaxAgeHours){$check=Test-MicrosoftSignedFile $Destination;if($check.Valid){$side=Read-MicrosoftTrustSidecar $Destination $Url ([string]$check.SHA256);if($side){$side.Source='Cache';$side.VerifiedAt=(Get-Date).ToString('o');return $side};$redirect=$null;try{$redirect=Resolve-MicrosoftRedirectChain $Url}catch{$redirect=[PSCustomObject]@{Success=$false;OriginalUri=$Url;RedirectChain=@();FinalUri='';FinalHost='';Error=$_.Exception.Message}};$r=New-MicrosoftTrustResult $true $Destination $check 'Cache' $Url $redirect '';if($r.TrustComplete){Write-MicrosoftTrustSidecar $Destination $r};return $r}}}
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $redirect=Resolve-MicrosoftRedirectChain $Url;if(-not $redirect.Success -or -not $redirect.FinalUri){throw 'Unable to resolve Microsoft redirect chain'}
        $tmp="$Destination.download";Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Invoke-WebRequest -Uri ([string]$redirect.FinalUri) -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 60 -OutFile $tmp -ErrorAction Stop|Out-Null
        $check=Test-MicrosoftSignedFile $tmp;if(-not $check.Valid){throw "Microsoft Authenticode validation failed: $($check.Status) signer=$($check.Signer)"}
        Move-Item -LiteralPath $tmp -Destination $Destination -Force
        $r=New-MicrosoftTrustResult $true $Destination $check 'Network' $Url $redirect '';if(-not $r.TrustComplete){throw 'Microsoft download trust evidence incomplete'};Write-MicrosoftTrustSidecar $Destination $r;return $r
    }catch{Remove-Item -LiteralPath "$Destination.download" -Force -ErrorAction SilentlyContinue;return [PSCustomObject]@{SchemaVersion=2;Success=$false;Path='';Version='';FileVersion='';ProductVersion='';SHA256='';SignatureStatus='';Signer='';Thumbprint='';Issuer='';NotBefore='';NotAfter='';Source='';OriginalUri=$Url;RedirectChain=@();FinalUri='';FinalHost='';VerifiedAt=(Get-Date).ToString('o');TrustComplete=$false;RedirectError='';Error=$_.Exception.Message}}
}

function Get-VCRedistOnlinePackage([string]$Arch,[switch]$Force) {
    if(-not $VCRedistUrls.ContainsKey($Arch)){return [PSCustomObject]@{Success=$false;TrustComplete=$false;Arch=$Arch;Path='';Version='';SHA256='';Error='Unsupported architecture'}}
    $dest=Join-Path $RuntimeCacheRoot ("vc_redist_$Arch.exe");$age=if($Force){0}else{24}
    $urls=@([string]$VCRedistUrls[$Arch])
    if($VCRedistFallbackUrls.ContainsKey($Arch)){$fb=[string]$VCRedistFallbackUrls[$Arch];if($fb -and $urls -notcontains $fb){$urls += $fb}}
    $last=$null
    foreach($url in $urls){
        $r=Invoke-OfficialMicrosoftDownload $url $dest $age
        $r|Add-Member -NotePropertyName Arch -NotePropertyValue $Arch -Force
        if($r.Success){return $r}
        $last=$r
    }
    if($last){return $last}
    return [PSCustomObject]@{Success=$false;TrustComplete=$false;Arch=$Arch;Path='';Version='';SHA256='';Error='官方安装包不可用'}
}

function Get-DirectXWebInstaller([switch]$Force) {
    $dest=Join-Path $RuntimeCacheRoot 'dxwebsetup.exe';$age=if($Force){0}else{168};$r=Invoke-OfficialMicrosoftDownload $DirectXWebInstallerUrl $dest $age
    if(-not $r.Success){try{$page=Invoke-WebRequest -Uri $DirectXOfficialPage -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 30 -ErrorAction Stop;$m=[regex]::Match([string]$page.Content,'(?i)https://download\.microsoft\.com/[^"''<> ]+/dxwebsetup\.exe');if($m.Success){$r=Invoke-OfficialMicrosoftDownload (($m.Value)-replace '\\/','/') $dest 0}}catch{}}
    return $r
}

function Get-DirectXOfflineInstaller([switch]$Force) {
    $dest=Join-Path $RuntimeCacheRoot 'directx_Jun2010_redist.exe';$age=if($Force){0}else{720};$r=Invoke-OfficialMicrosoftDownload $DirectXOfflineInstallerUrl $dest $age
    if(-not $r.Success){try{$page=Invoke-WebRequest -Uri $DirectXOfflinePage -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 30 -ErrorAction Stop;$m=[regex]::Match([string]$page.Content,'(?i)https://download\.microsoft\.com/[^"''<> ]+/directx_Jun2010_redist\.exe');if($m.Success){$r=Invoke-OfficialMicrosoftDownload (($m.Value)-replace '\\/','/') $dest 0}}catch{}}
    return $r
}

function Invoke-DxDiagCapture {
    $out = Join-Path $RuntimeCacheRoot 'dxdiag_latest.txt'
    try {
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        $dx = Join-Path $env:WINDIR 'System32\dxdiag.exe'
        $p = Start-Process -FilePath $dx -ArgumentList "/whql:off /t `"$out`"" -PassThru -WindowStyle Hidden -ErrorAction Stop
        $deadline=(Get-Date).AddSeconds(45)
        while(-not $p.HasExited -and (Get-Date) -lt $deadline){try{[System.Windows.Forms.Application]::DoEvents()}catch{};Start-Sleep -Milliseconds 200;try{$p.Refresh()}catch{}}
        $ok=$p.HasExited
        if (-not $ok) { try { $p.Kill() } catch {} }
        $limit = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $out) -and (Get-Date) -lt $limit) { Start-Sleep -Milliseconds 250 }
        if (Test-Path -LiteralPath $out) { return $out }
    } catch {}
    return ''
}

function Get-DirectXVersionText([switch]$Deep) {
    # Never launch dxdiag from a UI refresh/repair decision path. dxdiag can take
    # tens of seconds on some gaming systems and made v1.3.0 look frozen.
    # Full dxdiag capture is still available when exporting a diagnostic ZIP.
    if ($script:DxDiagVersionCache -and (((Get-Date) - $script:DxDiagCheckedAt).TotalMinutes -lt 10)) {
        return [string]$script:DxDiagVersionCache
    }
    try {
        $e = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\DirectX' -ErrorAction Stop
        if ($e.Version) { return [string]$e.Version }
    } catch {}
    return 'Windows DirectX'
}

function Get-DirectXCoreState([switch]$Deep) {
    $paths = @(
        (Join-Path $env:WINDIR 'System32\d3d12.dll'),
        (Join-Path $env:WINDIR 'System32\d3d11.dll'),
        (Join-Path $env:WINDIR 'System32\dxgi.dll'),
        (Join-Path $env:WINDIR 'System32\d2d1.dll'),
        (Join-Path $env:WINDIR 'System32\xinput1_4.dll')
    )
    if ([Environment]::Is64BitOperatingSystem) {
        $paths += @(
            (Join-Path $env:WINDIR 'SysWOW64\d3d11.dll'),
            (Join-Path $env:WINDIR 'SysWOW64\dxgi.dll'),
            (Join-Path $env:WINDIR 'SysWOW64\d2d1.dll'),
            (Join-Path $env:WINDIR 'SysWOW64\xinput1_4.dll')
        )
    }
    $bad = @()
    foreach ($p in $paths) {
        $t = Test-MicrosoftSignedFile $p -Fast:(-not $Deep)
        if (-not $t.Valid) { $bad += $p }
    }
    $dxv = Get-DirectXVersionText -Deep:$Deep
    return [PSCustomObject]@{Healthy=($bad.Count -eq 0);DirectXVersion=$dxv;BadFiles=$bad;CheckedFiles=$paths;Deep=[bool]$Deep}
}

function Get-DirectXLegacyState {
    $roots = @((Join-Path $env:WINDIR 'System32'))
    if ([Environment]::Is64BitOperatingSystem) { $roots += (Join-Path $env:WINDIR 'SysWOW64') }
    $names = @('d3dx9_43.dll','d3dx11_43.dll','xinput1_3.dll','XAudio2_7.dll')
    $missing = @()
    $suspicious = @()
    foreach ($root in $roots) {
        foreach ($n in $names) {
            $p = Join-Path $root $n
            if (-not (Test-Path -LiteralPath $p)) { $missing += $p; continue }
            try {
                $f = Get-Item -LiteralPath $p -ErrorAction Stop
                $company = [string]$f.VersionInfo.CompanyName
                if ($f.Length -le 0 -or ($company -and $company -notmatch '(?i)Microsoft')) { $suspicious += $p }
            } catch { $suspicious += $p }
        }
    }
    return [PSCustomObject]@{Healthy=($missing.Count -eq 0 -and $suspicious.Count -eq 0);Missing=$missing;BadSignature=$suspicious;ExpectedCount=($roots.Count*$names.Count)}
}

function Get-LegacyVCRedistInventory {
    $out = @()
    foreach ($root in @(
        'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
        'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
    )) {
        try {
            $out += Get-ItemProperty $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match '(?i)Microsoft Visual C\+\+ (2005|2008|2010|2012|2013).*Redistributable' } |
                Select-Object DisplayName,DisplayVersion,Publisher,PSChildName
        } catch {}
    }
    return @($out | Sort-Object DisplayName,DisplayVersion -Unique)
}

function Get-CachedVCRedistVersion([string]$Arch) {
    $dest=Join-Path $RuntimeCacheRoot ("vc_redist_$Arch.exe")
    if(-not (Test-Path -LiteralPath $dest)){return ''}
    try{
        $check=Test-MicrosoftSignedFile $dest
        if($check.Valid){
            $v=Normalize-VersionText ([string]$check.ProductVersion)
            if(-not $v){$v=Normalize-VersionText ([string]$check.FileVersion)}
            return $v
        }
    }catch{}
    return ''
}

function Read-RuntimeOfficialCache {
    $p = Join-Path $RuntimeCacheRoot 'official-vc14.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $o = Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json
        $at = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$o.CheckedAt, [ref]$at)) { return $null }
        if (((Get-Date) - $at).TotalHours -gt 24) { return $null }
        return $o
    } catch {
        return $null
    }
}

function Write-RuntimeOfficialCache([object]$Info,[string]$Best) {
    if (-not $Best) { return }
    $p = Join-Path $RuntimeCacheRoot 'official-vc14.json'
    try {
        $obj = [PSCustomObject]@{
            SchemaVersion=1
            CheckedAt=(Get-Date).ToString('o')
            OfficialVC14=$Best
            Info=$Info
        }
        $tmp = $p + '.tmp'
        $obj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $p -Force
    } catch {}
}

function Update-WingetVCRedistVersions([string[]]$ArchList) {
    $ids = @{ x64='Microsoft.VCRedist.2015+.x64'; x86='Microsoft.VCRedist.2015+.x86'; arm64='Microsoft.VCRedist.2015+.arm64' }
    if (-not $script:WingetVCVersionCache) { $script:WingetVCVersionCache = @{} }
    $wg = Get-WingetPath
    if (-not $wg) { return }
    $procs = @()
    foreach ($arch in @($ArchList)) {
        if (-not $ids.ContainsKey($arch)) { continue }
        $out = Join-Path $WorkRoot ('winget-vc-' + $arch + '.txt')
        $err = Join-Path $WorkRoot ('winget-vc-' + $arch + '.err.txt')
        try {
            Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
            $p = Start-Process -FilePath $wg -ArgumentList @('show','--id',$ids[$arch],'-e','--accept-source-agreements','--disable-interactivity') -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
            $procs += [PSCustomObject]@{Arch=$arch;Proc=$p;Out=$out;Err=$err}
        } catch {}
    }
    $deadline = (Get-Date).AddSeconds(12)
    foreach ($x in $procs) {
        while ($x.Proc -and -not $x.Proc.HasExited -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 150
            try { $x.Proc.Refresh() } catch {}
        }
        if ($x.Proc -and -not $x.Proc.HasExited) { try { $x.Proc.Kill() } catch {} }
        $text = ''
        if (Test-Path -LiteralPath $x.Out) { $text += [string](Get-Content -LiteralPath $x.Out -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path -LiteralPath $x.Err) { $text += [string](Get-Content -LiteralPath $x.Err -Raw -ErrorAction SilentlyContinue) }
        if ($text -match '(?im)^\s*Version:\s*([0-9.]+)') {
            $script:WingetVCVersionCache[$x.Arch] = (Normalize-VersionText $matches[1])
        }
    }
    $script:WingetVCVersionCacheAt = Get-Date
}

function Get-WingetVCRedistVersion([string]$Arch) {
    if ($script:WingetVCVersionCache -and $script:WingetVCVersionCache.ContainsKey($Arch) -and $script:WingetVCVersionCacheAt -and (((Get-Date) - $script:WingetVCVersionCacheAt).TotalMinutes -lt 5)) {
        return [string]$script:WingetVCVersionCache[$Arch]
    }
    [void](Update-WingetVCRedistVersions @($Arch))
    if ($script:WingetVCVersionCache -and $script:WingetVCVersionCache.ContainsKey($Arch)) {
        return [string]$script:WingetVCVersionCache[$Arch]
    }
    return ''
}

function Update-RuntimeOnlineInfo([switch]$Force) {
    $freshMinutes = if ($Force) { 1 } else { 30 }
    if ((Test-RuntimeOnlineInfoFresh $freshMinutes) -and $script:RuntimeOfficialVC14) {
        return [PSCustomObject]@{Success=$true;Info=$script:RuntimeOnlineInfo;Errors=@();Cached=$true}
    }
    $info = [ordered]@{}; $errors = @(); $best = ''
    $archs = @(Get-RequiredVCRedistArchitectures)
    [void](Update-WingetVCRedistVersions $archs)
    foreach ($arch in $archs) {
        $ver = Get-WingetVCRedistVersion $arch
        $source = 'Winget'
        if (-not $ver) { $ver = Get-CachedVCRedistVersion $arch; if ($ver) { $source = 'Cache' } }
        if (-not $ver -and $Force) {
            try {
                $pkg = Get-VCRedistOnlinePackage $arch -Force:$false
                if ($pkg -and $pkg.Success) {
                    $ver = Normalize-VersionText ([string]$pkg.ProductVersion)
                    if (-not $ver) { $ver = Normalize-VersionText ([string]$pkg.FileVersion) }
                    if (-not $ver) { $ver = Normalize-VersionText ([string]$pkg.Version) }
                    if ($ver) { $source = 'OfficialPackage' }
                }
            } catch {}
        }
        $ok = [bool]$ver
        $info["VC_$arch"] = [PSCustomObject]@{Success=$ok;Arch=$arch;Version=$ver;Source=$source;TrustComplete=$ok}
        if ($ok) {
            if (-not $best -or (Compare-VersionSafe $ver $best) -gt 0) { $best = $ver }
        } else {
            $errors += ("C++ 运行库（$arch）没连上官方源")
        }
    }
    if (-not $best) {
        $disk = Read-RuntimeOfficialCache
        if ($disk -and [string]$disk.OfficialVC14) {
            $best = Normalize-VersionText ([string]$disk.OfficialVC14)
            try {
                foreach ($prop in @($disk.Info.PSObject.Properties)) {
                    $pv = Normalize-VersionText ([string]$prop.Value.Version)
                    if ($pv) {
                        $info[$prop.Name] = [PSCustomObject]@{Success=$true;Arch=[string]$prop.Value.Arch;Version=$pv;Source='DiskCache';TrustComplete=$true}
                    }
                }
            } catch {}
            if ($best) { $errors = @(); $script:RuntimeStatusMessage = '已对比官方 C++ 运行库' }
        }
    }
    $script:RuntimeOnlineInfo = $info
    $script:RuntimeOnlineCheckedAt = Get-Date
    $script:RuntimeOfficialVC14 = $best
    if ($best) {
        $script:RuntimeStatusMessage = '已对比官方 C++ 运行库'
        if ($info.Values | Where-Object { $_.Source -in @('Winget','OfficialPackage','Cache') }) {
            Write-RuntimeOfficialCache $info $best
        }
    } else {
        $script:RuntimeStatusMessage = '这次没连上官方源，无法对比'
    }
    return [PSCustomObject]@{Success=([bool]$best);Info=$info;Errors=$errors;Cached=$false}
}

function Get-OfficialVC14Target([string]$Arch='') {
    if ($Arch -and $script:RuntimeOnlineInfo) {
        $key = 'VC_' + $Arch
        try {
            $row = $script:RuntimeOnlineInfo[$key]
            $pv = Normalize-VersionText ([string]$row.Version)
            if ($pv) { return [PSCustomObject]@{Version=$pv;Minimum='14.30.0.0';Source='Online';Arch=$Arch} }
        } catch {}
    }
    $v = Normalize-VersionText ([string]$script:RuntimeOfficialVC14)
    if (-not $v -and $script:RuntimeOnlineInfo) {
        foreach ($key in @($script:RuntimeOnlineInfo.Keys)) {
            if ($key -notlike 'VC_*') { continue }
            $pv = Normalize-VersionText ([string]$script:RuntimeOnlineInfo[$key].Version)
            if ($pv -and (-not $v -or (Compare-VersionSafe $pv $v) -gt 0)) { $v = $pv }
        }
    }
    if ($v) { return [PSCustomObject]@{Version=$v;Minimum='14.30.0.0';Source='Online';Arch=$Arch} }
    return [PSCustomObject]@{Version='14.42.0.0';Minimum='14.30.0.0';Source='BuiltIn';Arch=$Arch}
}

function Get-RuntimeDiagnosticRows([switch]$Deep) {
    $rows = @()
    $archName = @{ x64='64位'; x86='32位'; arm64='ARM' }
    $vcErrors = @()
    try { $vcErrors = @(Get-VCRuntimeErrorEvidence 24) } catch { $vcErrors = @() }
    $recentFail = ($vcErrors.Count -gt 0)
    foreach ($arch in @(Get-RequiredVCRedistArchitectures)) {
        $st = Get-VCRuntimeLocalState $arch -Deep:$Deep
        $vcTarget = Get-OfficialVC14Target $arch
        $label = 'C++ 运行库（' + $(if ($archName.ContainsKey($arch)) { $archName[$arch] } else { $arch }) + '）'
        $installed = [string]$st.EffectiveVersion
        $target = [string]$vcTarget.Version
        $online = ([string]$vcTarget.Source -eq 'Online' -and $target)
        $status = 'PASS'
        $runtime = '本机可用'
        $detail = '正常，可以运行游戏。'
        if (-not $st.Complete -or $st.Inconsistent -or ($st.LoadRan -and -not $st.LoadOk)) {
            $status = 'REPAIR'
            $runtime = '未安装'
            if ($st.Inconsistent) {
                $detail = 'C++ 运行库文件版本不一致，部分游戏会打不开。点「修复运行库」可以自动修。'
            } elseif ($st.LoadRan -and -not $st.LoadOk) {
                $detail = 'C++ 运行库文件没法正常加载。点「修复运行库」可以自动修。'
            } else {
                $detail = '没有完整的 C++ 运行库，部分游戏会打不开。点「修复运行库」可以自动修。'
            }
        } elseif ($online) {
            $cmp = Compare-VersionSafe $installed $target
            if ($cmp -lt 0) {
                $status = 'UPDATE'
                $runtime = '低于官方'
                $detail = '和官方版本不一样。点「修复运行库」会更新到官方版本。'
            } else {
                $runtime = '已和官方一致'
                $detail = '正常，已和官方版本一致。'
                if ($recentFail) {
                    $status = 'WARN'
                    $runtime = '建议再修'
                    $detail = '文件是齐的，但最近有游戏打不开运行库。点「修复运行库」可以再修一次。'
                }
            }
        } else {
            $cmpMin = Compare-VersionSafe $installed $vcTarget.Minimum
            if ($cmpMin -lt 0) {
                $status = 'WARN'
                $runtime = '版本偏低'
                $detail = '已经能用，但版本偏低。这次没连上官方源。点「修复运行库」可以更新。'
            } elseif ($recentFail) {
                $status = 'WARN'
                $runtime = '建议再修'
                $detail = '本机可用。最近有游戏打不开运行库。点「修复运行库」可以再修一次。'
            } else {
                $detail = '本机可用。这次没连上官方源，无法确认是否最新。'
            }
        }
        $rows += [PSCustomObject]@{
            Key="VC_$arch";Name=$label;Installed=$installed;Target=$target;
            Runtime=$runtime;ErrorCode='';Status=$status;Detail=$detail;Group='RUNTIME'
        }
    }

    $core = Get-DirectXCoreState -Deep:$Deep
    $legacy = Get-DirectXLegacyState

    $coreStatus = 'PASS'
    $coreDetail = '正常，游戏 DirectX 可用。'
    $coreRuntime = '本机可用'
    if (-not $core.Healthy) {
        $coreStatus = 'REPAIR'
        $coreDetail = '游戏 DirectX 不完整。点「修复运行库」会用系统自带修复处理。'
        $coreRuntime = '不完整'
    }
    $rows += [PSCustomObject]@{
        Key='DirectXCore';Name='游戏 DirectX';Installed='已安装';Target='';Runtime=$coreRuntime;ErrorCode='';Status=$coreStatus;Detail=$coreDetail;Group='RUNTIME'
    }

    $legacyStatus = 'PASS'
    $legacyDetail = '正常，老游戏兼容组件齐全。'
    $legacyRuntime = '本机可用'
    if (-not $legacy.Healthy) {
        $legacyStatus = 'REPAIR'
        $legacyDetail = '老游戏兼容组件缺失，部分老游戏可能打不开。点「修复运行库」可以自动装。'
        $legacyRuntime = '不完整'
    }
    $rows += [PSCustomObject]@{
        Key='DirectXLegacy';Name='老游戏兼容组件';Installed='已安装';Target='';Runtime=$legacyRuntime;ErrorCode='';Status=$legacyStatus;Detail=$legacyDetail;Group='RUNTIME'
    }
    return $rows
}

function Write-RuntimeOnlineWorker {
    $worker=@'
param([Parameter(Mandatory=$true)][string]$ResultPath,[Parameter(Mandatory=$true)][string]$CacheRoot,[Parameter(Mandatory=$true)][string]$EnginePath,[switch]$Force)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. $EnginePath -LibraryMode
$info=[ordered]@{};$errors=@()
foreach($a in @(Get-RequiredVCRedistArchitectures)){$dest=Join-Path $CacheRoot ("vc_redist_"+$a+".exe");$age=if($Force){0}else{24};$r=Invoke-OfficialMicrosoftDownload ([string]$VCRedistUrls[$a]) $dest $age;$r|Add-Member -NotePropertyName Arch -NotePropertyValue $a -Force;$info["VC_"+$a]=$r;if(-not $r.Success){$errors += "VC++ ${a}: $($r.Error)"}}
$dxDest=Join-Path $CacheRoot 'dxwebsetup.exe';$dxAge=if($Force){0}else{168};$dx=Invoke-OfficialMicrosoftDownload $DirectXWebInstallerUrl $dxDest $dxAge;$info['DirectXLegacy']=$dx;if(-not $dx.Success){$errors += "DirectX legacy: $($dx.Error)"}
$result=[PSCustomObject]@{SchemaVersion=2;EngineVersion=$AppVersion;BuildId=$BuildId;EngineSHA256=$script:EngineSHA256;Success=($errors.Count -eq 0);CheckedAt=(Get-Date).ToString('o');Errors=$errors;Info=$info}
$tmp=$ResultPath+'.tmp';$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $ResultPath -Force;exit $(if($result.Success){0}else{2})
'@
    try{$worker|Set-Content -LiteralPath $RuntimeWorkerPath -Encoding UTF8;return $true}catch{return $false}
}


function Import-RuntimeWorkerResult {
    if (-not (Test-Path -LiteralPath $RuntimeWorkerResultPath)) { return $null }
    try {
        $r = Get-Content -LiteralPath $RuntimeWorkerResultPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $info = [ordered]@{}
        foreach ($prop in @($r.Info.PSObject.Properties)) { $info[$prop.Name] = $prop.Value }
        $script:RuntimeOnlineInfo = $info
        try { $script:RuntimeOnlineCheckedAt = [datetime]$r.CheckedAt } catch { $script:RuntimeOnlineCheckedAt = Get-Date }
        if ([bool]$r.Success) { $script:RuntimeStatusMessage = 'Microsoft 官方源后台联网对比完成' }
        else { $script:RuntimeStatusMessage = '后台联网对比部分失败：' + (@($r.Errors) -join ' | ') }
        return [PSCustomObject]@{Success=[bool]$r.Success;Info=$info;Errors=@($r.Errors)}
    } catch {
        return [PSCustomObject]@{Success=$false;Info=$null;Errors=@("读取后台联网结果失败：$($_.Exception.Message)")}
    }
}

function Start-RuntimeOnlineProbeAsync([switch]$Force,[string]$Reason='手动') {
    $r=Update-RuntimeOnlineInfo -Force:$Force
    LogUI $script:RuntimeStatusMessage -Force
    return [bool]$r.Success
}

function Test-RuntimeOnlineInfoFresh([int]$Minutes=30) {
    if (-not $script:RuntimeOnlineInfo) { return $false }
    return (((Get-Date) - $script:RuntimeOnlineCheckedAt).TotalMinutes -le $Minutes)
}

function Wait-ProcessResponsive([System.Diagnostics.Process]$Process,[int]$SleepMs=180) {
    if(-not $Process){return 99999}
    try{
        while(-not $Process.HasExited){
            try{[System.Windows.Forms.Application]::DoEvents()}catch{}
            Start-Sleep -Milliseconds $SleepMs
            try{$Process.Refresh()}catch{}
        }
        return [int]$Process.ExitCode
    }catch{return 99999}
}

function Invoke-TrustedMicrosoftDownloadResponsive([string]$Url,[string]$Destination) {
    $worker=Join-Path $WorkRoot 'TrustedSingleDownloadWorker.ps1';$result=Join-Path $RuntimeCacheRoot ('TrustedDownload_'+[guid]::NewGuid().ToString('N')+'.json')
    $scriptText=@'
param([string]$Url,[string]$Destination,[string]$ResultPath,[string]$EnginePath)
$ErrorActionPreference='Stop';. $EnginePath -LibraryMode
$r=Invoke-OfficialMicrosoftDownload $Url $Destination 0;$tmp=$ResultPath+'.tmp';$r|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $ResultPath -Force;exit $(if($r.Success){0}else{2})
'@
    try{$scriptText|Set-Content -LiteralPath $worker -Encoding UTF8}catch{return [PSCustomObject]@{Success=$false;TrustComplete=$false;Error='无法生成可信下载 worker'}}
    $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe';$args="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$worker`" -Url `"$Url`" -Destination `"$Destination`" -ResultPath `"$result`" -EnginePath `"$PSCommandPath`""
    try{$proc=Start-Process -FilePath $ps -ArgumentList $args -PassThru -WindowStyle Hidden -ErrorAction Stop;[void](Wait-ProcessResponsive $proc 140);if(-not (Test-Path -LiteralPath $result)){return [PSCustomObject]@{Success=$false;TrustComplete=$false;Error='可信下载 worker 未返回结果'}};return (Get-Content -LiteralPath $result -Raw|ConvertFrom-Json)}catch{return [PSCustomObject]@{Success=$false;TrustComplete=$false;Error=$_.Exception.Message}}finally{Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue}
}

function Get-WingetPath {
    try {
        $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return [string]$cmd.Source }
    } catch {}
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\WindowsApps\winget.exe')
    )
    foreach ($p in $cands) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return ''
}

function Convert-RuntimeRepairExit([int]$Code) {
    if ($Code -in 0,1638,-1978335189,-1978334964,-1978335212) { return [PSCustomObject]@{Success=$true;Reboot=$false} }
    if ($Code -in 3010,1641) { return [PSCustomObject]@{Success=$true;Reboot=$true} }
    return [PSCustomObject]@{Success=$false;Reboot=$false}
}

function Get-LocalVCRedistInstaller([string]$Arch) {
    $label = switch ($Arch) { 'x86' { 'x86' } 'arm64' { 'ARM64' } default { 'x64' } }
    $hits = @()
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            $hits += Get-ItemProperty $root -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -match '(?i)Microsoft Visual C\+\+ 2015-\d+ Redistributable' -and
                    $_.DisplayName -match [regex]::Escape('(' + $label + ')')
                }
        } catch {}
    }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($h in @($hits)) {
        foreach ($prop in @('ModifyPath','BundleCachePath','UninstallString','InstallLocation')) {
            $raw = [string]$h.$prop
            if (-not $raw) { continue }
            $m = [regex]::Match($raw, '(?i)"([^"]*VC_redist[^"]*\.exe)"')
            if (-not $m.Success) { $m = [regex]::Match($raw, '(?i)([A-Za-z]:\\[^\s"]*VC_redist[^\s"]*\.exe)') }
            if ($m.Success) { [void]$paths.Add($m.Groups[1].Value) }
        }
    }
    $cache = Join-Path $env:ProgramData 'Package Cache'
    if (Test-Path -LiteralPath $cache) {
        try {
            Get-ChildItem -LiteralPath $cache -Filter ("VC_redist.$Arch.exe") -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 8 |
                ForEach-Object { [void]$paths.Add($_.FullName) }
        } catch {}
    }
    $appCache = Join-Path $RuntimeCacheRoot ("vc_redist_$Arch.exe")
    if (Test-Path -LiteralPath $appCache) { [void]$paths.Add($appCache) }
    foreach ($p in @($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $sig = Test-MicrosoftSignedFile $p
        if ($sig.Valid) { return [PSCustomObject]@{Success=$true;Path=$p;Source='Local';Version=[string]$sig.Version} }
    }
    return [PSCustomObject]@{Success=$false;Path='';Source='';Version=''}
}

function Invoke-SignedRedistExe([string]$Path,[string]$Args,[string]$OkText,[string]$FailText) {
    $sig = Test-MicrosoftSignedFile $Path
    if (-not $sig.Valid) { return [PSCustomObject]@{Success=$false;Reboot=$false;Message=$FailText} }
    try {
        $p = Start-Process -FilePath $Path -ArgumentList $Args -PassThru -WindowStyle Hidden
        $code = Wait-ProcessResponsive $p
        $st = Convert-RuntimeRepairExit $code
        return [PSCustomObject]@{Success=[bool]$st.Success;Reboot=[bool]$st.Reboot;Message=$(if($st.Success){$OkText}else{$FailText})}
    } catch {
        return [PSCustomObject]@{Success=$false;Reboot=$false;Message=$FailText}
    }
}

function Invoke-VCRedistWinget([string]$Arch) {
    $ids = @{ x64='Microsoft.VCRedist.2015+.x64'; x86='Microsoft.VCRedist.2015+.x86'; arm64='Microsoft.VCRedist.2015+.arm64' }
    if (-not $ids.ContainsKey($Arch)) { return [PSCustomObject]@{Success=$false;Reboot=$false;Message='C++ 运行库不支持此架构。'} }
    $wg = Get-WingetPath
    if (-not $wg) { return [PSCustomObject]@{Success=$false;Reboot=$false;Message='本机没有系统安装器，改用其他方式。'} }
    try {
        $p = Start-Process -FilePath $wg -ArgumentList @('install','--id',$ids[$Arch],'-e','--accept-package-agreements','--accept-source-agreements','--disable-interactivity','--silent') -PassThru -WindowStyle Hidden
        $code = Wait-ProcessResponsive $p
        $st = Convert-RuntimeRepairExit $code
        $okText = 'C++ 运行库已更新。'
        $failText = '系统安装器没能装上 C++ 运行库。'
        return [PSCustomObject]@{Success=[bool]$st.Success;Reboot=[bool]$st.Reboot;Message=$(if($st.Success){$okText}else{$failText})}
    } catch {
        return [PSCustomObject]@{Success=$false;Reboot=$false;Message='系统安装器启动失败。'}
    }
}

function Test-VCRuntimeRepaired([string]$Arch,[string]$Target,[bool]$NeedUpdate) {
    $st = Get-VCRuntimeLocalState $Arch
    if (-not $st.Healthy) { return $false }
    if ($NeedUpdate -and $Target) {
        if ((Compare-VersionSafe $st.EffectiveVersion $Target) -lt 0) { return $false }
    }
    return $true
}

function Invoke-VCRedistRepair([string]$Arch,[object]$Row) {
    $archName = @{ x64='64位'; x86='32位'; arm64='ARM' }
    $label = 'C++ 运行库（' + $(if ($archName.ContainsKey($Arch)) { $archName[$Arch] } else { $Arch }) + '）'
    $okText = $label + '已修好。'
    $failText = $label + '没法自动修好。'
    $upgrade = ($Row -and $Row.Status -in @('UPDATE','WARN'))
    $target = [string](Get-OfficialVC14Target $Arch).Version
    $tryNext = $true

    $local = Get-LocalVCRedistInstaller $Arch
    if ($local.Success) {
        $useLocal = $true
        if ($upgrade -and $target) {
            $localVer = Normalize-VersionText ([string]$local.Version)
            if (-not $localVer) {
                try { $localVer = Normalize-VersionText ([string](Test-MicrosoftSignedFile ([string]$local.Path)).Version) } catch {}
            }
            if ($localVer -and (Compare-VersionSafe $localVer $target) -lt 0) { $useLocal = $false }
        }
        if ($useLocal) {
            $args = if ($upgrade) { '/install /quiet /norestart' } elseif ($Row -and $Row.Installed) { '/repair /quiet /norestart' } else { '/install /quiet /norestart' }
            $r = Invoke-SignedRedistExe ([string]$local.Path) $args $okText $failText
            if ($r.Success -and (Test-VCRuntimeRepaired $Arch $target $upgrade)) { return $r }
            if ($r.Success) { $tryNext = $true } else { $tryNext = $true }
        }
    }
    $wg = Invoke-VCRedistWinget $Arch
    if ($wg.Success -and (Test-VCRuntimeRepaired $Arch $target $upgrade)) { $wg.Message = $okText; return $wg }
    $online = $null
    try { $online = Get-VCRedistOnlinePackage $Arch -Force } catch { $online = $null }
    if ($online -and $online.Success -and [string]$online.Path) {
        $r = Invoke-SignedRedistExe ([string]$online.Path) '/install /quiet /norestart' $okText $failText
        if ($r.Success -and (Test-VCRuntimeRepaired $Arch $target $upgrade)) { return $r }
        if ($r.Success) { return $r }
    }
    if (Test-VCRuntimeRepaired $Arch $target $false) {
        return [PSCustomObject]@{Success=$true;Reboot=$false;Message=$okText}
    }
    return [PSCustomObject]@{Success=$false;Reboot=$false;Message=$failText}
}

function Get-LocalDirectXLegacyInstaller {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($n in @('dxwebsetup.exe','directx_Jun2010_redist.exe','DXSETUP.exe')) {
        $p = Join-Path $RuntimeCacheRoot $n
        if (Test-Path -LiteralPath $p) { [void]$paths.Add($p) }
    }
    foreach ($root in @(
        (Join-Path $env:ProgramData 'Package Cache'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft DirectX SDK (June 2010)'),
        (Join-Path ${env:ProgramFiles(x86)} 'DirectX'),
        (Join-Path $env:ProgramFiles 'DirectX')
    )) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        try {
            Get-ChildItem -LiteralPath $root -Filter 'DXSETUP.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Select-Object -First 4 |
                ForEach-Object { [void]$paths.Add($_.FullName) }
            Get-ChildItem -LiteralPath $root -Filter 'dxwebsetup.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Select-Object -First 2 |
                ForEach-Object { [void]$paths.Add($_.FullName) }
        } catch {}
    }
    foreach ($p in @($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $sig = Test-MicrosoftSignedFile $p
        if ($sig.Valid) { return [PSCustomObject]@{Success=$true;Path=$p;Name=([IO.Path]::GetFileName($p))} }
    }
    return [PSCustomObject]@{Success=$false;Path='';Name=''}
}

function Invoke-DirectXLegacyRepair {
    $okText = '老游戏兼容组件已装好。'
    $failText = '老游戏兼容组件没法自动装上。'
    $local = Get-LocalDirectXLegacyInstaller
    if ($local.Success) {
        $name = [string]$local.Name
        if ($name -match '(?i)DXSETUP') {
            $r = Invoke-SignedRedistExe ([string]$local.Path) '/silent' $okText $failText
            if ($r.Success) { return $r }
        } elseif ($name -match '(?i)dxwebsetup') {
            $r = Invoke-SignedRedistExe ([string]$local.Path) '/Q' $okText $failText
            if ($r.Success) { return $r }
        } elseif ($name -match '(?i)directx_Jun2010') {
            $extract = Join-Path $RuntimeCacheRoot 'DirectX_June2010_Extracted'
            try {
                Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Force -Path $extract | Out-Null
                $x = Start-Process -FilePath ([string]$local.Path) -ArgumentList "/Q /T:`"$extract`"" -PassThru -WindowStyle Hidden
                $xCode = Wait-ProcessResponsive $x
                if ($xCode -eq 0) {
                    $dxsetup = Join-Path $extract 'DXSETUP.exe'
                    if (Test-Path -LiteralPath $dxsetup) {
                        $r = Invoke-SignedRedistExe $dxsetup '/silent' $okText $failText
                        if ($r.Success) { return $r }
                    }
                }
            } catch {}
        }
    }
    $online = $null
    try { $online = Get-DirectXWebInstaller -Force } catch { $online = $null }
    if ($online -and $online.Success -and [string]$online.Path) {
        $r = Invoke-SignedRedistExe ([string]$online.Path) '/Q' $okText $failText
        if ($r.Success) { return $r }
    }
    $offline = $null
    try { $offline = Get-DirectXOfflineInstaller -Force } catch { $offline = $null }
    if ($offline -and $offline.Success -and [string]$offline.Path) {
        $extract = Join-Path $RuntimeCacheRoot 'DirectX_June2010_Extracted'
        try {
            Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $extract | Out-Null
            $x = Start-Process -FilePath ([string]$offline.Path) -ArgumentList "/Q /T:`"$extract`"" -PassThru -WindowStyle Hidden
            $xCode = Wait-ProcessResponsive $x
            if ($xCode -eq 0) {
                $dxsetup = Join-Path $extract 'DXSETUP.exe'
                if (Test-Path -LiteralPath $dxsetup) {
                    $r = Invoke-SignedRedistExe $dxsetup '/silent' $okText $failText
                    if ($r.Success) { return $r }
                }
            }
        } catch {}
    }
    return [PSCustomObject]@{Success=$false;Reboot=$false;Message=$failText}
}


function Invoke-DirectXCoreRepair {
    $messages=@();$ok=$true;$reboot=$false;$needRepair=$true
    try{
        $cmd=Get-Command Repair-WindowsImage -ErrorAction SilentlyContinue
        if($cmd){
            $check=Repair-WindowsImage -Online -CheckHealth -NoRestart -ErrorAction Stop
            $state=[string]$check.ImageHealthState;$messages += "CheckHealth=$state"
            if($state -match '(?i)Healthy'){$needRepair=$false}
            elseif($state -match '(?i)NonRepairable'){$ok=$false;$messages+='组件存储报告 NonRepairable；停止自动 RestoreHealth'}
            if($needRepair -and $ok){
                $scan=Repair-WindowsImage -Online -ScanHealth -NoRestart -ErrorAction Stop;$scanState=[string]$scan.ImageHealthState;$messages += "ScanHealth=$scanState"
                if($scanState -match '(?i)Healthy'){$needRepair=$false}
                elseif($scanState -match '(?i)NonRepairable'){$ok=$false;$messages+='ScanHealth=NonRepairable；停止自动修复'}
            }
            if($needRepair -and $ok){$rest=Repair-WindowsImage -Online -RestoreHealth -NoRestart -ErrorAction Stop;$messages += ("RestoreHealth="+[string]$rest.ImageHealthState)}
        } else {$messages+='Repair-WindowsImage cmdlet 不可用，回退 DISM RestoreHealth'}
    }catch{$messages += ('DISM PowerShell 分级检查失败='+$_.Exception.Message);$needRepair=$true}
    if($needRepair -and $ok -and -not (Get-Command Repair-WindowsImage -ErrorAction SilentlyContinue)){
        try{$dism=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\dism.exe') -ArgumentList '/Online /Cleanup-Image /RestoreHealth /NoRestart' -PassThru;$dismCode=Wait-ProcessResponsive $dism;$messages += "DISM=$dismCode";if($dismCode -notin 0,3010){$ok=$false};if($dismCode -eq 3010){$reboot=$true}}catch{$ok=$false;$messages += "DISM启动失败=$($_.Exception.Message)"}
    }
    # SFC runs only when DirectX Core was actually judged unhealthy and servicing was attempted.
    if($needRepair -and $ok){try{$sfc=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\sfc.exe') -ArgumentList '/scannow' -PassThru;$sfcCode=Wait-ProcessResponsive $sfc;$messages += "SFC=$sfcCode";if($sfcCode -notin 0,1,2){$ok=$false}}catch{$ok=$false;$messages += "SFC启动失败=$($_.Exception.Message)"}}
    if(-not $needRepair){$messages += '组件存储健康；未执行 RestoreHealth/SFC'}
    $msg = if($ok){'游戏 DirectX 已用系统修复处理。'}else{'游戏 DirectX 没法自动修好。'}
    return [PSCustomObject]@{Success=$ok;Reboot=$reboot;Message=$msg}
}

function Invoke-RuntimeAutoRepair {
    $rows = @(Get-RuntimeDiagnosticRows)
    $todo = @($rows | Where-Object { $_.Status -in @('REPAIR','UPDATE','WARN') })
    if ($todo.Count -eq 0) {
        return [PSCustomObject]@{Success=$true;Reboot=$false;Messages=@('C++ 运行库和 DirectX 都正常，不必修复。')}
    }
    $messages = @()
    $success = $true
    $reboot = $false
    foreach ($r in $todo) {
        if ($r.Key -match '^VC_(?<a>x86|x64|arm64)$') {
            $x = Invoke-VCRedistRepair $matches['a'] $r
            $messages += $x.Message
            if (-not $x.Success) { $success = $false }
            if ($x.Reboot) { $reboot = $true }
        } elseif ($r.Key -eq 'DirectXLegacy') {
            $x = Invoke-DirectXLegacyRepair
            $messages += $x.Message
            if (-not $x.Success) { $success = $false }
            if ($x.Reboot) { $reboot = $true }
        } elseif ($r.Key -eq 'DirectXCore' -and $r.Status -eq 'REPAIR') {
            $x = Invoke-DirectXCoreRepair
            $messages += $x.Message
            if (-not $x.Success) { $success = $false }
            if ($x.Reboot) { $reboot = $true }
        }
    }
    if ($success) {
        try { (Get-Date).ToString('o') | Set-Content -LiteralPath $RuntimeRepairStampPath -Encoding ASCII } catch {}
    }
    $script:SnapshotCacheTime = [datetime]::MinValue
    $post = @(Get-RuntimeDiagnosticRows)
    $remaining = @($post | Where-Object { $_.Status -in @('REPAIR','UPDATE') })
    if ($remaining.Count -gt 0) {
        $success = $false
        $messages += '修完后再看，还有项目不完整。'
    } else {
        $messages += '修完后再看：C++ 运行库和 DirectX 都可以用。'
    }
    return [PSCustomObject]@{Success=$success;Reboot=$reboot;Messages=$messages}
}

function Get-RuntimeRepairEligibility([object]$Snap) {
    $pre=Get-EnvironmentPreflight 'Runtime' '';$reasons=@();$warnings=@();foreach($x in @($pre.Rows)){if($x.Blocking){$reasons += "$($x.Name): $($x.Detail)"}elseif($x.Status -eq 'WARN'){$warnings += "$($x.Name): $($x.Detail)"}}
    $todo=@($Snap.Rows|Where-Object{$_.Group -eq 'RUNTIME' -and $_.Status -in @('REPAIR','UPDATE','WARN')})
    $stateInfo=Resolve-EligibilityState $todo.Count 0 $pre @($reasons)
    if($stateInfo.State -eq 'NO_ACTION_REQUIRED'){$reasons=@()}
    $eligible=($stateInfo.State -eq 'ELIGIBLE' -and $reasons.Count -eq 0)
    $broken=@($todo|Where-Object{$_.Status -eq 'REPAIR'}).Count
    $update=@($todo|Where-Object{$_.Status -eq 'UPDATE'}).Count
    $decision=if($broken -gt 0){'运行库不完整，可以自动修复。'}elseif($update -gt 0){'和官方版本不一样，可以更新到官方版本。'}elseif($todo.Count -gt 0){'运行库版本偏低。这次没连上官方源，仍可更新。'}else{'运行库已和官方一致，或本机可用，不必修复。'}
    return [PSCustomObject]@{State=$stateInfo.State;Eligible=$eligible;Decision=$decision;EnvironmentStates=@($stateInfo.EnvironmentStates);Reasons=$reasons;Warnings=$warnings;Preflight=$pre;TargetRows=$todo}
}


function Initialize-DirectXSmokeType {
    if($script:NativeSmokeLoaded){return $true}
    $cs=@'
using System;
using System.Runtime.InteropServices;
public static class GameRuntimeNativeSmoke {
    [DllImport("dxgi.dll", ExactSpelling=true)] static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr ppFactory);
    [DllImport("d3d11.dll", ExactSpelling=true)] static extern int D3D11CreateDevice(IntPtr pAdapter, int DriverType, IntPtr Software, uint Flags, IntPtr pFeatureLevels, uint FeatureLevels, uint SDKVersion, out IntPtr ppDevice, out int pFeatureLevel, out IntPtr ppImmediateContext);
    [DllImport("d3d12.dll", ExactSpelling=true)] static extern int D3D12CreateDevice(IntPtr pAdapter, int MinimumFeatureLevel, ref Guid riid, out IntPtr ppDevice);
    static int Missing(){return unchecked((int)0x8007007E);} 
    public static int TestDXGI(){IntPtr p=IntPtr.Zero;try{Guid g=new Guid("770aae78-f26f-4dba-a829-253c83d1b387");int h=CreateDXGIFactory1(ref g,out p);if(p!=IntPtr.Zero)Marshal.Release(p);return h;}catch{return Missing();}}
    public static int TestD3D11(int driverType){IntPtr d=IntPtr.Zero;IntPtr c=IntPtr.Zero;int fl=0;try{int h=D3D11CreateDevice(IntPtr.Zero,driverType,IntPtr.Zero,0,IntPtr.Zero,0,7,out d,out fl,out c);if(c!=IntPtr.Zero)Marshal.Release(c);if(d!=IntPtr.Zero)Marshal.Release(d);return h;}catch{return Missing();}}
    public static int TestD3D12(){IntPtr d=IntPtr.Zero;try{Guid g=new Guid("189819f1-1db6-4b57-be54-1821339b85f7");int h=D3D12CreateDevice(IntPtr.Zero,0xb000,ref g,out d);if(d!=IntPtr.Zero)Marshal.Release(d);return h;}catch{return Missing();}}
}
'@
    try{Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction Stop|Out-Null;$script:NativeSmokeLoaded=$true;return $true}catch{return $false}
}

function Format-HResult([int]$Hr){try{$u=[BitConverter]::ToUInt32([BitConverter]::GetBytes($Hr),0);return ('0x{0:X8}' -f $u)}catch{return [string]$Hr}}
function Test-HResultOK([int]$Hr){return ($Hr -ge 0)}

function Invoke-DirectXAPISmokeTest {
    if(-not (Initialize-DirectXSmokeType)){return [PSCustomObject]@{Category='DirectX API';Test='Native API create-device';Status='FAIL';Detail='无法编译/加载 DirectX PInvoke 测试类型'}}
    $dxgi=[GameRuntimeNativeSmoke]::TestDXGI();$hw=[GameRuntimeNativeSmoke]::TestD3D11(1);$warp=[GameRuntimeNativeSmoke]::TestD3D11(5);$d12=[GameRuntimeNativeSmoke]::TestD3D12()
    $status='PASS'
    if(-not (Test-HResultOK $dxgi) -or ((-not (Test-HResultOK $hw)) -and (-not (Test-HResultOK $warp)))){$status='FAIL'}
    elseif(-not (Test-HResultOK $hw) -or -not (Test-HResultOK $d12)){$status='WARN'}
    $detail="DXGI=$(Format-HResult $dxgi); D3D11-HW=$(Format-HResult $hw); D3D11-WARP=$(Format-HResult $warp); D3D12=$(Format-HResult $d12)"
    if($status -eq 'WARN' -and (Test-HResultOK $warp) -and -not (Test-HResultOK $hw)){$detail+='；WARP 可用但硬件 D3D11 创建失败，优先检查显卡驱动/设备'}
    if($status -eq 'WARN' -and -not (Test-HResultOK $d12)){$detail+='；D3D12 设备创建失败可能是 GPU/驱动能力，不等同于 DirectX 系统文件损坏'}
    return [PSCustomObject]@{Category='DirectX API';Test='DXGI/D3D11/D3D12 真实创建设备';Status=$status;Detail=$detail}
}

function Write-VCRuntimeSmokeWorker {
    $p=Join-Path $WorkRoot 'VCRuntimeSmokeWorker.ps1'
    $w=@'
param([string]$Arch,[string]$OutPath)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;public static class L{[DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern IntPtr LoadLibraryW(string p);[DllImport("kernel32.dll",CharSet=CharSet.Ansi,SetLastError=true)]public static extern IntPtr GetProcAddress(IntPtr h,string n);[DllImport("kernel32.dll")]public static extern bool FreeLibrary(IntPtr h);}
"@
$root=Join-Path $env:WINDIR $(if($Arch -eq 'x86' -and [Environment]::Is64BitOperatingSystem){'SysWOW64'}else{'System32'})
$names=@('vcruntime140.dll','msvcp140.dll','msvcp140_1.dll');if($Arch -ne 'x86'){$names+='vcruntime140_1.dll'}
$rows=@();$ok=$true
foreach($n in $names){$path=Join-Path $root $n;$h=[IntPtr]::Zero;$err=0;if(Test-Path -LiteralPath $path){$h=[L]::LoadLibraryW($path);if($h -eq [IntPtr]::Zero){$err=[Runtime.InteropServices.Marshal]::GetLastWin32Error();$ok=$false}else{$probe=$true;if($n -ieq 'vcruntime140.dll'){$gp=[L]::GetProcAddress($h,'memcpy');if($gp -eq [IntPtr]::Zero){$probe=$false;$ok=$false;$err=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}};[void][L]::FreeLibrary($h)}}else{$ok=$false;$err=2};$rows+=[pscustomobject]@{File=$path;Loaded=($h -ne [IntPtr]::Zero);Win32Error=$err}}
[pscustomobject]@{Arch=$Arch;Success=$ok;Rows=$rows}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $OutPath -Encoding UTF8
exit $(if($ok){0}else{2})
'@
    try{$w|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}
}

function Invoke-VCRuntimeLoadSmokeTest([string]$Arch) {
    if($Arch -eq 'arm64'){return [PSCustomObject]@{Category='VC++ Load';Test='arm64 DLL Loader';Status='INFO';Detail='当前版本暂不在 x64 进程内执行原生 ARM64 Loader 测试；仍执行注册表/签名检查'}}
    $worker=Write-VCRuntimeSmokeWorker;if(-not $worker){return [PSCustomObject]@{Category='VC++ Load';Test="$Arch DLL Loader";Status='FAIL';Detail='无法生成 Loader 测试脚本'}}
    $out=Join-Path $DeepTestRoot ("vc_load_${Arch}_"+(Get-Date -Format 'yyyyMMddHHmmss')+'.json')
    $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if($Arch -eq 'x86' -and [Environment]::Is64BitOperatingSystem){$ps=Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'}
    try{
        $args="-NoProfile -ExecutionPolicy Bypass -File `"$worker`" -Arch $Arch -OutPath `"$out`""
        $p=Start-Process -FilePath $ps -ArgumentList $args -PassThru -WindowStyle Hidden
        $pCode=Wait-ProcessResponsive $p
        if(-not (Test-Path -LiteralPath $out)){throw "worker exit=$pCode no result"}
        $r=Get-Content -LiteralPath $out -Raw|ConvertFrom-Json
        $detail=@($r.Rows|ForEach-Object{"$([IO.Path]::GetFileName($_.File))=$(if($_.Loaded){'Loaded'}else{"FAIL:$($_.Win32Error)"})"}) -join '; '
        return [PSCustomObject]@{Category='VC++ Load';Test="$Arch 真实 DLL Loader";Status=$(if($r.Success){'PASS'}else{'FAIL'});Detail=$detail}
    }catch{return [PSCustomObject]@{Category='VC++ Load';Test="$Arch 真实 DLL Loader";Status='FAIL';Detail=$_.Exception.Message}}
}

function Invoke-GameRuntimeDeepTest {
    $rows=@()
    foreach($a in @(Get-RequiredVCRedistArchitectures)){$rows += Invoke-VCRuntimeLoadSmokeTest $a}
    $rows += Invoke-DirectXAPISmokeTest
    try{
        $display=@(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue)
        if($display.Count -eq 0){$rows += [PSCustomObject]@{Category='GPU';Test='Display PnP';Status='WARN';Detail='未读取到 Display 设备'}}
        else{foreach($d in $display){$rows += [PSCustomObject]@{Category='GPU';Test=[string]$d.FriendlyName;Status=$(if($d.Status -eq 'OK'){'PASS'}else{'WARN'});Detail=("PnP Status="+[string]$d.Status)}}}
    }catch{$rows += [PSCustomObject]@{Category='GPU';Test='Display PnP';Status='WARN';Detail='无法读取 PnP 显卡状态'}}
    $obj=[PSCustomObject]@{SchemaVersion=2;Version=$AppVersion;BuildId=$BuildId;EngineSHA256=$script:EngineSHA256;CheckedAt=(Get-Date).ToString('o');Rows=$rows}
    try{$obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $DeepTestLastPath -Encoding UTF8}catch{}
    return $rows
}

function Invoke-RuntimeRepairHeadless {
    if(-not (Get-AdminState)){throw 'Elevated broker required'}
    $script:SnapshotCacheTime=[datetime]::MinValue
    try { [void](Update-RuntimeOnlineInfo -Force) } catch {}
    $snap=Get-SystemSnapshot -Force
    $elig=Get-RuntimeRepairEligibility $snap
    if(-not $elig.Eligible){throw ('现在不能自动修运行库：'+(@($elig.Reasons)-join '；'))}
    $plan=New-RepairPlan 'RUNTIME' '' $snap
    if(-not $plan.Eligible){throw ('现在不能自动修运行库：'+(@($plan.BlockingReasons)-join '；'))}
    $tx=New-RepairTransaction $plan $snap
    Set-TransactionState $tx 'RepairStarted' '开始修复运行库'
    $script:RepairExecutionActive=$true
    try{$r=Invoke-RuntimeAutoRepair}finally{$script:RepairExecutionActive=$false}
    $detail=(@($r.Messages)|ForEach-Object{ConvertTo-CustomerSentence ([string]$_)} | Where-Object {$_}) -join ' '
    if(-not $detail){$detail=if($r.Success){'运行库已修好。'}else{'运行库没有完全修好。'}}
    if($r.Success){Set-TransactionState $tx 'SuccessPendingVerification' $detail}else{Set-TransactionState $tx 'NeedsAttention' $detail}
    return [PSCustomObject]@{Success=[bool]$r.Success;TransactionId=$tx.TransactionId;State=$tx.State;Detail=$detail}
}

