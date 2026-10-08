# 图形界面：把既有的诊断 / 修复 / 备份 / 恢复点能力包一层 WinForms 界面。
#
# 设计约束：
#   1. 不新增任何修改边界。界面只调用既有函数；修复前仍然展示计划并要求用户确认，
#      候选资格仍由 RemediationAllowed 等安全门槛决定。
#   2. 逻辑与界面分离：状态卡文案、修复计划摘要、按钮可用性都是纯函数，可在无界面环境下单测。
#   3. 程序集延迟加载：只有真正构建窗口时才加载 System.Windows.Forms。
#   4. 无控制台环境（打包后的图形版 exe）下不依赖 Write-Host：界面自己渲染日志，
#      调用既有函数时走它们的静默分支（$Json）。

function Get-NRGuiStatusCards {
    param(
        [Parameter(Mandatory)]$Diagnostics,
        $RestorePointSummary = $null
    )

    $cards = @()

    $healthStatus = [string](Get-NRPropertyValue -InputObject (Get-NRPropertyValue -InputObject $Diagnostics -Name 'NetworkHealth') -Name 'Status')
    $healthReason = [string](Get-NRPropertyValue -InputObject (Get-NRPropertyValue -InputObject $Diagnostics -Name 'NetworkHealth') -Name 'Reason')
    $healthSeverity = 'Info'
    switch ($healthStatus) {
        'Healthy'      { $healthSeverity = 'Ok' }
        'Degraded'     { $healthSeverity = 'Warn' }
        'Disconnected' { $healthSeverity = 'Error' }
        default        { $healthSeverity = 'Info' }
    }
    $cards += [pscustomobject]@{
        Title    = '网络健康度'
        Value    = $(if ($healthStatus) { $healthStatus } else { '未知' })
        Detail   = $healthReason
        Severity = $healthSeverity
    }

    $connectionCount = @((Get-NRPropertyValue -InputObject $Diagnostics -Name 'Connections')).Count
    $activeNames = @((Get-NRPropertyValue -InputObject $Diagnostics -Name 'ActiveProfileNames'))
    $cards += [pscustomobject]@{
        Title    = '当前连接'
        Value    = ('{0} 个' -f $connectionCount)
        Detail   = $(if ($activeNames.Count -gt 0) { ($activeNames -join '、') } else { '未读取到活动连接' })
        Severity = $(if ($connectionCount -gt 0) { 'Ok' } else { 'Warn' })
    }

    $safeCount = [int](Get-NRPropertyValue -InputObject $Diagnostics -Name 'SafeCandidateCount')
    $highRisk = [int](Get-NRPropertyValue -InputObject $Diagnostics -Name 'HighRiskCount')
    $cards += [pscustomobject]@{
        Title    = '可安全清理'
        Value    = ('{0} 个' -f $safeCount)
        Detail   = $(if ($safeCount -gt 0) { ('历史编号 Profile；另有 {0} 个受保护' -f $highRisk) } else { '没有命中的历史编号 Profile' })
        Severity = $(if ($safeCount -gt 0) { 'Warn' } else { 'Ok' })
    }

    $restoreCount = 0
    $restoreDetail = '尚未创建'
    $pruneCandidates = 0
    if ($RestorePointSummary) {
        $restoreCount = [int](Get-NRPropertyValue -InputObject $RestorePointSummary -Name 'Total')
        $pruneCandidates = [int](Get-NRPropertyValue -InputObject $RestorePointSummary -Name 'PruneCandidates')
        $safetyCount = [int](Get-NRPropertyValue -InputObject $RestorePointSummary -Name 'PreRepair') + [int](Get-NRPropertyValue -InputObject $RestorePointSummary -Name 'PreRestore')
        $pinnedCount = [int](Get-NRPropertyValue -InputObject $RestorePointSummary -Name 'Pinned')
        $restoreDetail = ('安全点 {0} 个，已固定 {1} 个' -f $safetyCount, $pinnedCount)
        if ($pruneCandidates -gt 0) { $restoreDetail = ('{0}；{1} 个可清理' -f $restoreDetail, $pruneCandidates) }
    }
    $cards += [pscustomobject]@{
        Title    = '恢复点'
        Value    = ('{0} 个' -f $restoreCount)
        Detail   = $restoreDetail
        Severity = $(if ($pruneCandidates -gt 0) { 'Warn' } else { 'Info' })
    }

    $degraded = @((Get-NRPropertyValue -InputObject $Diagnostics -Name 'DiagnosticsErrors')).Count
    $cards += [pscustomobject]@{
        Title    = '诊断完整性'
        Value    = $(if ($degraded -eq 0) { '完整' } else { ('{0} 项降级' -f $degraded) })
        Detail   = $(if ($degraded -eq 0) { '所有诊断阶段均成功读取' } else { '部分诊断阶段未能读取，结论需谨慎解读' })
        Severity = $(if ($degraded -eq 0) { 'Ok' } else { 'Warn' })
    }

    @($cards)
}

