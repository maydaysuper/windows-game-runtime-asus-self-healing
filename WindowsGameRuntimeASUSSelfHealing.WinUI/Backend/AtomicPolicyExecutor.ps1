#requires -version 5.1
<#
Structured recipe / atomic policy envelope.

This does NOT replace or rewrite the hash-locked ASUS legacy adapters. It is the migration
boundary around them: Broker validates an engine-pinned Recipe before a legacy adapter can be
entered. New repair steps should be added as explicit atomic operations here instead of adding
ad-hoc destructive PowerShell to the WinUI layer.
#>

function Get-WgrSha256([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path)){return ''}
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Import-WgrRecipeCatalog([string]$Root,[hashtable]$Build) {
    $path=Join-Path $Root 'RecipeCatalog.psd1'
    if(-not(Test-Path -LiteralPath $path)){throw 'RecipeCatalog.psd1 missing'}
    $actual=Get-WgrSha256 $path
    if($actual -ne [string]$Build.RecipeCatalogSHA256){throw 'RecipeCatalog SHA256 mismatch vs BuildInfo'}
    $catalog=Import-PowerShellDataFile -LiteralPath $path
    if(-not $catalog -or [int]$catalog.SchemaVersion -ne 1){throw 'Unsupported RecipeCatalog schema'}
    if([string]$catalog.Policy.UnknownAsusVersionBehavior -ne 'DIAGNOSE_ONLY'){throw 'Recipe policy must keep unknown ASUS versions diagnose-only'}
    if([bool]$catalog.Policy.AutomaticDDU){throw 'Recipe policy cannot enable automatic DDU'}
    if([bool]$catalog.Policy.BlindDriverRemoval){throw 'Recipe policy cannot enable blind driver removal'}
    return $catalog
}

function Get-WgrRecipe([hashtable]$Catalog,[string]$Group) {
    if(-not $Catalog -or -not $Catalog.Recipes){throw 'Recipe catalog unavailable'}
    $recipe=$Catalog.Recipes[$Group]
    if(-not $recipe){throw "No structured recipe for group: $Group"}
    return $recipe
}

function Assert-WgrRecipeEnvelope([hashtable]$Catalog,[string]$Group,[hashtable]$Build) {
    $recipe=Get-WgrRecipe $Catalog $Group
    if([string]$recipe.Group -ne $Group){throw 'Recipe group mismatch'}
    if([string]$recipe.UnknownVersionBehavior -notin @('DIAGNOSE_ONLY','TRUSTED_MICROSOFT_PACKAGE_ONLY','SAFE_OS_ONLY')){throw 'Unsafe unknown-version recipe behavior'}

    if([string]$recipe.Kind -eq 'LEGACY_ADAPTER'){
        if($Group -notin @('PV','HOLTEK','ENE')){throw 'Legacy adapter recipe group is not allow-listed'}
        if(-not $Build.LegacyAdapterHashes -or -not $Build.LegacyAdapterHashes.ContainsKey($Group)){throw 'BuildInfo legacy adapter lock missing'}
        $expected=([string]$Build.LegacyAdapterHashes[$Group]).ToLowerInvariant()
        if(([string]$recipe.AdapterSHA256).ToLowerInvariant() -ne $expected){throw 'Recipe adapter SHA256 differs from immutable BuildInfo lock'}
        if([string]$recipe.UnknownVersionBehavior -ne 'DIAGNOSE_ONLY'){throw 'Legacy ASUS recipe must remain diagnose-only for unknown versions'}
    }
    return $recipe
}

function Test-WgrAtomicPolicyPath([string]$Path,[string[]]$AllowedRoots) {
    if(-not $Path){return $false}
    try{$full=[IO.Path]::GetFullPath($Path).TrimEnd('\')+'\'}catch{return $false}
    foreach($rootText in @($AllowedRoots)){
        if(-not $rootText){continue}
        try{$root=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($rootText)).TrimEnd('\')+'\'}catch{continue}
        if($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){return $true}
    }
    return $false
}

function Invoke-WgrAtomicPolicyOperation([hashtable]$Policy,[string]$Operation,[hashtable]$Arguments) {
    if(-not $Policy){throw 'Atomic policy is required'}
    switch($Operation){
        'CreateDirectory' {
            $path=[string]$Arguments.Path
            if(-not(Test-WgrAtomicPolicyPath $path @($Policy.AllowedWriteRoots))){throw "Policy denied CreateDirectory: $path"}
            New-Item -ItemType Directory -Force -Path $path|Out-Null
            return
        }
        'CopyFile' {
            $destination=[string]$Arguments.Destination
            if(-not(Test-WgrAtomicPolicyPath $destination @($Policy.AllowedWriteRoots))){throw "Policy denied CopyFile destination: $destination"}
            Copy-Item -LiteralPath ([string]$Arguments.Source) -Destination $destination -Force -ErrorAction Stop
            return
        }
        'StopService' {
            $name=[string]$Arguments.Name
            if(@($Policy.AllowedServices) -notcontains $name){throw "Policy denied StopService: $name"}
            Stop-Service -Name $name -Force -ErrorAction Stop
            return
        }
        'StartService' {
            $name=[string]$Arguments.Name
            if(@($Policy.AllowedServices) -notcontains $name){throw "Policy denied StartService: $name"}
            Start-Service -Name $name -ErrorAction Stop
            return
        }
        default { throw "Unsupported atomic policy operation: $Operation" }
    }
}
