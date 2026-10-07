function Invoke-NRValidation {
    param([Parameter(Mandatory)]$Before,[switch]$SkipConnectivityTest)
    Write-NRLog 'Starting post-repair validation.'
    $after = Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest
    $remaining = @($after.Candidates | Where-Object RemediationAllowed)
    $success = $true
    $reasons = New-Object System.Collections.Generic.List[string]

    foreach ($old in @($Before.Connections)) {
        $match = @($after.Connections | Where-Object InterfaceIndex -eq $old.InterfaceIndex)
        if ($match.Count -eq 0) {
            [void]$reasons.Add(('活动连接消失：InterfaceIndex={0}' -f $old.InterfaceIndex))
            $success = $false
        }
    }

    foreach ($oldIp in @($Before.IPConfiguration | Where-Object IPv4Gateway)) {
        $matchIp = @($after.IPConfiguration | Where-Object InterfaceIndex -eq $oldIp.InterfaceIndex)
        if ($matchIp.Count -eq 0) {
            [void]$reasons.Add(('IP 配置消失：InterfaceIndex={0}' -f $oldIp.InterfaceIndex))
            $success = $false
        } elseif (-not $matchIp[0].IPv4Gateway) {
            [void]$reasons.Add(('默认网关消失：InterfaceIndex={0}' -f $oldIp.InterfaceIndex))
            $success = $false
        }
    }

    if ($remaining.Count -gt 0) {
        [void]$reasons.Add(('仍存在 {0} 个可自动修复候选 Profile。' -f $remaining.Count))
        $success = $false
    }
    if (-not $SkipConnectivityTest -and (-not $after.Connectivity.DNS -or -not $after.Connectivity.TCP443)) {
        [void]$reasons.Add('NCSI DNS/HTTP 验证未通过。')
        $success = $false
    }

    Write-NRLog ('Validation result: Success={0}' -f $success)
    [pscustomobject]@{Success=$success;RemainingSafeCandidates=$remaining.Count;Diagnostics=$after;Reasons=@($reasons);Timestamp=(Get-Date).ToString('o')}
}
