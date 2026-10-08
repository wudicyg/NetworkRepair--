# 多级恢复点：把 backups/ 下累积的快照组织为可列举、可选择、可安全轮转的分级恢复点。
# 设计约束：
#   1. 只读优先——列举与策略计算绝不修改磁盘。
#   2. 删除必须显式确认，且只允许删除备份根目录的直接子目录。
#   3. 安全点（PreRepair / PreRestore）与已固定（Pinned）的恢复点享有更高保留下限。

function Write-NRRestorePointLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'WARN'
    )
    Write-NRSafeLog -Message $Message -Level $Level
}

function Get-NRRestorePointLevelName {
    param([object]$Level)

    if ($null -eq $Level -or [string]::IsNullOrWhiteSpace([string]$Level)) {
        return 'Manual'
    }

    $normalized = ([string]$Level).Trim()
    if ($normalized -eq 'Manual') { return 'Manual' }
    if ($normalized -eq 'PreRepair') { return 'PreRepair' }
    if ($normalized -eq 'PreRestore') { return 'PreRestore' }

    # 未知等级不做猜测，交由保留策略保守保留。
    'Unknown'
}

function Get-NRRestorePointRequiredFiles {
    @('NetworkList.reg', 'NetworkList-Profiles.reg')
}

function Get-NRRestorePoint {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $name = Split-Path -Leaf $resolvedPath
    $manifestPath = Join-Path $resolvedPath 'manifest.json'

    $manifest = $null
    $manifestState = 'Ok'
    $manifestError = $null
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $manifestState = 'Missing'
    } else {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            $manifestState = 'Unreadable'
            $manifestError = $_.Exception.Message
        }
    }

    $level = 'Manual'
    $pinned = $false
    $version = $null
    $computerName = $null
    $recordedTimestamp = $null
    if ($manifest) {
        $level = Get-NRRestorePointLevelName -Level (Get-NRPropertyValue -InputObject $manifest -Name 'Level')
        $pinned = [bool](Get-NRPropertyValue -InputObject $manifest -Name 'Pinned')
        $version = Get-NRPropertyValue -InputObject $manifest -Name 'Version'
        $computerName = Get-NRPropertyValue -InputObject $manifest -Name 'ComputerName'
        $recordedTimestamp = Get-NRPropertyValue -InputObject $manifest -Name 'Timestamp'
    }

    $created = $null
    if ($recordedTimestamp) {
        try {
            $created = [datetime]::Parse([string]$recordedTimestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        } catch {
            $created = $null
        }
    }
    if (-not $created -and $name -match '^\d{8}_\d{6}_\d{3}$') {
        try {
            $created = [datetime]::ParseExact($name, 'yyyyMMdd_HHmmss_fff', [Globalization.CultureInfo]::InvariantCulture)
        } catch {
            $created = $null
        }
    }
    if (-not $created) {
        $created = (Get-Item -LiteralPath $resolvedPath).LastWriteTime
    }

    $missingFiles = @(Get-NRRestorePointRequiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $resolvedPath $_)) })

    $integrity = 'Ok'
    if ($manifestState -eq 'Unreadable') { $integrity = 'Unreadable' }
    elseif ($missingFiles.Count -gt 0) { $integrity = 'Incomplete' }
    elseif ($manifestState -eq 'Missing') { $integrity = 'NoManifest' }

    [pscustomobject]@{
        Index         = $null
        Name          = $name
        Path          = $resolvedPath
        Created       = $created
        Level         = $level
        Pinned        = $pinned
        Version       = $version
        ComputerName  = $computerName
        Integrity     = $integrity
        IsIntact      = ($integrity -eq 'Ok')
        ManifestState = $manifestState
        ManifestError = $manifestError
        MissingFiles  = @($missingFiles)
        IsSafetyPoint = (($level -eq 'PreRepair') -or ($level -eq 'PreRestore'))
    }
}

function Resolve-NRRestorePointRoot {
    param([string]$BackupRoot)

    if (-not [string]::IsNullOrWhiteSpace($BackupRoot)) { return $BackupRoot }
    [string](Get-Variable -Name 'Backups' -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
}

function Get-NRRestorePoints {
    param([string]$BackupRoot)

    $root = Resolve-NRRestorePointRoot -BackupRoot $BackupRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return @() }
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $points = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        try {
            $points += (Get-NRRestorePoint -Path $directory.FullName)
        } catch {
            Write-NRRestorePointLog -Message ('Restore point skipped: {0} ({1})' -f $directory.FullName, $_.Exception.Message)
        }
    }

    $ordered = @($points | Sort-Object -Property Created -Descending)
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $ordered[$i].Index = $i + 1
    }
    @($ordered)
}

