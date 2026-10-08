#requires -Version 5.1
<#
.SYNOPSIS
    为 GitHub Release 附件设置中文显示标签。

.DESCRIPTION
    GitHub 会剥掉附件名里的非 ASCII 字符（实测：上传「网络修复工具_1.0.0.exe」会存成「_1.0.0.exe」），
    因此发布页附件名必须使用 ASCII；中文名称改由附件的 label 字段承载，在 Releases 页面展示。

    因为本文件包含中文字面量，必须保持 UTF-8 BOM，这样发布工作流的步骤本身可以保持纯 ASCII
    （GitHub Actions 会把 run 脚本写成不带 BOM 的 UTF-8，PowerShell 5.1 在中文区域会解析失败）。

.NOTES
    单个附件打标签失败只警告，不影响已经发布的附件本身；只有查不到 Release 才抛错。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$Token = $env:GH_TOKEN,
    [string]$ApiUrl = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL } else { 'https://api.github.com' }
}
if ([string]::IsNullOrWhiteSpace($Repository)) { throw '未提供 -Repository，也无法从 GITHUB_REPOSITORY 读取。' }
if ([string]::IsNullOrWhiteSpace($Token)) { throw '未提供 -Token，也无法从 GH_TOKEN 读取。' }

$labels = @(
    [pscustomobject]@{ Match = '*Portable.exe'; Label = '网络修复工具（双击即用，免安装）' }
    [pscustomobject]@{ Match = '*.zip';        Label = '完整发布包（含中文入口、使用说明与源码）' }
    [pscustomobject]@{ Match = '*.sha256';     Label = 'SHA-256 校验值' }
)

$headers = @{
    Authorization = ('Bearer {0}' -f $Token)
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'networkrepair-release'
}

$releaseUri = '{0}/repos/{1}/releases/tags/{2}' -f $ApiUrl, $Repository, $Tag
$release = Invoke-RestMethod -Uri $releaseUri -Headers $headers -Method Get -TimeoutSec 60
Write-Host ('Release {0} has {1} asset(s).' -f $release.tag_name, @($release.assets).Count)

foreach ($asset in @($release.assets)) {
    $label = $null
    foreach ($rule in $labels) {
        if ($asset.name -like $rule.Match) { $label = $rule.Label; break }
    }
    if (-not $label) { continue }

    try {
        $body = @{ label = $label } | ConvertTo-Json -Compress
        $assetUri = '{0}/repos/{1}/releases/assets/{2}' -f $ApiUrl, $Repository, $asset.id
        Invoke-RestMethod -Uri $assetUri -Headers $headers -Method Patch -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 | Out-Null
        Write-Host ('Label applied: {0}' -f $asset.name)
    } catch {
        Write-Warning ('无法为附件 {0} 设置标签：{1}' -f $asset.name, $_.Exception.Message)
    }
}

Write-Host 'Asset labels processed.'
