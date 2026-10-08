Describe 'NetworkRepair test suite' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src\Common.ps1')
        . (Join-Path $root 'src\NetworkListManager.ps1')
        . (Join-Path $root 'src\NetworkIdentity.ps1')
        . (Join-Path $root 'src\Ncsi.ps1')
        . (Join-Path $root 'src\Diagnostics.ps1')
        . (Join-Path $root 'src\Backup.ps1')
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

    It 'compares registry snapshots canonically across ordering and registry-name casing' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_test_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $a=Join-Path $dir 'a.reg';$b=Join-Path $dir 'b.reg'
            @('Windows Registry Editor Version 5.00','[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles]','"Name"="Office"','"Blob"=hex:01,02,\','03,04') | Set-Content -LiteralPath $a -Encoding UTF8
            @('Windows Registry Editor Version 5.00','[hkey_local_machine\software\microsoft\windows nt\currentversion\networklist\profiles]','"blob"=hex:01,02,\','03,04','"NAME"="Office"') | Set-Content -LiteralPath $b -Encoding UTF8
            $r=Compare-NRRegSnapshotFiles -ExpectedPath $a -ActualPath $b
            $r.Match | Should -BeTrue
            $r.ExpectedHash | Should -Be $r.ActualHash
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'detects registry snapshot data differences' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_test_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $a=Join-Path $dir 'a.reg';$b=Join-Path $dir 'b.reg'
            @('[HKEY_LOCAL_MACHINE\SOFTWARE\NetworkRepair]','"Name"="Office"') | Set-Content -LiteralPath $a -Encoding UTF8
            @('[HKEY_LOCAL_MACHINE\SOFTWARE\NetworkRepair]','"Name"="Home"') | Set-Content -LiteralPath $b -Encoding UTF8
            $r=Compare-NRRegSnapshotFiles -ExpectedPath $a -ActualPath $b
            $r.Match | Should -BeFalse
            $r.Differences.Count | Should -BeGreaterThan 0
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'rejects invalid network names' {
        (Test-NRNetworkName -Name ('a' * 129)).Valid | Should -BeFalse
        (Test-NRNetworkName -Name 'bad/name').Valid | Should -BeFalse
        (Test-NRNetworkName -Name '   ').Valid | Should -BeFalse
        (Test-NRNetworkName -Name 'Office').Valid | Should -BeTrue
    }
}
