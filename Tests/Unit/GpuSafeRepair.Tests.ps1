#requires -version 5.1
BeforeAll {
    $backend = Join-Path $PSScriptRoot '..\..\WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\GpuSafeRepair.ps1'
    . $backend
}

Describe 'Test-WgrGpuCachePath' {
    It 'allows DirectX shader cache under LocalAppData' {
        $path = Join-Path $env:LOCALAPPDATA 'D3DSCache\blob'
        Test-WgrGpuCachePath $path | Should -Be $true
    }
    It 'denies Windows system directories' {
        Test-WgrGpuCachePath 'C:\Windows\System32\drivers' | Should -Be $false
    }
}

Describe 'Get-WgrGpuVendors' {
    It 'identifies NVIDIA from PNP id' {
        Mock Get-CimInstance {
            @([pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4090'; PNPDeviceID = 'PCI\VEN_10DE&DEV_0000' })
        }
        @(Get-WgrGpuVendors) | Should -Contain 'NVIDIA'
    }
    It 'identifies AMD from PNP id' {
        Mock Get-CimInstance {
            @([pscustomobject]@{ Name = 'AMD Radeon RX 7900 XTX'; PNPDeviceID = 'PCI\VEN_1002&DEV_0000' })
        }
        @(Get-WgrGpuVendors) | Should -Contain 'AMD'
    }
    It 'returns a collection without throwing' {
        { Get-WgrGpuVendors } | Should -Not -Throw
    }
}
