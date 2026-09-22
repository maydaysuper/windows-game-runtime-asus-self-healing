#requires -version 5.1
BeforeAll {
    $backend = Join-Path $PSScriptRoot '..\..\WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\AtomicPolicyExecutor.ps1'
    . $backend
}

Describe 'Test-WgrAtomicPolicyPath' {
    It 'allows a path under an allowed root' {
        $root = Join-Path $env:TEMP 'WgrPolicyRoot'
        $child = Join-Path $root 'nested\file.txt'
        Test-WgrAtomicPolicyPath $child @($root) | Should -Be $true
    }
    It 'denies a path outside allowed roots' {
        Test-WgrAtomicPolicyPath 'C:\Windows\System32\cmd.exe' @((Join-Path $env:TEMP 'WgrPolicyRoot')) | Should -Be $false
    }
}
