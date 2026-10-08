function Get-NRRepairPlan {
    param(
        [object[]]$Candidates = @(),
        [switch]$Deep
    )

    $safe = @($Candidates | Where-Object { $_ -and $_.RemediationAllowed })
    $skipped = @($Candidates | Where-Object { $_ -and (-not $_.RemediationAllowed) })

    $actions = @()

    foreach ($candidate in $safe) {
        $actions += [pscustomobject]@{
            Action = 'DeleteProfile'
            KeyName = $candidate.KeyName
            ProfileName = $candidate.ProfileName
            RiskLevel = $candidate.RiskLevel
            RiskScore = $candidate.RiskScore
            Reason = $candidate.Reason
        }
    }

    if ($Deep) {
        $actions += [pscustomobject]@{
            Action = 'ClearNewNetworks'
            KeyName = $null
            ProfileName = $null
            RiskLevel = 'Caution'
            RiskScore = $null
            Reason = 'Deep Repair 请求刷新 NetworkList\NewNetworks。'
        }
    }

    [pscustomobject]@{
        Deep = [bool]$Deep
        SafeCandidates = @($safe)
        SkippedCandidates = @($skipped)
        Actions = @($actions)
        DeleteProfileCount = @($actions | Where-Object { $_.Action -eq 'DeleteProfile' }).Count
        ClearNewNetworksRequested = [bool](($actions | Where-Object { $_.Action -eq 'ClearNewNetworks' }).Count -gt 0)
        RequiresBackup = [bool]($actions.Count -gt 0)
        IsNoOp = ($actions.Count -eq 0)
    }
}
