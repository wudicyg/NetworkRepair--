[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$SkipConnectivityTest,
    [switch]$IncludeSensitiveDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $Root 'src'

$Script:AppName = 'NetMedic'
$entryVersionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $Root 'NetworkRepair.ps1') -Raw -Encoding UTF8), '\$Script:AppVersion\s*=\s*''([^'']+)''')
if (-not $entryVersionMatch.Success) {
    throw 'Unable to determine NetMedic version from NetworkRepair.ps1.'
}
$Script:AppVersion = $entryVersionMatch.Groups[1].Value
$Script:Root = $Root
$Script:Src = $Src
$Script:Backups = Join-Path $Root 'backups'
$Script:Logs = Join-Path $env:TEMP 'NetMedic-Validation'
$Script:Reports = Join-Path $env:TEMP 'NetMedic-Validation'
if (-not (Test-Path -LiteralPath $Script:Logs)) {
    New-Item -ItemType Directory -Path $Script:Logs -Force | Out-Null
}
$Script:LogFile = Join-Path $Script:Logs ('validation_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))

. (Join-Path $Src 'Common.ps1')
. (Join-Path $Src 'NetworkListManager.ps1')
. (Join-Path $Src 'NetworkIdentity.ps1')
. (Join-Path $Src 'RepairPlan.ps1')
. (Join-Path $Src 'Ncsi.ps1')
. (Join-Path $Src 'Diagnostics.ps1')

$diagnostics = Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest

$evidence = [pscustomobject]@{
    SchemaVersion = '1.0'
    ReadOnly = $true
    GeneratedAt = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    Application = $Script:AppName
    ApplicationVersion = $Script:AppVersion
    Windows = $diagnostics.Windows
    NetworkHealth = $diagnostics.NetworkHealth
    ProfileHygieneStatus = $diagnostics.ProfileHygieneStatus
    RepairRecommendation = $diagnostics.RepairRecommendation
    SafeCandidateCount = $diagnostics.SafeCandidateCount
    HighRiskCount = $diagnostics.HighRiskCount
    NumberedProfileCount = @($diagnostics.Candidates | Where-Object {
        $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
    }).Count
    CurrentConnections = @($diagnostics.Connections | Select-Object Name,InterfaceAlias,NetworkCategory,IPv4Connectivity,IPv6Connectivity)
    Adapters = @($diagnostics.Adapters | Select-Object Name,InterfaceDescription,Status,LinkSpeed,MediaType,Virtual)
    NetworkListManager = [pscustomobject]@{
        Available = [bool]$diagnostics.NetworkListManager.Available
        NetworkCount = if ($diagnostics.NetworkListManager.Available) { @($diagnostics.NetworkListManager.Networks).Count } else { 0 }
        ExactNetworkIdCorrelationCount = @($diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
    }
    Candidates = @($diagnostics.Candidates | Select-Object KeyName,ProfileName,Managed,IsActive,RiskScore,RiskLevel,RemediationAllowed,DiagnosticCodes,NetworkId,NetworkName,NetworkCorrelation,NlmIsConnected,Reason,LastWrite)
    IPConfiguration = @($diagnostics.IPConfiguration | Select-Object InterfaceAlias,InterfaceIndex,IPv4Addresses,IPv6Addresses,IPv4Gateway,IPv4Dhcp,DnsServersIPv4)
    Gateways = @($diagnostics.Gateways)
    DnsServers = @($diagnostics.DnsServers)
    NCSI = $diagnostics.NCSI
    IssueDetails = @($diagnostics.IssueDetails | Select-Object Code,Severity,Message)
}


if ($IncludeSensitiveDetails) {
    [void]$evidence.PSObject.Properties.Remove('Sanitized')
    $evidence | Add-Member -NotePropertyName Sanitized -NotePropertyValue $false -Force
    $evidence | Add-Member -NotePropertyName IncludesSensitiveDetails -NotePropertyValue $true -Force
    Write-Warning '敏感详情模式会导出计算机名、Profile/接口名、NetworkId、注册表路径和 IP 配置。请只保存在本机安全位置，切勿公开上传。'
} else {
    $evidence = ConvertTo-NRSanitizedDiagnosticSummary -Diagnostics $diagnostics
    $evidence | Add-Member -NotePropertyName EvidenceType -NotePropertyValue 'SanitizedReadOnlyValidation' -Force
}

if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Output ('Validation evidence written to: {0}' -f $OutputPath)
} else {
    $evidence | ConvertTo-Json -Depth 12
}