function Get-NRGuiPlanSummary {
    param(
        [Parameter(Mandatory)]$Plan,
        [switch]$Deep
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $deleteCount = 0
    $refreshRequested = [bool](Get-NRPropertyValue -InputObject $Plan -Name 'ClearNewNetworksRequested')

    foreach ($action in @((Get-NRPropertyValue -InputObject $Plan -Name 'Actions'))) {
        if (-not $action) { continue }
        switch ([string]$action.Action) {
            'DeleteProfile' {
                $deleteCount++
                [void]$lines.Add(('  · 删除历史 Profile：{0}（风险 {1}）' -f $action.ProfileName, $action.RiskLevel))
            }
            'ClearNewNetworks' {
                [void]$lines.Add('  · 刷新 NetworkList\NewNetworks 记录')
            }
            default {
                [void]$lines.Add(('  · {0}' -f $action.Action))
            }
        }
    }

    $headline = if ($Deep) { '即将执行：深度修复' } else { '即将执行：安全修复' }
    $body = New-Object System.Collections.Generic.List[string]
    [void]$body.Add($headline)
    [void]$body.Add('')
    if ($lines.Count -eq 0) {
        [void]$body.Add('  （没有需要执行的操作）')
    } else {
        foreach ($line in $lines) { [void]$body.Add($line) }
    }
    [void]$body.Add('')
    if ($refreshRequested) { [void]$body.Add('  · 会额外刷新 NewNetworks 记录') }
    [void]$body.Add(('  将删除 {0} 个 Profile。' -f $deleteCount))
    [void]$body.Add('')
    [void]$body.Add('执行前会自动创建恢复点；修改后会验证，失败会自动回滚。')
    [void]$body.Add('')
    [void]$body.Add('确认继续吗？')

    ($body -join "`r`n")
}

function Get-NRGuiActionAvailability {
    param(
        [switch]$Busy,
        [switch]$IsAdministrator
    )

    $enabled = (-not $Busy)
    @{
        Diagnose    = $enabled
        SafeRepair  = $enabled
        DeepRepair  = $enabled
        Backup      = $enabled
        RestorePoints = $enabled
        ExportReport = $enabled
        OpenLogs    = $enabled
        About       = $true
    }
}

function Get-NRGuiSeverityColor {
    param([string]$Severity)

    switch ($Severity) {
        'Ok'    { [System.Drawing.Color]::FromArgb(0, 122, 60) }
        'Warn'  { [System.Drawing.Color]::FromArgb(176, 108, 0) }
        'Error' { [System.Drawing.Color]::FromArgb(176, 0, 0) }
        default { [System.Drawing.Color]::FromArgb(60, 60, 60) }
    }
}

function Initialize-NRGuiAssemblies {
    if (-not ('System.Windows.Forms.Form' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms
    }
    if (-not ('System.Drawing.Font' -as [type])) {
        Add-Type -AssemblyName System.Drawing
    }
}

function New-NRGuiStatusCard {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][int]$Column
    )

    $box = New-Object System.Windows.Forms.GroupBox
    $box.Text = $Title
    $box.Dock = 'Fill'
    $box.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Name = ('value_{0}' -f $Column)
    $valueLabel.Dock = 'Top'
    $valueLabel.Height = 34
    $valueLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
    $valueLabel.TextAlign = 'MiddleLeft'
    $valueLabel.Text = '—'

    $detailLabel = New-Object System.Windows.Forms.Label
    $detailLabel.Name = ('detail_{0}' -f $Column)
    $detailLabel.Dock = 'Fill'
    $detailLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
    $detailLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
    $detailLabel.Text = ''

    $box.Controls.Add($detailLabel)
    $box.Controls.Add($valueLabel)
    $box
}

