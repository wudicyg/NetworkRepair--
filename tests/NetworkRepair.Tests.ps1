Describe 'NetworkRepair safety rules' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src\Common.ps1')
        . (Join-Path $root 'src\NetworkListManager.ps1')
        . (Join-Path $root 'src\Ncsi.ps1')
        . (Join-Path $root 'src\Diagnostics.ps1')
    }

    It 'marks an inactive Chinese numbered profile as Low and removable' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 3';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0]
        $r.RiskLevel | Should -Be 'Low'
        $r.RemediationAllowed | Should -BeTrue
        $r.DiagnosticCodes | Should -Contain 'NR1001'
    }

    It 'protects an active numbered profile' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 3';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @('网络 3'))[0]
        $r.RiskLevel | Should -Be 'High'
        $r.RemediationAllowed | Should -BeFalse
        $r.DiagnosticCodes | Should -Contain 'NR1002'
    }

    It 'supports English numbered profile names' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='Network 4';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0]
        $r.RiskLevel | Should -Be 'Low'
        $r.RemediationAllowed | Should -BeTrue
    }

    It 'does not flag base profile names' {
        $p1=[pscustomobject]@{KeyName='x';ProfileName='Network';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $p2=[pscustomobject]@{KeyName='y';ProfileName='网络';Category=0;Managed=0;RegistryPath='HKLM:\dummy2';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p1,$p2) -ActiveNames @())
        @($r | Where-Object RemediationAllowed).Count | Should -Be 0
    }

    It 'never permits managed profiles to be auto-remediated' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 5';Category=0;Managed=1;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0]
        $r.RiskLevel | Should -Be 'High'
        $r.RemediationAllowed | Should -BeFalse
        $r.DiagnosticCodes | Should -Contain 'NR1003'
    }
}

Describe 'NetworkRepair v0.2.0 helper behavior' {
    It 'exposes NCSI configuration reader' {
        (Get-Command Get-NRNcsiConfiguration -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'exposes Network List Manager diagnostic reader' {
        (Get-Command Get-NRNetworkListManagerNetworks -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
