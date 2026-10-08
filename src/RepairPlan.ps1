function Get-NRNetworkHealthAssessment {
    param(
        [object[]]$Connections = @(),
        [object]$NCSI = $null
    )

    $connections = @($Connections)
    $internetProfiles = @($connections | Where-Object {
        ([string]$_.IPv4Connectivity -eq 'Internet') -or
        ([string]$_.IPv6Connectivity -eq 'Internet')
    })

    $ncsiKnown = $null -ne $NCSI -and -not [bool]$NCSI.Skipped
    $ncsiHealthy = $ncsiKnown -and [bool]$NCSI.Dns -and [bool]$NCSI.Http
    $ncsiFailed = $ncsiKnown -and (-not [bool]$NCSI.Dns) -and (-not [bool]$NCSI.Http)

    if ($ncsiHealthy) {
        $status = 'Healthy'
        $reason = 'NCSI DNS 与 HTTP 探测均成功，网络具备正常 Internet 连通性。'
    } elseif ($internetProfiles.Count -gt 0 -and -not $ncsiFailed) {
        $status = 'Healthy'
        $reason = '连接 Profile 报告 Internet 连通性。'
    } elseif ($connections.Count -eq 0) {
        $status = 'Disconnected'
        $reason = '未读取到当前连接 Profile。'
    } elseif ($ncsiFailed) {
        $status = 'Degraded'
        $reason = 'NCSI DNS 与 HTTP 探测均失败。'
    } elseif ($internetProfiles.Count -eq 0) {
        $status = 'Degraded'
        $reason = '当前连接未报告 Internet 连通性。'
    } else {
        $status = 'Unknown'
        $reason = '现有网络信号不足以可靠判断整体连通性。'
    }

    [pscustomobject]@{
        Status = $status
        OperationallyHealthy = ($status -eq 'Healthy')
        Reason = $reason
        NCSIHealthy = $ncsiHealthy
        NCSIKnown = $ncsiKnown
        InternetProfileCount = $internetProfiles.Count
    }
}

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

    $deleteCount=@($actions | Where-Object { $_.Action -eq 'DeleteProfile' }).Count
    $clearRequested=(@($actions | Where-Object { $_.Action -eq 'ClearNewNetworks' }).Count -gt 0)
    $requiresBackup=($actions.Count -gt 0)
    $isNoOp=($actions.Count -eq 0)

    [pscustomobject]@{
        Deep = [bool]$Deep
        SafeCandidates = @($safe)
        SkippedCandidates = @($skipped)
        Actions = @($actions)
        DeleteProfileCount = $deleteCount
        ClearNewNetworksRequested = $clearRequested
        RequiresBackup = $requiresBackup
        IsNoOp = $isNoOp
    }
}

function Get-NRRepairDecision {
    param(
        [Parameter(Mandatory)]$Diagnostics,
        [switch]$Deep
    )

    $plan = Get-NRRepairPlan -Candidates $Diagnostics.Candidates -Deep:$Deep
    $numberedProfiles = @($Diagnostics.Candidates | Where-Object {
        $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
    })

    $profileHygieneStatus = if ($plan.DeleteProfileCount -gt 0) {
        'HistoricalProfilesFound'
    } elseif ($numberedProfiles.Count -gt 0) {
        'ProtectedNumberedProfilesPresent'
    } else {
        'Clean'
    }

    if ($plan.DeleteProfileCount -gt 0) {
        $recommendation = if ($Diagnostics.NetworkHealth.Status -eq 'Healthy') {
            'CleanHistoricalProfiles'
        } else {
            'RepairAndCleanProfiles'
        }
    } elseif ($Diagnostics.NetworkHealth.Status -eq 'Healthy') {
        $recommendation = 'NoAction'
    } else {
        $recommendation = 'InvestigateNetwork'
    }

    [pscustomobject]@{
        NetworkHealth = $Diagnostics.NetworkHealth
        ProfileHygieneStatus = $profileHygieneStatus
        HistoricalProfileCount = $plan.DeleteProfileCount
        NumberedProfileCount = $numberedProfiles.Count
        Recommendation = $recommendation
        Plan = $plan
    }
}