function Get-NRGuiApplicationIcon {
    <#
        窗口与任务栏图标：打包成 exe 时用 exe 自身的图标；以脚本方式运行时退回包内的
        assets\NetworkRepair.ico。两条路都拿不到就返回 $null（用系统默认图标）。
    #>
    $isScriptHost = [bool](Get-Variable -Name 'ScriptHost' -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
    if (-not $isScriptHost) {
        try {
            $hostImage = [string](Get-Variable -Name 'HostImage' -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
            if ($hostImage -and (Test-Path -LiteralPath $hostImage)) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($hostImage)
                if ($icon) { return $icon }
            }
        } catch { }
    }
    try {
        $root = [string](Get-Variable -Name 'Root' -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
        if ($root) {
            $candidate = Join-Path $root 'assets\NetworkRepair.ico'
            if (Test-Path -LiteralPath $candidate) { return (New-Object System.Drawing.Icon($candidate)) }
        }
    } catch { }
    $null
}

function New-NRGuiForm {
    Initialize-NRGuiAssemblies

    $form = New-Object System.Windows.Forms.Form
    $form.Name = 'NetworkRepairGuiForm'
    $form.Text = ('NetworkRepair 网络修复工具 v{0}' -f $Script:AppVersion)
    $form.Size = New-Object System.Drawing.Size(980, 700)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 620)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $form.BackColor = [System.Drawing.Color]::WhiteSmoke
    $applicationIcon = Get-NRGuiApplicationIcon
    if ($applicationIcon) { $form.Icon = $applicationIcon }

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Name = 'rootLayout'
    $root.Dock = 'Fill'
    $root.ColumnCount = 1
    $root.RowCount = 5
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 62)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 96)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 50)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))

    # 顶部标题
    $header = New-Object System.Windows.Forms.Panel
    $header.Name = 'headerPanel'
    $header.Dock = 'Fill'
    $header.BackColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Name = 'titleLabel'
    $titleLabel.Dock = 'Fill'
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.TextAlign = 'MiddleLeft'
    $titleLabel.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $titleLabel.Text = ('  NetworkRepair 网络修复工具   v{0}' -f $Script:AppVersion)
    [void]$header.Controls.Add($titleLabel)

    # 状态卡
    $cards = New-Object System.Windows.Forms.TableLayoutPanel
    $cards.Name = 'cardsPanel'
    $cards.Dock = 'Fill'
    $cards.ColumnCount = 5
    $cards.RowCount = 1
    for ($i = 0; $i -lt 5; $i++) {
        [void]$cards.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
        [void]$cards.Controls.Add((New-NRGuiStatusCard -Title @('网络健康度','当前连接','可安全清理','恢复点','诊断完整性')[$i] -Column $i), $i, 0)
    }

    # 操作按钮
    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Name = 'buttonsPanel'
    $buttons.Dock = 'Fill'
    $buttons.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 0)
    $buttonSpecs = @(
        [pscustomobject]@{ Name = 'btnDiagnose';      Text = '重新诊断';       Key = 'Diagnose' }
        [pscustomobject]@{ Name = 'btnSafeRepair';    Text = '安全修复（推荐）'; Key = 'SafeRepair' }
        [pscustomobject]@{ Name = 'btnDeepRepair';    Text = '深度修复（谨慎）'; Key = 'DeepRepair' }
        [pscustomobject]@{ Name = 'btnBackup';        Text = '手动备份';       Key = 'Backup' }
        [pscustomobject]@{ Name = 'btnRestorePoints'; Text = '恢复点管理';     Key = 'RestorePoints' }
        [pscustomobject]@{ Name = 'btnExportReport';  Text = '导出诊断报告';   Key = 'ExportReport' }
        [pscustomobject]@{ Name = 'btnOpenLogs';      Text = '打开日志目录';   Key = 'OpenLogs' }
        [pscustomobject]@{ Name = 'btnCheckUpdate';   Text = '检查更新';       Key = 'CheckUpdate' }
        [pscustomobject]@{ Name = 'btnAbout';         Text = '关于';           Key = 'About' }
    )
    foreach ($spec in $buttonSpecs) {
        $button = New-Object System.Windows.Forms.Button
        $button.Name = $spec.Name
        $button.Text = $spec.Text
        $button.Tag = $spec.Key
        $button.AutoSize = $true
        $button.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
        $button.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
        [void]$buttons.Controls.Add($button)
    }

    # 日志
    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Name = 'logBox'
    $log.Dock = 'Fill'
    $log.ReadOnly = $true
    $log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $log.ForeColor = [System.Drawing.Color]::Gainsboro
    $log.Font = New-Object System.Drawing.Font('Consolas', 9)
    $log.BorderStyle = 'FixedSingle'
    $log.Margin = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
    $log.DetectUrls = $false

    # 底部状态
    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.Name = 'statusPanel'
    $statusPanel.Dock = 'Fill'
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Name = 'statusLabel'
    $statusLabel.Dock = 'Fill'
    $statusLabel.TextAlign = 'MiddleLeft'
    $statusLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $statusLabel.Text = '就绪'
    [void]$statusPanel.Controls.Add($statusLabel)

    [void]$root.Controls.Add($header, 0, 0)
    [void]$root.Controls.Add($cards, 0, 1)
    [void]$root.Controls.Add($buttons, 0, 2)
    [void]$root.Controls.Add($log, 0, 3)
    [void]$root.Controls.Add($statusPanel, 0, 4)
    [void]$form.Controls.Add($root)

    $form
}

function Get-NRGuiControlTree {
    param([Parameter(Mandatory)][System.Windows.Forms.Control]$Control)

    # 注意：这里不要用 List[object] 收集再 @() 包装——PowerShell 5.1 下
    # @(List[object]) 会抛「Argument types do not match / 参数类型不匹配」。用普通数组。
    $items = @()
    foreach ($child in @($Control.Controls)) {
        $items += [pscustomobject]@{
            Name   = [string]$child.Name
            Type   = $child.GetType().Name
            Width  = [int]$child.Width
            Height = [int]$child.Height
        }
        $items += @(Get-NRGuiControlTree -Control $child)
    }
    @($items)
}

