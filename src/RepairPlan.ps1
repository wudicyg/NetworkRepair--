function Get-NRRepairPlan {
    param(
        [object[]]$Candidates = @(),
        [switch]$Deep
    )

    $safe = @($Candidates | Where-Object { $_ -and $_.RemediationAllowed })
    $skipped = @($Candidates | Where-Object { $_ -and (-not $_.RemediationAllowed) })

    $actions = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $safe) {
        [void]$actions.Add([pscustomobject]@{
            Action = 'DeleteProfile'
            KeyName = $candidate.KeyName
            ProfileName = $candidate.ProfileName
            RiskLevel = $candidate.RiskLevel
            RiskScore = $candidate.RiskScore
            Reason = $candidate.Reason
        })
    }

    if ($Deep) {
        [void]$actions.Add([pscustomobject]@{
            Action = 'ClearNewNetworks'
            KeyName = $null
            ProfileName = $null
            RiskLevel = 'Caution'
            RiskScore = $null
            Reason = 'Deep Repair 请求刷新 NetworkList\NewNetworks。'
        })
    }

    [pscustomobject]@{
        Deep = [bool]$Deep
        SafeCandidates = @($safe)
        SkippedCandidates = @($skipped)
        Actions = @($actions)
        DeleteProfileCount = @($actions | Where-Object { $_.Action -eq 'DeleteProfile' }).Count
        ClearNewNetworksRequested = [bool](@($actions | Where-Object { $_.Action -eq 'ClearNewNetworks' }).Count)
        RequiresBackup = [bool]$actions.Count
        IsNoOp = ($actions.Count -eq 0)
    }
}
