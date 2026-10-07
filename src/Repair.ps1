function Remove-NRProfile {
    param([Parameter(Mandatory)]$Profile)
    if ($Profile.IsActive) { throw ('拒绝删除当前活动 Profile：{0}' -f $Profile.ProfileName) }
    if (-not $Profile.RemediationAllowed) { throw ('拒绝删除未通过自动修复安全门槛的 Profile：{0}' -f $Profile.ProfileName) }
    Write-NRLog ('Removing profile {0} ({1})' -f $Profile.ProfileName, $Profile.KeyName)
    Remove-Item -LiteralPath $Profile.RegistryPath -Recurse -Force -ErrorAction Stop
}

function Invoke-NRRepair {
    param([switch]$Deep,[switch]$DryRun,[switch]$AssumeYes,[switch]$SkipConnectivityTest)
    $d = Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest
    $safe = @($d.Candidates | Where-Object RemediationAllowed)
    $high = @($d.Candidates | Where-Object { -not $_.RemediationAllowed })
    if (-not $Json) { Show-NRDiagnostics -Diagnostics $d }

    if ($safe.Count -eq 0) {
        Write-NRLine '没有可安全自动处理的 Profile。' 'Green'
        Write-NRLog 'No safe repair candidates.'
        return [pscustomobject]@{Success=$true;Changed=0;Candidates=@();Backup=$null;Validation=$null;Deep=[bool]$Deep;DryRun=[bool]$DryRun}
    }

    $plan = @{
        SafeProfileDeletions = @($safe | Select-Object KeyName,ProfileName,RiskScore,RiskLevel,Reason,DiagnosticCodes,LastWrite)
        HighRiskSkipped = @($high | Select-Object KeyName,ProfileName,RiskScore,RiskLevel,Reason,DiagnosticCodes)
        DeepRequested = [bool]$Deep
    }

    if (-not $Json) {
        Write-NRSection $(if ($Deep) { '深度修复计划' } else { '安全修复计划' })
        foreach ($p in $safe) { Write-NRLine ('[DELETE] {0} | risk={1}/{2}' -f $p.ProfileName,$p.RiskLevel,$p.RiskScore) 'Yellow' }
        if ($high.Count) { Write-NRLine ('[SKIP] 已跳过 {0} 个需人工确认的项。' -f $high.Count) 'Red' }
    }

    if ($DryRun) {
        Write-NRLog 'Dry Run completed. No changes made.'
        return [pscustomobject]@{Success=$true;Changed=0;Candidates=$plan.SafeProfileDeletions;Backup=$null;Validation=$d;Deep=[bool]$Deep;DryRun=$true;Plan=$plan}
    }

    if (-not (Confirm-NRAction -Message '将按上述计划修改网络 Profile。执行前会自动创建完整备份，继续？' -AssumeYes:$AssumeYes)) {
        Write-NRLog 'Repair cancelled by user.' 'WARN'
        return [pscustomobject]@{Success=$false;Changed=0;Cancelled=$true;Candidates=$plan.SafeProfileDeletions;Backup=$null;Plan=$plan}
    }

    $backup = New-NRBackup
    $changed = 0
    try {
        foreach ($p in $safe) { Remove-NRProfile -Profile $p; $changed++ }
        if ($Deep) { Clear-NRNewNetworks }
        Restart-NRNetworkServices
        $validation = Invoke-NRValidation -Before $d -SkipConnectivityTest:$SkipConnectivityTest
        if (-not $validation.Success) { throw '修复后验证失败，准备自动回滚。' }
        Write-NRLog ('Repair succeeded. Changed={0}' -f $changed)
        [pscustomobject]@{Success=$true;Changed=$changed;Candidates=$plan.SafeProfileDeletions;Backup=$backup;Validation=$validation;Deep=[bool]$Deep;DryRun=$false;Plan=$plan}
    }
    catch {
        Write-NRLog ('Repair failed: {0}' -f $_.Exception.Message) 'ERROR'
        $restore = Restore-NRBackup -BackupPath $backup.Path -AssumeYes:$true
        [pscustomobject]@{Success=$false;Changed=$changed;Error=$_.Exception.Message;Backup=$backup;Rollback=$restore;Plan=$plan}
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
