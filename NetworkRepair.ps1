[CmdletBinding()]
param(
    [ValidateSet('Menu','Scan','DryRun','Repair','DeepRepair','Backup','Restore','Report','Rename','Version')]
    [string]$Mode = 'Menu',
    [string]$BackupPath,
    [string]$ReportPath,
    [string]$NetworkId,
    [string]$NewName,
    [switch]$Json,
    [switch]$SkipConnectivityTest,
    [switch]$Yes,
    [switch]$NoColor
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Script:AppName = 'NetworkRepair'
$Script:AppVersion = '0.3.0-dev'
$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Src = Join-Path $Script:Root 'src'
$Script:Backups = Join-Path $Script:Root 'backups'
$Script:Logs = Join-Path $Script:Root 'logs'
$Script:Reports = Join-Path $Script:Root 'reports'
. (Join-Path $Script:Src 'Common.ps1')
. (Join-Path $Script:Src 'Diagnostics.ps1')
. (Join-Path $Script:Src 'NetworkListManager.ps1')
. (Join-Path $Script:Src 'NetworkIdentity.ps1')
. (Join-Path $Script:Src 'Ncsi.ps1')
. (Join-Path $Script:Src 'Backup.ps1')
. (Join-Path $Script:Src 'Repair.ps1')
. (Join-Path $Script:Src 'Validation.ps1')
Initialize-NRPaths
$Script:LogFile = New-NRLogFile
function Show-NRBanner {
    if ($NoColor) { $c = 'White' } else { $c = 'Cyan' }
    Write-NRLine ('=' * 68) $c
    Write-NRLine (' NetworkRepair v{0} - Windows 网络配置诊断与修复工具' -f $Script:AppVersion) $c
    Write-NRLine ' 安全原则：先诊断 → 先备份 → 再修改 → 最后验证' $c
    Write-NRLine ('=' * 68) $c
}
function Show-NRMenu {
    Write-NRLine ''
    Write-NRLine '当前可用操作：' 'White'
    Write-NRLine '  [1] 自动诊断' 'White'
    Write-NRLine '  [2] 安全修复（推荐）' 'White'
    Write-NRLine '  [3] 深度修复（谨慎）' 'Yellow'
    Write-NRLine '  [4] 备份当前网络配置' 'White'
    Write-NRLine '  [5] 从备份恢复' 'White'
    Write-NRLine '  [6] 导出诊断报告' 'White'
    Write-NRLine '  [7] Dry Run（只预览，不修改）' 'White'
    Write-NRLine '  [8] 安全重命名网络（显式指定 NetworkId）' 'White'
    Write-NRLine '  [0] 退出' 'White'
    Write-NRLine ''
}
function Invoke-NRMenu {
    do {
        Clear-Host
        Show-NRBanner
        Show-NRMenu
        $choice = Read-Host '请选择'
        switch ($choice) {
            '1' { Invoke-NRScan | Out-Null; Pause-NR }
            '2' { Invoke-NRRepair -Deep:$false -AssumeYes:$Yes | Out-Null; Pause-NR }
            '3' { Invoke-NRRepair -Deep:$true -AssumeYes:$Yes | Out-Null; Pause-NR }
            '4' { $b = New-NRBackup; Write-NRLine ('备份完成：{0}' -f $b.Path) 'Green'; Pause-NR }
            '5' { $p = Read-Host '请输入备份目录或 .reg 文件路径'; if ($p) { Restore-NRBackup -BackupPath $p -AssumeYes:$Yes | Out-Null }; Pause-NR }
            '6' { $r = Export-NRReport; Write-NRLine ('报告：{0}' -f $r.Path) 'Green'; Pause-NR }
            '7' { Invoke-NRRepair -Deep:$false -DryRun -AssumeYes:$false | Out-Null; Pause-NR }
            '8' { $id=Read-Host 'NetworkId (GUID)'; $name=Read-Host '新名称'; Invoke-NRNetworkRenameOperation -NetworkId $id -NewName $name -AssumeYes:$false | Out-Null; Pause-NR }
            '0' { return 0 }
            default { Write-NRLine '无效选择。' 'Yellow'; Start-Sleep -Milliseconds 700 }
        }
    } while ($true)
}
function Pause-NR { if (-not $Json) { [void](Read-Host '按 Enter 继续') } }
try {
    if ($Mode -eq 'Version') { Write-Output (('{0} v{1}' -f $Script:AppName, $Script:AppVersion)); exit 0 }
    $relaunch = New-Object System.Collections.Generic.List[string]
    [void]$relaunch.Add('-Mode'); [void]$relaunch.Add($Mode)
    if ($BackupPath) { [void]$relaunch.Add('-BackupPath'); [void]$relaunch.Add(('"{0}"' -f ($BackupPath -replace '"','\"'))) }
    if ($ReportPath) { [void]$relaunch.Add('-ReportPath'); [void]$relaunch.Add(('"{0}"' -f ($ReportPath -replace '"','\"'))) }
    if ($NetworkId) { [void]$relaunch.Add('-NetworkId'); [void]$relaunch.Add($NetworkId) }
    if ($NewName) { [void]$relaunch.Add('-NewName'); [void]$relaunch.Add(('"{0}"' -f $NewName)) }
    if ($Json) { [void]$relaunch.Add('-Json') }
    if ($SkipConnectivityTest) { [void]$relaunch.Add('-SkipConnectivityTest') }
    if ($Yes) { [void]$relaunch.Add('-Yes') }
    if ($NoColor) { [void]$relaunch.Add('-NoColor') }
    Assert-NRAdministrator -RelaunchArguments ($relaunch -join ' ')
    switch ($Mode) {
        'Menu' { exit (Invoke-NRMenu) }
        'Scan' { $r = Invoke-NRScan -SkipConnectivityTest:$SkipConnectivityTest; if ($Json) { $r | ConvertTo-Json -Depth 8 } }
        'DryRun' { $r = Invoke-NRRepair -Deep:$false -DryRun -AssumeYes:$false -SkipConnectivityTest:$SkipConnectivityTest; if ($Json) { $r | ConvertTo-Json -Depth 8 } }
        'Repair' { $r = Invoke-NRRepair -Deep:$false -AssumeYes:$Yes -SkipConnectivityTest:$SkipConnectivityTest; if ($Json) { $r | ConvertTo-Json -Depth 8 }; if (-not $r.Success) { exit 5 } }
        'DeepRepair' { $r = Invoke-NRRepair -Deep:$true -AssumeYes:$Yes -SkipConnectivityTest:$SkipConnectivityTest; if ($Json) { $r | ConvertTo-Json -Depth 8 }; if (-not $r.Success) { exit 5 } }
        'Backup' { $r = New-NRBackup; if ($Json) { $r | ConvertTo-Json -Depth 8 } else { Write-NRLine ('备份完成：{0}' -f $r.Path) 'Green' } }
        'Rename' {
            if (-not $NetworkId -or -not $NewName) { throw 'Rename 模式必须提供 -NetworkId 和 -NewName。' }
            $r = Invoke-NRNetworkRenameOperation -NetworkId $NetworkId -NewName $NewName -AssumeYes:$Yes
            if ($Json) { $r | ConvertTo-Json -Depth 8 }
            if (-not $r.Success) { exit 7 }
        }
        'Restore' { if (-not $BackupPath) { throw 'Restore 模式必须提供 -BackupPath。' }; $r = Restore-NRBackup -BackupPath $BackupPath -AssumeYes:$Yes; if ($Json) { $r | ConvertTo-Json -Depth 8 }; if (-not $r.Success) { exit 6 } }
        'Report' { $r = Export-NRReport -Path $ReportPath -SkipConnectivityTest:$SkipConnectivityTest; if ($Json) { $r | ConvertTo-Json -Depth 8 } else { Write-NRLine ('报告：{0}' -f $r.Path) 'Green' } }
    }
    exit 0
} catch {
    Write-NRLog ('FATAL: {0}' -f $_.Exception.Message) 'ERROR'
    Write-NRLine ('[错误] {0}' -f $_.Exception.Message) 'Red'
    Write-NRLine ('日志：{0}' -f $Script:LogFile) 'Yellow'
    if ($Json) { [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; Log = $Script:LogFile } | ConvertTo-Json -Depth 4 }
    exit 1
}
