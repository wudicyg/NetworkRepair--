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

if ($IncludeSensitiveDetails) {
    Write-Warning '敏感详情模式已启用。证据可能包含计算机名、适配器/Profile 名称、MAC/IP 地址、NetworkId、注册表路径及探测细节；仅保存在本机，不要公开上传。'
    $evidence = [pscustomobject]@{
        SchemaVersion = '1.0'
        EvidenceType = 'SensitiveReadOnlyValidation'
        ReadOnly = $true
        Sanitized = $false
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
        Candidates = @($diagnostics.Candidates)
        Connections = @($diagnostics.Connections)
        Adapters = @($diagnostics.Adapters)
        NetworkListManager = $diagnostics.NetworkListManager
        NetworkIdentityCorrelations = @($diagnostics.NetworkIdentityCorrelations)
        RegistryProfiles = @($diagnostics.RegistryProfiles)
        IPConfiguration = @($diagnostics.IPConfiguration)
        Gateways = @($diagnostics.Gateways)
        DnsServers = @($diagnostics.DnsServers)
        NCSI = $diagnostics.NCSI
        IssueDetails = @($diagnostics.IssueDetails)
        DiagnosticsErrors = @($diagnostics.DiagnosticsErrors)
    }
} else {
    $evidence = ConvertTo-NRSanitizedDiagnosticSummary -Diagnostics $diagnostics
    $evidence | Add-Member -NotePropertyName EvidenceType -NotePropertyValue 'SanitizedReadOnlyValidation'
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
