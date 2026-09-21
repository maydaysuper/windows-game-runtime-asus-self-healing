#requires -version 5.1
param(
    [Parameter(Mandatory=$true)][string]$RequestPath,
    [Parameter(Mandatory=$true)][string]$EnginePath
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $EnginePath
$BuildInfoPath=Join-Path $Root 'BuildInfo.psd1'
if(-not(Test-Path -LiteralPath $BuildInfoPath)){throw 'BuildInfo.psd1 missing'}
$Build=Import-PowerShellDataFile -LiteralPath $BuildInfoPath

function Is-Admin {
    try {
        $id=[Security.Principal.WindowsIdentity]::GetCurrent()
        $p=New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
function Hash([string]$p){try{return (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}catch{return ''}}
function Write-Response([object]$Req,[bool]$Success,[string]$Detail,[object]$Data=$null){
    try {
        $o=[PSCustomObject]@{
            SchemaVersion=2
            RequestId=[string]$Req.RequestId
            Action=[string]$Req.Action
            Success=$Success
            Detail=$Detail
            CompletedAt=(Get-Date).ToString('o')
            EngineVersion=[string]$Build.Version
            BuildId=[string]$Build.BuildId
            BrokerSHA256=(Hash $PSCommandPath)
            Data=$Data
        }
        $tmp=[string]$Req.ResponsePath+'.tmp'
        $o|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination ([string]$Req.ResponsePath) -Force
    } catch {}
}

$req=$null
try {
    if(-not(Is-Admin)){throw 'Broker is not elevated'}
    if(-not(Test-Path -LiteralPath $RequestPath)){throw 'Request file missing'}
    if(-not(Test-Path -LiteralPath $EnginePath)){throw 'Engine file missing'}
    if((Hash $PSCommandPath) -ne [string]$Build.BrokerSHA256){throw 'Broker SHA256 does not match BuildInfo'}
    if((Hash $EnginePath) -ne [string]$Build.EngineSHA256){throw 'Engine SHA256 does not match BuildInfo'}

    $atomicPolicyPath=Join-Path $Root 'AtomicPolicyExecutor.ps1'
    if(-not(Test-Path -LiteralPath $atomicPolicyPath)){throw 'AtomicPolicyExecutor.ps1 missing'}
    if((Hash $atomicPolicyPath) -ne [string]$Build.AtomicPolicyExecutorSHA256){throw 'AtomicPolicyExecutor SHA256 does not match BuildInfo'}
    . $atomicPolicyPath
    $recipeCatalog=Import-WgrRecipeCatalog $Root $Build

    $req=Get-Content -LiteralPath $RequestPath -Raw|ConvertFrom-Json
    if([int]$req.SchemaVersion -ne 2){throw 'Unsupported request schema'}
    if([string]$req.EngineVersion -ne [string]$Build.Version -or [string]$req.BuildId -ne [string]$Build.BuildId){throw 'Broker request BuildInfo mismatch'}
    if([string]$req.EngineSHA256 -ne [string]$Build.EngineSHA256){throw 'Broker request Engine SHA256 mismatch'}
    $created=[datetime]$req.CreatedAt
    if(((Get-Date)-$created).TotalMinutes -gt 15){throw 'Stale broker request (>15 minutes)'}

    $allowed=@('ASUS_REPAIR','RUNTIME_REPAIR','CONTINUE','WER_ENABLE','WER_DISABLE','GPU_SAFE_REPAIR')
    if($allowed -notcontains [string]$req.Action){throw 'Action is not broker allow-listed'}

    # Validate the structured recipe envelope before loading the large engine. This is an
    # additional gate; RepairCenter still re-runs full Eligibility and exact identity checks.
    if([string]$req.Action -eq 'ASUS_REPAIR'){
        if([string]$req.Group -notin @('PV','HOLTEK','ENE')){throw 'Invalid ASUS repair group'}
        [void](Assert-WgrRecipeEnvelope $recipeCatalog ([string]$req.Group) $Build)
    } elseif([string]$req.Action -eq 'RUNTIME_REPAIR') {
        [void](Assert-WgrRecipeEnvelope $recipeCatalog 'RUNTIME' $Build)
    } elseif([string]$req.Action -eq 'GPU_SAFE_REPAIR') {
        [void](Assert-WgrRecipeEnvelope $recipeCatalog 'GPU_SAFE' $Build)
        $gpuRepairPath=Join-Path $Root 'GpuSafeRepair.ps1'
        if(-not(Test-Path -LiteralPath $gpuRepairPath)){throw 'GpuSafeRepair.ps1 missing'}
        if((Hash $gpuRepairPath) -ne [string]$Build.GpuSafeRepairSHA256){throw 'GpuSafeRepair SHA256 does not match BuildInfo'}
        . $gpuRepairPath
    }

    . $EnginePath -LibraryMode
    if($AppVersion -ne [string]$Build.Version -or $BuildId -ne [string]$Build.BuildId){throw 'Engine runtime BuildInfo mismatch after load'}

    $result=$null
    switch([string]$req.Action){
        'ASUS_REPAIR' {$result=Invoke-ASUSRepairHeadless ([string]$req.Group)}
        'RUNTIME_REPAIR' {$result=Invoke-RuntimeRepairHeadless}
        'CONTINUE' {$result=Invoke-ContinuePendingRepairHeadless}
        'WER_ENABLE' {$d=Set-WerLocalDumpConfiguration ([string]$req.ExeName) $true;$result=[PSCustomObject]@{Success=$true;Detail=$d;State='COMPLETED'}}
        'WER_DISABLE' {$d=Set-WerLocalDumpConfiguration ([string]$req.ExeName) $false;$result=[PSCustomObject]@{Success=$true;Detail=$d;State='COMPLETED'}}
        'GPU_SAFE_REPAIR' {$result=Invoke-WgrGpuSafeRepair}
    }

    $ok=$true
    $detail='Completed'
    if($result){
        if($null -ne $result.Success){$ok=[bool]$result.Success}
        if($result.Detail){$detail=[string]$result.Detail}
    }
    Write-Response $req $ok $detail $result
    if($ok){exit 0}else{exit 2}
}
catch {
    $msg=$_.Exception.Message
    if($req){Write-Response $req $false $msg $null}
    exit 1
}