function Invoke-NRGuiSmokeTest {
    <#
        无界面自检：构建完整窗口、核对关键控件都已创建且尺寸有效，然后释放。
        用于在 CI / 无交互环境下证明界面代码可以真正构建，而不只是能通过语法解析。
    #>
    $report = [pscustomobject]@{
        Success           = $false
        Error             = $null
        ControlCount      = 0
        NamedControls     = @()
        ZeroSizedControls = @()
    }

    try {
        $form = New-NRGuiForm
        try {
            $tree = @(Get-NRGuiControlTree -Control $form)
            $named = @($tree | Where-Object { $_.Name } | ForEach-Object { $_.Name })
            $zero = @($tree | Where-Object { $_.Width -le 0 -or $_.Height -le 0 } | ForEach-Object { $_.Name })

            foreach ($required in @('rootLayout','headerPanel','titleLabel','cardsPanel','buttonsPanel','logBox','statusPanel','statusLabel','btnDiagnose','btnSafeRepair','btnDeepRepair','btnBackup','btnRestorePoints','btnExportReport','btnOpenLogs','btnCheckUpdate','btnAbout')) {
                if ($named -notcontains $required) { throw ('界面缺少控件：{0}' -f $required) }
            }

            $report.ControlCount = $tree.Count
            $report.NamedControls = @($named)
            $report.ZeroSizedControls = @($zero)
            $report.Success = $true
        } finally {
            $form.Dispose()
        }
    } catch {
        $report.Error = $_.Exception.Message
    }

    $report
}

