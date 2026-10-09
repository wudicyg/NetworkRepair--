[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$SkipConnectivityTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $Root 'src'
$Script:AppName = 'NetMedic'
$entryVersionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $Root 'NetworkRepair.ps1') -Raw -Encoding UTF8), '\$Script:AppVersion\s*=\s*''([^'']+)''')
if (-not $entryVersionMatch.Success) { throw 'Unable to determine NetMedic version from NetworkRepair.ps1.' }
$Script:AppVersion = $entryVersionMatch.Groups[1].Value
$Script:Root = $Root
$Script:Src = $Src
$Script:Backups = Join-Path $Root 'backups'
$Script:Logs = Join-Path ([IO.Path]::GetTempPath()) 'NetMedic-Support'
$Script:Reports = Join-Path ([IO.Path]::GetTempPath()) 'NetMedic-Support'
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

function Export-NRSanitizedDiagnosticBundle {
    param(
        [string]$Path,
        [switch]$SkipConnectivityTest
    )

    $diagnostics = Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest
    $summary = ConvertTo-NRSanitizedDiagnosticSummary -Diagnostics $diagnostics

    if (-not $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = Join-Path $Script:Reports ('NetMedic_Sanitized_{0}.zip' -f $stamp)
    }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('NetMedic_Sanitized_{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $jsonPath = Join-Path $tempDir 'diagnostic.json'
        $readmePath = Join-Path $tempDir 'README.txt'
        $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        @(
            'NetMedic sanitized diagnostic bundle'
            ''
            'This bundle contains an allowlist-based, read-only diagnostic summary.'
            'It excludes computer name, adapter names, profile names, MAC/IP addresses, NetworkId values, registry paths, probe URLs/errors, and credentials.'
            'Review the generated diagnostic.json before sharing because OS build and timestamp can still narrow the environment.'
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
        SafeCandidateCount = $summary.SafeCandidateCount
        ProfileHygieneStatus = $summary.ProfileHygieneStatus
        NetworkHealthStatus = $summary.NetworkHealthStatus
    }
}

try {
    $result = Export-NRSanitizedDiagnosticBundle -Path $OutputPath -SkipConnectivityTest:$SkipConnectivityTest
    $result | ConvertTo-Json -Depth 6
} catch {
    Write-NRSafeLog ('Sanitized diagnostic bundle export failed: {0}' -f $_.Exception.Message) 'ERROR'
    [pscustomobject]@{
        Success = $false
        Sanitized = $true
        ReadOnly = $true
        Error = '诊断包生成失败。请在本机检查日志；不要公开上传原始日志。'
    } | ConvertTo-Json -Depth 6
    exit 1
}