function Resolve-NRRestorePoint {
    param(
        [Parameter(Mandatory)][object[]]$RestorePoints,
        [Parameter(Mandatory)][int]$Index
    )

    $points = @($RestorePoints | Where-Object { $_ })
    if ($points.Count -eq 0) {
        throw '当前没有任何恢复点可供选择。'
    }

    $selected = @($points | Where-Object { $_.Index -eq $Index })
    if ($selected.Count -eq 0) {
        throw ('恢复点序号超出范围：{0}（当前共 {1} 个恢复点）。' -f $Index, $points.Count)
    }
    if (-not $selected[0].IsIntact) {
        throw ('所选恢复点完整性异常（{0}），拒绝使用：{1}' -f $selected[0].Integrity, $selected[0].Path)
    }

    $selected[0]
}

function Get-NRRestorePointSafetyLevels {
    @('PreRepair', 'PreRestore')
}

function Get-NRRestorePointRetentionPlan {
    param(
        [object[]]$RestorePoints = @(),
        [ValidateRange(1, 1000)][int]$KeepPerLevel = 10,
        [ValidateRange(1, 1000)][int]$KeepSafetyPerLevel = 3
    )

    $points = @($RestorePoints | Where-Object { $_ })
    $safetyLevels = Get-NRRestorePointSafetyLevels
    $keep = @()
    $remove = @()

    foreach ($level in @($points | Select-Object -ExpandProperty Level -Unique)) {
        $ofLevel = @($points | Where-Object { $_.Level -eq $level } | Sort-Object -Property Created -Descending)

        $limit = $KeepPerLevel
        if ($safetyLevels -contains $level) {
            $limit = [Math]::Max($KeepPerLevel, $KeepSafetyPerLevel)
        }

        $position = 0
        foreach ($point in $ofLevel) {
            $position++

            $reason = $null
            if ($point.Pinned) {
                $reason = '已固定（Pinned），永不参与清理'
            } elseif ($level -eq 'Unknown') {
                $reason = '等级未知，保守保留'
            } elseif ($position -le $limit) {
                if ($safetyLevels -contains $level) {
                    $reason = ('安全点保留额度内（第 {0}/{1} 个）' -f $position, $limit)
                } else {
                    $reason = ('保留额度内（第 {0}/{1} 个）' -f $position, $limit)
                }
            }

            if ($reason) {
                $keep += [pscustomobject]@{
                    RestorePoint = $point
                    Path         = $point.Path
                    Name         = $point.Name
                    Created      = $point.Created
                    Level        = $point.Level
                    Index        = $point.Index
                    Pinned       = $point.Pinned
                    Integrity    = $point.Integrity
                    Reason       = $reason
                }
                continue
            }

            $removeReason = ('超出保留额度（第 {0} 个，额度 {1}）' -f $position, $limit)
            if (-not $point.IsIntact) {
                $removeReason = ('超出保留额度且完整性异常（{0}）' -f $point.Integrity)
            }
            $remove += [pscustomobject]@{
                RestorePoint = $point
                Path         = $point.Path
                Name         = $point.Name
                Created      = $point.Created
                Level        = $point.Level
                Index        = $point.Index
                Pinned       = $point.Pinned
                Integrity    = $point.Integrity
                Reason       = $removeReason
            }
        }
    }

    [pscustomobject]@{
        KeepPerLevel       = $KeepPerLevel
        KeepSafetyPerLevel = $KeepSafetyPerLevel
        TotalCount         = $points.Count
        KeepCount          = $keep.Count
        RemoveCount        = $remove.Count
        Keep               = @($keep)
        Remove             = @($remove)
        IsNoOp             = ($remove.Count -eq 0)
    }
}

function Get-NRRestorePointSummary {
    param(
        [string]$BackupRoot,
        [ValidateRange(1, 1000)][int]$KeepPerLevel = 10,
        [ValidateRange(1, 1000)][int]$KeepSafetyPerLevel = 3
    )

    $points = @(Get-NRRestorePoints -BackupRoot $BackupRoot)
    $plan = Get-NRRestorePointRetentionPlan -RestorePoints $points -KeepPerLevel $KeepPerLevel -KeepSafetyPerLevel $KeepSafetyPerLevel

    $newest = $null
    if ($points.Count -gt 0) { $newest = $points[0].Created }

    [pscustomobject]@{
        Total           = $points.Count
        Manual          = @($points | Where-Object { $_.Level -eq 'Manual' }).Count
        PreRepair       = @($points | Where-Object { $_.Level -eq 'PreRepair' }).Count
        PreRestore      = @($points | Where-Object { $_.Level -eq 'PreRestore' }).Count
        Pinned          = @($points | Where-Object { $_.Pinned }).Count
        NotIntact       = @($points | Where-Object { -not $_.IsIntact }).Count
        PruneCandidates = $plan.RemoveCount
        NewestCreated   = $newest
        Points          = $points
        Plan            = $plan
    }
}