function Write-NRGuiLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Head')][string]$Kind = 'Info'
    )

    if (-not $script:NRGuiLog) { return }

    $color = switch ($Kind) {
        'Ok'    { [System.Drawing.Color]::FromArgb(120, 220, 140) }
        'Warn'  { [System.Drawing.Color]::FromArgb(240, 200, 110) }
        'Error' { [System.Drawing.Color]::FromArgb(255, 130, 130) }
        'Head'  { [System.Drawing.Color]::FromArgb(130, 200, 255) }
        default { [System.Drawing.Color]::Gainsboro }
    }

    $stamp = (Get-Date -Format 'HH:mm:ss')
    $script:NRGuiLog.SelectionStart = $script:NRGuiLog.TextLength
    $script:NRGuiLog.SelectionColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $script:NRGuiLog.AppendText(('[ {0} ] ' -f $stamp))
    $script:NRGuiLog.SelectionColor = $color
    $script:NRGuiLog.AppendText($Message + "`r`n")
    $script:NRGuiLog.SelectionStart = $script:NRGuiLog.TextLength
    $script:NRGuiLog.ScrollToCaret()
    Write-NRSafeLog -Message $Message
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-NRGuiStatus {
    param([string]$Text)
    if ($script:NRGuiStatus) { $script:NRGuiStatus.Text = $Text }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-NRGuiBusy {
    param([Parameter(Mandatory)][bool]$Busy)

    $script:NRGuiBusy = $Busy
    $availability = Get-NRGuiActionAvailability -Busy:$Busy
    foreach ($button in @($script:NRGuiButtons)) {
        if (-not $button) { continue }
        $button.Enabled = [bool]$availability[[string]$button.Tag]
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-NRGuiOperation {
    <#
        在「忙碌」状态下执行一段操作：禁用按钮、持续泵送消息让界面保持重绘，
        结束后恢复按钮并统一处理异常，避免界面假死或异常静默丢失。
    #>
    param(
        [Parameter(Mandatory)][string]$StatusText,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )

    Set-NRGuiBusy -Busy $true
    Set-NRGuiStatus -Text $StatusText

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 120
    $timer.Add_Tick({ [System.Windows.Forms.Application]::DoEvents() })
    $timer.Start()

    try {
        & $Action @ArgumentList
    } catch {
        Write-NRGuiLog -Message ('操作失败：{0}' -f $_.Exception.Message) -Kind 'Error'
        [void][System.Windows.Forms.MessageBox]::Show(('操作失败：' + "`r`n`r`n" + $_.Exception.Message), 'NetworkRepair', 'OK', 'Error')
    } finally {
        $timer.Stop()
        $timer.Dispose()
        Set-NRGuiBusy -Busy $false
        Set-NRGuiStatus -Text '就绪'
    }
}

function Update-NRGuiStatusCards {
    param(
        [Parameter(Mandatory)]$Diagnostics,
        $RestorePointSummary = $null
    )

    $cards = @(Get-NRGuiStatusCards -Diagnostics $Diagnostics -RestorePointSummary $RestorePointSummary)
    for ($i = 0; $i -lt $cards.Count; $i++) {
        $valueLabel = $script:NRGuiCards[$i].Controls[('value_{0}' -f $i)]
        $detailLabel = $script:NRGuiCards[$i].Controls[('detail_{0}' -f $i)]
        if ($valueLabel) {
            $valueLabel.Text = $cards[$i].Value
            $valueLabel.ForeColor = Get-NRGuiSeverityColor -Severity $cards[$i].Severity
        }
        if ($detailLabel) { $detailLabel.Text = $cards[$i].Detail }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-NRGuiDiagnostics {
    <#
        统一入口：跑一次诊断并顺带取恢复点摘要。$Json 走静默分支，界面自己负责渲染。
    #>
    $diagnostics = Get-NRDiagnostics -SkipConnectivityTest
    $summary = $null
    try { $summary = Get-NRRestorePointSummary } catch { Write-NRGuiLog -Message ('恢复点摘要读取失败：{0}' -f $_.Exception.Message) -Kind 'Warn' }
    [pscustomobject]@{ Diagnostics = $diagnostics; RestorePointSummary = $summary }
}

function Update-NRGuiFromDiagnostics {
    $snapshot = Get-NRGuiDiagnostics
    Update-NRGuiStatusCards -Diagnostics $snapshot.Diagnostics -RestorePointSummary $snapshot.RestorePointSummary
    $snapshot
}

function Invoke-NRGuiRepair {
    param([Parameter(Mandatory)][bool]$Deep)

    Write-NRGuiLog -Message $(if ($Deep) { '开始深度修复流程…' } else { '开始安全修复流程…' }) -Kind 'Head'

    $snapshot = Get-NRGuiDiagnostics
    $diagnostics = $snapshot.Diagnostics
    $decision = Get-NRRepairDecision -Diagnostics $diagnostics -Deep:$Deep
    $plan = $decision.Plan

    if ($plan.IsNoOp) {
        Write-NRGuiLog -Message '没有需要执行的修复操作，未修改任何配置。' -Kind 'Ok'
        Update-NRGuiStatusCards -Diagnostics $diagnostics -RestorePointSummary $snapshot.RestorePointSummary
        [void][System.Windows.Forms.MessageBox]::Show(
            ("当前无需修复。" + "`r`n`r`n" + "网络健康状态：" + $diagnostics.NetworkHealth.Status + "`r`n" + $diagnostics.NetworkHealth.Reason),
            'NetworkRepair', 'OK', 'Information')
        return
    }

    $summaryText = Get-NRGuiPlanSummary -Plan $plan -Deep:$Deep
    $answer = [System.Windows.Forms.MessageBox]::Show($summaryText, $(if ($Deep) { '深度修复计划' } else { '安全修复计划' }), 'YesNo', 'Warning')
    if ($answer -ne 'Yes') {
        Write-NRGuiLog -Message '已取消，未修改任何配置。' -Kind 'Warn'
        return
    }

    $result = Invoke-NRRepair -Deep:$Deep -AssumeYes -SkipConnectivityTest
    if ($result.Cancelled) {
        Write-NRGuiLog -Message '修复被取消。' -Kind 'Warn'
        return
    }

    if ($result.Success) {
        Write-NRGuiLog -Message ('修复完成：删除 {0} 个历史 Profile。' -f $result.Changed) -Kind 'Ok'
        if ($result.Backup) { Write-NRGuiLog -Message ('恢复点：{0}' -f $result.Backup.Path) }
        $serviceRefresh = Get-NRPropertyValue -InputObject $result -Name 'ServiceRefresh'
        if ($serviceRefresh) { Write-NRGuiLog -Message ('服务刷新：{0}' -f $serviceRefresh.Message) -Kind $(if ($serviceRefresh.Degraded) { 'Warn' } else { 'Info' }) }
        $validation = Get-NRPropertyValue -InputObject $result -Name 'Validation'
        if ($validation) {
            Write-NRGuiLog -Message ('修复后验证：{0}；网络健康：{1}' -f $(if ($validation.Success) { '通过' } else { '未通过' }), $validation.Diagnostics.NetworkHealth.Status) -Kind $(if ($validation.Success) { 'Ok' } else { 'Error' })
        }
        [void][System.Windows.Forms.MessageBox]::Show(('修复完成，已删除 ' + $result.Changed + ' 个历史 Profile，修改前已自动创建恢复点。'), 'NetworkRepair', 'OK', 'Information')
    } else {
        Write-NRGuiLog -Message ('修复失败：{0}' -f $result.Error) -Kind 'Error'
        if ($result.Rollback) {
            Write-NRGuiLog -Message ('自动回滚：{0}' -f $(if ($result.Rollback.Success) { '成功，已恢复到修改前状态' } else { '失败：' + $result.Rollback.Error })) -Kind $(if ($result.Rollback.Success) { 'Warn' } else { 'Error' })
        }
        [void][System.Windows.Forms.MessageBox]::Show(('修复失败：' + "`r`n`r`n" + $result.Error), 'NetworkRepair', 'OK', 'Error')
    }

    [void](Update-NRGuiFromDiagnostics)
}

function Invoke-NRGuiBackup {
    Write-NRGuiLog -Message '正在创建手动恢复点…' -Kind 'Head'
    $backup = New-NRBackup -Level 'Manual'
    Write-NRGuiLog -Message ('恢复点已创建：{0}' -f $backup.Path) -Kind 'Ok'
    [void](Update-NRGuiFromDiagnostics)
    [void][System.Windows.Forms.MessageBox]::Show(('恢复点已创建：' + "`r`n" + $backup.Path), 'NetworkRepair', 'OK', 'Information')
}

function Invoke-NRGuiExportReport {
    Write-NRGuiLog -Message '正在导出脱敏诊断报告…' -Kind 'Head'
    $report = Export-NRReport -SkipConnectivityTest
    Write-NRGuiLog -Message ('报告已导出：{0}' -f $report.Path) -Kind 'Ok'
    [void][System.Windows.Forms.MessageBox]::Show(('诊断报告已导出（已脱敏）：' + "`r`n" + $report.Path), 'NetworkRepair', 'OK', 'Information')
}

function Invoke-NRGuiUpdateCheck {
    <#
        检查是否有新版本。**只检查、只跳转**：不下载、不替换自身。
        界面上给出结论，用户自己在浏览器里下载。
    #>
    param([switch]$Silent)

    Write-NRGuiLog -Message '正在检查更新（只访问 GitHub 公开的发布信息，不上报任何数据）…' -Kind 'Head'
    $update = Get-NRLatestRelease
    $message = Get-NRUpdateCheckMessage -Result $update
    Write-NRGuiLog -Message $message -Kind $(if ($update.IsNewer) { 'Warn' } elseif ($update.Success) { 'Ok' } else { 'Warn' })

    if ($Silent) { return $update }

    if (-not $update.Success) {
        [void][System.Windows.Forms.MessageBox]::Show(
            ('无法检查更新：' + "`r`n`r`n" + $update.Error + "`r`n`r`n" + '可能是当前网络无法访问 GitHub。这不影响其他功能。'),
            '检查更新', 'OK', 'Warning')
        return $update
    }
    if (-not $update.IsNewer) {
        [void][System.Windows.Forms.MessageBox]::Show(
            ('已是最新版本 ' + $update.CurrentVersion + '。'),
            '检查更新', 'OK', 'Information')
        return $update
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        ('发现新版本 ' + $update.Version + '（当前 ' + $update.CurrentVersion + '）。' + "`r`n`r`n" +
         '是否打开下载页面？本程序不会自动下载或替换自身，请自行确认后再替换。'),
        '检查更新', 'YesNo', 'Information')
    if ($answer -eq 'Yes' -and $update.Url) {
        try {
            Start-Process -FilePath $update.Url | Out-Null
        } catch {
            Write-NRGuiLog -Message ('无法打开浏览器：{0}' -f $_.Exception.Message) -Kind 'Warn'
        }
    }
    $update
}

function Show-NRGuiRestorePointDialog {
    Initialize-NRGuiAssemblies

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Name = 'restorePointDialog'
    $dialog.Text = '恢复点管理'
    $dialog.Size = New-Object System.Drawing.Size(820, 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = $script:NRGuiFont

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 46)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))

    $list = New-Object System.Windows.Forms.ListView
    $list.Name = 'restorePointList'
    $list.Dock = 'Fill'
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.GridLines = $true
    foreach ($column in @(
        [pscustomobject]@{ Text = '序号'; Width = 50 }
        [pscustomobject]@{ Text = '时间'; Width = 160 }
        [pscustomobject]@{ Text = '等级'; Width = 100 }
        [pscustomobject]@{ Text = '目录'; Width = 210 }
        [pscustomobject]@{ Text = '状态'; Width = 230 }
    )) {
        [void]$list.Columns.Add($column.Text, $column.Width)
    }

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Fill'
    $buttons.Padding = New-Object System.Windows.Forms.Padding(6, 6, 6, 0)
    foreach ($spec in @(
        [pscustomobject]@{ Name = 'btnRestore';     Text = '从选中恢复点恢复' }
        [pscustomobject]@{ Name = 'btnPin';         Text = '固定 / 取消固定' }
        [pscustomobject]@{ Name = 'btnPrune';       Text = '清理超出额度' }
        [pscustomobject]@{ Name = 'btnRefreshPts';  Text = '刷新' }
        [pscustomobject]@{ Name = 'btnClosePts';    Text = '关闭' }
    )) {
        $button = New-Object System.Windows.Forms.Button
        $button.Name = $spec.Name
        $button.Text = $spec.Text
        $button.AutoSize = $true
        $button.Padding = New-Object System.Windows.Forms.Padding(8, 3, 8, 3)
        $button.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
        [void]$buttons.Controls.Add($button)
    }

    $hint = New-Object System.Windows.Forms.Label
    $hint.Dock = 'Fill'
    $hint.TextAlign = 'MiddleLeft'
    $hint.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
    $hint.Text = '安全点（PreRepair / PreRestore）与已固定的恢复点享有更高保留下限；清理只删除超出额度的恢复点。'

    [void]$layout.Controls.Add($list, 0, 0)
    [void]$layout.Controls.Add($buttons, 0, 1)
    [void]$layout.Controls.Add($hint, 0, 2)
    [void]$dialog.Controls.Add($layout)

    $state = [pscustomobject]@{ Points = @() }

    $refresh = {
        $list.Items.Clear()
        $state.Points = @(Get-NRRestorePoints)
        foreach ($point in $state.Points) {
            $flags = New-Object System.Collections.Generic.List[string]
            if ($point.IsSafetyPoint) { [void]$flags.Add('安全点') }
            if ($point.Pinned) { [void]$flags.Add('已固定') }
            if (-not $point.IsIntact) { [void]$flags.Add('完整性：' + $point.Integrity) }
            $item = New-Object System.Windows.Forms.ListViewItem([string]$point.Index)
            [void]$item.SubItems.Add($point.Created.ToString('yyyy-MM-dd HH:mm:ss'))
            [void]$item.SubItems.Add($point.Level)
            [void]$item.SubItems.Add($point.Name)
            [void]$item.SubItems.Add(($flags -join ' / '))
            $item.Tag = $point
            [void]$list.Items.Add($item)
        }
        if ($state.Points.Count -eq 0) { $hint.Text = '还没有任何恢复点：执行一次修复或手动备份后就会出现。' }
    }

    $selectedPoint = {
        if ($list.SelectedItems.Count -eq 0) { return $null }
        $list.SelectedItems[0].Tag
    }

    $buttons.Controls['btnRefreshPts'].Add_Click({ & $refresh }.GetNewClosure())
    $buttons.Controls['btnClosePts'].Add_Click({ $dialog.Close() })

    # 操作体通过 -ArgumentList 显式接收所需变量，避免依赖脚本块的作用域继承。
    $buttons.Controls['btnRestore'].Add_Click({
        $point = & $selectedPoint
        if (-not $point) { [void][System.Windows.Forms.MessageBox]::Show('请先在列表中选择一个恢复点。', 'NetworkRepair', 'OK', 'Information'); return }
        if (-not $point.IsIntact) { [void][System.Windows.Forms.MessageBox]::Show('所选恢复点完整性异常，已拒绝使用。', 'NetworkRepair', 'OK', 'Error'); return }
        $answer = [System.Windows.Forms.MessageBox]::Show(('即将从恢复点 [' + $point.Index + '] ' + $point.Name + ' 恢复。' + "`r`n`r`n" + '确认继续吗？'), '确认恢复', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        Invoke-NRGuiOperation -StatusText '正在恢复…' -ArgumentList @($point, $refresh) -Action {
            param($point, $refresh)
            $result = Restore-NRBackup -RestorePointIndex $point.Index -AssumeYes
            if ($result.Success) {
                Write-NRGuiLog -Message ('恢复完成：{0}' -f $result.Path) -Kind 'Ok'
            } else {
                Write-NRGuiLog -Message ('恢复失败：{0}' -f $result.Error) -Kind 'Error'
            }
            & $refresh
            [void](Update-NRGuiFromDiagnostics)
        }
    }.GetNewClosure())

    $buttons.Controls['btnPin'].Add_Click({
        $point = & $selectedPoint
        if (-not $point) { [void][System.Windows.Forms.MessageBox]::Show('请先在列表中选择一个恢复点。', 'NetworkRepair', 'OK', 'Information'); return }
        Invoke-NRGuiOperation -StatusText '正在更新固定标记…' -ArgumentList @($point, $refresh) -Action {
            param($point, $refresh)
            $result = Set-NRRestorePointPin -Path $point.Path -Pinned:(-not $point.Pinned)
            Write-NRGuiLog -Message ('恢复点 [{0}] 固定标记：{1}' -f $result.Index, $result.Pinned) -Kind 'Ok'
            & $refresh
        }
    }.GetNewClosure())

    $buttons.Controls['btnPrune'].Add_Click({
        $plan = Get-NRRestorePointRetentionPlan -RestorePoints @(Get-NRRestorePoints)
        if ($plan.RemoveCount -eq 0) {
            [void][System.Windows.Forms.MessageBox]::Show('没有超出保留额度的恢复点，无需清理。', 'NetworkRepair', 'OK', 'Information')
            return
        }
        $lines = @($plan.Remove | ForEach-Object { '  · [{0}] {1}  {2}' -f $_.Index, $_.Created.ToString('yyyy-MM-dd HH:mm:ss'), $_.Name })
        $answer = [System.Windows.Forms.MessageBox]::Show(('将删除 ' + $plan.RemoveCount + ' 个超出保留额度的恢复点：' + "`r`n`r`n" + ($lines -join "`r`n") + "`r`n`r`n" + '删除后无法再通过本工具恢复。继续吗？'), '确认清理', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        Invoke-NRGuiOperation -StatusText '正在清理恢复点…' -ArgumentList @($plan, $refresh) -Action {
            param($plan, $refresh)
            $result = Invoke-NRRestorePointPrune -Plan $plan -AssumeYes
            Write-NRGuiLog -Message ('清理结果：删除 {0} 个，剩余 {1} 个。{2}' -f $result.RemovedCount, $result.RemainingCount, $result.Message) -Kind $(if ($result.Success) { 'Ok' } else { 'Warn' })
            & $refresh
            [void](Update-NRGuiFromDiagnostics)
        }
    }.GetNewClosure())

    & $refresh
    [void]$dialog.ShowDialog($script:NRGuiForm)
    $dialog.Dispose()
    [void](Update-NRGuiFromDiagnostics)
}

function Show-NRGui {
    Initialize-NRGuiAssemblies
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

    # 界面自己渲染日志：把既有函数的输出切到静默分支，避免向不存在的控制台写内容。
    $Json = $true
    $NoColor = $true

    $form = New-NRGuiForm
    $script:NRGuiForm = $form
    $script:NRGuiFont = $form.Font
    $script:NRGuiLog = $form.Controls['rootLayout'].Controls['logBox']
    $script:NRGuiStatus = $form.Controls['rootLayout'].Controls['statusPanel'].Controls['statusLabel']
    $script:NRGuiCards = @()
    $script:NRGuiButtons = @()
    $script:NRGuiBusy = $false

    $cardsPanel = $form.Controls['rootLayout'].Controls['cardsPanel']
    for ($i = 0; $i -lt 5; $i++) { $script:NRGuiCards += $cardsPanel.GetControlFromPosition($i, 0) }

    $buttonsPanel = $form.Controls['rootLayout'].Controls['buttonsPanel']
    foreach ($control in @($buttonsPanel.Controls)) { $script:NRGuiButtons += $control }

    $handlers = @{
        Diagnose = {
            Invoke-NRGuiOperation -StatusText '正在诊断…' -Action {
                $snapshot = Update-NRGuiFromDiagnostics
                $health = $snapshot.Diagnostics.NetworkHealth
                Write-NRGuiLog -Message ('诊断完成：网络健康={0}；可安全清理={1} 个。' -f $health.Status, $snapshot.Diagnostics.SafeCandidateCount) -Kind 'Ok'
                Write-NRGuiLog -Message ('结论：{0}' -f $health.Reason)
            }
        }
        SafeRepair   = { Invoke-NRGuiOperation -StatusText '正在执行安全修复…' -Action { Invoke-NRGuiRepair -Deep $false } }
        DeepRepair   = { Invoke-NRGuiOperation -StatusText '正在执行深度修复…' -Action { Invoke-NRGuiRepair -Deep $true } }
        Backup       = { Invoke-NRGuiOperation -StatusText '正在创建恢复点…' -Action { Invoke-NRGuiBackup } }
        ExportReport = { Invoke-NRGuiOperation -StatusText '正在导出诊断报告…' -Action { Invoke-NRGuiExportReport } }
        RestorePoints = { Invoke-NRGuiOperation -StatusText '正在读取恢复点…' -Action { Show-NRGuiRestorePointDialog } }
        OpenLogs = {
            if (Test-Path -LiteralPath $Script:Logs) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $Script:Logs) | Out-Null }
        }
        CheckUpdate = { Invoke-NRGuiOperation -StatusText '正在检查更新…' -Action { [void](Invoke-NRGuiUpdateCheck) } }
        About = {
            [void][System.Windows.Forms.MessageBox]::Show(
                ('NetworkRepair v' + $Script:AppVersion + "`r`n`r`n" +
                 'Windows 网络配置诊断与修复工具' + "`r`n" +
                 '安全原则：先诊断 → 先备份 → 再修改 → 最后验证' + "`r`n`r`n" +
                 '高级用户仍可使用命令行版本（备用启动目录中的批处理或 NetworkRepair.single.ps1）。'),
                '关于 NetworkRepair', 'OK', 'Information')
        }
    }

    foreach ($button in $script:NRGuiButtons) {
        $key = [string]$button.Tag
        if ($handlers.ContainsKey($key)) { $button.Add_Click($handlers[$key]) }
    }

    $form.Add_Shown({
        Write-NRGuiLog -Message ('NetworkRepair v{0} 已启动。' -f $Script:AppVersion) -Kind 'Head'
        Write-NRGuiLog -Message '安全原则：先诊断 → 先备份 → 再修改 → 最后验证。'
        Invoke-NRGuiOperation -StatusText '正在执行首次诊断…' -Action {
            $snapshot = Update-NRGuiFromDiagnostics
            $script:NRGuiStartupHealth = [string]$snapshot.Diagnostics.NetworkHealth.Status
            Write-NRGuiLog -Message ('网络健康={0}；可安全清理={1} 个；恢复点={2} 个。' -f $snapshot.Diagnostics.NetworkHealth.Status, $snapshot.Diagnostics.SafeCandidateCount, [int](Get-NRPropertyValue -InputObject $snapshot.RestorePointSummary -Name 'Total')) -Kind 'Ok'
        }
        # 启动时的更新检查只在网络健康时做：本工具常被用来修网络，网络不通时不要卡在这里。
        if ($script:NRGuiStartupHealth -ceq 'Healthy') {
            Invoke-NRGuiOperation -StatusText '正在检查更新…' -Action { [void](Invoke-NRGuiUpdateCheck -Silent) }
        } else {
            Write-NRGuiLog -Message '当前网络健康度不足，已跳过启动时的更新检查（可稍后手动点「检查更新」）。' -Kind 'Warn'
        }
    })

    try {
        [void]$form.ShowDialog()
    } finally {
        $form.Dispose()
        $script:NRGuiForm = $null
    }
}
