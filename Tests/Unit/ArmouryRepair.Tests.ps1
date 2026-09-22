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
        Mock Start-Process { throw ([System.ComponentModel.Win32Exception]::new(1150)) }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\ArmouryCrate.exe') -SkipProcessCheck
        $result.Attempts | Should -Be 3
        $result.Success | Should -Be $false
        $result.AlreadyRunning | Should -Be $false
        $result.Path | Should -Be 'C:\fake\ArmouryCrate.exe'
        $result.ErrorCode | Should -Be 1150
        $result.Error | Should -Not -BeNullOrEmpty
        @($result.ErrorHistory).Count | Should -Be 3
        $result.ErrorHistory[2].ErrorCode | Should -Be 1150
        $result.ErrorHistory[2].Attempt | Should -Be 3
    }
    It 'records mixed Win32 codes in order and keeps the last ErrorCode' {
        $script:codes = @(5, 1150, 2)
        $script:i = 0
        Mock Start-Process {
            $code = $script:codes[$script:i]
            $script:i++
            throw ([System.ComponentModel.Win32Exception]::new($code))
        }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\ArmouryCrate.exe') -SkipProcessCheck
        $result.Success | Should -Be $false
        $result.Attempts | Should -Be 3
        $result.ErrorCode | Should -Be 2
        @($result.ErrorHistory).Count | Should -Be 3
        $result.ErrorHistory[0].Attempt | Should -Be 1
        $result.ErrorHistory[0].ErrorCode | Should -Be 5
        $result.ErrorHistory[1].Attempt | Should -Be 2
        $result.ErrorHistory[1].ErrorCode | Should -Be 1150
        $result.ErrorHistory[2].Attempt | Should -Be 3
        $result.ErrorHistory[2].ErrorCode | Should -Be 2
        $result.ErrorHistory[0].Path | Should -Be 'C:\fake\ArmouryCrate.exe'
        $result.ErrorHistory[0].Error | Should -Not -BeNullOrEmpty
    }
    It 'records HResult when the exception is not Win32Exception' {
        Mock Start-Process { throw (New-Object System.InvalidOperationException 'boom') }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\ArmouryCrate.exe') -SkipProcessCheck
        $result.Success | Should -Be $false
        $result.Attempts | Should -Be 3
        @($result.ErrorHistory).Count | Should -Be 3
        $result.ErrorCode | Should -Be ([int][System.InvalidOperationException]::new('boom').HResult)
        $result.ErrorHistory[0].ErrorCode | Should -Be $result.ErrorCode
        $result.Error | Should -Match 'boom'
    }
    It 'rotates executables across retries' {
        Mock Start-Process {
            throw ([System.ComponentModel.Win32Exception]::new(2))
        }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\first.exe','C:\fake\second.exe') -SkipProcessCheck
        $result.Success | Should -Be $false
        $result.Attempts | Should -Be 3
        @($result.ErrorHistory).Count | Should -Be 3
        $result.ErrorHistory[0].Path | Should -Be 'C:\fake\first.exe'
        $result.ErrorHistory[1].Path | Should -Be 'C:\fake\second.exe'
        $result.ErrorHistory[2].Path | Should -Be 'C:\fake\first.exe'
        $result.Path | Should -Be 'C:\fake\first.exe'
        $result.ErrorCode | Should -Be 2
    }
    It 'stops after the second attempt succeeds' {
        $script:count = 0
        Mock Start-Process {
            $script:count++
            if ($script:count -lt 2) { throw ([System.ComponentModel.Win32Exception]::new(5)) }
        }
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @('C:\fake\ArmouryCrate.exe') -SkipProcessCheck
        $result.Attempts | Should -Be 2
        $result.Success | Should -Be $true
        @($result.ErrorHistory).Count | Should -Be 1
        $result.ErrorHistory[0].ErrorCode | Should -Be 5
        $result.ErrorCode | Should -Be $null
    }
    It 'records missing executable without retrying' {
        $result = Invoke-WgrArmouryLaunchAttempt -MaxRetries 3 -DelaySeconds 0 -Executables @() -SkipProcessCheck
        $result.Success | Should -Be $false
        $result.Attempts | Should -Be 0
        $result.ErrorCode | Should -Be $null
        $result.Error | Should -Match '没有找到'
        @($result.ErrorHistory).Count | Should -Be 0
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