function Invoke-NRRestorePointPrune {
    param(
        [Parameter(Mandatory)]$Plan,
        [string]$BackupRoot,
        [switch]$AssumeYes
    )

    $root = Resolve-NRRestorePointRoot -BackupRoot $BackupRoot
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
        throw '无法确定备份目录，清理中止。'
    }
    $resolvedRoot = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path

    $targets = @($Plan.Remove | Where-Object { $_ })
    if ($targets.Count -eq 0) {
        $remaining = @(Get-NRRestorePoints -BackupRoot $resolvedRoot)
        return [pscustomobject]@{
            Success        = $true
            Cancelled      = $false
            Verified       = $true
            Removed        = @()
            RemovedCount   = 0
            Failed         = @()
            Skipped        = @()
            RemainingCount = $remaining.Count
            Message        = '没有超出保留额度的恢复点，无需清理。'
        }
    }

    if (-not (Confirm-NRAction -Message ('即将删除 {0} 个超出保留额度的恢复点，删除后无法再通过本工具恢复。继续？' -f $targets.Count) -AssumeYes:$AssumeYes)) {
        $remaining = @(Get-NRRestorePoints -BackupRoot $resolvedRoot)
        return [pscustomobject]@{
            Success        = $false
            Cancelled      = $true
            Verified       = $false
            Removed        = @()
            RemovedCount   = 0
            Failed         = @()
            Skipped        = @()
            RemainingCount = $remaining.Count
            Message        = '用户取消了恢复点清理。'
        }
    }

    $removed = @()
    $failed = @()
    $skipped = @()
    foreach ($item in $targets) {
        $targetPath = [string]$item.Path
        $resolved = $null
        try {
            $resolved = (Resolve-Path -LiteralPath $targetPath -ErrorAction Stop).Path
        } catch {
            $resolved = $null
        }

        if (-not $resolved) {
            $skipped += [pscustomobject]@{ Path = $targetPath; Reason = '路径不存在，已跳过' }
            continue
        }

        # 安全护栏：只允许删除备份根目录的直接子目录，防止 manifest 被篡改后越权删除。
        if ((Split-Path -Parent $resolved) -ne $resolvedRoot) {
            $skipped += [pscustomobject]@{ Path = $resolved; Reason = '不在备份根目录的直接子目录中，已跳过' }
            continue
        }

        try {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
            $removed += $resolved
        } catch {
            $failed += [pscustomobject]@{ Path = $resolved; Error = $_.Exception.Message }
        }
    }

    $remaining = @(Get-NRRestorePoints -BackupRoot $resolvedRoot)
    $success = (($failed.Count -eq 0) -and (@($skipped).Count -eq 0))
    $verified = $success
    if ($null -ne $Plan.PSObject.Properties['TotalCount']) {
        $expectedRemaining = [int]$Plan.TotalCount - @($removed).Count
        $verified = ($success -and ($remaining.Count -eq $expectedRemaining))
    }

    $message = '恢复点清理完成。'
    if (-not $success) { $message = '恢复点清理未完全达成预期，请检查跳过与失败明细。' }
    elseif (-not $verified) { $message = '恢复点清理后剩余数量与预期不一致，请检查。' }

    [pscustomobject]@{
        Success        = $success
        Cancelled      = $false
        Verified       = $verified
        Removed        = @($removed)
        RemovedCount   = @($removed).Count
        Failed         = @($failed)
        Skipped        = @($skipped)
        RemainingCount = $remaining.Count
        Remaining      = @($remaining)
        Message        = $message
    }
}

function Set-NRRestorePointPin {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Pinned
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $manifestPath = Join-Path $resolvedPath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw ('恢复点缺少 manifest.json，无法修改固定标记：{0}' -f $resolvedPath)
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $manifest.PSObject.Properties['Pinned']) {
        $manifest.Pinned = [bool]$Pinned
    } else {
        $manifest | Add-Member -MemberType NoteProperty -Name 'Pinned' -Value ([bool]$Pinned)
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-NRRestorePointLog -Message ('Restore point pin updated: {0} -> Pinned={1}' -f $resolvedPath, [bool]$Pinned) -Level 'INFO'
    Get-NRRestorePoint -Path $resolvedPath
}

