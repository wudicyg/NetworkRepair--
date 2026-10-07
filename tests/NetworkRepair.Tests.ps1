Describe 'NetworkRepair safety rules' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src\Common.ps1')
        . (Join-Path $root 'src\NetworkListManager.ps1')
        . (Join-Path $root 'src\Ncsi.ps1')
        . (Join-Path $root 'src\Diagnostics.ps1')
    }
    It 'marks an inactive numbered Chinese profile as Low risk and removable' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 3';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @());$r[0].Risk|Should -Be 'Low';$r[0].IsActive|Should -BeFalse
    }
    It 'marks an active numbered profile as High risk' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 3';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        @(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @('网络 3'))[0].Risk|Should -Be 'High'
    }
    It 'supports English Network N naming' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='Network 4';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        @(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0].Risk|Should -Be 'Low'
    }
    It 'does not flag base names' {
        $p1=[pscustomobject]@{KeyName='x';ProfileName='Network';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $p2=[pscustomobject]@{KeyName='y';ProfileName='网络';Category=0;Managed=0;RegistryPath='HKLM:\dummy2';LastWrite=(Get-Date)}
        @(@(Get-NRSuspiciousProfiles -RegistryProfiles @($p1,$p2) -ActiveNames @())|Where-Object Risk -eq 'Low').Count|Should -Be 0
    }
    It 'does not flag managed profiles as safe' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 5';Category=0;Managed=1;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        @(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0].Risk|Should -Be 'High'
    }
}

    It 'marks an active numbered profile as High and protected' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 3';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @('网络 3'))[0]
        $r.RiskLevel | Should -Be 'High'
        $r.RemediationAllowed | Should -BeFalse
        $r.DiagnosticCodes | Should -Contain 'NR1002'
    }

    It 'supports English Network N naming' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='Network 4';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        @(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0].RemediationAllowed | Should -BeTrue
    }

    It 'never permits managed profiles to be auto-remediated' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 5';Category=0;Managed=1;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0]
        $r.RemediationAllowed | Should -BeFalse
        $r.RiskLevel | Should -Be 'High'
        $r.DiagnosticCodes | Should -Contain 'NR1003'
    }
