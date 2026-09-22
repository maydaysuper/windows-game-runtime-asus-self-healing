#requires -version 5.1
BeforeAll {
    $backend = Join-Path $PSScriptRoot '..\..\WindowsGameRuntimeASUSSelfHealing.WinUI\Backend\RuntimeEngine.ps1'
    . $backend
}

Describe 'Compare-VersionSafe' {
    It 'treats equal four-part versions as 0' {
        Compare-VersionSafe '14.44.35211.0' '14.44.35211.0' | Should -Be 0
    }
    It 'pads shorter versions' {
        Compare-VersionSafe '14.44.35211' '14.44.35211.0' | Should -Be 0
    }
    It 'orders newer Microsoft VC++ above older' {
        (Compare-VersionSafe '14.44.35211.0' '14.40.33810.0') -gt 0 | Should -Be $true
    }
    It 'strips a leading v' {
        Compare-VersionSafe 'v14.44.35211.0' '14.44.35211.0' | Should -Be 0
    }
}

Describe 'Normalize-VersionText' {
    It 'extracts dotted versions from extra text' {
        Normalize-VersionText 'Microsoft Visual C++ 14.44.35211.0' | Should -Be '14.44.35211.0'
    }
}
