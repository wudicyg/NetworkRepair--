#requires -Version 5.1
<#
.SYNOPSIS
    校验已构建的 NetMedic 发布包：内容布局、单一入口、中文文件名编码与校验值。

.DESCRIPTION
    本脚本集中承载所有中文字面量，CI 的 run 步骤因此可以保持纯 ASCII。
    原因：GitHub Actions 会把 run 脚本写成「不带 BOM 的 UTF-8」临时文件，Windows PowerShell 5.1
    在中文区域会按 ANSI 解码，内联中文会被还原成引号或括号，导致步骤脚本直接解析失败。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageOutputDirectory,
    [switch]$RequireExecutable,
    [switch]$VerifyEntryRuns
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedEntry = '网络医生.exe'
$expectedQuickStart = '使用说明.md'
$expectedLauncher = '备用启动\启动-网络医生.bat'
$expectedSingleScript = 'NetworkRepair.single.ps1'
$legacyLauncher = 'NetworkRepair.bat'

$requiredEntries = @(
    $expectedEntry,
    $expectedSingleScript,
    $expectedQuickStart,
    '备用启动',
    'NetworkRepair.ps1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'src',
    'docs',
    'tools',
    'RELEASE-MANIFEST.txt'
)
$forbiddenEntries = @('tests', '.git', '.github', 'backups', 'logs', 'reports')

$zip = Get-ChildItem -LiteralPath $PackageOutputDirectory -Filter *.zip | Select-Object -First 1
if (-not $zip) { throw ('未找到发布包 zip：{0}' -f $PackageOutputDirectory) }
Write-Host ('Package: {0}' -f $zip.Name)

# 校验值文件必须按同名匹配：现在会同时产出「打包 zip」与「便携 exe」两份校验文件。
$shaFile = Get-ChildItem -LiteralPath $PackageOutputDirectory -Filter *.sha256 | Where-Object { $_.BaseName -eq $zip.BaseName } | Select-Object -First 1
if (-not $shaFile) { throw '未找到与 zip 同名的 SHA-256 文件。' }
$lines = @(Get-Content -LiteralPath $shaFile.FullName -Encoding ASCII | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($lines.Count -ne 1) { throw 'SHA-256 文件必须只包含一行非空内容。' }
$parts = $lines[0] -split '\s+', 2
if ($parts.Count -ne 2 -or $parts[0].Length -ne 64 -or $parts[0] -notmatch '^[0-9a-fA-F]{64}$') { throw 'SHA-256 文件格式不合法。' }
if ($parts[1].Trim() -ne $zip.Name) { throw ('校验文件名与 zip 不一致：{0}' -f $parts[1].Trim()) }
$actualHash = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $parts[0].ToLowerInvariant()) { throw ('SHA-256 不匹配：期望 {0}，实际 {1}' -f $parts[0], $actualHash) }
Write-Host ('SHA-256 verified: {0}' -f $actualHash)

# zip 条目名核对：中文文件名必须原样往返，否则解压后是乱码。
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
try {
    $entryNames = @($archive.Entries | ForEach-Object { ($_.FullName -replace '\\', '/') })
} finally {
    $archive.Dispose()
}
foreach ($expected in @($expectedEntry, $expectedQuickStart, ($expectedLauncher -replace '\\', '/'), $expectedSingleScript)) {
    $matched = @($entryNames | Where-Object { $_ -like ('*/' + $expected) })
    if ($matched.Count -ne 1) { throw ('打包后的条目缺失或重复（中文名编码可能有问题）：{0}' -f $expected) }
}
Write-Host 'Packaged entry names verified.'

# 解压后核对真实布局。
$temp = Join-Path ([IO.Path]::GetTempPath()) ('NetMedicPackageCheck_{0}' -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $temp -Force
    $root = Get-ChildItem -LiteralPath $temp -Directory | Select-Object -First 1
    if (-not $root) { throw '发布包根目录缺失。' }

    foreach ($required in $requiredEntries) {
        if (-not (Test-Path -LiteralPath (Join-Path $root.FullName $required))) {
            throw ('缺少必需内容：{0}' -f $required)
        }
    }
    foreach ($forbidden in $forbiddenEntries) {
        if (Test-Path -LiteralPath (Join-Path $root.FullName $forbidden)) {
            throw ('包含不应分发的内容：{0}' -f $forbidden)
        }
    }
    if (Test-Path -LiteralPath (Join-Path $root.FullName $legacyLauncher)) {
        throw ('面向普通用户的发布包不应再包含旧 ASCII 启动器：{0}' -f $legacyLauncher)
    }
    if ($RequireExecutable -and -not (Test-Path -LiteralPath (Join-Path $root.FullName $expectedEntry))) {
        throw '发布包中缺少可执行入口。'
    }
    Write-Host 'Release package layout verified.'

    if ($VerifyEntryRuns) {
        $singleScript = Join-Path $root.FullName $expectedSingleScript
        $output = (& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File $singleScript -Mode Version) -join ' '
        if ($output -notmatch 'NetMedic v') { throw ('单文件脚本运行输出异常：{0}' -f $output) }
        Write-Host ('Single-file script output: {0}' -f $output)
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Release package verification passed.'
