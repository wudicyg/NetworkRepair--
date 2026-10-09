[CmdletBinding()]
param(
    [string]$OutputPath
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
    param([string]$Path)

    $diagnostics = Get-NRDiagnostics

    $bundle = ConvertTo-NRSanitizedDiagnosticSummary -Diagnostics $diagnostics

    $json = $bundle | ConvertTo-Json -Depth 12
    if (-not $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = Join-Path $Script:Reports ('NetMedic_Sanitized_{0}.zip' -f $stamp)
    }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('NetMedic_Sanitized_{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $jsonPath = Join-Path $tempDir 'diagnostic.json'
        $readmePath = Join-Path $tempDir 'README.txt'
        $json | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        @(
            'NetMedic sanitized diagnostic bundle'
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