function Switch-NRRestorePointPin {
    param(
        [Parameter(Mandatory)][object[]]$RestorePoints,
        [Parameter(Mandatory)][int]$Index,
        [switch]$AssumeYes
    )

    $point = Resolve-NRRestorePoint -RestorePoints $RestorePoints -Index $Index
    $target = -not $point.Pinned

    if (-not (Confirm-NRAction -Message ('将恢复点 [{0}] {1} 的固定标记设为 {2}。继续？' -f $point.Index, $point.Name, $target) -AssumeYes:$AssumeYes)) {
        return [pscustomobject]@{ Success = $false; Cancelled = $true; Point = $point; Pinned = $point.Pinned }
    }

    $updated = Set-NRRestorePointPin -Path $point.Path -Pinned:$target
    [pscustomobject]@{ Success = $true; Cancelled = $false; Point = $updated; Pinned = $updated.Pinned }
}

function Show-NRRestorePointList {
    param([object[]]$RestorePoints = @())

    $points = @($RestorePoints | Where-Object { $_ })
    if ($points.Count -eq 0) {
        Write-NRLine '未发现任何恢复点。' 'Yellow'
        Write-NRLog 'No restore points found.'
        return
    }

    Write-NRLine ('可用恢复点（共 {0} 个，按时间新→旧）：' -f $points.Count) 'Cyan'
    foreach ($point in $points) {
        $flags = New-Object System.Collections.Generic.List[string]
        if ($point.IsSafetyPoint) { [void]$flags.Add('安全点') }
        if ($point.Pinned) { [void]$flags.Add('已固定') }
        if (-not $point.IsIntact) { [void]$flags.Add('完整性:' + $point.Integrity) }

        $flagText = ''
        if ($flags.Count -gt 0) { $flagText = '  [' + ($flags -join '/') + ']' }

        $color = 'White'
        if (-not $point.IsIntact) { $color = 'Yellow' }
        Write-NRLine ('  [{0}] {1}  {2,-10}  {3}{4}' -f $point.Index, $point.Created.ToString('yyyy-MM-dd HH:mm:ss'), $point.Level, $point.Name, $flagText) $color
    }
}

function Show-NRRestorePointPlan {
    param([Parameter(Mandatory)]$Plan)

    Write-NRSection '恢复点保留策略'
    Write-NRLine ('恢复点总数 {0}：保留 {1} 个，超出额度 {2} 个。' -f $Plan.TotalCount, $Plan.KeepCount, $Plan.RemoveCount) 'White'
    Write-NRLine ('保留策略：每级最多 {0} 个，安全点（PreRepair/PreRestore）至少 {1} 个，已固定恢复点永不清理。' -f $Plan.KeepPerLevel, $Plan.KeepSafetyPerLevel) 'DarkGray'

    if ($Plan.RemoveCount -eq 0) {
        Write-NRLine '无需清理，未超出保留额度。' 'Green'
        return
    }

    Write-NRLine '将删除以下恢复点：' 'Yellow'
    foreach ($item in $Plan.Remove) {
        Write-NRLine ('  [{0}] {1}  {2,-10}  {3}  ({4})' -f $item.Index, $item.Created.ToString('yyyy-MM-dd HH:mm:ss'), $item.Level, $item.Name, $item.Reason) 'Yellow'
    }
}

function Invoke-NRRestorePointPruneInteractive {
    param(
        [string]$BackupRoot,
        [switch]$AssumeYes
    )

    $points = @(Get-NRRestorePoints -BackupRoot $BackupRoot)
    $plan = Get-NRRestorePointRetentionPlan -RestorePoints $points
    Show-NRRestorePointPlan -Plan $plan
    if ($plan.RemoveCount -eq 0) { return $plan }

    $result = Invoke-NRRestorePointPrune -Plan $plan -BackupRoot $BackupRoot -AssumeYes:$AssumeYes
    if ($result.Cancelled) {
        Write-NRLine '已取消恢复点清理。' 'Yellow'
    } elseif ($result.Success) {
        Write-NRLine ('已删除 {0} 个恢复点，剩余 {1} 个。' -f $result.RemovedCount, $result.RemainingCount) 'Green'
    } else {
        Write-NRLine ('清理未完全成功：删除 {0} 个，失败 {1} 个。' -f $result.RemovedCount, @($result.Failed).Count) 'Red'
    }
    $result
}
