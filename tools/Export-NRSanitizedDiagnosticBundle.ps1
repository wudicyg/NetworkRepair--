[CmdletBinding()]
<#
.SYNOPSIS
    生成 NetMedic 脱敏诊断包（可安全公开发布到 Issue / Discussions）。

.DESCRIPTION
    这是脚本方式的调用入口。真正的裁剪逻辑在 `src\SanitizedReport.ps1`，
    这样图形界面、命令行与压平后的单文件分发可以共用同一份实现。

    脱敏诊断包刻意排除：机器名、MAC 地址、IP 地址、注册表路径、NetworkId、
    URL 与凭据。需要完整数据排障时请用 `-Mode Report`，但那会自动落盘敏感信息，
    公开前必须自行脱敏。

.PARAMETER OutputPath
    输出 zip 路径。省略时写入临时目录下的 NetMedic_Sanitized_<时间戳>.zip。

.EXAMPLE
    .\tools\Export-NRSanitizedDiagnosticBundle.ps1
#>
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
. (Join-Path $Src 'SanitizedReport.ps1')

try {
    $result = Export-NRSanitizedDiagnosticBundle -Path $OutputPath
    $result | ConvertTo-Json -Depth 6
} catch {
    [pscustomobject]@{
        Success   = $false
        Sanitized = $true
        ReadOnly  = $true
        Error     = $_.Exception.Message
    } | ConvertTo-Json -Depth 6
    exit 1
}
