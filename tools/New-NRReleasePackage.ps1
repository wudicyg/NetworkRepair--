#requires -Version 5.1
<#
.SYNOPSIS
    构建 NetworkRepair 正式发布包：单文件 exe + 完整源码包 + 校验值。

.DESCRIPTION
    产出：
      <输出目录>\NetworkRepair_<版本>_Windows\          发布包目录
        ├─ 网络修复工具.exe                              单文件主程序（默认带提权清单）
        ├─ 网络修复工具_<版本>.exe                       便携版副本，便于单独分发
        ├─ 使用说明.md                                   面向普通用户的中文说明
        ├─ 备用启动\启动-网络修复工具.bat                备用启动器
        ├─ NetworkRepair.single.ps1                      压平后的单文件脚本
        └─ 源码与文档（NetworkRepair.ps1 / src / tools / docs / ...）
      <输出目录>\NetworkRepair_<版本>_Windows.zip        发布包压缩文件（UTF-8 中文名）
      <输出目录>\*.sha256                                对应的 SHA-256 校验文件

.NOTES
    压缩使用 ZipFile + UTF-8 条目名，避免中文文件名在解压后变成乱码。
    编译 exe 需要 ps2exe；没有 ps2exe 时加 -SkipExecutable 只产出脚本包。
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'release'),
    [string]$ExecutableName = '网络修复工具.exe',
    [string]$PortableExecutableName = $null,
    [string]$Ps2ExeModulePath,
    [switch]$NoElevationManifest,
    [switch]$SkipExecutable
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
if ([string]::IsNullOrWhiteSpace($PortableExecutableName)) {
    $PortableExecutableName = ('网络修复工具_{0}.exe' -f $version)
}

$packageName = 'NetworkRepair_{0}_Windows' -f $version
$packageRoot = Join-Path $OutputDirectory $packageName
$zipPath = Join-Path $OutputDirectory ($packageName + '.zip')
$hashPath = Join-Path $OutputDirectory ($packageName + '.sha256')

$files = @(
    'NetworkRepair.ps1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'CODE_OF_CONDUCT.md',
    '使用说明.md'
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
    Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $file) -Force
}

foreach ($directory in $directories) {
    $source = Join-Path $Root $directory
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required release directory missing: $directory"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $directory) -Recurse -Force
}

# 在包内生成面向普通用户的单一入口（单文件脚本 + exe + 备用启动器）。
$distributionTool = Join-Path $PSScriptRoot 'New-NRSingleFileDistribution.ps1'
$distributionArguments = @{
    OutputDirectory        = $packageRoot
    ExecutableName         = $ExecutableName
    PreserveOutputDirectory = $true
    SkipExecutable         = $SkipExecutable
    NoElevationManifest    = $NoElevationManifest
}
if ($Ps2ExeModulePath) { $distributionArguments.Ps2ExeModulePath = $Ps2ExeModulePath }
$distribution = & $distributionTool @distributionArguments | ConvertFrom-Json
if (-not $distribution.Success) {
    throw ('单文件分发构建失败：{0}' -f $distribution.ExecutableError)
}

$executableInPackage = Join-Path $packageRoot $ExecutableName
$portableExecutable = $null
$portableHash = $null
if (-not $SkipExecutable) {
    if (-not (Test-Path -LiteralPath $executableInPackage)) {
        throw '发布包中未生成可执行主程序。'
    }
    $portableExecutable = Join-Path $OutputDirectory $PortableExecutableName
    Copy-Item -LiteralPath $executableInPackage -Destination $portableExecutable -Force
    $portableHashValue = (Get-FileHash -LiteralPath $portableExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
    $portableHash = Join-Path $OutputDirectory (([IO.Path]::GetFileNameWithoutExtension($PortableExecutableName)) + '.sha256')
    ('{0}  {1}' -f $portableHashValue, $PortableExecutableName) | Set-Content -LiteralPath $portableHash -Encoding ASCII
}

$elevationText = 'requireAdministrator（双击后由 Windows 提示提权）'
if ($NoElevationManifest) { $elevationText = '未嵌入（由脚本自行请求提权）' }
$manifest = Join-Path $packageRoot 'RELEASE-MANIFEST.txt'
@(
    'NetworkRepair release package'
    ('Version: {0}' -f $version)
    ('GeneratedAt: {0}' -f (Get-Date).ToString('o'))
    ('Entry: {0}' -f $ExecutableName)
    ('Elevation: {0}' -f $elevationText)
    ('SingleFileScript: {0}' -f (Split-Path -Leaf $distribution.SingleScript))
    ('InlinedModules: {0}' -f $distribution.InlinedModuleCount)
    ''
    'Included: single-file entry (exe + script + fallback launcher), source modules, documentation, support tools.'
    'Excluded: .git, .github, tests, backups, logs, reports, validation runtime data, and local machine state.'
) | Set-Content -LiteralPath $manifest -Encoding UTF8

# 中文文件名必须用 UTF-8 条目名写入，否则在部分解压工具下会变成乱码。
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
    $packageRoot,
    $zipPath,
    [IO.Compression.CompressionLevel]::Optimal,
    $true,
    [Text.Encoding]::UTF8
)

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
('{0}  {1}' -f $hash, (Split-Path -Leaf $zipPath)) | Set-Content -LiteralPath $hashPath -Encoding ASCII

[pscustomobject]@{
    Success           = $true
    Version           = $version
    Package           = $zipPath
    PackageRoot       = $packageRoot
    Sha256            = $hashPath
    Sha256Value       = $hash
    PortableExe       = $portableExecutable
    PortableExeSha256 = $portableHash
    EntryName         = $ExecutableName
    SingleScript      = $distribution.SingleScript
    Launcher          = $distribution.Launcher
    InlinedModules    = $distribution.InlinedModuleCount
    ElevationVerified = $distribution.ElevationVerified
} | ConvertTo-Json -Depth 5
