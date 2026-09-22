#requires -version 5.1
# Pester 5 tests for Armoury Crate 501 / launch repair.
BeforeAll {
    $backend = Join-Path $PSScriptRoot '..\..\WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\ArmouryCrateSafeRepair.ps1'
    . $backend
}

Describe 'Test-WgrArmouryTempPath' {
    It 'allows installer leftovers under TEMP' {
        $path = Join-Path $env:TEMP 'ArmouryCrateInstaller'
        Test-WgrArmouryTempPath $path | Should -Be $true
    }
    It 'denies System32' {
        Test-WgrArmouryTempPath 'C:\Windows\System32\ArmourySetup' | Should -Be $false
    }
    It 'denies DriverStore' {
        Test-WgrArmouryTempPath 'C:\Windows\System32\DriverStore\Armoury' | Should -Be $false
    }
}

Describe 'Invoke-WgrArmouryLaunchAttempt' {
    It 'retries until MaxRetries when Start-Process always fails' {
        Mock Start-Process { throw 'AppX activation failed' }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\ArmouryCrate.exe') -SkipProcessCheck
        $result.Attempts | Should -Be 3
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Not -Be $null
    }
    It 'stops after the second attempt succeeds' {
        $script:count = 0
        Mock Start-Process {
            $script:count++
            if ($script:count -lt 2) { throw 'fail' }
        }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\ArmouryCrate.exe') -SkipProcessCheck
        $result.Attempts | Should -Be 2
        $result.Success | Should -Be $true
    }
}

Describe 'Get-WgrArmouryServiceNames' {
    It 'includes the three core Armoury services' {
        $names = @(Get-WgrArmouryServiceNames)
        $names | Should -Contain 'ArmouryCrateService'
        $names | Should -Contain 'ROG Live Service'
        $names | Should -Contain 'LightingService'
    }
}
