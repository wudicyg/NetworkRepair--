# 服务刷新策略：按操作实际影响范围决定是否刷新，按依赖顺序重启，在有界时间内等待服务与
# Network List Manager COM 恢复可用，并把结构化结果回传给调用方。
#
# 依赖关系：netprofm 依赖 NlaSvc。停止顺序为 netprofm → NlaSvc，启动顺序相反。
# 旧实现是「无条件 Restart-Service -Force + 固定 Start-Sleep 2 秒」：既无法证明服务真的
# 恢复，也无法把失败回传，还会在没有任何注册表改动时照样重启网络服务。

function Get-NRNetworkServiceDefinitions {
    # StopOrder 越小越先停；StartOrder 越小越先启动。
    @(
        [pscustomobject]@{ Name = 'NlaSvc';   DisplayName = 'Network Location Awareness'; StopOrder = 2; StartOrder = 1 }
        [pscustomobject]@{ Name = 'netprofm'; DisplayName = 'Network List Service';       StopOrder = 1; StartOrder = 2 }
    )
}

function Get-NRServiceRefreshPlan {
    param(
        [ValidateSet('Skip', 'NetworkList')][string]$Scope = 'NetworkList'
    )

    if ($Scope -eq 'Skip') {
        return [pscustomobject]@{
            Scope      = 'Skip'
            Required   = $false
            Reason     = '本次操作没有修改 NetworkList 注册表范围，无需刷新网络服务。'
            Services   = @()
            StopOrder  = @()
            StartOrder = @()
        }
    }

    $services = @(Get-NRNetworkServiceDefinitions)
    [pscustomobject]@{
        Scope      = 'NetworkList'
        Required   = $true
        Reason     = 'NetworkList\Profiles 或 NewNetworks 范围发生变化，需要刷新 NlaSvc 与 netprofm。'
        Services   = $services
        StopOrder  = @($services | Sort-Object StopOrder | Select-Object -ExpandProperty Name)
        StartOrder = @($services | Sort-Object StartOrder | Select-Object -ExpandProperty Name)
    }
}

function Test-NRServiceNameIn {
    param(
        [object[]]$Items = @(),
        [Parameter(Mandatory)][string]$Name
    )
    (@($Items | Where-Object { $_ -and $_.Name -ceq $Name }).Count -gt 0)
}

function Wait-NRServiceStatus {
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Running', 'Stopped')][string]$Status = 'Running',
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 20,
        [ValidateRange(100, 5000)][int]$IntervalMilliseconds = 500
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($service -and ([string]$service.Status -eq $Status)) { return $true }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Milliseconds $IntervalMilliseconds
    }
}

function Wait-NRNetworkListManagerReady {
    param(
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 20,
        [ValidateRange(100, 5000)][int]$IntervalMilliseconds = 1000
    )

    $attempts = 0
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $attempts++
        $probe = Get-NRNetworkListManagerNetworks
        if ($probe.Available) {
            return [pscustomobject]@{ Ready = $true; Attempts = $attempts; Error = $null }
        }
        if ((Get-Date) -ge $deadline) {
            return [pscustomobject]@{ Ready = $false; Attempts = $attempts; Error = $probe.Error }
        }
        Start-Sleep -Milliseconds $IntervalMilliseconds
    }
}

