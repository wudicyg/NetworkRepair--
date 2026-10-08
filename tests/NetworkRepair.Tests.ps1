Describe 'NetworkRepair test suite' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src\Common.ps1')
        . (Join-Path $root 'src\NetworkListManager.ps1')
        . (Join-Path $root 'src\NetworkIdentity.ps1')
        . (Join-Path $root 'src\RepairPlan.ps1')
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

    It 'exposes NCSI configuration reader' {
        (Get-Command Get-NRNcsiConfiguration -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'exposes Network List Manager diagnostic reader' {
        (Get-Command Get-NRNetworkListManagerNetworks -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'normalizes GUID values consistently' {
        (Normalize-NRGuidKey -Value '{12345678-1234-1234-1234-123456789ABC}') | Should -Be '12345678-1234-1234-1234-123456789abc'
    }

    It 'correlates an exact registry Profile key with a NetworkId' {
        $profile=[pscustomobject]@{KeyName='{12345678-1234-1234-1234-123456789ABC}';ProfileName='Network 2'}
        $network=[pscustomobject]@{NetworkId='12345678-1234-1234-1234-123456789abc';Name='Office';IsConnected=$false;IsConnectedToInternet=$false;ConnectionCount=1}
        $r=@(Get-NRNetworkIdentityCorrelation -RegistryProfiles @($profile) -NlmNetworks @($network))[0]
        $r.Correlation | Should -Be 'ExactNetworkId'
        $r.NetworkName | Should -Be 'Office'
    }

    It 'uses exact NetworkId correlation to protect a connected numbered profile' {
        $p=[pscustomobject]@{KeyName='{12345678-1234-1234-1234-123456789ABC}';ProfileName='Network 2';Category=0;Managed=0;RegistryPath='HKLM:\dummy';LastWrite=(Get-Date)}
        $i=[pscustomobject]@{ProfileKeyName=$p.KeyName;NetworkId='12345678-1234-1234-1234-123456789abc';NetworkName='Office';NlmIsConnected=$true;Correlation='ExactNetworkId'}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @() -IdentityCorrelations @($i))[0]
        $r.NetworkId | Should -Be '12345678-1234-1234-1234-123456789abc'
        $r.NetworkCorrelation | Should -Be 'ExactNetworkId'
        $r.IsActive | Should -BeTrue
        $r.RemediationAllowed | Should -BeFalse
        $r.DiagnosticCodes | Should -Contain 'NR1002'
    }

    It 'builds a delete plan only from remediation-allowed candidates' {
        $safe=[pscustomobject]@{KeyName='safe';ProfileName='Network 2';RemediationAllowed=$true;RiskLevel='Low';RiskScore=30;Reason='inactive';}
        $blocked=[pscustomobject]@{KeyName='blocked';ProfileName='Network 3';RemediationAllowed=$false;RiskLevel='High';RiskScore=90;Reason='active';}
        $plan=Get-NRRepairPlan -Candidates @($safe,$blocked)
        $plan.DeleteProfileCount | Should -Be 1
        $plan.IsNoOp | Should -BeFalse
        @($plan.Actions | Where-Object Action -eq 'DeleteProfile').Count | Should -Be 1
        $plan.SkippedCandidates.Count | Should -Be 1
    }

    It 'creates a Deep Repair refresh action even without deletable profiles' {
        $blocked=[pscustomobject]@{KeyName='blocked';ProfileName='Network 3';RemediationAllowed=$false;RiskLevel='High';RiskScore=90;Reason='active';}
        $plan=Get-NRRepairPlan -Candidates @($blocked) -Deep
        $plan.DeleteProfileCount | Should -Be 0
        $plan.ClearNewNetworksRequested | Should -BeTrue
        $plan.IsNoOp | Should -BeFalse
        @($plan.Actions | Where-Object Action -eq 'ClearNewNetworks').Count | Should -Be 1
    }

    It 'rejects invalid network names' {
        (Test-NRNetworkName -Name ('a' * 129)).Valid | Should -BeFalse
        (Test-NRNetworkName -Name 'bad/name').Valid | Should -BeFalse
        (Test-NRNetworkName -Name '   ').Valid | Should -BeFalse
        (Test-NRNetworkName -Name 'Office').Valid | Should -BeTrue
    }
}
