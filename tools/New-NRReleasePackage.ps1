#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'release')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot

$entry = Join-Path $Root 'NetworkRepair.ps1'
if (-not (Test-Path -LiteralPath $entry)) {
    throw 'NetworkRepair.ps1 not found.'
}

$content = Get-Content -LiteralPath $entry -Raw -Encoding UTF8
$pattern = '\$Script:AppVersion\s*=\s*''([^'']+)''' 
$match = [regex]::Match($content, $pattern)
if (-not $match.Success) {
    throw 'Unable to determine NetworkRepair version from NetworkRepair.ps1.'
}
$version = $match.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'NetworkRepair version is empty.'
}

$packageName = 'NetworkRepair_{0}_Windows' -f $version
$packageRoot = Join-Path $OutputDirectory $packageName
$zipPath = Join-Path $OutputDirectory ($packageName + '.zip')
$hashPath = Join-Path $OutputDirectory ($packageName + '.sha256')

$files = @(
    'NetworkRepair.bat',
    'NetworkRepair.ps1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'CODE_OF_CONDUCT.md'
)

$directories = @(
    'src',
    'docs',
    'tools'
)

if (Test-Path -LiteralPath $OutputDirectory) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

foreach ($file in $files) {
    $source = Join-Path $Root $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required release file missing: $file"
    }
    $target = Join-Path $packageRoot $file
    Copy-Item -LiteralPath $source -Destination $target -Force
}

foreach ($directory in $directories) {
    $source = Join-Path $Root $directory
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required release directory missing: $directory"
    }
    $target = Join-Path $packageRoot $directory
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

$manifest = Join-Path $packageRoot 'RELEASE-MANIFEST.txt'
@(
    'NetworkRepair release package'
    ('Version: {0}' -f $version)
    ('GeneratedAt: {0}' -f (Get-Date).ToString('o'))
    ''
    'Included: application files, source modules, release documentation, and support tools.'
    'Excluded: .git, .github, tests, backups, logs, reports, validation runtime data, and local machine state.'
) | Set-Content -LiteralPath $manifest -Encoding UTF8

Compress-Archive -Path $packageRoot -DestinationPath $zipPath -Force
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
('{0}  {1}' -f $hash, (Split-Path -Leaf $zipPath)) | Set-Content -LiteralPath $hashPath -Encoding ASCII

[pscustomobject]@{
    Success = $true
    Version = $version
    Package = $zipPath
    Sha256 = $hashPath
    Sha256Value = $hash
} | ConvertTo-Json -Depth 5