function Invoke-NRServiceRefresh {
    param(
        [ValidateSet('Skip', 'NetworkList')][string]$Scope = 'NetworkList',
        [ValidateRange(1, 300)][int]$ServiceTimeoutSeconds = 20,
        [ValidateRange(1, 300)][int]$ReadyTimeoutSeconds = 20,
        [ValidateRange(1, 5)][int]$StartAttempts = 2,
        [switch]$SkipReadinessProbe
    )

    $started = Get-Date
    $plan = Get-NRServiceRefreshPlan -Scope $Scope

    if (-not $plan.Required) {
        Write-NRSafeLog ('Service refresh skipped: {0}' -f $plan.Reason)
        return [pscustomobject]@{
            Scope            = 'Skip'
            Required         = $false
            Refreshed        = @()
            NotRunning       = @()
            Missing          = @()
            Failed           = @()
            Collateral       = @()
            ComReady         = $true
            ComProbeAttempts = 0
            Success          = $true
            Degraded         = $false
            DurationSeconds  = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
            Message          = $plan.Reason
            Plan             = $plan
        }
    }

    $refreshed = @()
    $notRunning = @()
    $missing = @()
    $failed = @()
    $collateral = @()

    foreach ($name in $plan.StopOrder) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $service) {
            $missing += $name
            Write-NRSafeLog ('Service not installed, skipped: {0}' -f $name) 'WARN'
            continue
        }
        if ([string]$service.Status -ne 'Running') {
            # 原本未运行的服务不主动启动，避免扩大修改范围，只如实记录。
            $notRunning += [pscustomobject]@{ Name = $name; Status = [string]$service.Status }
            Write-NRSafeLog ('Service not running, refresh skipped: {0} ({1})' -f $name, $service.Status) 'WARN'
            continue
        }

        # -Force 会连带停止依赖服务，先记录不在本策略清单内的依赖服务，稍后一并拉起。
        foreach ($dependent in @(Get-Service -Name $name -DependentServices -ErrorAction SilentlyContinue)) {
            if (($plan.Services | Select-Object -ExpandProperty Name) -notcontains $dependent.Name) {
                if (-not (Test-NRServiceNameIn -Items $collateral -Name $dependent.Name) -and [string]$dependent.Status -eq 'Running') {
                    $collateral += [pscustomobject]@{ Name = $dependent.Name; Status = 'Running' }
                    Write-NRSafeLog ('Recording dependent service for restart: {0}' -f $dependent.Name) 'WARN'
                }
            }
        }

        try {
            Write-NRSafeLog ('Stopping service for refresh: {0}' -f $name)
            Stop-Service -Name $name -Force -ErrorAction Stop
            if (-not (Wait-NRServiceStatus -Name $name -Status 'Stopped' -TimeoutSeconds $ServiceTimeoutSeconds)) {
                throw ('等待服务停止超时：{0}' -f $name)
            }
        } catch {
            $failed += [pscustomobject]@{ Name = $name; Phase = 'Stop'; Error = $_.Exception.Message }
            Write-NRSafeLog ('Service stop failed: {0} ({1})' -f $name, $_.Exception.Message) 'ERROR'
        }
    }

    $startTargets = @($plan.StartOrder) + @($collateral | Select-Object -ExpandProperty Name)
    foreach ($name in $startTargets) {
        if (Test-NRServiceNameIn -Items $notRunning -Name $name) { continue }
        if (Test-NRServiceNameIn -Items $failed -Name $name) { continue }
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { continue }

        $attempt = 0
        $started0 = $false
        $lastError = $null
        while ($attempt -lt $StartAttempts -and -not $started0) {
            $attempt++
            try {
                Write-NRSafeLog ('Starting service after refresh: {0} (attempt {1})' -f $name, $attempt)
                Start-Service -Name $name -ErrorAction Stop
                if (Wait-NRServiceStatus -Name $name -Status 'Running' -TimeoutSeconds $ServiceTimeoutSeconds) {
                    $started0 = $true
                } else {
                    $lastError = ('等待服务启动超时：{0}' -f $name)
                    Write-NRSafeLog $lastError 'WARN'
                }
            } catch {
                $lastError = $_.Exception.Message
                Write-NRSafeLog ('Service start attempt {0} failed: {1} ({2})' -f $attempt, $name, $lastError) 'WARN'
            }
        }

        if ($started0) {
            $refreshed += $name
        } else {
            $failed += [pscustomobject]@{ Name = $name; Phase = 'Start'; Error = $lastError }
            Write-NRSafeLog ('Service start failed after {0} attempt(s): {1}' -f $attempt, $name) 'ERROR'
        }
    }

    $comReady = $true
    $comAttempts = 0
    $comError = $null
    if (-not $SkipReadinessProbe) {
        $ready = Wait-NRNetworkListManagerReady -TimeoutSeconds $ReadyTimeoutSeconds
        $comReady = [bool]$ready.Ready
        $comAttempts = [int]$ready.Attempts
        $comError = $ready.Error
        if (-not $comReady) {
            Write-NRSafeLog ('Network List Manager COM did not become ready: {0}' -f $comError) 'ERROR'
        }
    }

    $success = ($failed.Count -eq 0)
    $degraded = ((-not $success) -or (-not $comReady))

    $message = '网络服务刷新完成，Network List Manager 已就绪。'
    if (-not $success) {
        $message = ('网络服务刷新存在失败项：{0}。' -f ((@($failed | ForEach-Object { '{0}({1})' -f $_.Name, $_.Phase }) -join '、')))
    } elseif (-not $comReady) {
        $message = '服务已刷新，但 Network List Manager COM 未在有界时间内就绪。'
    } elseif ($notRunning.Count -gt 0) {
        $message = ('网络服务刷新完成；{0} 个服务原本未运行，未主动启动。' -f $notRunning.Count)
    }

    [pscustomobject]@{
        Scope            = 'NetworkList'
        Required         = $true
        Refreshed        = @($refreshed)
        NotRunning       = @($notRunning)
        Missing          = @($missing)
        Failed           = @($failed)
        Collateral       = @($collateral)
        ComReady         = $comReady
        ComProbeAttempts = $comAttempts
        ComError         = $comError
        Success          = $success
        Degraded         = $degraded
        DurationSeconds  = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        Message          = $message
        Plan             = $plan
    }
}
