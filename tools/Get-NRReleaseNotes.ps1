#requires -Version 5.1
<#
.SYNOPSIS
    从 CHANGELOG.md 抽取指定版本的更新段落，生成 GitHub Release 正文。

.DESCRIPTION
    发布流水线此前使用 `gh release create --generate-notes`，正文只会列出 PR 标题
    （例如「chore: rename the project to NetMedic」），对下载程序的普通用户几乎没有信息量，
    而且发布页描述会与 CHANGELOG 里手写的内容脱节。

    这里改为直接使用 CHANGELOG.md 中该版本的段落，并附加一段「该下载哪个文件」的说明，
    让发布页只靠自身就能说清"这一版更新了什么、我该下哪个文件"。

.PARAMETER Version
    要生成正文的版本号，不带 v 前缀（例如 1.4.0）。

.PARAMETER ChangelogPath
    CHANGELOG.md 路径，默认取仓库根目录。

.PARAMETER OutputPath
    正文输出路径。省略时写到 CHANGELOG.md 同目录下的 RELEASE-NOTES.md。

.PARAMETER Repository
    仓库全名，用于生成 CHANGELOG 的绝对链接。

.EXAMPLE
    .\tools\Get-NRReleaseNotes.ps1 -Version 1.4.0 -OutputPath .\release\RELEASE-NOTES.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$ChangelogPath,
    [string]$OutputPath,
    [string]$Repository = 'wudicyg/netmedic',
    # 产物命名：默认是当前品牌；修正历史发布页时传入当时的命名即可。
    [string]$PortableNamePattern = 'NetMedic-{0}-Portable.exe',
    [string]$ZipNamePattern = 'NetMedic_{0}_Windows.zip',
    [string]$EntryName = '网络医生.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $ChangelogPath) { $ChangelogPath = Join-Path $root 'CHANGELOG.md' }
if (-not $OutputPath) { $OutputPath = Join-Path $root 'RELEASE-NOTES.md' }

if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) {
    throw ('找不到 CHANGELOG：{0}' -f $ChangelogPath)
}

$normalized = $Version.Trim()
if ($normalized.StartsWith('v') -or $normalized.StartsWith('V')) { $normalized = $normalized.Substring(1) }

$lines = Get-Content -LiteralPath $ChangelogPath -Encoding UTF8
$sectionPattern = '^##\s+\[{0}\]' -f [regex]::Escape($normalized)
$startIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $sectionPattern) { $startIndex = $i; break }
}
if ($startIndex -lt 0) {
    throw ('CHANGELOG 中没有 {0} 的段落，拒绝生成空的发布正文。' -f $normalized)
}

# 段落从本版本的标题行之后开始，直到下一个二级标题（## ）为止。
$bodyLines = New-Object System.Collections.Generic.List[string]
for ($i = $startIndex + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s') { break }
    [void]$bodyLines.Add($lines[$i])
}
while ($bodyLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($bodyLines[0])) {
    $bodyLines.RemoveAt(0)
}
while ($bodyLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($bodyLines[$bodyLines.Count - 1])) {
    $bodyLines.RemoveAt($bodyLines.Count - 1)
}
if ($bodyLines.Count -eq 0) {
    throw ('CHANGELOG 中 {0} 的段落是空的。' -f $normalized)
}

$portableName = $PortableNamePattern -f $normalized
$zipName = $ZipNamePattern -f $normalized
$changelogUrl = 'https://github.com/{0}/blob/main/CHANGELOG.md' -f $Repository

$output = New-Object System.Collections.Generic.List[string]
[void]$output.Add(('## NetMedic {0} 更新内容' -f $normalized))
[void]$output.Add('')
foreach ($line in $bodyLines) { [void]$output.Add($line) }
[void]$output.Add('')
[void]$output.Add('### 该下载哪个文件')
[void]$output.Add('')
[void]$output.Add(('- **`{0}`**：双击即用，无需解压（推荐）。首次运行会请求管理员权限，因为读写网络配置需要它。' -f $portableName))
[void]$output.Add(('- **`{0}`**：完整发布包，解压后双击包内的 `{1}`（同一个程序）。含使用说明、备用启动器与源码。' -f $zipName, $EntryName))
[void]$output.Add('- 两个 `.sha256` 文件是对应产物的 SHA-256 校验值，可用 `Get-FileHash` 或 `certutil -hashfile` 核对。')
[void]$output.Add('')
[void]$output.Add('> 发布页附件名只支持 ASCII，中文名称显示在附件的说明（label）上。')
[void]$output.Add('')
[void]$output.Add(('完整变更日志：[CHANGELOG.md]({0})' -f $changelogUrl))

$directory = Split-Path -Parent $OutputPath
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
[IO.File]::WriteAllText($OutputPath, (($output -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))

[pscustomobject]@{
    Success    = $true
    Version    = $normalized
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    Bytes      = (Get-Item -LiteralPath $OutputPath).Length
    Lines      = $output.Count
} | ConvertTo-Json -Depth 4
