function Invoke-NRValidation {
    param([Parameter(Mandatory)]$Before,[switch]$SkipConnectivityTest)
    Write-NRLog 'Starting post-repair validation.';$after=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;$remaining=@($after.Candidates|Where-Object Risk -eq 'Low');$success=$true;$reasons=New-Object System.Collections.Generic.List[string]
    foreach($old in @($Before.Connections)){if(@($after.Connections|Where-Object InterfaceIndex -eq $old.InterfaceIndex).Count -eq 0){[void]$reasons.Add(('活动连接消失：InterfaceIndex={0}'-f $old.InterfaceIndex));$success=$false}}
    if($remaining.Count){[void]$reasons.Add(('仍存在 {0} 个低风险候选 Profile。'-f $remaining.Count));$success=$false}
    if(-not $SkipConnectivityTest -and (-not $after.Connectivity.DNS -or -not $after.Connectivity.TCP443)){[void]$reasons.Add('Internet/DNS 验证未通过。');$success=$false}
    Write-NRLog ('Validation result: Success={0}'-f $success);[pscustomobject]@{Success=$success;RemainingSafeCandidates=$remaining.Count;Diagnostics=$after;Reasons=@($reasons);Timestamp=(Get-Date).ToString('o')}
}
