Describe 'NetworkRepair test suite' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'src\Common.ps1')
        . (Join-Path $root 'src\NetworkListManager.ps1')
        . (Join-Path $root 'src\NetworkIdentity.ps1')
        . (Join-Path $root 'src\RepairPlan.ps1')
        . (Join-Path $root 'src\Ncsi.ps1')
        . (Join-Path $root 'src\Diagnostics.ps1')
        . (Join-Path $root 'src\Backup.ps1')
        . (Join-Path $root 'src\RestorePoints.ps1')
        . (Join-Path $root 'src\Services.ps1')
        . (Join-Path $root 'src\Gui.ps1')

        function New-TestRestorePoint {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Timestamp,
                [string]$Level = 'Manual',
                [switch]$Pinned,
                [switch]$SkipScopedFiles,
                [string]$ManifestContent
            )
            $path = Join-Path $Root $Name
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            @('x') | Set-Content -LiteralPath (Join-Path $path 'NetworkList.reg') -Encoding UTF8
            if (-not $SkipScopedFiles) {
                @('x') | Set-Content -LiteralPath (Join-Path $path 'NetworkList-Profiles.reg') -Encoding UTF8
            }
            $manifestPath = Join-Path $path 'manifest.json'
            if ($ManifestContent) {
                $ManifestContent | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            } elseif ($Level) {
                [pscustomobject]@{ App='NetworkRepair'; Version='1.0.0'; Level=$Level; Pinned=[bool]$Pinned; Timestamp=$Timestamp } |
                    ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            } else {
                [pscustomobject]@{ App='NetworkRepair'; Version='0.4.0'; Timestamp=$Timestamp } |
                    ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            }
            $path
        }
    }

    It 'returns null for missing optional registry properties' {
        $p=[pscustomobject]@{ProfileName='Network 9'}
        (Get-NRPropertyValue -InputObject $p -Name 'Managed') | Should -BeNullOrEmpty
        (Get-NRPropertyValue -InputObject $p -Name 'Category') | Should -BeNullOrEmpty
        (Get-NRPropertyValue -InputObject $p -Name 'Description') | Should -BeNullOrEmpty
        (Get-NRPropertyValue -InputObject $p -Name 'ProfileName') | Should -Be 'Network 9'
    }

    It 'forwards SkipConnectivityTest through interactive menu actions' {
        $entryPath = Join-Path $root 'NetworkRepair.ps1'
        $content = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
        $content | Should -Match 'Invoke-NRScan -SkipConnectivityTest:\$SkipConnectivityTest'
        $content | Should -Match 'Invoke-NRRepair -Deep:\$false -AssumeYes:\$Yes -SkipConnectivityTest:\$SkipConnectivityTest'
        $content | Should -Match 'Invoke-NRRepair -Deep:\$true -AssumeYes:\$Yes -SkipConnectivityTest:\$SkipConnectivityTest'
        $content | Should -Match 'Export-NRReport -SkipConnectivityTest:\$SkipConnectivityTest'
        $content | Should -Not -Match '\bDryRun\b'
        $content | Should -Not -Match 'Invoke-NRRepair -Deep:\$false -DryRun'
        $content | Should -Match ([regex]::Escape("Write-NRLine '  [7] 安全重命名网络（显式指定名称）' 'White'"))
        $content | Should -Not -Match ([regex]::Escape("Write-NRLine '  [8]"))
    }
    It 'shows the read-only quick status in the interactive menu' {
        $entryPath = Join-Path $root 'NetworkRepair.ps1'
        $content = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
        $content | Should -Match 'Show-NRQuickStatus'
        $content | Should -Match ([regex]::Escape('Skipped = $true'))
        $content | Should -Match '快速状态：网络='
        $content | Should -Match '跳过 NCSI 主动探测'
    }
    It 'keeps read-only validation evidence version synchronized with the entry script' {
        $toolPath = Join-Path $root 'tools\Invoke-NRReadOnlyValidation.ps1'
        $content = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
        $content | Should -Match 'entryVersionMatch'
        $content | Should -Match ([regex]::Escape("Groups[1].Value"))
        $content | Should -Not -Match ([regex]::Escape('$Script:AppVersion = ''0.4.0-dev'''))
    }

    It 'keeps diagnostic degradation warnings visible in the human-readable report' {
        $entryPath = Join-Path $root 'src\Diagnostics.ps1'
        $content = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
        $content | Should -Match "Write-NRSection '诊断降级提示'"
        $content | Should -Match '\[DEGRADED\]'
        $content | Should -Match 'DiagnosticsErrors'
    }
    It 'accepts registry profile input without LastWriteTime metadata' {
        $p=[pscustomobject]@{KeyName='x';ProfileName='网络 9';Category=0;Managed=0;RegistryPath='HKLM:\\dummy'}
        $r=@(Get-NRSuspiciousProfiles -RegistryProfiles @($p) -ActiveNames @())[0]
        $r.RiskLevel | Should -Be 'Low'
        $r.RemediationAllowed | Should -BeTrue
        $r.LastWrite | Should -BeNullOrEmpty
    }

    It 'handles interfaces without an IPv4Address property' {
        Mock -CommandName Get-NetIPConfiguration -MockWith {
            [pscustomobject]@{
                InterfaceIndex = 99
                InterfaceAlias = 'TestVirtual'
                IPv6Address = @()
                IPv4DefaultGateway = $null
            }
        }
        Mock -CommandName Get-NetIPInterface -MockWith {
            [pscustomobject]@{ Dhcp = 'Disabled' }
        }
        Mock -CommandName Get-DnsClientServerAddress -MockWith {
            [pscustomobject]@{ ServerAddresses = @() }
        }
        $r=@(Get-NRIPDiagnostics)
        $r.Count | Should -Be 1
        $r[0].InterfaceAlias | Should -Be 'TestVirtual'
        $r[0].IPv4Addresses.Count | Should -Be 0
        $r[0].IPv6Addresses.Count | Should -Be 0
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

    It 'keeps sanitized bundle version synchronized with the entry script' {
        $toolPath = Join-Path $root 'tools\Export-NRSanitizedDiagnosticBundle.ps1'
        $entryPath = Join-Path $root 'NetworkRepair.ps1'
        $tool = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
        $entry = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
        $tool | Should -Match 'entryVersionMatch'
        $tool | Should -Match 'entryVersionMatch.Groups\[1\]\.Value'
        $tool | Should -Not -Match "'0.4.0-dev'"
        $entry | Should -Match '\$Script:AppVersion'
    }

    It 'keeps sanitized bundle numbered profile regexes intact' {
        $toolPath = Join-Path $root 'tools\Export-NRSanitizedDiagnosticBundle.ps1'
        $content = Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
        $content | Should -Match "\^网络\\s\+\\d\+\$"
        $content | Should -Match "\^Network\\s\+\\d\+\$"
        $content | Should -Match "\^\(网络\|Network\)\\s\+\\d\+\$"
        $content | Should -Not -Match "网络s\+d\+"
        $content | Should -Not -Match "Networks\+d\+"
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

    It 'backs up scoped NetworkList keys for safe restore' {
        $path = Join-Path $root 'src\Backup.ps1'
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $content | Should -Match 'NetworkList-Profiles\.reg'
        $content | Should -Match 'NetworkList-NewNetworks\.reg'
        $content | Should -Match 'ProfilesBackup'
        $content | Should -Match 'NewNetworksBackup'
    }

    It 'keeps Restore scoped to Profiles and NewNetworks' {
        $path = Join-Path $root 'src\Backup.ps1'
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $content | Should -Match 'function Resolve-NRScopedBackupFile\s*\{'
        $content | Should -Match 'function Test-NRRegistryScopeSnapshotMatch\s*\{'
        $content | Should -Not -Match ([regex]::Escape('& reg.exe import $reg'))
        $content | Should -Match 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\NetworkList\\Profiles'
        $content | Should -Match 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\NetworkList\\NewNetworks'
    }

    It 'defines only one scoped restore rollback implementation' {
        $path = Join-Path $root 'src\\Backup.ps1'
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        ([regex]::Matches($content, 'function Invoke-NRRestoreSafetyRollback\s*\{')).Count | Should -Be 1
        $content | Should -Not -Match ([regex]::Escape('& reg.exe import $SafetyBackup.RegistryBackup'))
        $content | Should -Match ([regex]::Escape('& reg.exe import $file'))
    }

    It 'resolves scoped restore files from a backup directory or NetworkList.reg path' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_scope_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $full=Join-Path $dir 'NetworkList.reg'
            $profiles=Join-Path $dir 'NetworkList-Profiles.reg'
            $newNetworks=Join-Path $dir 'NetworkList-NewNetworks.reg'
            @('full') | Set-Content -LiteralPath $full -Encoding UTF8
            @('profiles') | Set-Content -LiteralPath $profiles -Encoding UTF8
            @('new-networks') | Set-Content -LiteralPath $newNetworks -Encoding UTF8

            Resolve-NRScopedBackupFile -BackupPath $dir -ScopeName 'Profiles' | Should -Be $profiles
            Resolve-NRScopedBackupFile -BackupPath $dir -ScopeName 'NewNetworks' | Should -Be $newNetworks
            Resolve-NRScopedBackupFile -BackupPath $full -ScopeName 'Profiles' | Should -Be $profiles
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'rejects legacy full-tree backups that lack scoped restore files' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_legacy_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            @('full') | Set-Content -LiteralPath (Join-Path $dir 'NetworkList.reg') -Encoding UTF8
            Resolve-NRScopedBackupFile -BackupPath $dir -ScopeName 'Profiles' | Should -BeNullOrEmpty
            Resolve-NRScopedBackupFile -BackupPath $dir -ScopeName 'NewNetworks' | Should -BeNullOrEmpty
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'treats NewNetworks as optional when the scoped backup file is absent' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_optional_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            @('full') | Set-Content -LiteralPath (Join-Path $dir 'NetworkList.reg') -Encoding UTF8
            @('profiles') | Set-Content -LiteralPath (Join-Path $dir 'NetworkList-Profiles.reg') -Encoding UTF8
            Resolve-NRScopedBackupFile -BackupPath $dir -ScopeName 'Profiles' | Should -Not -BeNullOrEmpty
            Resolve-NRScopedBackupFile -BackupPath $dir -ScopeName 'NewNetworks' | Should -BeNullOrEmpty
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
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


    It 'reports healthy network independently from historical profile hygiene' {
        $connections=@([pscustomobject]@{IPv4Connectivity='Internet';IPv6Connectivity='Internet'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$true;Http=$true}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $h.Status | Should -Be 'Healthy'

        $candidate=[pscustomobject]@{KeyName='x';ProfileName='Network 7';RemediationAllowed=$true;RiskLevel='Low';RiskScore=30;Reason='inactive'}
        $diagnostics=[pscustomobject]@{
            Candidates=@($candidate)
            NetworkHealth=$h
        }
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics
        $decision.NetworkHealth.Status | Should -Be 'Healthy'
        $decision.ProfileHygieneStatus | Should -Be 'HistoricalProfilesFound'
        $decision.Recommendation | Should -Be 'CleanHistoricalProfiles'
        $decision.Plan.DeleteProfileCount | Should -Be 1
    }

    It 'keeps cleaning historical numbered profiles on a healthy network' {
        $connections=@([pscustomobject]@{IPv4Connectivity='Internet';IPv6Connectivity='Internet'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$true;Http=$true}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $candidates=@(
            [pscustomobject]@{KeyName='a';ProfileName='网络 2';RemediationAllowed=$true;RiskLevel='Low';RiskScore=30;Reason='inactive'}
            [pscustomobject]@{KeyName='b';ProfileName='网络 3';RemediationAllowed=$true;RiskLevel='Low';RiskScore=30;Reason='inactive'}
            [pscustomobject]@{KeyName='c';ProfileName='Network 4';RemediationAllowed=$true;RiskLevel='Low';RiskScore=30;Reason='inactive'}
        )
        $diagnostics=[pscustomobject]@{Candidates=$candidates;NetworkHealth=$h}
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics
        $decision.NetworkHealth.OperationallyHealthy | Should -BeTrue
        $decision.ProfileHygieneStatus | Should -Be 'HistoricalProfilesFound'
        $decision.HistoricalProfileCount | Should -Be 3
        $decision.Recommendation | Should -Be 'CleanHistoricalProfiles'
        $decision.Plan.DeleteProfileCount | Should -Be 3
        @($decision.Plan.Actions | Where-Object Action -eq 'DeleteProfile').Count | Should -Be 3
    }

    It 'reports healthy network with no cleanup need as no action' {
        $connections=@([pscustomobject]@{IPv4Connectivity='Internet';IPv6Connectivity='Internet'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$true;Http=$true}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $diagnostics=[pscustomobject]@{Candidates=@();NetworkHealth=$h}
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics
        $decision.NetworkHealth.Status | Should -Be 'Healthy'
        $decision.ProfileHygieneStatus | Should -Be 'Clean'
        $decision.Recommendation | Should -Be 'NoAction'
        $decision.Plan.IsNoOp | Should -BeTrue
    }

    It 'blocks Deep Repair when the network is healthy and no safe cleanup exists' {
        $connections=@([pscustomobject]@{IPv4Connectivity='Internet';IPv6Connectivity='Internet'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$true;Http=$true}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $candidate=[pscustomobject]@{KeyName='x';ProfileName='Network 8';RemediationAllowed=$false;IsActive=$true;RiskLevel='High';RiskScore=90;Reason='active'}
        $diagnostics=[pscustomobject]@{Candidates=@($candidate);NetworkHealth=$h}
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics -Deep
        $decision.Recommendation | Should -Be 'NoAction'
        $decision.Plan.IsNoOp | Should -BeTrue
        $decision.Plan.DeleteProfileCount | Should -Be 0
        $decision.Plan.ClearNewNetworksRequested | Should -BeFalse
    }

    It 'does not classify a healthy numbered active profile as safe cleanup' {
        $connections=@([pscustomobject]@{IPv4Connectivity='Internet'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$true;Http=$true}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $candidate=[pscustomobject]@{KeyName='x';ProfileName='Network 8';RemediationAllowed=$false;IsActive=$true;RiskLevel='High';RiskScore=90;Reason='active'}
        $diagnostics=[pscustomobject]@{Candidates=@($candidate);NetworkHealth=$h}
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics
        $decision.Recommendation | Should -Be 'NoAction'
        $decision.ProfileHygieneStatus | Should -Be 'ProtectedNumberedProfilesPresent'
        $decision.Plan.DeleteProfileCount | Should -Be 0
    }

    It 'does not auto-remediate when the network is degraded and no safe candidate exists' {
        $connections=@([pscustomobject]@{IPv4Connectivity='LocalNetwork';IPv6Connectivity='NoTraffic'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$false;Http=$false}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $candidate=[pscustomobject]@{KeyName='x';ProfileName='Network 9';RemediationAllowed=$false;IsActive=$true;RiskLevel='High';RiskScore=90;Reason='active'}
        $diagnostics=[pscustomobject]@{Candidates=@($candidate);NetworkHealth=$h}
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics
        $decision.NetworkHealth.Status | Should -Be 'Degraded'
        $decision.Recommendation | Should -Be 'InvestigateNetwork'
        $decision.Plan.IsNoOp | Should -BeTrue
        $decision.Plan.RequiresBackup | Should -BeFalse
    }

    It 'allows explicit Deep Repair on a non-healthy network when no profile is safely removable' {
        $connections=@([pscustomobject]@{IPv4Connectivity='LocalNetwork';IPv6Connectivity='NoTraffic'})
        $ncsi=[pscustomobject]@{Skipped=$false;Dns=$false;Http=$false}
        $h=Get-NRNetworkHealthAssessment -Connections $connections -NCSI $ncsi
        $diagnostics=[pscustomobject]@{Candidates=@();NetworkHealth=$h}
        $decision=Get-NRRepairDecision -Diagnostics $diagnostics -Deep
        $decision.NetworkHealth.Status | Should -Be 'Degraded'
        $decision.Recommendation | Should -Be 'InvestigateNetwork'
        $decision.Plan.IsNoOp | Should -BeFalse
        $decision.Plan.DeleteProfileCount | Should -Be 0
        $decision.Plan.ClearNewNetworksRequested | Should -BeTrue
        $decision.Plan.RequiresBackup | Should -BeTrue
    }
    It 'rejects invalid network names' {
        (Test-NRNetworkName -Name ('a' * 129)).Valid | Should -BeFalse
        (Test-NRNetworkName -Name 'bad/name').Valid | Should -BeFalse
        (Test-NRNetworkName -Name '   ').Valid | Should -BeFalse
        (Test-NRNetworkName -Name 'Office').Valid | Should -BeTrue
    }

    It 'lists restore points newest first with levels and integrity state' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rp_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00' -Level 'Manual')
            [void](New-TestRestorePoint -Root $dir -Name '20260102_010101_001' -Timestamp '2026-01-02T01:01:01.0000000+08:00' -Level 'PreRepair')

            $points=@(Get-NRRestorePoints -BackupRoot $dir)
            $points.Count | Should -Be 2
            $points[0].Level | Should -Be 'PreRepair'
            $points[0].Index | Should -Be 1
            $points[1].Level | Should -Be 'Manual'
            $points[1].Index | Should -Be 2
            $points[0].IsSafetyPoint | Should -BeTrue
            $points[1].IsSafetyPoint | Should -BeFalse
            $points[0].IsIntact | Should -BeTrue
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'treats restore points without level metadata as legacy manual points' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rplevel_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00' -Level '')
            [void](New-TestRestorePoint -Root $dir -Name '20260102_010101_001' -Timestamp '2026-01-02T01:01:01.0000000+08:00' -Level 'FutureLevel')

            $points=@(Get-NRRestorePoints -BackupRoot $dir)
            @($points | Where-Object { $_.Name -eq '20260101_010101_001' })[0].Level | Should -Be 'Manual'
            @($points | Where-Object { $_.Name -eq '20260102_010101_001' })[0].Level | Should -Be 'Unknown'

            $plan=Get-NRRestorePointRetentionPlan -RestorePoints $points -KeepPerLevel 1
            @($plan.Remove | Where-Object { $_.Level -eq 'Unknown' }).Count | Should -Be 0
            @($plan.Keep | Where-Object { $_.Level -eq 'Unknown' }).Count | Should -Be 1
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'marks restore points with missing scoped files as incomplete and refuses to select them' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpbad_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00' -SkipScopedFiles)

            $point=@(Get-NRRestorePoints -BackupRoot $dir)[0]
            $point.Integrity | Should -Be 'Incomplete'
            $point.IsIntact | Should -BeFalse
            $point.MissingFiles | Should -Contain 'NetworkList-Profiles.reg'
            { Resolve-NRRestorePoint -RestorePoints @($point) -Index 1 } | Should -Throw
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'does not throw when a restore point manifest is unreadable' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpjson_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00' -Level 'Manual' -ManifestContent '{ this is not json')

            $point=@(Get-NRRestorePoints -BackupRoot $dir)[0]
            $point.Integrity | Should -Be 'Unreadable'
            $point.IsIntact | Should -BeFalse
            $point.Level | Should -Be 'Manual'
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'rejects an out-of-range restore point index' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpidx_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00')
            $points=@(Get-NRRestorePoints -BackupRoot $dir)
            { Resolve-NRRestorePoint -RestorePoints $points -Index 7 } | Should -Throw
            (Resolve-NRRestorePoint -RestorePoints $points -Index 1).Index | Should -Be 1
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'keeps the newest restore points per level and never removes pinned points' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpplan_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $day=1
            foreach ($level in @('Manual','Manual','Manual','Manual','PreRepair','PreRepair','PreRepair')) {
                $pinned=$false
                if ($day -eq 1) { $pinned=$true }
                [void](New-TestRestorePoint -Root $dir -Name ('202601{0:d2}_010101_001' -f $day) -Timestamp ('2026-01-{0:d2}T01:01:01.0000000+08:00' -f $day) -Level $level -Pinned:$pinned)
                $day++
            }

            $points=@(Get-NRRestorePoints -BackupRoot $dir)
            $points.Count | Should -Be 7

            $plan=Get-NRRestorePointRetentionPlan -RestorePoints $points -KeepPerLevel 2 -KeepSafetyPerLevel 3
            @($plan.Keep | Where-Object { $_.Level -eq 'Manual' }).Count | Should -Be 3
            @($plan.Remove | Where-Object { $_.Level -eq 'Manual' }).Count | Should -Be 1
            @($plan.Keep | Where-Object { $_.Level -eq 'PreRepair' }).Count | Should -Be 3
            @($plan.Remove | Where-Object { $_.Level -eq 'PreRepair' }).Count | Should -Be 0
            $plan.RemoveCount | Should -Be 1
            $plan.IsNoOp | Should -BeFalse
            @($plan.Remove | Where-Object { $_.Pinned }).Count | Should -Be 0
            @($plan.Keep | Where-Object { $_.Pinned }).Count | Should -Be 1
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'pins a restore point so it survives retention, and unpins it again' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rppin_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00')
            [void](New-TestRestorePoint -Root $dir -Name '20260102_010101_001' -Timestamp '2026-01-02T01:01:01.0000000+08:00')

            $oldest=(@(Get-NRRestorePoints -BackupRoot $dir) | Where-Object { $_.Name -eq '20260101_010101_001' })
            (Set-NRRestorePointPin -Path $oldest.Path -Pinned).Pinned | Should -BeTrue

            $plan=Get-NRRestorePointRetentionPlan -RestorePoints @(Get-NRRestorePoints -BackupRoot $dir) -KeepPerLevel 1
            @($plan.Keep | Where-Object { $_.Name -eq '20260101_010101_001' }).Count | Should -Be 1
            @($plan.Remove | Where-Object { $_.Name -eq '20260101_010101_001' }).Count | Should -Be 0

            (Set-NRRestorePointPin -Path $oldest.Path).Pinned | Should -BeFalse
            $planAfter=Get-NRRestorePointRetentionPlan -RestorePoints @(Get-NRRestorePoints -BackupRoot $dir) -KeepPerLevel 1
            @($planAfter.Remove | Where-Object { $_.Name -eq '20260101_010101_001' }).Count | Should -Be 1
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'prunes only the planned restore points and verifies the remaining set' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpprune_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            foreach ($day in 1..3) {
                [void](New-TestRestorePoint -Root $dir -Name ('202601{0:d2}_010101_001' -f $day) -Timestamp ('2026-01-{0:d2}T01:01:01.0000000+08:00' -f $day))
            }
            $plan=Get-NRRestorePointRetentionPlan -RestorePoints @(Get-NRRestorePoints -BackupRoot $dir) -KeepPerLevel 1
            $plan.RemoveCount | Should -Be 2

            $result=Invoke-NRRestorePointPrune -Plan $plan -BackupRoot $dir -AssumeYes
            $result.Success | Should -BeTrue
            $result.Verified | Should -BeTrue
            $result.RemovedCount | Should -Be 2
            $result.RemainingCount | Should -Be 1
            (Test-Path -LiteralPath (Join-Path $dir '20260103_010101_001')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $dir '20260101_010101_001')) | Should -BeFalse
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'refuses to delete restore point paths outside the backup root' {
        $outer=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpouter_{0}'-f [guid]::NewGuid().ToString('N'))
        $backupRoot=Join-Path $outer 'backups'
        $victim=Join-Path $outer 'keep-me'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $victim -Force | Out-Null
        try {
            $plan=[pscustomobject]@{ Remove=@([pscustomobject]@{ Path=$victim }) }
            $result=Invoke-NRRestorePointPrune -Plan $plan -BackupRoot $backupRoot -AssumeYes
            $result.RemovedCount | Should -Be 0
            @($result.Skipped).Count | Should -Be 1
            $result.Success | Should -BeFalse
            (Test-Path -LiteralPath $victim) | Should -BeTrue
        } finally {Remove-Item -LiteralPath $outer -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'does not delete anything when the retention plan has no candidates' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpnoop_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            [void](New-TestRestorePoint -Root $dir -Name '20260101_010101_001' -Timestamp '2026-01-01T01:01:01.0000000+08:00')
            $plan=Get-NRRestorePointRetentionPlan -RestorePoints @(Get-NRRestorePoints -BackupRoot $dir) -KeepPerLevel 5
            $plan.IsNoOp | Should -BeTrue

            $result=Invoke-NRRestorePointPrune -Plan $plan -BackupRoot $dir -AssumeYes
            $result.Success | Should -BeTrue
            $result.RemovedCount | Should -Be 0
            $result.RemainingCount | Should -Be 1
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'reports prune candidates in the restore point summary' {
        $dir=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_rpsum_{0}'-f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            foreach ($day in 1..3) {
                [void](New-TestRestorePoint -Root $dir -Name ('202601{0:d2}_010101_001' -f $day) -Timestamp ('2026-01-{0:d2}T01:01:01.0000000+08:00' -f $day))
            }
            $summary=Get-NRRestorePointSummary -BackupRoot $dir -KeepPerLevel 2
            $summary.Total | Should -Be 3
            $summary.Manual | Should -Be 3
            $summary.Pinned | Should -Be 0
            $summary.NotIntact | Should -Be 0
            $summary.PruneCandidates | Should -Be 1
            @($summary.Points).Count | Should -Be 3
        } finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'wires multi-level restore points into the entry script, menu and backup levels' {
        $entry=Get-Content -LiteralPath (Join-Path $root 'NetworkRepair.ps1') -Raw -Encoding UTF8
        $entry | Should -Match ([regex]::Escape('RestorePoints.ps1'))
        $entry | Should -Match ([regex]::Escape("'RestorePoints'"))
        $entry | Should -Match ([regex]::Escape("'Prune'"))
        $entry | Should -Match 'Restore-NRBackup -RestorePointIndex'
        $entry | Should -Match 'Show-NRRestorePointList'
        $entry | Should -Match 'Invoke-NRRestorePointPruneInteractive'
        $entry | Should -Match 'Switch-NRRestorePointPin'
        $entry | Should -Not -Match ([regex]::Escape("Write-NRLine '  [8]"))
        $entry | Should -Not -Match '\bDryRun\b'

        $backup=Get-Content -LiteralPath (Join-Path $root 'src\Backup.ps1') -Raw -Encoding UTF8
        $backup | Should -Match ([regex]::Escape('Level=$Level;Pinned=$false'))
        $backup | Should -Match ([regex]::Escape("New-NRBackup -Level 'PreRestore'"))
        $backup | Should -Match 'RestorePointIndex'

        $repair=Get-Content -LiteralPath (Join-Path $root 'src\Repair.ps1') -Raw -Encoding UTF8
        $repair | Should -Match ([regex]::Escape("New-NRBackup -Level 'PreRepair'"))
    }

    It 'plans the service refresh in dependency order' {
        $plan=Get-NRServiceRefreshPlan -Scope 'NetworkList'
        $plan.Required | Should -BeTrue
        @($plan.StopOrder) | Should -Be @('netprofm','NlaSvc')
        @($plan.StartOrder) | Should -Be @('NlaSvc','netprofm')

        $skip=Get-NRServiceRefreshPlan -Scope 'Skip'
        $skip.Required | Should -BeFalse
        @($skip.StopOrder).Count | Should -Be 0
        @($skip.StartOrder).Count | Should -Be 0
    }

    It 'touches no service at all when the refresh scope is skipped' {
        Mock -CommandName Get-Service -MockWith { throw 'service lookup must not happen for a skipped refresh' }
        $r=Invoke-NRServiceRefresh -Scope 'Skip'
        $r.Required | Should -BeFalse
        $r.Success | Should -BeTrue
        $r.Degraded | Should -BeFalse
        @($r.Refreshed).Count | Should -Be 0
        Should -Invoke -CommandName Get-Service -Times 0 -Exactly
    }

    It 'waits for a bounded time for the expected service status' {
        $script:probe=0
        Mock -CommandName Get-Service -MockWith {
            $script:probe++
            if ($script:probe -ge 3) { [pscustomobject]@{ Status = 'Running' } } else { [pscustomobject]@{ Status = 'StartPending' } }
        }
        (Wait-NRServiceStatus -Name 'NlaSvc' -Status 'Running' -TimeoutSeconds 5 -IntervalMilliseconds 100) | Should -BeTrue
        $script:probe | Should -BeGreaterOrEqual 3

        Mock -CommandName Get-Service -MockWith { [pscustomobject]@{ Status = 'Stopped' } }
        (Wait-NRServiceStatus -Name 'NlaSvc' -Status 'Running' -TimeoutSeconds 1 -IntervalMilliseconds 100) | Should -BeFalse
    }

    It 'refreshes services in dependency order and reports readiness' {
        Mock -CommandName Get-Service -MockWith {
            if ($DependentServices) { return @() }
            [pscustomobject]@{ Name = $Name; Status = 'Running' }
        }
        Mock -CommandName Stop-Service -MockWith { }
        Mock -CommandName Start-Service -MockWith { }
        Mock -CommandName Wait-NRServiceStatus -MockWith { $true }
        Mock -CommandName Wait-NRNetworkListManagerReady -MockWith { [pscustomobject]@{ Ready = $true; Attempts = 1; Error = $null } }

        $r=Invoke-NRServiceRefresh -Scope 'NetworkList'
        $r.Success | Should -BeTrue
        $r.Degraded | Should -BeFalse
        $r.ComReady | Should -BeTrue
        @($r.Refreshed) | Should -Contain 'NlaSvc'
        @($r.Refreshed) | Should -Contain 'netprofm'
        @($r.Failed).Count | Should -Be 0
        Should -Invoke -CommandName Stop-Service -Times 2 -Exactly
        Should -Invoke -CommandName Start-Service -Times 2 -Exactly
    }

    It 'reports a failed service start instead of swallowing it' {
        Mock -CommandName Get-Service -MockWith {
            if ($DependentServices) { return @() }
            [pscustomobject]@{ Name = $Name; Status = 'Running' }
        }
        Mock -CommandName Stop-Service -MockWith { }
        Mock -CommandName Start-Service -MockWith { throw 'start failed' }
        Mock -CommandName Wait-NRServiceStatus -MockWith { $Status -eq 'Stopped' }
        Mock -CommandName Wait-NRNetworkListManagerReady -MockWith { [pscustomobject]@{ Ready = $false; Attempts = 3; Error = 'COM 不可用' } }

        $r=Invoke-NRServiceRefresh -Scope 'NetworkList' -StartAttempts 1 -ServiceTimeoutSeconds 1
        $r.Success | Should -BeFalse
        $r.Degraded | Should -BeTrue
        $r.ComReady | Should -BeFalse
        @($r.Failed).Count | Should -Be 2
        @($r.Failed | Where-Object { $_.Phase -eq 'Start' }).Count | Should -Be 2
        Should -Invoke -CommandName Start-Service -Times 2 -Exactly
    }

    It 'never starts a service that was not already running' {
        Mock -CommandName Get-Service -MockWith {
            if ($DependentServices) { return @() }
            [pscustomobject]@{ Name = $Name; Status = 'Stopped' }
        }
        Mock -CommandName Stop-Service -MockWith { }
        Mock -CommandName Start-Service -MockWith { }
        Mock -CommandName Wait-NRServiceStatus -MockWith { $true }
        Mock -CommandName Wait-NRNetworkListManagerReady -MockWith { [pscustomobject]@{ Ready = $true; Attempts = 1; Error = $null } }

        $r=Invoke-NRServiceRefresh -Scope 'NetworkList'
        @($r.NotRunning).Count | Should -Be 2
        @($r.Refreshed).Count | Should -Be 0
        $r.Success | Should -BeTrue
        Should -Invoke -CommandName Start-Service -Times 0 -Exactly
    }

    It 'records dependent services pulled down by a forced stop' {
        Mock -CommandName Get-Service -MockWith {
            if ($DependentServices) { return @([pscustomobject]@{ Name = 'NlmSvcExtra'; Status = 'Running' }) }
            [pscustomobject]@{ Name = $Name; Status = 'Running' }
        }
        Mock -CommandName Stop-Service -MockWith { }
        Mock -CommandName Start-Service -MockWith { }
        Mock -CommandName Wait-NRServiceStatus -MockWith { $true }
        Mock -CommandName Wait-NRNetworkListManagerReady -MockWith { [pscustomobject]@{ Ready = $true; Attempts = 1; Error = $null } }

        $r=Invoke-NRServiceRefresh -Scope 'NetworkList'
        @($r.Collateral).Count | Should -Be 1
        @($r.Refreshed) | Should -Contain 'NlmSvcExtra'
        @($r.Failed).Count | Should -Be 0
        Should -Invoke -CommandName Start-Service -Times 3 -Exactly
    }

    It 'wires the scoped service refresh strategy into every modification path' {
        $entry=Get-Content -LiteralPath (Join-Path $root 'NetworkRepair.ps1') -Raw -Encoding UTF8
        $entry | Should -Match ([regex]::Escape('Services.ps1'))

        $services=Get-Content -LiteralPath (Join-Path $root 'src\Services.ps1') -Raw -Encoding UTF8
        $services | Should -Match 'function Invoke-NRServiceRefresh'
        $services | Should -Match 'function Wait-NRServiceStatus'
        $services | Should -Match 'function Wait-NRNetworkListManagerReady'
        # 只对非注释代码行断言：注释里会提到被替换掉的旧实现。
        $serviceCode = (@($services -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        $serviceCode | Should -Not -Match 'Restart-Service'
        $serviceCode | Should -Not -Match ([regex]::Escape('Start-Sleep -Seconds 2'))
        $serviceCode | Should -Match 'Stop-Service'
        $serviceCode | Should -Match 'Start-Service'

        $repair=Get-Content -LiteralPath (Join-Path $root 'src\Repair.ps1') -Raw -Encoding UTF8
        $repair | Should -Not -Match 'function Restart-NRNetworkServices'
        $repair | Should -Match 'Invoke-NRServiceRefresh -Scope \$refreshScope'
        $repair | Should -Match ([regex]::Escape("if (`$changed -gt 0 -or `$newNetworksCleared) { `$refreshScope = 'NetworkList' }"))
        $repair | Should -Match 'ServiceRefresh=\$serviceRefresh'

        $backup=Get-Content -LiteralPath (Join-Path $root 'src\Backup.ps1') -Raw -Encoding UTF8
        $backup | Should -Not -Match 'Restart-NRNetworkServices'
        ([regex]::Matches($backup,"Invoke-NRServiceRefresh -Scope 'NetworkList'")).Count | Should -Be 2
        $backup | Should -Match 'ServiceRefresh=\$serviceRefresh'

        $identity=Get-Content -LiteralPath (Join-Path $root 'src\NetworkIdentity.ps1') -Raw -Encoding UTF8
        $identity | Should -Not -Match 'Restart-NRNetworkServices'
        $identity | Should -Match "Invoke-NRServiceRefresh -Scope 'NetworkList'"
        $identity | Should -Match ([regex]::Escape("New-NRBackup -Level 'PreRepair'"))
        $identity | Should -Match 'ServiceRefresh=\$serviceRefresh'

        $common=Get-Content -LiteralPath (Join-Path $root 'src\Common.ps1') -Raw -Encoding UTF8
        $common | Should -Match 'function Write-NRSafeLog'
    }

    It 'keeps a UTF-8 BOM on every PowerShell script' {
        # Windows PowerShell 5.1 在中文区域会按 ANSI 解码没有 BOM 的脚本，中文注释里的多字节
        # 序列可能被还原成引号或括号，直接把脚本解析搞崩。这条约定必须由测试守住。
        $scripts = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.ps1 | Where-Object { $_.FullName -notmatch '\\(backups|logs|reports)\\' })
        $scripts.Count | Should -BeGreaterThan 0

        $missing = @()
        foreach ($script in $scripts) {
            $bytes = [IO.File]::ReadAllBytes($script.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            if (-not $hasBom) { $missing += $script.FullName.Substring($root.Length + 1) }
        }
        $missing.Count | Should -Be 0 -Because ('缺少 UTF-8 BOM 的脚本：' + ($missing -join ', '))
    }

    It 'flattens every module into one runnable single-file script' {
        $out=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_dist_{0}'-f [guid]::NewGuid().ToString('N'))
        try {
            $result = & (Join-Path $root 'tools\New-NRSingleFileDistribution.ps1') -OutputDirectory $out -SkipExecutable | ConvertFrom-Json
            $result.Success | Should -BeTrue
            $result.InlinedModuleCount | Should -BeGreaterThan 5
            (Test-Path -LiteralPath $result.SingleScript) | Should -BeTrue
            (Test-Path -LiteralPath $result.Launcher) | Should -BeTrue

            $merged = Get-Content -LiteralPath $result.SingleScript -Raw -Encoding UTF8
            $merged | Should -Not -Match ([regex]::Escape('Join-Path $Script:Src'))
            foreach ($function in @('Initialize-NRPaths','Get-NRNetworkListManagerNetworks','Get-NRRestorePoints','Invoke-NRServiceRefresh')) {
                $merged | Should -Match ([regex]::Escape('function ' + $function))
            }

            # 启动器必须是纯 ASCII：批处理对中文内容和代码页都很敏感，中文只应出现在文件名上。
            $launcherBytes = [IO.File]::ReadAllBytes($result.Launcher)
            (@($launcherBytes | Where-Object { $_ -gt 127 }).Count) | Should -Be 0

            # 单文件脚本必须真的能跑起来，而不只是「看起来压平了」。
            $output = (& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File $result.SingleScript -Mode Version) -join ' '
            $output | Should -Match 'NetworkRepair v'
        } finally {Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue}
    }

    It 'packages one obvious Chinese-named entry for regular users' {
        $packager = Get-Content -LiteralPath (Join-Path $root 'tools\New-NRReleasePackage.ps1') -Raw -Encoding UTF8
        $packager | Should -Match ([regex]::Escape("'使用说明.md'"))
        $packager | Should -Match '网络修复工具'
        # 中文文件名必须用 UTF-8 条目名写入 zip，否则解压后是乱码。
        $packager | Should -Match 'CreateFromDirectory'
        $packager | Should -Match 'UTF8'
        # 旧的 ASCII 启动器不再随包分发，避免普通用户在两个入口之间犹豫。
        $packager | Should -Not -Match ([regex]::Escape("'NetworkRepair.bat'"))

        $quickStart = Get-Content -LiteralPath (Join-Path $root '使用说明.md') -Raw -Encoding UTF8
        $quickStart | Should -Match '网络修复工具\.exe'
        $quickStart | Should -Match '备用启动'
    }

    It 'resolves the entry path even when the host exposes no script path' {
        # 打包成 exe 后 $MyInvocation.MyCommand 没有 Path 属性；入口解析必须退回到进程映像，
        # 否则 Set-StrictMode 会把「找不到属性 Path」升级成致命错误。
        $entry = Get-Content -LiteralPath (Join-Path $root 'NetworkRepair.ps1') -Raw -Encoding UTF8
        $entry | Should -Match 'PSObject\.Properties\[''Path''\]'
        $entry | Should -Match 'MainModule\.FileName'
        $entry | Should -Not -Match ([regex]::Escape('Split-Path -Parent $MyInvocation.MyCommand.Path'))

        $common = Get-Content -LiteralPath (Join-Path $root 'src\Common.ps1') -Raw -Encoding UTF8
        $common | Should -Match 'ScriptHost'
        $common | Should -Match 'EntryPath'
    }

    It 'keeps GitHub workflow files free of non-ASCII text' {
        # runner 会把 run 脚本写成「不带 BOM 的 UTF-8」临时文件，Windows PowerShell 5.1 在中文
        # 区域按 ANSI 解码后，内联中文会被还原成引号并导致整个步骤解析失败（真实踩过）。
        # 因此工作流保持纯 ASCII，中文只出现在带 BOM 的仓库脚本里。
        $workflowDirectory = Join-Path $root '.github\workflows'
        $workflows = @(Get-ChildItem -LiteralPath $workflowDirectory -File -Filter *.yml)
        $workflows.Count | Should -BeGreaterThan 0

        $offenders = @()
        foreach ($workflow in $workflows) {
            $text = Get-Content -LiteralPath $workflow.FullName -Raw -Encoding UTF8
            $nonAscii = @($text.ToCharArray() | Where-Object { [int]$_ -gt 127 })
            if ($nonAscii.Count -gt 0) { $offenders += ('{0}（{1} 个非 ASCII 字符）' -f $workflow.Name, $nonAscii.Count) }
        }
        $offenders.Count | Should -Be 0 -Because ('工作流文件必须保持纯 ASCII：' + ($offenders -join ', '))
    }

    It 'declares a releasable application version' {
        $entry = Get-Content -LiteralPath (Join-Path $root 'NetworkRepair.ps1') -Raw -Encoding UTF8
        $version = ([regex]::Match($entry, "AppVersion\s*=\s*'([^']+)'")).Groups[1].Value
        $version | Should -Match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'

        # 发布工作流要求标签版本与程序版本完全一致；发布前 CHANGELOG 必须已经写明该版本。
        $changelog = Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw -Encoding UTF8
        $changelog | Should -Match ([regex]::Escape('## [' + $version + ']'))
    }

    It 'keeps release asset names ASCII because GitHub strips other characters' {
        # 实测：上传「网络修复工具_1.0.0.exe」会被 GitHub 存成「_1.0.0.exe」，非 ASCII 字符丢失。
        $packager = Get-Content -LiteralPath (Join-Path $root 'tools\New-NRReleasePackage.ps1') -Raw -Encoding UTF8
        $packager | Should -Match ([regex]::Escape('NetworkRepair-{0}-Portable.exe'))

        # 中文显示名改由附件 label 承载，并且打标签逻辑放在带 BOM 的仓库脚本里，
        # 这样发布工作流步骤可以保持纯 ASCII。
        $labelTool = Join-Path $root 'tools\Set-NRReleaseAssetLabels.ps1'
        (Test-Path -LiteralPath $labelTool) | Should -BeTrue
        $labelText = Get-Content -LiteralPath $labelTool -Raw -Encoding UTF8
        $labelText | Should -Match 'label'
        $labelText | Should -Match '网络修复工具'

        $release = Get-Content -LiteralPath (Join-Path $root '.github\workflows\release.yml') -Raw -Encoding UTF8
        $release | Should -Match ([regex]::Escape('Set-NRReleaseAssetLabels.ps1'))
    }

    It 'avoids the PowerShell 5.1 generic list of object trap' {
        # @(List[object]) 在 Windows PowerShell 5.1 下会抛「Argument types do not match /
        # 参数类型不匹配」。这个坑在仓库里已经踩中两次，直接禁止该写法，改用普通数组。
        $offenders = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.ps1 | Where-Object { $_.FullName -notmatch '\\(backups|logs|reports)\\' })) {
            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            if ($content -match 'System\.Collections\.Generic\.List\[object\]') { $offenders += $file.FullName.Substring($root.Length + 1) }
        }
        $offenders.Count | Should -Be 0 -Because ('这些文件使用了 List[object]：' + ($offenders -join ', '))
    }

    It 'wires the graphical interface into the entry script' {
        $entry = Get-Content -LiteralPath (Join-Path $root 'NetworkRepair.ps1') -Raw -Encoding UTF8
        $entry | Should -Match ([regex]::Escape("'Gui'"))
        $entry | Should -Match ([regex]::Escape("'GuiSmoke'"))
        $entry | Should -Match ([regex]::Escape('Gui.ps1'))
        $entry | Should -Match 'Show-NRGui'
        $entry | Should -Match 'Invoke-NRGuiSmokeTest'
        # 自检模式必须在提权之前返回，CI 才能在没有管理员权限时验证界面代码。
        $smokeIndex = $entry.IndexOf("if (`$Mode -eq 'GuiSmoke')")
        $adminIndex = $entry.IndexOf('Assert-NRAdministrator')
        $smokeIndex | Should -BeGreaterThan 0
        $adminIndex | Should -BeGreaterThan $smokeIndex

        $gui = Get-Content -LiteralPath (Join-Path $root 'src\Gui.ps1') -Raw -Encoding UTF8
        foreach ($function in @('Show-NRGui','Invoke-NRGuiSmokeTest','New-NRGuiForm','Get-NRGuiStatusCards','Get-NRGuiPlanSummary')) {
            $gui | Should -Match ([regex]::Escape('function ' + $function))
        }
    }

    It 'builds the graphical form in a headless smoke test' {
        $smoke = Invoke-NRGuiSmokeTest
        $smoke.Success | Should -BeTrue -Because ([string]$smoke.Error)
        $smoke.ControlCount | Should -BeGreaterThan 20
        @($smoke.ZeroSizedControls).Count | Should -Be 0
        $smoke.NamedControls | Should -Contain 'btnSafeRepair'
        $smoke.NamedControls | Should -Contain 'btnRestorePoints'
        $smoke.NamedControls | Should -Contain 'logBox'
    }

    It 'describes status cards and the repair plan without a user interface' {
        $diagnostics = [pscustomobject]@{
            NetworkHealth      = [pscustomobject]@{ Status = 'Healthy'; Reason = 'NCSI 正常' }
            Connections        = @([pscustomobject]@{ Name = '以太网' })
            ActiveProfileNames = @('以太网')
            SafeCandidateCount = 2
            HighRiskCount      = 1
            DiagnosticsErrors  = @()
        }
        $restoreSummary = [pscustomobject]@{ Total = 4; PreRepair = 2; PreRestore = 1; Pinned = 1; PruneCandidates = 0 }

        $cards = @(Get-NRGuiStatusCards -Diagnostics $diagnostics -RestorePointSummary $restoreSummary)
        $cards.Count | Should -Be 5
        ($cards | Where-Object { $_.Title -eq '网络健康度' }).Value | Should -Be 'Healthy'
        ($cards | Where-Object { $_.Title -eq '可安全清理' }).Value | Should -Be '2 个'
        ($cards | Where-Object { $_.Title -eq '恢复点' }).Value | Should -Be '4 个'
        ($cards | Where-Object { $_.Title -eq '恢复点' }).Detail | Should -Match '安全点 3 个'
        ($cards | Where-Object { $_.Title -eq '诊断完整性' }).Severity | Should -Be 'Ok'

        $plan = [pscustomobject]@{
            Actions = @(
                [pscustomobject]@{ Action = 'DeleteProfile'; ProfileName = '网络 3'; RiskLevel = 'Low' }
                [pscustomobject]@{ Action = 'ClearNewNetworks' }
            )
            ClearNewNetworksRequested = $true
        }
        $text = Get-NRGuiPlanSummary -Plan $plan -Deep
        $text | Should -Match '深度修复'
        $text | Should -Match '网络 3'
        $text | Should -Match 'NewNetworks'
        $text | Should -Match '将删除 1 个 Profile'
        $text | Should -Match '自动回滚'

        (Get-NRGuiActionAvailability -Busy).SafeRepair | Should -BeFalse
        (Get-NRGuiActionAvailability).SafeRepair | Should -BeTrue
    }

    It 'defaults the packaged executable to the graphical interface' {
        $tool = Get-Content -LiteralPath (Join-Path $root 'tools\New-NRSingleFileDistribution.ps1') -Raw -Encoding UTF8
        $tool | Should -Match ([regex]::Escape("[string]`$DefaultMode = 'Gui'"))
        $tool | Should -Match 'NoConsole'
        # ps2exe 在无控制台模式下会把脚本输出变成模态对话框并阻塞进程，图形版必须同时加 -noOutput。
        $tool | Should -Match 'NoOutput'
        # 备用启动器必须显式回到控制台 TUI，否则控制台入口会消失。
        $tool | Should -Match ([regex]::Escape('-Mode Menu'))
    }
}
