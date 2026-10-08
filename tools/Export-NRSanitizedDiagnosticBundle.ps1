[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $Root 'src'

$Script:AppName = 'NetworkRepair'
$Script:AppVersion = '0.4.0-dev'
$Script:Root = $Root
$Script:Src = $Src
$Script:Backups = Join-Path $Root 'backups'
$Script:Logs = Join-Path ([IO.Path]::GetTempPath()) 'NetworkRepair-Support'
$Script:Reports = Join-Path ([IO.Path]::GetTempPath()) 'NetworkRepair-Support'
if (-not (Test-Path -LiteralPath $Script:Logs)) {
    New-Item -ItemType Directory -Path $Script:Logs -Force | Out-Null
}
$Script:LogFile = Join-Path $Script:Logs ('support_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))

. (Join-Path $Src 'Common.ps1')
. (Join-Path $Src 'NetworkListManager.ps1')
. (Join-Path $Src 'NetworkIdentity.ps1')
. (Join-Path $Src 'RepairPlan.ps1')
. (Join-Path $Src 'Ncsi.ps1')
. (Join-Path $Src 'Diagnostics.ps1')

function ConvertTo-NRSanitizedCandidate {
    param([Parameter(Mandatory)]$Candidate)

    $profileClass = 'Other'
    if ($Candidate.ProfileName -and ([string]$Candidate.ProfileName).Trim() -match '^网络s+d+$') {
        $profileClass = 'ChineseNumbered'
    } elseif ($Candidate.ProfileName -and ([string]$Candidate.ProfileName).Trim() -match '^Networks+d+$') {
        $profileClass = 'EnglishNumbered'
    }

    [pscustomobject]@{
        ProfileClass = $profileClass
        Managed = [bool]$Candidate.Managed
        IsActive = [bool]$Candidate.IsActive
        RiskScore = $Candidate.RiskScore
        RiskLevel = $Candidate.RiskLevel
        RemediationAllowed = [bool]$Candidate.RemediationAllowed
        DiagnosticCodes = @($Candidate.DiagnosticCodes)
        NetworkCorrelation = [string]$Candidate.NetworkCorrelation
        NlmIsConnected = [bool]$Candidate.NlmIsConnected
    }
}

function Export-NRSanitizedDiagnosticBundle {
    param([string]$Path)

    $diagnostics = Get-NRDiagnostics

    $bundle = [pscustomobject]@{
        SchemaVersion = '1.0'
        Sanitized = $true
        ReadOnly = $true
        GeneratedAt = (Get-Date).ToString('o')
        Application = $Script:AppName
        ApplicationVersion = $Script:AppVersion
        Windows = [pscustomobject]@{
            Caption = [string]$diagnostics.Windows.Caption
            Version = [string]$diagnostics.Windows.Version
            Build = [string]$diagnostics.Windows.Build
            Architecture = [string]$diagnostics.Windows.Architecture
            PowerShell = [string]$diagnostics.Windows.PowerShell
        }
        NetworkHealth = $diagnostics.NetworkHealth
        ProfileHygieneStatus = [string]$diagnostics.ProfileHygieneStatus
        RepairRecommendation = [string]$diagnostics.RepairRecommendation
        SafeCandidateCount = [int]$diagnostics.SafeCandidateCount
        HighRiskCount = [int]$diagnostics.HighRiskCount
        NumberedProfileCount = @($diagnostics.Candidates | Where-Object {
            $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)s+d+$'
        }).Count
        CurrentConnections = @($diagnostics.Connections | ForEach-Object {
            [pscustomobject]@{
                NetworkCategory = $_.NetworkCategory
                IPv4Connectivity = $_.IPv4Connectivity
                IPv6Connectivity = $_.IPv6Connectivity
            }
        })
        Adapters = @($diagnostics.Adapters | ForEach-Object {
            [pscustomobject]@{
                Status = $_.Status
                LinkSpeed = $_.LinkSpeed
                MediaType = $_.MediaType
                Virtual = $_.Virtual
            }
        })
        NetworkListManager = [pscustomobject]@{
            Available = [bool]$diagnostics.NetworkListManager.Available
            NetworkCount = if ($diagnostics.NetworkListManager.Available) { @($diagnostics.NetworkListManager.Networks).Count } else { 0 }
            ExactNetworkIdCorrelationCount = @($diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        }
        Candidates = @($diagnostics.Candidates | ForEach-Object {
            ConvertTo-NRSanitizedCandidate -Candidate $_
        })
        IPConfiguration = @($diagnostics.IPConfiguration | ForEach-Object {
            [pscustomobject]@{
                InterfaceIndex = $_.InterfaceIndex
                IPv4AddressCount = @($_.IPv4Addresses).Count
                IPv6AddressCount = @($_.IPv6Addresses).Count
                HasIPv4Gateway = @($_.IPv4Gateway).Count -gt 0
                IPv4Dhcp = $_.IPv4Dhcp
                IPv6Dhcp = $_.IPv6Dhcp
                DnsServerIPv4Count = @($_.DnsServersIPv4).Count
                DnsServerIPv6Count = @($_.DnsServersIPv6).Count
            }
        })
        GatewayDiagnostics = [pscustomobject]@{
            TestedCount = @($diagnostics.Gateways).Count
            FailedCount = @($diagnostics.Gateways | Where-Object { -not $_.Reachable }).Count
        }
        DnsDiagnostics = [pscustomobject]@{
            TestedCount = @($diagnostics.DnsServers).Count
            FailedCount = @($diagnostics.DnsServers | Where-Object { -not $_.ResolvesNCSI }).Count
        }
        NCSI = [pscustomobject]@{
            Skipped = [bool]$diagnostics.NCSI.Skipped
            Enabled = $diagnostics.NCSI.Enabled
            Dns = $diagnostics.NCSI.Dns
            Http = $diagnostics.NCSI.Http
        }
        IssueDetails = @($diagnostics.IssueDetails | Select-Object Code,Severity,Message)
        DiagnosticErrorCount = @($diagnostics.DiagnosticsErrors).Count
        Redaction = [pscustomobject]@{
            ComputerName = $true
            MacAddress = $true
            IPAddress = $true
            RegistryPath = $true
            NetworkId = $true
            NetworkUrl = $true
            Credentials = $true
        }
    }

    $json = $bundle | ConvertTo-Json -Depth 12
    if (-not $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = Join-Path $Script:Reports ('NetworkRepair_Sanitized_{0}.zip' -f $stamp)
    }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_Sanitized_{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $jsonPath = Join-Path $tempDir 'diagnostic.json'
        $readmePath = Join-Path $tempDir 'README.txt'
        $json | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        @(
            'NetworkRepair sanitized diagnostic bundle'
            ''
            'This bundle is read-only diagnostic evidence.'
            'It intentionally excludes computer name, MAC addresses, IP addresses, registry paths, NetworkId values, URLs, and credentials.'
        ) | Set-Content -LiteralPath $readmePath -Encoding UTF8

        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $Path -Force
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Success = $true
        Path = $Path
        Sanitized = $true
        ReadOnly = $true
        SafeCandidateCount = $bundle.SafeCandidateCount
        ProfileHygieneStatus = $bundle.ProfileHygieneStatus
        NetworkHealth = $bundle.NetworkHealth.Status
    }
}

try {
    $result = Export-NRSanitizedDiagnosticBundle -Path $OutputPath
    $result | ConvertTo-Json -Depth 6
} catch {
    [pscustomobject]@{
        Success = $false
        Sanitized = $true
        ReadOnly = $true
        Error = $_.Exception.Message
    } | ConvertTo-Json -Depth 6
    exit 1
}