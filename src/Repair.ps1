function Remove-NRProfile {
    param([Parameter(Mandatory)]$Profile)
    if ($Profile.IsActive) { throw ('拒绝删除当前活动 Profile：{0}' -f $Profile.ProfileName) }
    if (-not $Profile.RemediationAllowed) { throw ('拒绝删除未通过自动修复安全门槛的 Profile：{0}' -f $Profile.ProfileName) }
    Write-NRLog ('Removing profile {0} ({1})' -f $Profile.ProfileName, $Profile.KeyName)
    Remove-Item -LiteralPath $Profile.RegistryPath -Recurse -Force -ErrorAction Stop
}

function Invoke-NRRepair {
    param([switch]$Deep,[switch]$AssumeYes,[switch]$SkipConnectivityTest)

    $d = Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest
    $decision = Get-NRRepairDecision -Diagnostics $d -Deep:$Deep
    $plan = $decision.Plan

    if (-not $Json) { Show-NRDiagnostics -Diagnostics $d }

    if ($plan.IsNoOp) {
        if ($decision.Recommendation -eq 'NoAction') {
            Write-NRLine '网络状态正常，且没有发现可安全清理的历史编号 Profile，无需修复。' 'Green'
        } elseif ($decision.Recommendation -eq 'InvestigateNetwork') {
            Write-NRLine '当前存在网络健康问题，但没有发现可自动清理的 Profile；建议先调查网络故障。' 'Yellow'
        } else {
            Write-NRLine '没有需要执行的修复操作。' 'Green'
        }
        Write-NRLog 'Repair plan is a no-op.'
        return [pscustomobject]@{
            Success=$true
            Changed=0
            Candidates=@()
            Backup=$null
            Validation=$null
            Deep=[bool]$Deep
            Plan=$plan
            Decision=$decision
        }
    }

    if (-not $Json) {
        Write-NRSection $(if ($Deep) { '深度修复计划' } else { '安全修复计划' })
        foreach ($action in @($plan.Actions)) {
            if ($action.Action -eq 'DeleteProfile') {
                Write-NRLine ('[DELETE] {0} | risk={1}/{2}' -f $action.ProfileName,$action.RiskLevel,$action.RiskScore) 'Yellow'
            } elseif ($action.Action -eq 'ClearNewNetworks') {
                Write-NRLine '[REFRESH] NetworkList\NewNetworks' 'Yellow'
            }
        }
        if ($plan.SkippedCandidates.Count) {
            Write-NRLine ('[SKIP] 已跳过 {0} 个未通过安全门槛的 Profile。' -f $plan.SkippedCandidates.Count) 'Red'
        }
    }


    if (-not (Confirm-NRAction -Message '将按上述计划修改网络配置。执行前会自动创建完整备份，继续？' -AssumeYes:$AssumeYes)) {
        Write-NRLog 'Repair cancelled by user.' 'WARN'
        if (-not $Json) {
            Write-NRLine '已取消，没有修改任何网络配置。' 'Yellow'
        }
        return [pscustomobject]@{
            Success=$false
            Changed=0
            Cancelled=$true
            Candidates=@($plan.SafeCandidates | Select-Object KeyName,ProfileName,RiskScore,RiskLevel,Reason,DiagnosticCodes,LastWrite)
            Backup=$null
            Plan=$plan
            Decision=$decision
        }
    }

    if (-not $Json) {
        Write-NRSection $(if ($Deep) { '执行修复' } else { '执行安全修复' })
        Write-NRLine '正在创建完整备份，请稍候...' 'Cyan'
    }
    Write-NRLog 'Repair execution started.'
    $backup = New-NRBackup -Level 'PreRepair'
    if (-not $Json) {
        Write-NRLine ('备份完成：{0}' -f $backup.Path) 'Green'
    }

    $changed = 0
    try {
        foreach ($candidate in @($plan.SafeCandidates)) {
            if (-not $Json) {
                Write-NRLine ('正在删除 Profile：{0}' -f $candidate.ProfileName) 'Yellow'
            }
            Remove-NRProfile -Profile $candidate
            $changed++
            if (-not $Json) {
                Write-NRLine ('已删除：{0}' -f $candidate.ProfileName) 'Green'
            }
        }

        if ($plan.ClearNewNetworksRequested) {
            if (-not $Json) {
                Write-NRLine '正在刷新 NetworkList\NewNetworks...' 'Yellow'
            }
            Clear-NRNewNetworks
            if (-not $Json) {
                Write-NRLine 'NewNetworks 刷新完成。' 'Green'
            }
        }

        if (-not $Json) {
            Write-NRLine '正在重启相关网络服务，请稍候...' 'Cyan'
        }
        Restart-NRNetworkServices
        if (-not $Json) {
            Write-NRLine '网络服务处理完成。' 'Green'
            Write-NRLine '正在进行修复后验证，请稍候...' 'Cyan'
        }

        $validation = Invoke-NRValidation -Before $d -SkipConnectivityTest:$SkipConnectivityTest
        if (-not $validation.Success) {
            throw '修复后验证失败，准备自动回滚。'
        }

        Write-NRLog ('Repair succeeded. Changed={0}' -f $changed)
        if (-not $Json) {
            Write-NRSection '修复完成'
            Write-NRLine ('修改数量：{0}' -f $changed) 'Green'
            if ($changed -gt 0) {
                Write-NRLine ('删除 Profile：{0}' -f ((@($plan.SafeCandidates | Select-Object -ExpandProperty ProfileName) -join '、'))) 'Green'
            }
            Write-NRLine ('备份：{0}' -f $backup.Path) 'Green'
            Write-NRLine '验证：通过' 'Green'
            Write-NRLine ('网络健康：{0}' -f $validation.Diagnostics.NetworkHealth.Status) 'Green'
            Write-NRLine ('剩余可安全清理 Profile：{0}' -f $validation.RemainingSafeCandidates) 'Green'
        }

        [pscustomobject]@{
            Success=$true
            Changed=$changed
            Candidates=@($plan.SafeCandidates | Select-Object KeyName,ProfileName,RiskScore,RiskLevel,Reason,DiagnosticCodes,LastWrite)
            Backup=$backup
            Validation=$validation
            Deep=[bool]$Deep
            Plan=$plan
            Decision=$decision
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-NRLog ('Repair failed: {0}' -f $errorMessage) 'ERROR'
        if (-not $Json) {
            Write-NRLine ('修复失败：{0}' -f $errorMessage) 'Red'
            Write-NRLine '正在使用刚才创建的备份自动回滚，请稍候...' 'Yellow'
        }

        $restore = Restore-NRBackup -BackupPath $backup.Path -AssumeYes:$true
        if (-not $Json) {
            if ($restore.Success) {
                Write-NRLine '自动回滚成功，系统已恢复到修复前状态。' 'Green'
                Write-NRLine ('回滚所用备份：{0}' -f $backup.Path) 'Green'
            } else {
                Write-NRLine ('自动回滚也失败：{0}' -f $restore.Error) 'Red'
                Write-NRLine ('请保留并手工使用备份恢复：{0}' -f $backup.Path) 'Red'
            }
        }

        [pscustomobject]@{
            Success=$false
            Changed=$changed
            Error=$errorMessage
            Backup=$backup
            Rollback=$restore
            Plan=$plan
            Decision=$decision
        }
    }
}

function Clear-NRNewNetworks {
    $path = Join-Path (Get-NRRegistryRoot) 'NewNetworks'
    if (-not (Test-Path -LiteralPath $path)) { return }
    Write-NRLog 'Deep repair: clearing NewNetworks contents only.'
    Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
    try { Remove-ItemProperty -LiteralPath $path -Name 'NetworkList' -ErrorAction SilentlyContinue } catch { }
}

function Restart-NRNetworkServices {
    foreach ($name in @('NlaSvc','netprofm')) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        try {
            if ($svc.Status -eq 'Running') {
                Write-NRLog ('Restarting service: {0}' -f $name)
                Restart-Service -Name $name -Force -ErrorAction Stop
            }
        } catch {
            Write-NRLog ('Could not restart {0}: {1}' -f $name,$_.Exception.Message) 'WARN'
        }
    }
    Start-Sleep -Seconds 2
}
