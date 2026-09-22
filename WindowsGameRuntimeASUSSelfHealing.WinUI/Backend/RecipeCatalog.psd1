@{
    SchemaVersion = 1
    Policy = @{
        UnknownAsusVersionBehavior = 'DIAGNOSE_ONLY'
        AutomaticDDU = $false
        BlindDriverRemoval = $false
        RequireBrokerReEligibility = $true
        RequireLegacyAdapterHashLock = $true
    }
    Recipes = @{
        PV = @{
            RecipeId = 'ASUS.PV.4151.v1'
            Kind = 'LEGACY_ADAPTER'
            Group = 'PV'
            ExpectedErrorCode = '4151'
            AdapterFile = 'ASUS_4151_TargetedFix.ps1'
            AdapterSHA256 = 'bff8e7ded470438834f00eeb5efb4cae3312c8e6b919052a9a6161bb8a5f6a04'
            UnknownVersionBehavior = 'DIAGNOSE_ONLY'
        }
        HOLTEK = @{
            RecipeId = 'ASUS.HOLTEK.4151.v1'
            Kind = 'LEGACY_ADAPTER'
            Group = 'HOLTEK'
            ExpectedErrorCode = '4151'
            AdapterFile = 'ASUS_CoreHAL_4151_Fix.ps1'
            AdapterSHA256 = '9217d88ee0632d3c36cc96e6c8edcaf5f156ab555da521511705f91dab6d2674'
            UnknownVersionBehavior = 'DIAGNOSE_ONLY'
        }
        ENE = @{
            RecipeId = 'ASUS.ENE.4152.v1'
            Kind = 'LEGACY_ADAPTER'
            Group = 'ENE'
            ExpectedErrorCode = '4152'
            AdapterFile = 'ASUS_ENE_M2_4152_Fix.ps1'
            AdapterSHA256 = 'b90eb3aba023d1fc73116b3400f7b4e66a4b2ead73799f9365096a4b3a5e9637'
            UnknownVersionBehavior = 'DIAGNOSE_ONLY'
        }
        RUNTIME = @{
            RecipeId = 'MICROSOFT.RUNTIME.REPAIR.v1'
            Kind = 'ENGINE_NATIVE'
            Group = 'RUNTIME'
            UnknownVersionBehavior = 'TRUSTED_MICROSOFT_PACKAGE_ONLY'
        }
        GPU_SAFE = @{
            RecipeId = 'WINDOWS.GPU.SAFE_REPAIR.v1'
            Kind = 'SAFE_OS_REMEDIATION'
            Group = 'GPU_SAFE'
            UnknownVersionBehavior = 'SAFE_OS_ONLY'
        }
        ASUS_CRATE = @{
            RecipeId = 'ASUS.CRATE.LAUNCH_501.v1'
            Kind = 'SAFE_OS_REMEDIATION'
            Group = 'ASUS_CRATE'
            UnknownVersionBehavior = 'SAFE_OS_ONLY'
        }
    }
}
