function Get-NRAdapters {
    try { @(Get-NetAdapter -ErrorAction Stop | Select-Object Name,InterfaceDescription,InterfaceIndex,Status,MacAddress,LinkSpeed,MediaType,Virtual) } catch { Write-NRLog ('Get-NetAdapter failed: {0}' -f $_.Exception.Message) 'WARN'; @() }
}
function Get-NRConnectionProfiles {
    try { @(Get-NetConnectionProfile -ErrorAction Stop | Select-Object Name,InterfaceAlias,InterfaceIndex,NetworkCategory,IPv4Connectivity,IPv6Connectivity,@{n='DomainAuthenticationKind';e={if ($_.PSObject.Properties.Name -contains 'DomainAuthenticationKind') {$_.DomainAuthenticationKind}else{$null}}}) } catch { Write-NRLog ('Get-NetConnectionProfile failed: {0}' -f $_.Exception.Message) 'WARN'; @() }
}
function Test-NRInternetConnectivity {
    param([switch]$Skip)
    if ($Skip) { return [pscustomobject]@{Skipped=$true;DNS=$null;TCP443=$null} }
    $dnsOk=$false;$tcpOk=$false
    try { Resolve-DnsName 'dns.msftncsi.com' -ErrorAction Stop | Out-Null;$dnsOk=$true } catch {}
    try { $tcpOk=[bool](Test-NetConnection -ComputerName 'dns.msftncsi.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) } catch {}
    [pscustomobject]@{Skipped=$false;DNS=$dnsOk;TCP443=$tcpOk}
}
function Invoke-NRScan { param([switch]$SkipConnectivityTest);Write-NRLog 'Starting diagnostic scan.';$d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;if(-not $Json){Show-NRDiagnostics -Diagnostics $d};Write-NRLog ('Diagnostic scan complete. SafeCandidates={0}, HighRisk={1}'-f $d.SafeCandidateCount,$d.HighRiskCount);$d }
function ConvertTo-NRSanitizedDiagnosticSummary {
    param([Parameter(Mandatory)]$Diagnostics)

    $appName = 'NetMedic'
    $appVersion = $null
    $appNameVariable = Get-Variable -Name AppName -Scope Script -ErrorAction SilentlyContinue
    $appVersionVariable = Get-Variable -Name AppVersion -Scope Script -ErrorAction SilentlyContinue
    if ($appNameVariable -and $appNameVariable.Value) { $appName = [string]$appNameVariable.Value }
    if ($appVersionVariable -and $appVersionVariable.Value) { $appVersion = [string]$appVersionVariable.Value }

    [pscustomobject]@{
        SchemaVersion = '1.0'
        Sanitized = $true
        ReadOnly = $true
        GeneratedAt = if ($Diagnostics.Timestamp) { [string]$Diagnostics.Timestamp } else { (Get-Date).ToString('o') }
        Application = $appName
        ApplicationVersion = $appVersion
        Windows = [pscustomobject]@{
            Caption = [string]$Diagnostics.Windows.Caption
            Version = [string]$Diagnostics.Windows.Version
            Build = [string]$Diagnostics.Windows.Build
            Architecture = [string]$Diagnostics.Windows.Architecture
            PowerShell = [string]$Diagnostics.Windows.PowerShell
        }
        NetworkHealth = $Diagnostics.NetworkHealth
        ProfileHygieneStatus = [string]$Diagnostics.ProfileHygieneStatus
        RepairRecommendation = [string]$Diagnostics.RepairRecommendation
        SafeCandidateCount = [int]$Diagnostics.SafeCandidateCount
        HighRiskCount = [int]$Diagnostics.HighRiskCount
        NumberedProfileCount = @($Diagnostics.Candidates | Where-Object {
            $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network) +[0-9]+
    param([string]$Path,[switch]$SkipConnectivityTest)
    if(!$Path){$Path=Join-Path $Script:Reports ('NetMedic_Report_{0}.json'-f (Get-Date -Format 'yyyyMMdd_HHmmss'))}
    $d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;$d|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8
    Write-NRLog ('Diagnostic report exported: {0}'-f $Path);[pscustomobject]@{Success=$true;Path=$Path;Diagnostics=$d}
}


function Get-NRIPDiagnostics {
    $rows = @()
    try {
        $configs = @(Get-NetIPConfiguration -All -ErrorAction Stop)
        foreach ($cfg in $configs) {
            $index = [int]$cfg.InterfaceIndex
            $ipv4Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ipv6Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue
            $dns4 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $dns6 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $gateway = @()

            $ipv4Addresses = @()
            $ipv4Property = $cfg.PSObject.Properties['IPv4Address']
            if ($null -ne $ipv4Property -and $null -ne $ipv4Property.Value) {
                $ipv4Addresses = @($ipv4Property.Value | ForEach-Object { [string]$_.IPv4Address })
            }

            $ipv6Addresses = @()
            $ipv6Property = $cfg.PSObject.Properties['IPv6Address']
            if ($null -ne $ipv6Property -and $null -ne $ipv6Property.Value) {
                $ipv6Addresses = @($ipv6Property.Value | ForEach-Object { [string]$_.IPv6Address })
            }

            $gatewayProperty = $cfg.PSObject.Properties['IPv4DefaultGateway']
            if ($null -ne $gatewayProperty -and $null -ne $gatewayProperty.Value) {
                $gateway = @($gatewayProperty.Value | Where-Object { $_ } | ForEach-Object {
                    if ($_.PSObject.Properties['NextHop']) { [string]$_.NextHop }
                } | Where-Object { $_ })
            }

            $rows += [pscustomobject]@{
                InterfaceAlias = [string]$cfg.InterfaceAlias
                InterfaceIndex = $index
                IPv4Addresses = @($ipv4Addresses)
                IPv6Addresses = @($ipv6Addresses)
                IPv4Gateway = @($gateway)
                IPv4Dhcp = if ($ipv4Interface) { [string]$ipv4Interface.Dhcp } else { $null }
                IPv6Dhcp = if ($ipv6Interface) { [string]$ipv6Interface.Dhcp } else { $null }
                DnsServersIPv4 = @($dns4)
                DnsServersIPv6 = @($dns6)
            }
        }
    }
    catch {
        Write-NRLog ('IP diagnostics failed: {0}' -f $_.Exception.Message) 'WARN'
    }
    @($rows)
}

function Test-NRGateways {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.IPv4Gateway })) {
        foreach ($gateway in @($cfg.IPv4Gateway)) {
            $ok = $false
            try { $ok = [bool](Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Gateway = $gateway; Reachable = $ok }
        }
    }
    @($results)
}

function Test-NRDnsServers {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.DnsServersIPv4 })) {
        foreach ($server in @($cfg.DnsServersIPv4)) {
            $ok = $false
            try { Resolve-DnsName -Name 'dns.msftncsi.com' -Server $server -Type A -ErrorAction Stop | Out-Null; $ok = $true } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Server = $server; ResolvesNCSI = $ok }
        }
    }
    @($results)
}


function Get-NRSuspiciousProfiles {
    param(
        [Parameter(Mandatory)][object[]]$RegistryProfiles,
        [string[]]$ActiveNames = @(),
        [string[]]$NlmActiveNames = @(),
        [object[]]$IdentityCorrelations = @()
    )
    $activeSet = @{}
    foreach ($n in @($ActiveNames + $NlmActiveNames)) { if ($n) { $activeSet[$n.ToLowerInvariant()] = $true } }
    $identityIndex = @{}
    foreach ($i in @($IdentityCorrelations)) { if ($i.ProfileKeyName) { $identityIndex[(Normalize-NRGuidKey -Value $i.ProfileKeyName)] = $i } }

    foreach ($p in $RegistryProfiles) {
        if ([string]::IsNullOrWhiteSpace($p.ProfileName)) { continue }
        $name = $p.ProfileName.Trim()
        $numbered = $name -match '^(网络|Network)\s+\d+$'
        $isActive = $activeSet.ContainsKey($name.ToLowerInvariant())
        $managed = ($p.Managed -eq 1 -or $p.Managed -eq $true)
        $identity = $null
        $normalizedKey = Normalize-NRGuidKey -Value $p.KeyName
        if ($normalizedKey -and $identityIndex.ContainsKey($normalizedKey)) { $identity = $identityIndex[$normalizedKey] }
        if ($identity -and $identity.NlmIsConnected) { $isActive = $true }
        $score = 0
        $codes = New-Object System.Collections.Generic.List[string]
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($numbered) { $score += 20; [void]$codes.Add('NR1001'); [void]$reasons.Add('名称符合编号网络模式') }
        if ($numbered -and -not $isActive) { $score += 10; [void]$reasons.Add('当前不是活动连接') }
        if ($p.LastWrite -and ((Get-Date) - [datetime]$p.LastWrite).TotalDays -ge 30 -and $numbered) { $score += 10; [void]$reasons.Add('记录已超过 30 天未修改') }
        if ($managed) { $score += 80; [void]$codes.Add('NR1003'); [void]$reasons.Add('Managed Profile，禁止自动修改') }
        if ($identity -and $identity.Correlation -eq 'ExactNetworkId') { [void]$reasons.Add('已通过 NetworkId 与 Network List Manager 精确关联') }
        if ($identity -and $identity.NlmIsConnected -and $numbered) { $score += 80; [void]$codes.Add('NR1002'); [void]$reasons.Add('Network List Manager 报告该网络当前已连接') }
        if ($isActive -and $numbered) { $score += 70; [void]$codes.Add('NR1002'); [void]$reasons.Add('当前仍为活动连接，禁止自动删除') }
        $level = if ($score -ge 70) { 'High' } elseif ($score -ge 45) { 'Caution' } elseif ($score -ge 25) { 'Low' } else { 'None' }
        $remediationAllowed = $numbered -and (-not $isActive) -and (-not $managed)
        if ($remediationAllowed -and $level -eq 'None') { $level = 'Low' }
        [pscustomobject]@{
            KeyName = $p.KeyName
            ProfileName = $p.ProfileName
            Category = $p.Category
            Managed = $p.Managed
            IsActive = $isActive
            RiskScore = $score
            RiskLevel = $level
            Risk = $level
            RemediationAllowed = $remediationAllowed
            DiagnosticCodes = @($codes)
            Reasons = @($reasons)
            NetworkId = if ($identity) { $identity.NetworkId } else { $null }
            NetworkName = if ($identity) { $identity.NetworkName } else { $null }
            NetworkCorrelation = if ($identity) { $identity.Correlation } else { 'None' }
            NlmIsConnected = if ($identity) { $identity.NlmIsConnected } else { $false }
            Reason = if ($reasons.Count) { $reasons -join '；' } else { '正常或未命中安全清理规则' }
            RegistryPath = $p.RegistryPath
            LastWrite = $p.LastWrite
        }
    }
}

function Get-NRDiagnostics {
    param([switch]$SkipConnectivityTest)

    $diagnosticErrors = @()

    try { $windows = Get-NRWindowsInfo }
    catch {
        $diagnosticErrors += 'Windows 信息读取失败：' + $_.Exception.Message
        $windows = [pscustomobject]@{
            Caption = 'Unknown'
            Version = $null
            Build = $null
            Architecture = $null
            PowerShell = $PSVersionTable.PSVersion.ToString()
        }
    }

    try { $adapters = @(Get-NRAdapters) }
    catch {
        $diagnosticErrors += '网络适配器读取失败：' + $_.Exception.Message
        $adapters = @()
    }

    try { $connections = @(Get-NRConnectionProfiles) }
    catch {
        $diagnosticErrors += 'Connection Profile 读取失败：' + $_.Exception.Message
        $connections = @()
    }

    try { $registryProfiles = @(Get-NRProfileRegistryObjects) }
    catch {
        $diagnosticErrors += '注册表 Profile 读取失败：' + $_.Exception.Message
        $registryProfiles = @()
    }

    try { $nlm = Get-NRNetworkListManagerNetworks }
    catch {
        $diagnosticErrors += 'Network List Manager 诊断失败：' + $_.Exception.Message
        $nlm = [pscustomobject]@{ Available = $false; Networks = @(); Error = $_.Exception.Message }
    }

    $activeNames = @($connections | Where-Object { $_.Name } | Select-Object -ExpandProperty Name -Unique)
    $nlmActiveNames = @()
    if ($nlm.Available) {
        try {
            $nlmActiveNames = @($nlm.Networks | Where-Object IsConnected | Select-Object -ExpandProperty Name -Unique)
        }
        catch {
            $diagnosticErrors += 'NLM 活动网络读取失败：' + $_.Exception.Message
        }
    }

    $identityCorrelations = @()
    if ($nlm.Available) {
        try { $identityCorrelations = @(Get-NRNetworkIdentityCorrelation -RegistryProfiles $registryProfiles -NlmNetworks $nlm.Networks) }
        catch { $diagnosticErrors += 'NetworkId 关联诊断失败：' + $_.Exception.Message }
    }

    try {
        $suspects = @(Get-NRSuspiciousProfiles -RegistryProfiles $registryProfiles -ActiveNames $activeNames -NlmActiveNames $nlmActiveNames -IdentityCorrelations $identityCorrelations)
    }
    catch {
        $diagnosticErrors += 'Profile 风险分析失败：' + $_.Exception.Message
        $suspects = @()
    }

    try { $ip = @(Get-NRIPDiagnostics) }
    catch {
        $diagnosticErrors += 'IP 诊断失败：' + $_.Exception.Message
        $ip = @()
    }

    $gateways = @()
    if (@($ip).Count -gt 0) {
        try { $gateways = @(Test-NRGateways -Configurations @($ip)) }
        catch { $diagnosticErrors += '网关诊断失败：' + $_.Exception.Message }
    }

    $dnsServers = @()
    if (@($ip).Count -gt 0) {
        try { $dnsServers = @(Test-NRDnsServers -Configurations @($ip)) }
        catch { $diagnosticErrors += 'DNS 服务器诊断失败：' + $_.Exception.Message }
    }

    try { $ncsi = Test-NRNcsi -Skip:$SkipConnectivityTest }
    catch {
        $diagnosticErrors += 'NCSI 诊断失败：' + $_.Exception.Message
        $ncsi = [pscustomobject]@{
            Skipped = $true
            Enabled = $null
            Dns = $null
            Http = $null
            DnsHost = $null
            WebUrl = $null
            DnsError = $_.Exception.Message
            HttpError = $null
            Configuration = $null
        }
    }

    try { $networkHealth = Get-NRNetworkHealthAssessment -Connections @($connections) -NCSI $ncsi }
    catch {
        $diagnosticErrors += '网络健康评估失败：' + $_.Exception.Message
        $networkHealth = [pscustomobject]@{
            Status = 'Unknown'
            OperationallyHealthy = $false
            Reason = '网络健康评估无法完成。'
            NCSIHealthy = $false
            NCSIKnown = $false
            InternetProfileCount = 0
        }
    }

    $safeCandidates = @($suspects | Where-Object { $_.RemediationAllowed })
    $highRisk = @($suspects | Where-Object { $_.RiskLevel -eq 'High' -or $_.RiskLevel -eq 'Caution' })
    $issueDetails = @()

    if (@($safeCandidates).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1001';Severity='Low';Message=('发现 {0} 个疑似历史/重复网络 Profile。' -f @($safeCandidates).Count)}
    }
    if (@($highRisk).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1002';Severity='Warning';Message=('发现 {0} 个高风险或需人工确认的 Profile。' -f @($highRisk).Count)}
    }
    if (@($gateways | Where-Object { -not $_.Reachable }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2201';Severity='Warning';Message='一个或多个默认网关不可达。'}
    }
    if (@($dnsServers | Where-Object { -not $_.ResolvesNCSI }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2101';Severity='Warning';Message='一个或多个配置的 DNS 服务器无法解析 NCSI DNS 主机。'}
    }
    if (-not $SkipConnectivityTest -and $ncsi.Enabled -eq 0) {
        $issueDetails += [pscustomobject]@{Code='NR2003';Severity='Warning';Message='NCSI 主动探测已被禁用。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Dns) {
        $issueDetails += [pscustomobject]@{Code='NR2001';Severity='Warning';Message='NCSI DNS 探测失败。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Http) {
        $issueDetails += [pscustomobject]@{Code='NR2002';Severity='Warning';Message='NCSI HTTP Web 探测失败。'}
    }

    $connectivity = [pscustomobject]@{
        Skipped = $ncsi.Skipped
        DNS = $ncsi.Dns
        TCP443 = $ncsi.Http
        NCSI = $ncsi
    }

    $numberedProfiles = @($suspects | Where-Object {
        $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
    })
    $profileHygieneStatus = 'Clean'
    if (@($safeCandidates).Count -gt 0) {
        $profileHygieneStatus = 'HistoricalProfilesFound'
    } elseif (@($numberedProfiles).Count -gt 0) {
        $profileHygieneStatus = 'ProtectedNumberedProfilesPresent'
    }

    $repairRecommendation = 'InvestigateNetwork'
    if (@($safeCandidates).Count -gt 0) {
        $repairRecommendation = 'CleanHistoricalProfiles'
    } elseif ($networkHealth.Status -eq 'Healthy') {
        $repairRecommendation = 'NoAction'
    }

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Windows = $windows
        Adapters = @($adapters)
        Connections = @($connections)
        ActiveProfileNames = @($activeNames)
        NlmActiveProfileNames = @($nlmActiveNames)
        NetworkListManager = $nlm
        NetworkIdentityCorrelations = @($identityCorrelations)
        RegistryProfiles = @($registryProfiles)
        Candidates = @($suspects)
        IPConfiguration = @($ip)
        Gateways = @($gateways)
        DnsServers = @($dnsServers)
        NCSI = $ncsi
        Connectivity = $connectivity
        NetworkHealth = $networkHealth
        ProfileHygieneStatus = $profileHygieneStatus
        RepairRecommendation = $repairRecommendation
        DiagnosticsErrors = @($diagnosticErrors)
        Issues = @($issueDetails | ForEach-Object Message)
        IssueDetails = @($issueDetails)
        SafeCandidateCount = @($safeCandidates).Count
        HighRiskCount = @($highRisk).Count
    }
}

function Show-NRDiagnostics {
    param([Parameter(Mandatory)]$Diagnostics)
    Show-NRBanner
    Write-NRSection '系统'
    Write-NRLine ('Windows    : {0} {1} (Build {2})' -f $Diagnostics.Windows.Caption, $Diagnostics.Windows.Version, $Diagnostics.Windows.Build)
    Write-NRLine ('PowerShell : {0}' -f $Diagnostics.Windows.PowerShell)

    Write-NRSection '当前连接'
    if ($Diagnostics.Connections.Count -eq 0) { Write-NRLine '没有读取到活动连接 Profile。' 'Yellow' }
    else { foreach ($c in $Diagnostics.Connections) { Write-NRLine ('{0} | 网卡={1} | 类型={2} | IPv4={3} | IPv6={4}' -f $c.Name, $c.InterfaceAlias, $c.NetworkCategory, $c.IPv4Connectivity, $c.IPv6Connectivity) } }

    Write-NRSection 'Network List Manager'
    if ($Diagnostics.NetworkListManager.Available) {
        Write-NRLine ('已读取 {0} 个网络对象。' -f $Diagnostics.NetworkListManager.Networks.Count) 'Green'
        $exact = @($Diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        Write-NRLine ('Profile ↔ NetworkId 精确关联：{0} 个。' -f $exact) 'Green'
    }
    else { Write-NRLine 'Network List Manager COM 不可用，已回退到 PowerShell/注册表诊断。' 'Yellow' }

    Write-NRSection 'IP / DHCP / 网关 / DNS'
    foreach ($cfg in @($Diagnostics.IPConfiguration)) {
        Write-NRLine ('{0} | IPv4={1} | DHCPv4={2} | Gateway={3} | DNS={4}' -f $cfg.InterfaceAlias, (@($cfg.IPv4Addresses) -join ','), $cfg.IPv4Dhcp, (@($cfg.IPv4Gateway) -join ','), (@($cfg.DnsServersIPv4) -join ','))
    }

    Write-NRSection 'NCSI'
    if ($Diagnostics.NCSI.Skipped) { Write-NRLine '已跳过 NCSI 网络探测。' 'Yellow' }
    else { Write-NRLine ('DNS={0} | HTTP={1} | Probe={2}' -f $Diagnostics.NCSI.Dns, $Diagnostics.NCSI.Http, $Diagnostics.NCSI.WebUrl) $(if ($Diagnostics.NCSI.Dns -and $Diagnostics.NCSI.Http) { 'Green' } else { 'Yellow' }) }

    Write-NRSection '可疑 Profile'
    if ($Diagnostics.Candidates.Count -eq 0) { Write-NRLine '没有命中当前的安全清理规则。' 'Green' }
    else { foreach ($p in $Diagnostics.Candidates) { $color = if ($p.RemediationAllowed) { 'Yellow' } else { 'Red' }; Write-NRLine ('[{0} score={1}] {2} | Active={3} | Managed={4} | {5}' -f $p.RiskLevel, $p.RiskScore, $p.ProfileName, $p.IsActive, $p.Managed, $p.Reason) $color } }

    Write-NRSection '健康状态与修复建议'
    $healthColor = 'Red'
    if ($Diagnostics.NetworkHealth.Status -eq 'Healthy') {
        $healthColor = 'Green'
    } elseif ($Diagnostics.NetworkHealth.Status -eq 'Degraded') {
        $healthColor = 'Yellow'
    }
    Write-NRLine ('网络健康：{0} | {1}' -f $Diagnostics.NetworkHealth.Status,$Diagnostics.NetworkHealth.Reason) $healthColor
    switch ($Diagnostics.ProfileHygieneStatus) {
        'HistoricalProfilesFound' {
            Write-NRLine ('Profile 状态：发现 {0} 个可安全清理的历史编号 Profile（网络本身不一定有故障）。' -f $Diagnostics.SafeCandidateCount) 'Yellow'
        }
        'ProtectedNumberedProfilesPresent' {
            Write-NRLine 'Profile 状态：发现编号 Profile，但当前对象受到活动/Managed 等安全规则保护，不会自动删除。' 'Yellow'
        }
        default {
            Write-NRLine 'Profile 状态：未发现需要自动清理的编号历史 Profile。' 'Green'
        }
    }
    switch ($Diagnostics.RepairRecommendation) {
        'CleanHistoricalProfiles' {
            Write-NRLine '建议：网络本身健康，但存在历史编号 Profile，可进入安全清理流程。' 'Yellow'
        }
        'InvestigateNetwork' {
            Write-NRLine '建议：当前网络存在连通性问题，应优先调查网络故障。' 'Yellow'
        }
        default {
            Write-NRLine '建议：当前网络健康且没有可安全清理的历史 Profile，无需修复。' 'Green'
        }
    }

    if (@($Diagnostics.DiagnosticsErrors).Count -gt 0) {
        Write-NRSection '诊断降级提示'
        Write-NRLine ('有 {0} 个诊断阶段未能完整读取；以上结论应结合日志谨慎解读。' -f @($Diagnostics.DiagnosticsErrors).Count) 'Yellow'
        foreach ($errorItem in @($Diagnostics.DiagnosticsErrors)) {
            Write-NRLine ('[DEGRADED] {0}' -f $errorItem) 'Yellow'
        }
    }
    Write-NRSection '结论'
    if ($Diagnostics.IssueDetails.Count -eq 0) {
        Write-NRLine '当前没有发现明显网络故障。' 'Green'
    } else {
        foreach ($i in $Diagnostics.IssueDetails) {
            Write-NRLine ('[{0}] {1}' -f $i.Code, $i.Message) 'Yellow'
        }
    }
}

        }).Count
        CurrentConnections = @($Diagnostics.Connections | ForEach-Object {
            [pscustomobject]@{
                NetworkCategory = $_.NetworkCategory
                IPv4Connectivity = $_.IPv4Connectivity
                IPv6Connectivity = $_.IPv6Connectivity
            }
        })
        Adapters = @($Diagnostics.Adapters | ForEach-Object {
            [pscustomobject]@{
                Status = $_.Status
                LinkSpeed = $_.LinkSpeed
                MediaType = $_.MediaType
                Virtual = $_.Virtual
            }
        })
        NetworkListManager = [pscustomobject]@{
            Available = [bool]$Diagnostics.NetworkListManager.Available
            NetworkCount = if ($Diagnostics.NetworkListManager.Available) { @($Diagnostics.NetworkListManager.Networks).Count } else { 0 }
            ExactNetworkIdCorrelationCount = @($Diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        }
        Candidates = @($Diagnostics.Candidates | ForEach-Object {
            [pscustomobject]@{
                ProfileClass = if ($_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^网络 +[0-9]+
    param([string]$Path,[switch]$SkipConnectivityTest)
    if(!$Path){$Path=Join-Path $Script:Reports ('NetMedic_Report_{0}.json'-f (Get-Date -Format 'yyyyMMdd_HHmmss'))}
    $d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;$d|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8
    Write-NRLog ('Diagnostic report exported: {0}'-f $Path);[pscustomobject]@{Success=$true;Path=$Path;Diagnostics=$d}
}


function Get-NRIPDiagnostics {
    $rows = @()
    try {
        $configs = @(Get-NetIPConfiguration -All -ErrorAction Stop)
        foreach ($cfg in $configs) {
            $index = [int]$cfg.InterfaceIndex
            $ipv4Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ipv6Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue
            $dns4 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $dns6 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $gateway = @()

            $ipv4Addresses = @()
            $ipv4Property = $cfg.PSObject.Properties['IPv4Address']
            if ($null -ne $ipv4Property -and $null -ne $ipv4Property.Value) {
                $ipv4Addresses = @($ipv4Property.Value | ForEach-Object { [string]$_.IPv4Address })
            }

            $ipv6Addresses = @()
            $ipv6Property = $cfg.PSObject.Properties['IPv6Address']
            if ($null -ne $ipv6Property -and $null -ne $ipv6Property.Value) {
                $ipv6Addresses = @($ipv6Property.Value | ForEach-Object { [string]$_.IPv6Address })
            }

            $gatewayProperty = $cfg.PSObject.Properties['IPv4DefaultGateway']
            if ($null -ne $gatewayProperty -and $null -ne $gatewayProperty.Value) {
                $gateway = @($gatewayProperty.Value | Where-Object { $_ } | ForEach-Object {
                    if ($_.PSObject.Properties['NextHop']) { [string]$_.NextHop }
                } | Where-Object { $_ })
            }

            $rows += [pscustomobject]@{
                InterfaceAlias = [string]$cfg.InterfaceAlias
                InterfaceIndex = $index
                IPv4Addresses = @($ipv4Addresses)
                IPv6Addresses = @($ipv6Addresses)
                IPv4Gateway = @($gateway)
                IPv4Dhcp = if ($ipv4Interface) { [string]$ipv4Interface.Dhcp } else { $null }
                IPv6Dhcp = if ($ipv6Interface) { [string]$ipv6Interface.Dhcp } else { $null }
                DnsServersIPv4 = @($dns4)
                DnsServersIPv6 = @($dns6)
            }
        }
    }
    catch {
        Write-NRLog ('IP diagnostics failed: {0}' -f $_.Exception.Message) 'WARN'
    }
    @($rows)
}

function Test-NRGateways {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.IPv4Gateway })) {
        foreach ($gateway in @($cfg.IPv4Gateway)) {
            $ok = $false
            try { $ok = [bool](Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Gateway = $gateway; Reachable = $ok }
        }
    }
    @($results)
}

function Test-NRDnsServers {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.DnsServersIPv4 })) {
        foreach ($server in @($cfg.DnsServersIPv4)) {
            $ok = $false
            try { Resolve-DnsName -Name 'dns.msftncsi.com' -Server $server -Type A -ErrorAction Stop | Out-Null; $ok = $true } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Server = $server; ResolvesNCSI = $ok }
        }
    }
    @($results)
}


function Get-NRSuspiciousProfiles {
    param(
        [Parameter(Mandatory)][object[]]$RegistryProfiles,
        [string[]]$ActiveNames = @(),
        [string[]]$NlmActiveNames = @(),
        [object[]]$IdentityCorrelations = @()
    )
    $activeSet = @{}
    foreach ($n in @($ActiveNames + $NlmActiveNames)) { if ($n) { $activeSet[$n.ToLowerInvariant()] = $true } }
    $identityIndex = @{}
    foreach ($i in @($IdentityCorrelations)) { if ($i.ProfileKeyName) { $identityIndex[(Normalize-NRGuidKey -Value $i.ProfileKeyName)] = $i } }

    foreach ($p in $RegistryProfiles) {
        if ([string]::IsNullOrWhiteSpace($p.ProfileName)) { continue }
        $name = $p.ProfileName.Trim()
        $numbered = $name -match '^(网络|Network)\s+\d+$'
        $isActive = $activeSet.ContainsKey($name.ToLowerInvariant())
        $managed = ($p.Managed -eq 1 -or $p.Managed -eq $true)
        $identity = $null
        $normalizedKey = Normalize-NRGuidKey -Value $p.KeyName
        if ($normalizedKey -and $identityIndex.ContainsKey($normalizedKey)) { $identity = $identityIndex[$normalizedKey] }
        if ($identity -and $identity.NlmIsConnected) { $isActive = $true }
        $score = 0
        $codes = New-Object System.Collections.Generic.List[string]
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($numbered) { $score += 20; [void]$codes.Add('NR1001'); [void]$reasons.Add('名称符合编号网络模式') }
        if ($numbered -and -not $isActive) { $score += 10; [void]$reasons.Add('当前不是活动连接') }
        if ($p.LastWrite -and ((Get-Date) - [datetime]$p.LastWrite).TotalDays -ge 30 -and $numbered) { $score += 10; [void]$reasons.Add('记录已超过 30 天未修改') }
        if ($managed) { $score += 80; [void]$codes.Add('NR1003'); [void]$reasons.Add('Managed Profile，禁止自动修改') }
        if ($identity -and $identity.Correlation -eq 'ExactNetworkId') { [void]$reasons.Add('已通过 NetworkId 与 Network List Manager 精确关联') }
        if ($identity -and $identity.NlmIsConnected -and $numbered) { $score += 80; [void]$codes.Add('NR1002'); [void]$reasons.Add('Network List Manager 报告该网络当前已连接') }
        if ($isActive -and $numbered) { $score += 70; [void]$codes.Add('NR1002'); [void]$reasons.Add('当前仍为活动连接，禁止自动删除') }
        $level = if ($score -ge 70) { 'High' } elseif ($score -ge 45) { 'Caution' } elseif ($score -ge 25) { 'Low' } else { 'None' }
        $remediationAllowed = $numbered -and (-not $isActive) -and (-not $managed)
        if ($remediationAllowed -and $level -eq 'None') { $level = 'Low' }
        [pscustomobject]@{
            KeyName = $p.KeyName
            ProfileName = $p.ProfileName
            Category = $p.Category
            Managed = $p.Managed
            IsActive = $isActive
            RiskScore = $score
            RiskLevel = $level
            Risk = $level
            RemediationAllowed = $remediationAllowed
            DiagnosticCodes = @($codes)
            Reasons = @($reasons)
            NetworkId = if ($identity) { $identity.NetworkId } else { $null }
            NetworkName = if ($identity) { $identity.NetworkName } else { $null }
            NetworkCorrelation = if ($identity) { $identity.Correlation } else { 'None' }
            NlmIsConnected = if ($identity) { $identity.NlmIsConnected } else { $false }
            Reason = if ($reasons.Count) { $reasons -join '；' } else { '正常或未命中安全清理规则' }
            RegistryPath = $p.RegistryPath
            LastWrite = $p.LastWrite
        }
    }
}

function Get-NRDiagnostics {
    param([switch]$SkipConnectivityTest)

    $diagnosticErrors = @()

    try { $windows = Get-NRWindowsInfo }
    catch {
        $diagnosticErrors += 'Windows 信息读取失败：' + $_.Exception.Message
        $windows = [pscustomobject]@{
            Caption = 'Unknown'
            Version = $null
            Build = $null
            Architecture = $null
            PowerShell = $PSVersionTable.PSVersion.ToString()
        }
    }

    try { $adapters = @(Get-NRAdapters) }
    catch {
        $diagnosticErrors += '网络适配器读取失败：' + $_.Exception.Message
        $adapters = @()
    }

    try { $connections = @(Get-NRConnectionProfiles) }
    catch {
        $diagnosticErrors += 'Connection Profile 读取失败：' + $_.Exception.Message
        $connections = @()
    }

    try { $registryProfiles = @(Get-NRProfileRegistryObjects) }
    catch {
        $diagnosticErrors += '注册表 Profile 读取失败：' + $_.Exception.Message
        $registryProfiles = @()
    }

    try { $nlm = Get-NRNetworkListManagerNetworks }
    catch {
        $diagnosticErrors += 'Network List Manager 诊断失败：' + $_.Exception.Message
        $nlm = [pscustomobject]@{ Available = $false; Networks = @(); Error = $_.Exception.Message }
    }

    $activeNames = @($connections | Where-Object { $_.Name } | Select-Object -ExpandProperty Name -Unique)
    $nlmActiveNames = @()
    if ($nlm.Available) {
        try {
            $nlmActiveNames = @($nlm.Networks | Where-Object IsConnected | Select-Object -ExpandProperty Name -Unique)
        }
        catch {
            $diagnosticErrors += 'NLM 活动网络读取失败：' + $_.Exception.Message
        }
    }

    $identityCorrelations = @()
    if ($nlm.Available) {
        try { $identityCorrelations = @(Get-NRNetworkIdentityCorrelation -RegistryProfiles $registryProfiles -NlmNetworks $nlm.Networks) }
        catch { $diagnosticErrors += 'NetworkId 关联诊断失败：' + $_.Exception.Message }
    }

    try {
        $suspects = @(Get-NRSuspiciousProfiles -RegistryProfiles $registryProfiles -ActiveNames $activeNames -NlmActiveNames $nlmActiveNames -IdentityCorrelations $identityCorrelations)
    }
    catch {
        $diagnosticErrors += 'Profile 风险分析失败：' + $_.Exception.Message
        $suspects = @()
    }

    try { $ip = @(Get-NRIPDiagnostics) }
    catch {
        $diagnosticErrors += 'IP 诊断失败：' + $_.Exception.Message
        $ip = @()
    }

    $gateways = @()
    if (@($ip).Count -gt 0) {
        try { $gateways = @(Test-NRGateways -Configurations @($ip)) }
        catch { $diagnosticErrors += '网关诊断失败：' + $_.Exception.Message }
    }

    $dnsServers = @()
    if (@($ip).Count -gt 0) {
        try { $dnsServers = @(Test-NRDnsServers -Configurations @($ip)) }
        catch { $diagnosticErrors += 'DNS 服务器诊断失败：' + $_.Exception.Message }
    }

    try { $ncsi = Test-NRNcsi -Skip:$SkipConnectivityTest }
    catch {
        $diagnosticErrors += 'NCSI 诊断失败：' + $_.Exception.Message
        $ncsi = [pscustomobject]@{
            Skipped = $true
            Enabled = $null
            Dns = $null
            Http = $null
            DnsHost = $null
            WebUrl = $null
            DnsError = $_.Exception.Message
            HttpError = $null
            Configuration = $null
        }
    }

    try { $networkHealth = Get-NRNetworkHealthAssessment -Connections @($connections) -NCSI $ncsi }
    catch {
        $diagnosticErrors += '网络健康评估失败：' + $_.Exception.Message
        $networkHealth = [pscustomobject]@{
            Status = 'Unknown'
            OperationallyHealthy = $false
            Reason = '网络健康评估无法完成。'
            NCSIHealthy = $false
            NCSIKnown = $false
            InternetProfileCount = 0
        }
    }

    $safeCandidates = @($suspects | Where-Object { $_.RemediationAllowed })
    $highRisk = @($suspects | Where-Object { $_.RiskLevel -eq 'High' -or $_.RiskLevel -eq 'Caution' })
    $issueDetails = @()

    if (@($safeCandidates).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1001';Severity='Low';Message=('发现 {0} 个疑似历史/重复网络 Profile。' -f @($safeCandidates).Count)}
    }
    if (@($highRisk).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1002';Severity='Warning';Message=('发现 {0} 个高风险或需人工确认的 Profile。' -f @($highRisk).Count)}
    }
    if (@($gateways | Where-Object { -not $_.Reachable }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2201';Severity='Warning';Message='一个或多个默认网关不可达。'}
    }
    if (@($dnsServers | Where-Object { -not $_.ResolvesNCSI }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2101';Severity='Warning';Message='一个或多个配置的 DNS 服务器无法解析 NCSI DNS 主机。'}
    }
    if (-not $SkipConnectivityTest -and $ncsi.Enabled -eq 0) {
        $issueDetails += [pscustomobject]@{Code='NR2003';Severity='Warning';Message='NCSI 主动探测已被禁用。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Dns) {
        $issueDetails += [pscustomobject]@{Code='NR2001';Severity='Warning';Message='NCSI DNS 探测失败。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Http) {
        $issueDetails += [pscustomobject]@{Code='NR2002';Severity='Warning';Message='NCSI HTTP Web 探测失败。'}
    }

    $connectivity = [pscustomobject]@{
        Skipped = $ncsi.Skipped
        DNS = $ncsi.Dns
        TCP443 = $ncsi.Http
        NCSI = $ncsi
    }

    $numberedProfiles = @($suspects | Where-Object {
        $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
    })
    $profileHygieneStatus = 'Clean'
    if (@($safeCandidates).Count -gt 0) {
        $profileHygieneStatus = 'HistoricalProfilesFound'
    } elseif (@($numberedProfiles).Count -gt 0) {
        $profileHygieneStatus = 'ProtectedNumberedProfilesPresent'
    }

    $repairRecommendation = 'InvestigateNetwork'
    if (@($safeCandidates).Count -gt 0) {
        $repairRecommendation = 'CleanHistoricalProfiles'
    } elseif ($networkHealth.Status -eq 'Healthy') {
        $repairRecommendation = 'NoAction'
    }

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Windows = $windows
        Adapters = @($adapters)
        Connections = @($connections)
        ActiveProfileNames = @($activeNames)
        NlmActiveProfileNames = @($nlmActiveNames)
        NetworkListManager = $nlm
        NetworkIdentityCorrelations = @($identityCorrelations)
        RegistryProfiles = @($registryProfiles)
        Candidates = @($suspects)
        IPConfiguration = @($ip)
        Gateways = @($gateways)
        DnsServers = @($dnsServers)
        NCSI = $ncsi
        Connectivity = $connectivity
        NetworkHealth = $networkHealth
        ProfileHygieneStatus = $profileHygieneStatus
        RepairRecommendation = $repairRecommendation
        DiagnosticsErrors = @($diagnosticErrors)
        Issues = @($issueDetails | ForEach-Object Message)
        IssueDetails = @($issueDetails)
        SafeCandidateCount = @($safeCandidates).Count
        HighRiskCount = @($highRisk).Count
    }
}

function Show-NRDiagnostics {
    param([Parameter(Mandatory)]$Diagnostics)
    Show-NRBanner
    Write-NRSection '系统'
    Write-NRLine ('Windows    : {0} {1} (Build {2})' -f $Diagnostics.Windows.Caption, $Diagnostics.Windows.Version, $Diagnostics.Windows.Build)
    Write-NRLine ('PowerShell : {0}' -f $Diagnostics.Windows.PowerShell)

    Write-NRSection '当前连接'
    if ($Diagnostics.Connections.Count -eq 0) { Write-NRLine '没有读取到活动连接 Profile。' 'Yellow' }
    else { foreach ($c in $Diagnostics.Connections) { Write-NRLine ('{0} | 网卡={1} | 类型={2} | IPv4={3} | IPv6={4}' -f $c.Name, $c.InterfaceAlias, $c.NetworkCategory, $c.IPv4Connectivity, $c.IPv6Connectivity) } }

    Write-NRSection 'Network List Manager'
    if ($Diagnostics.NetworkListManager.Available) {
        Write-NRLine ('已读取 {0} 个网络对象。' -f $Diagnostics.NetworkListManager.Networks.Count) 'Green'
        $exact = @($Diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        Write-NRLine ('Profile ↔ NetworkId 精确关联：{0} 个。' -f $exact) 'Green'
    }
    else { Write-NRLine 'Network List Manager COM 不可用，已回退到 PowerShell/注册表诊断。' 'Yellow' }

    Write-NRSection 'IP / DHCP / 网关 / DNS'
    foreach ($cfg in @($Diagnostics.IPConfiguration)) {
        Write-NRLine ('{0} | IPv4={1} | DHCPv4={2} | Gateway={3} | DNS={4}' -f $cfg.InterfaceAlias, (@($cfg.IPv4Addresses) -join ','), $cfg.IPv4Dhcp, (@($cfg.IPv4Gateway) -join ','), (@($cfg.DnsServersIPv4) -join ','))
    }

    Write-NRSection 'NCSI'
    if ($Diagnostics.NCSI.Skipped) { Write-NRLine '已跳过 NCSI 网络探测。' 'Yellow' }
    else { Write-NRLine ('DNS={0} | HTTP={1} | Probe={2}' -f $Diagnostics.NCSI.Dns, $Diagnostics.NCSI.Http, $Diagnostics.NCSI.WebUrl) $(if ($Diagnostics.NCSI.Dns -and $Diagnostics.NCSI.Http) { 'Green' } else { 'Yellow' }) }

    Write-NRSection '可疑 Profile'
    if ($Diagnostics.Candidates.Count -eq 0) { Write-NRLine '没有命中当前的安全清理规则。' 'Green' }
    else { foreach ($p in $Diagnostics.Candidates) { $color = if ($p.RemediationAllowed) { 'Yellow' } else { 'Red' }; Write-NRLine ('[{0} score={1}] {2} | Active={3} | Managed={4} | {5}' -f $p.RiskLevel, $p.RiskScore, $p.ProfileName, $p.IsActive, $p.Managed, $p.Reason) $color } }

    Write-NRSection '健康状态与修复建议'
    $healthColor = 'Red'
    if ($Diagnostics.NetworkHealth.Status -eq 'Healthy') {
        $healthColor = 'Green'
    } elseif ($Diagnostics.NetworkHealth.Status -eq 'Degraded') {
        $healthColor = 'Yellow'
    }
    Write-NRLine ('网络健康：{0} | {1}' -f $Diagnostics.NetworkHealth.Status,$Diagnostics.NetworkHealth.Reason) $healthColor
    switch ($Diagnostics.ProfileHygieneStatus) {
        'HistoricalProfilesFound' {
            Write-NRLine ('Profile 状态：发现 {0} 个可安全清理的历史编号 Profile（网络本身不一定有故障）。' -f $Diagnostics.SafeCandidateCount) 'Yellow'
        }
        'ProtectedNumberedProfilesPresent' {
            Write-NRLine 'Profile 状态：发现编号 Profile，但当前对象受到活动/Managed 等安全规则保护，不会自动删除。' 'Yellow'
        }
        default {
            Write-NRLine 'Profile 状态：未发现需要自动清理的编号历史 Profile。' 'Green'
        }
    }
    switch ($Diagnostics.RepairRecommendation) {
        'CleanHistoricalProfiles' {
            Write-NRLine '建议：网络本身健康，但存在历史编号 Profile，可进入安全清理流程。' 'Yellow'
        }
        'InvestigateNetwork' {
            Write-NRLine '建议：当前网络存在连通性问题，应优先调查网络故障。' 'Yellow'
        }
        default {
            Write-NRLine '建议：当前网络健康且没有可安全清理的历史 Profile，无需修复。' 'Green'
        }
    }

    if (@($Diagnostics.DiagnosticsErrors).Count -gt 0) {
        Write-NRSection '诊断降级提示'
        Write-NRLine ('有 {0} 个诊断阶段未能完整读取；以上结论应结合日志谨慎解读。' -f @($Diagnostics.DiagnosticsErrors).Count) 'Yellow'
        foreach ($errorItem in @($Diagnostics.DiagnosticsErrors)) {
            Write-NRLine ('[DEGRADED] {0}' -f $errorItem) 'Yellow'
        }
    }
    Write-NRSection '结论'
    if ($Diagnostics.IssueDetails.Count -eq 0) {
        Write-NRLine '当前没有发现明显网络故障。' 'Green'
    } else {
        foreach ($i in $Diagnostics.IssueDetails) {
            Write-NRLine ('[{0}] {1}' -f $i.Code, $i.Message) 'Yellow'
        }
    }
}
) { 'ChineseNumbered' } elseif ($_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^Network +[0-9]+
    param([string]$Path,[switch]$SkipConnectivityTest)
    if(!$Path){$Path=Join-Path $Script:Reports ('NetMedic_Report_{0}.json'-f (Get-Date -Format 'yyyyMMdd_HHmmss'))}
    $d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;$d|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8
    Write-NRLog ('Diagnostic report exported: {0}'-f $Path);[pscustomobject]@{Success=$true;Path=$Path;Diagnostics=$d}
}


function Get-NRIPDiagnostics {
    $rows = @()
    try {
        $configs = @(Get-NetIPConfiguration -All -ErrorAction Stop)
        foreach ($cfg in $configs) {
            $index = [int]$cfg.InterfaceIndex
            $ipv4Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ipv6Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue
            $dns4 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $dns6 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $gateway = @()

            $ipv4Addresses = @()
            $ipv4Property = $cfg.PSObject.Properties['IPv4Address']
            if ($null -ne $ipv4Property -and $null -ne $ipv4Property.Value) {
                $ipv4Addresses = @($ipv4Property.Value | ForEach-Object { [string]$_.IPv4Address })
            }

            $ipv6Addresses = @()
            $ipv6Property = $cfg.PSObject.Properties['IPv6Address']
            if ($null -ne $ipv6Property -and $null -ne $ipv6Property.Value) {
                $ipv6Addresses = @($ipv6Property.Value | ForEach-Object { [string]$_.IPv6Address })
            }

            $gatewayProperty = $cfg.PSObject.Properties['IPv4DefaultGateway']
            if ($null -ne $gatewayProperty -and $null -ne $gatewayProperty.Value) {
                $gateway = @($gatewayProperty.Value | Where-Object { $_ } | ForEach-Object {
                    if ($_.PSObject.Properties['NextHop']) { [string]$_.NextHop }
                } | Where-Object { $_ })
            }

            $rows += [pscustomobject]@{
                InterfaceAlias = [string]$cfg.InterfaceAlias
                InterfaceIndex = $index
                IPv4Addresses = @($ipv4Addresses)
                IPv6Addresses = @($ipv6Addresses)
                IPv4Gateway = @($gateway)
                IPv4Dhcp = if ($ipv4Interface) { [string]$ipv4Interface.Dhcp } else { $null }
                IPv6Dhcp = if ($ipv6Interface) { [string]$ipv6Interface.Dhcp } else { $null }
                DnsServersIPv4 = @($dns4)
                DnsServersIPv6 = @($dns6)
            }
        }
    }
    catch {
        Write-NRLog ('IP diagnostics failed: {0}' -f $_.Exception.Message) 'WARN'
    }
    @($rows)
}

function Test-NRGateways {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.IPv4Gateway })) {
        foreach ($gateway in @($cfg.IPv4Gateway)) {
            $ok = $false
            try { $ok = [bool](Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Gateway = $gateway; Reachable = $ok }
        }
    }
    @($results)
}

function Test-NRDnsServers {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.DnsServersIPv4 })) {
        foreach ($server in @($cfg.DnsServersIPv4)) {
            $ok = $false
            try { Resolve-DnsName -Name 'dns.msftncsi.com' -Server $server -Type A -ErrorAction Stop | Out-Null; $ok = $true } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Server = $server; ResolvesNCSI = $ok }
        }
    }
    @($results)
}


function Get-NRSuspiciousProfiles {
    param(
        [Parameter(Mandatory)][object[]]$RegistryProfiles,
        [string[]]$ActiveNames = @(),
        [string[]]$NlmActiveNames = @(),
        [object[]]$IdentityCorrelations = @()
    )
    $activeSet = @{}
    foreach ($n in @($ActiveNames + $NlmActiveNames)) { if ($n) { $activeSet[$n.ToLowerInvariant()] = $true } }
    $identityIndex = @{}
    foreach ($i in @($IdentityCorrelations)) { if ($i.ProfileKeyName) { $identityIndex[(Normalize-NRGuidKey -Value $i.ProfileKeyName)] = $i } }

    foreach ($p in $RegistryProfiles) {
        if ([string]::IsNullOrWhiteSpace($p.ProfileName)) { continue }
        $name = $p.ProfileName.Trim()
        $numbered = $name -match '^(网络|Network)\s+\d+$'
        $isActive = $activeSet.ContainsKey($name.ToLowerInvariant())
        $managed = ($p.Managed -eq 1 -or $p.Managed -eq $true)
        $identity = $null
        $normalizedKey = Normalize-NRGuidKey -Value $p.KeyName
        if ($normalizedKey -and $identityIndex.ContainsKey($normalizedKey)) { $identity = $identityIndex[$normalizedKey] }
        if ($identity -and $identity.NlmIsConnected) { $isActive = $true }
        $score = 0
        $codes = New-Object System.Collections.Generic.List[string]
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($numbered) { $score += 20; [void]$codes.Add('NR1001'); [void]$reasons.Add('名称符合编号网络模式') }
        if ($numbered -and -not $isActive) { $score += 10; [void]$reasons.Add('当前不是活动连接') }
        if ($p.LastWrite -and ((Get-Date) - [datetime]$p.LastWrite).TotalDays -ge 30 -and $numbered) { $score += 10; [void]$reasons.Add('记录已超过 30 天未修改') }
        if ($managed) { $score += 80; [void]$codes.Add('NR1003'); [void]$reasons.Add('Managed Profile，禁止自动修改') }
        if ($identity -and $identity.Correlation -eq 'ExactNetworkId') { [void]$reasons.Add('已通过 NetworkId 与 Network List Manager 精确关联') }
        if ($identity -and $identity.NlmIsConnected -and $numbered) { $score += 80; [void]$codes.Add('NR1002'); [void]$reasons.Add('Network List Manager 报告该网络当前已连接') }
        if ($isActive -and $numbered) { $score += 70; [void]$codes.Add('NR1002'); [void]$reasons.Add('当前仍为活动连接，禁止自动删除') }
        $level = if ($score -ge 70) { 'High' } elseif ($score -ge 45) { 'Caution' } elseif ($score -ge 25) { 'Low' } else { 'None' }
        $remediationAllowed = $numbered -and (-not $isActive) -and (-not $managed)
        if ($remediationAllowed -and $level -eq 'None') { $level = 'Low' }
        [pscustomobject]@{
            KeyName = $p.KeyName
            ProfileName = $p.ProfileName
            Category = $p.Category
            Managed = $p.Managed
            IsActive = $isActive
            RiskScore = $score
            RiskLevel = $level
            Risk = $level
            RemediationAllowed = $remediationAllowed
            DiagnosticCodes = @($codes)
            Reasons = @($reasons)
            NetworkId = if ($identity) { $identity.NetworkId } else { $null }
            NetworkName = if ($identity) { $identity.NetworkName } else { $null }
            NetworkCorrelation = if ($identity) { $identity.Correlation } else { 'None' }
            NlmIsConnected = if ($identity) { $identity.NlmIsConnected } else { $false }
            Reason = if ($reasons.Count) { $reasons -join '；' } else { '正常或未命中安全清理规则' }
            RegistryPath = $p.RegistryPath
            LastWrite = $p.LastWrite
        }
    }
}

function Get-NRDiagnostics {
    param([switch]$SkipConnectivityTest)

    $diagnosticErrors = @()

    try { $windows = Get-NRWindowsInfo }
    catch {
        $diagnosticErrors += 'Windows 信息读取失败：' + $_.Exception.Message
        $windows = [pscustomobject]@{
            Caption = 'Unknown'
            Version = $null
            Build = $null
            Architecture = $null
            PowerShell = $PSVersionTable.PSVersion.ToString()
        }
    }

    try { $adapters = @(Get-NRAdapters) }
    catch {
        $diagnosticErrors += '网络适配器读取失败：' + $_.Exception.Message
        $adapters = @()
    }

    try { $connections = @(Get-NRConnectionProfiles) }
    catch {
        $diagnosticErrors += 'Connection Profile 读取失败：' + $_.Exception.Message
        $connections = @()
    }

    try { $registryProfiles = @(Get-NRProfileRegistryObjects) }
    catch {
        $diagnosticErrors += '注册表 Profile 读取失败：' + $_.Exception.Message
        $registryProfiles = @()
    }

    try { $nlm = Get-NRNetworkListManagerNetworks }
    catch {
        $diagnosticErrors += 'Network List Manager 诊断失败：' + $_.Exception.Message
        $nlm = [pscustomobject]@{ Available = $false; Networks = @(); Error = $_.Exception.Message }
    }

    $activeNames = @($connections | Where-Object { $_.Name } | Select-Object -ExpandProperty Name -Unique)
    $nlmActiveNames = @()
    if ($nlm.Available) {
        try {
            $nlmActiveNames = @($nlm.Networks | Where-Object IsConnected | Select-Object -ExpandProperty Name -Unique)
        }
        catch {
            $diagnosticErrors += 'NLM 活动网络读取失败：' + $_.Exception.Message
        }
    }

    $identityCorrelations = @()
    if ($nlm.Available) {
        try { $identityCorrelations = @(Get-NRNetworkIdentityCorrelation -RegistryProfiles $registryProfiles -NlmNetworks $nlm.Networks) }
        catch { $diagnosticErrors += 'NetworkId 关联诊断失败：' + $_.Exception.Message }
    }

    try {
        $suspects = @(Get-NRSuspiciousProfiles -RegistryProfiles $registryProfiles -ActiveNames $activeNames -NlmActiveNames $nlmActiveNames -IdentityCorrelations $identityCorrelations)
    }
    catch {
        $diagnosticErrors += 'Profile 风险分析失败：' + $_.Exception.Message
        $suspects = @()
    }

    try { $ip = @(Get-NRIPDiagnostics) }
    catch {
        $diagnosticErrors += 'IP 诊断失败：' + $_.Exception.Message
        $ip = @()
    }

    $gateways = @()
    if (@($ip).Count -gt 0) {
        try { $gateways = @(Test-NRGateways -Configurations @($ip)) }
        catch { $diagnosticErrors += '网关诊断失败：' + $_.Exception.Message }
    }

    $dnsServers = @()
    if (@($ip).Count -gt 0) {
        try { $dnsServers = @(Test-NRDnsServers -Configurations @($ip)) }
        catch { $diagnosticErrors += 'DNS 服务器诊断失败：' + $_.Exception.Message }
    }

    try { $ncsi = Test-NRNcsi -Skip:$SkipConnectivityTest }
    catch {
        $diagnosticErrors += 'NCSI 诊断失败：' + $_.Exception.Message
        $ncsi = [pscustomobject]@{
            Skipped = $true
            Enabled = $null
            Dns = $null
            Http = $null
            DnsHost = $null
            WebUrl = $null
            DnsError = $_.Exception.Message
            HttpError = $null
            Configuration = $null
        }
    }

    try { $networkHealth = Get-NRNetworkHealthAssessment -Connections @($connections) -NCSI $ncsi }
    catch {
        $diagnosticErrors += '网络健康评估失败：' + $_.Exception.Message
        $networkHealth = [pscustomobject]@{
            Status = 'Unknown'
            OperationallyHealthy = $false
            Reason = '网络健康评估无法完成。'
            NCSIHealthy = $false
            NCSIKnown = $false
            InternetProfileCount = 0
        }
    }

    $safeCandidates = @($suspects | Where-Object { $_.RemediationAllowed })
    $highRisk = @($suspects | Where-Object { $_.RiskLevel -eq 'High' -or $_.RiskLevel -eq 'Caution' })
    $issueDetails = @()

    if (@($safeCandidates).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1001';Severity='Low';Message=('发现 {0} 个疑似历史/重复网络 Profile。' -f @($safeCandidates).Count)}
    }
    if (@($highRisk).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1002';Severity='Warning';Message=('发现 {0} 个高风险或需人工确认的 Profile。' -f @($highRisk).Count)}
    }
    if (@($gateways | Where-Object { -not $_.Reachable }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2201';Severity='Warning';Message='一个或多个默认网关不可达。'}
    }
    if (@($dnsServers | Where-Object { -not $_.ResolvesNCSI }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2101';Severity='Warning';Message='一个或多个配置的 DNS 服务器无法解析 NCSI DNS 主机。'}
    }
    if (-not $SkipConnectivityTest -and $ncsi.Enabled -eq 0) {
        $issueDetails += [pscustomobject]@{Code='NR2003';Severity='Warning';Message='NCSI 主动探测已被禁用。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Dns) {
        $issueDetails += [pscustomobject]@{Code='NR2001';Severity='Warning';Message='NCSI DNS 探测失败。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Http) {
        $issueDetails += [pscustomobject]@{Code='NR2002';Severity='Warning';Message='NCSI HTTP Web 探测失败。'}
    }

    $connectivity = [pscustomobject]@{
        Skipped = $ncsi.Skipped
        DNS = $ncsi.Dns
        TCP443 = $ncsi.Http
        NCSI = $ncsi
    }

    $numberedProfiles = @($suspects | Where-Object {
        $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
    })
    $profileHygieneStatus = 'Clean'
    if (@($safeCandidates).Count -gt 0) {
        $profileHygieneStatus = 'HistoricalProfilesFound'
    } elseif (@($numberedProfiles).Count -gt 0) {
        $profileHygieneStatus = 'ProtectedNumberedProfilesPresent'
    }

    $repairRecommendation = 'InvestigateNetwork'
    if (@($safeCandidates).Count -gt 0) {
        $repairRecommendation = 'CleanHistoricalProfiles'
    } elseif ($networkHealth.Status -eq 'Healthy') {
        $repairRecommendation = 'NoAction'
    }

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Windows = $windows
        Adapters = @($adapters)
        Connections = @($connections)
        ActiveProfileNames = @($activeNames)
        NlmActiveProfileNames = @($nlmActiveNames)
        NetworkListManager = $nlm
        NetworkIdentityCorrelations = @($identityCorrelations)
        RegistryProfiles = @($registryProfiles)
        Candidates = @($suspects)
        IPConfiguration = @($ip)
        Gateways = @($gateways)
        DnsServers = @($dnsServers)
        NCSI = $ncsi
        Connectivity = $connectivity
        NetworkHealth = $networkHealth
        ProfileHygieneStatus = $profileHygieneStatus
        RepairRecommendation = $repairRecommendation
        DiagnosticsErrors = @($diagnosticErrors)
        Issues = @($issueDetails | ForEach-Object Message)
        IssueDetails = @($issueDetails)
        SafeCandidateCount = @($safeCandidates).Count
        HighRiskCount = @($highRisk).Count
    }
}

function Show-NRDiagnostics {
    param([Parameter(Mandatory)]$Diagnostics)
    Show-NRBanner
    Write-NRSection '系统'
    Write-NRLine ('Windows    : {0} {1} (Build {2})' -f $Diagnostics.Windows.Caption, $Diagnostics.Windows.Version, $Diagnostics.Windows.Build)
    Write-NRLine ('PowerShell : {0}' -f $Diagnostics.Windows.PowerShell)

    Write-NRSection '当前连接'
    if ($Diagnostics.Connections.Count -eq 0) { Write-NRLine '没有读取到活动连接 Profile。' 'Yellow' }
    else { foreach ($c in $Diagnostics.Connections) { Write-NRLine ('{0} | 网卡={1} | 类型={2} | IPv4={3} | IPv6={4}' -f $c.Name, $c.InterfaceAlias, $c.NetworkCategory, $c.IPv4Connectivity, $c.IPv6Connectivity) } }

    Write-NRSection 'Network List Manager'
    if ($Diagnostics.NetworkListManager.Available) {
        Write-NRLine ('已读取 {0} 个网络对象。' -f $Diagnostics.NetworkListManager.Networks.Count) 'Green'
        $exact = @($Diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        Write-NRLine ('Profile ↔ NetworkId 精确关联：{0} 个。' -f $exact) 'Green'
    }
    else { Write-NRLine 'Network List Manager COM 不可用，已回退到 PowerShell/注册表诊断。' 'Yellow' }

    Write-NRSection 'IP / DHCP / 网关 / DNS'
    foreach ($cfg in @($Diagnostics.IPConfiguration)) {
        Write-NRLine ('{0} | IPv4={1} | DHCPv4={2} | Gateway={3} | DNS={4}' -f $cfg.InterfaceAlias, (@($cfg.IPv4Addresses) -join ','), $cfg.IPv4Dhcp, (@($cfg.IPv4Gateway) -join ','), (@($cfg.DnsServersIPv4) -join ','))
    }

    Write-NRSection 'NCSI'
    if ($Diagnostics.NCSI.Skipped) { Write-NRLine '已跳过 NCSI 网络探测。' 'Yellow' }
    else { Write-NRLine ('DNS={0} | HTTP={1} | Probe={2}' -f $Diagnostics.NCSI.Dns, $Diagnostics.NCSI.Http, $Diagnostics.NCSI.WebUrl) $(if ($Diagnostics.NCSI.Dns -and $Diagnostics.NCSI.Http) { 'Green' } else { 'Yellow' }) }

    Write-NRSection '可疑 Profile'
    if ($Diagnostics.Candidates.Count -eq 0) { Write-NRLine '没有命中当前的安全清理规则。' 'Green' }
    else { foreach ($p in $Diagnostics.Candidates) { $color = if ($p.RemediationAllowed) { 'Yellow' } else { 'Red' }; Write-NRLine ('[{0} score={1}] {2} | Active={3} | Managed={4} | {5}' -f $p.RiskLevel, $p.RiskScore, $p.ProfileName, $p.IsActive, $p.Managed, $p.Reason) $color } }

    Write-NRSection '健康状态与修复建议'
    $healthColor = 'Red'
    if ($Diagnostics.NetworkHealth.Status -eq 'Healthy') {
        $healthColor = 'Green'
    } elseif ($Diagnostics.NetworkHealth.Status -eq 'Degraded') {
        $healthColor = 'Yellow'
    }
    Write-NRLine ('网络健康：{0} | {1}' -f $Diagnostics.NetworkHealth.Status,$Diagnostics.NetworkHealth.Reason) $healthColor
    switch ($Diagnostics.ProfileHygieneStatus) {
        'HistoricalProfilesFound' {
            Write-NRLine ('Profile 状态：发现 {0} 个可安全清理的历史编号 Profile（网络本身不一定有故障）。' -f $Diagnostics.SafeCandidateCount) 'Yellow'
        }
        'ProtectedNumberedProfilesPresent' {
            Write-NRLine 'Profile 状态：发现编号 Profile，但当前对象受到活动/Managed 等安全规则保护，不会自动删除。' 'Yellow'
        }
        default {
            Write-NRLine 'Profile 状态：未发现需要自动清理的编号历史 Profile。' 'Green'
        }
    }
    switch ($Diagnostics.RepairRecommendation) {
        'CleanHistoricalProfiles' {
            Write-NRLine '建议：网络本身健康，但存在历史编号 Profile，可进入安全清理流程。' 'Yellow'
        }
        'InvestigateNetwork' {
            Write-NRLine '建议：当前网络存在连通性问题，应优先调查网络故障。' 'Yellow'
        }
        default {
            Write-NRLine '建议：当前网络健康且没有可安全清理的历史 Profile，无需修复。' 'Green'
        }
    }

    if (@($Diagnostics.DiagnosticsErrors).Count -gt 0) {
        Write-NRSection '诊断降级提示'
        Write-NRLine ('有 {0} 个诊断阶段未能完整读取；以上结论应结合日志谨慎解读。' -f @($Diagnostics.DiagnosticsErrors).Count) 'Yellow'
        foreach ($errorItem in @($Diagnostics.DiagnosticsErrors)) {
            Write-NRLine ('[DEGRADED] {0}' -f $errorItem) 'Yellow'
        }
    }
    Write-NRSection '结论'
    if ($Diagnostics.IssueDetails.Count -eq 0) {
        Write-NRLine '当前没有发现明显网络故障。' 'Green'
    } else {
        foreach ($i in $Diagnostics.IssueDetails) {
            Write-NRLine ('[{0}] {1}' -f $i.Code, $i.Message) 'Yellow'
        }
    }
}
) { 'EnglishNumbered' } else { 'Other' }
                Managed = [bool]$_.Managed
                IsActive = [bool]$_.IsActive
                RiskScore = $_.RiskScore
                RiskLevel = $_.RiskLevel
                RemediationAllowed = [bool]$_.RemediationAllowed
                DiagnosticCodes = @($_.DiagnosticCodes)
                NetworkCorrelation = [string]$_.NetworkCorrelation
                NlmIsConnected = [bool]$_.NlmIsConnected
            }
        })
        IPConfiguration = @($Diagnostics.IPConfiguration | ForEach-Object {
            [pscustomobject]@{
                IPv4AddressCount = @($_.IPv4Addresses).Count
                IPv6AddressCount = @($_.IPv6Addresses).Count
                HasIPv4Gateway = @($_.IPv4Gateway).Count -gt 0
                IPv4Dhcp = $_.IPv4Dhcp
                IPv6Dhcp = $_.IPv6Dhcp
                DnsServerIPv4Count = @($_.DnsServersIPv4).Count
                DnsServerIPv6Count = @($_.DnsServersIPv6).Count
            }
        })
        GatewayDiagnostics = [pscustomobject]@{
            TestedCount = @($Diagnostics.Gateways).Count
            FailedCount = @($Diagnostics.Gateways | Where-Object { -not $_.Reachable }).Count
        }
        DnsDiagnostics = [pscustomobject]@{
            TestedCount = @($Diagnostics.DnsServers).Count
            FailedCount = @($Diagnostics.DnsServers | Where-Object { -not $_.ResolvesNCSI }).Count
        }
        NCSI = [pscustomobject]@{
            Skipped = [bool]$Diagnostics.NCSI.Skipped
            Enabled = $Diagnostics.NCSI.Enabled
            Dns = $Diagnostics.NCSI.Dns
            Http = $Diagnostics.NCSI.Http
        }
        IssueDetails = @($Diagnostics.IssueDetails | Select-Object Code,Severity)
        DiagnosticErrorCount = @($Diagnostics.DiagnosticsErrors).Count
        Redaction = [pscustomobject]@{
            ComputerName = $true
            MacAddress = $true
            IPAddress = $true
            RegistryPath = $true
            NetworkId = $true
            NetworkName = $true
            InterfaceAlias = $true
            NetworkUrl = $true
            Credentials = $true
        }
    }
}

function Export-NRReport {
    param([string]$Path,[switch]$SkipConnectivityTest,[switch]$IncludeSensitiveDetails)
    if(!$Path){$Path=Join-Path $Script:Reports ('NetMedic_Report_{0}.json'-f (Get-Date -Format 'yyyyMMdd_HHmmss'))}
    $d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest
    if ($IncludeSensitiveDetails) {
        $reportData = $d
        Write-NRLog 'Exporting a full diagnostic report containing sensitive local identifiers.' 'WARN'
    } else {
        $reportData = ConvertTo-NRSanitizedDiagnosticSummary -Diagnostics $d
    }
    $reportData | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-NRLog ('Diagnostic report exported: {0}; Sanitized={1}' -f $Path,(-not [bool]$IncludeSensitiveDetails))
    [pscustomobject]@{Success=$true;Path=$Path;Sanitized=(-not [bool]$IncludeSensitiveDetails);IncludesSensitiveDetails=[bool]$IncludeSensitiveDetails;Diagnostics=$reportData}
}
    param([string]$Path,[switch]$SkipConnectivityTest)
    if(!$Path){$Path=Join-Path $Script:Reports ('NetMedic_Report_{0}.json'-f (Get-Date -Format 'yyyyMMdd_HHmmss'))}
    $d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;$d|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8
    Write-NRLog ('Diagnostic report exported: {0}'-f $Path);[pscustomobject]@{Success=$true;Path=$Path;Diagnostics=$d}
}


function Get-NRIPDiagnostics {
    $rows = @()
    try {
        $configs = @(Get-NetIPConfiguration -All -ErrorAction Stop)
        foreach ($cfg in $configs) {
            $index = [int]$cfg.InterfaceIndex
            $ipv4Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ipv6Interface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue
            $dns4 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $dns6 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $gateway = @()

            $ipv4Addresses = @()
            $ipv4Property = $cfg.PSObject.Properties['IPv4Address']
            if ($null -ne $ipv4Property -and $null -ne $ipv4Property.Value) {
                $ipv4Addresses = @($ipv4Property.Value | ForEach-Object { [string]$_.IPv4Address })
            }

            $ipv6Addresses = @()
            $ipv6Property = $cfg.PSObject.Properties['IPv6Address']
            if ($null -ne $ipv6Property -and $null -ne $ipv6Property.Value) {
                $ipv6Addresses = @($ipv6Property.Value | ForEach-Object { [string]$_.IPv6Address })
            }

            $gatewayProperty = $cfg.PSObject.Properties['IPv4DefaultGateway']
            if ($null -ne $gatewayProperty -and $null -ne $gatewayProperty.Value) {
                $gateway = @($gatewayProperty.Value | Where-Object { $_ } | ForEach-Object {
                    if ($_.PSObject.Properties['NextHop']) { [string]$_.NextHop }
                } | Where-Object { $_ })
            }

            $rows += [pscustomobject]@{
                InterfaceAlias = [string]$cfg.InterfaceAlias
                InterfaceIndex = $index
                IPv4Addresses = @($ipv4Addresses)
                IPv6Addresses = @($ipv6Addresses)
                IPv4Gateway = @($gateway)
                IPv4Dhcp = if ($ipv4Interface) { [string]$ipv4Interface.Dhcp } else { $null }
                IPv6Dhcp = if ($ipv6Interface) { [string]$ipv6Interface.Dhcp } else { $null }
                DnsServersIPv4 = @($dns4)
                DnsServersIPv6 = @($dns6)
            }
        }
    }
    catch {
        Write-NRLog ('IP diagnostics failed: {0}' -f $_.Exception.Message) 'WARN'
    }
    @($rows)
}

function Test-NRGateways {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.IPv4Gateway })) {
        foreach ($gateway in @($cfg.IPv4Gateway)) {
            $ok = $false
            try { $ok = [bool](Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Gateway = $gateway; Reachable = $ok }
        }
    }
    @($results)
}

function Test-NRDnsServers {
    param([Parameter(Mandatory)][object[]]$Configurations)
    $results = foreach ($cfg in @($Configurations | Where-Object { $_.DnsServersIPv4 })) {
        foreach ($server in @($cfg.DnsServersIPv4)) {
            $ok = $false
            try { Resolve-DnsName -Name 'dns.msftncsi.com' -Server $server -Type A -ErrorAction Stop | Out-Null; $ok = $true } catch { }
            [pscustomobject]@{ InterfaceAlias = $cfg.InterfaceAlias; Server = $server; ResolvesNCSI = $ok }
        }
    }
    @($results)
}


function Get-NRSuspiciousProfiles {
    param(
        [Parameter(Mandatory)][object[]]$RegistryProfiles,
        [string[]]$ActiveNames = @(),
        [string[]]$NlmActiveNames = @(),
        [object[]]$IdentityCorrelations = @()
    )
    $activeSet = @{}
    foreach ($n in @($ActiveNames + $NlmActiveNames)) { if ($n) { $activeSet[$n.ToLowerInvariant()] = $true } }
    $identityIndex = @{}
    foreach ($i in @($IdentityCorrelations)) { if ($i.ProfileKeyName) { $identityIndex[(Normalize-NRGuidKey -Value $i.ProfileKeyName)] = $i } }

    foreach ($p in $RegistryProfiles) {
        if ([string]::IsNullOrWhiteSpace($p.ProfileName)) { continue }
        $name = $p.ProfileName.Trim()
        $numbered = $name -match '^(网络|Network)\s+\d+$'
        $isActive = $activeSet.ContainsKey($name.ToLowerInvariant())
        $managed = ($p.Managed -eq 1 -or $p.Managed -eq $true)
        $identity = $null
        $normalizedKey = Normalize-NRGuidKey -Value $p.KeyName
        if ($normalizedKey -and $identityIndex.ContainsKey($normalizedKey)) { $identity = $identityIndex[$normalizedKey] }
        if ($identity -and $identity.NlmIsConnected) { $isActive = $true }
        $score = 0
        $codes = New-Object System.Collections.Generic.List[string]
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($numbered) { $score += 20; [void]$codes.Add('NR1001'); [void]$reasons.Add('名称符合编号网络模式') }
        if ($numbered -and -not $isActive) { $score += 10; [void]$reasons.Add('当前不是活动连接') }
        if ($p.LastWrite -and ((Get-Date) - [datetime]$p.LastWrite).TotalDays -ge 30 -and $numbered) { $score += 10; [void]$reasons.Add('记录已超过 30 天未修改') }
        if ($managed) { $score += 80; [void]$codes.Add('NR1003'); [void]$reasons.Add('Managed Profile，禁止自动修改') }
        if ($identity -and $identity.Correlation -eq 'ExactNetworkId') { [void]$reasons.Add('已通过 NetworkId 与 Network List Manager 精确关联') }
        if ($identity -and $identity.NlmIsConnected -and $numbered) { $score += 80; [void]$codes.Add('NR1002'); [void]$reasons.Add('Network List Manager 报告该网络当前已连接') }
        if ($isActive -and $numbered) { $score += 70; [void]$codes.Add('NR1002'); [void]$reasons.Add('当前仍为活动连接，禁止自动删除') }
        $level = if ($score -ge 70) { 'High' } elseif ($score -ge 45) { 'Caution' } elseif ($score -ge 25) { 'Low' } else { 'None' }
        $remediationAllowed = $numbered -and (-not $isActive) -and (-not $managed)
        if ($remediationAllowed -and $level -eq 'None') { $level = 'Low' }
        [pscustomobject]@{
            KeyName = $p.KeyName
            ProfileName = $p.ProfileName
            Category = $p.Category
            Managed = $p.Managed
            IsActive = $isActive
            RiskScore = $score
            RiskLevel = $level
            Risk = $level
            RemediationAllowed = $remediationAllowed
            DiagnosticCodes = @($codes)
            Reasons = @($reasons)
            NetworkId = if ($identity) { $identity.NetworkId } else { $null }
            NetworkName = if ($identity) { $identity.NetworkName } else { $null }
            NetworkCorrelation = if ($identity) { $identity.Correlation } else { 'None' }
            NlmIsConnected = if ($identity) { $identity.NlmIsConnected } else { $false }
            Reason = if ($reasons.Count) { $reasons -join '；' } else { '正常或未命中安全清理规则' }
            RegistryPath = $p.RegistryPath
            LastWrite = $p.LastWrite
        }
    }
}

function Get-NRDiagnostics {
    param([switch]$SkipConnectivityTest)

    $diagnosticErrors = @()

    try { $windows = Get-NRWindowsInfo }
    catch {
        $diagnosticErrors += 'Windows 信息读取失败：' + $_.Exception.Message
        $windows = [pscustomobject]@{
            Caption = 'Unknown'
            Version = $null
            Build = $null
            Architecture = $null
            PowerShell = $PSVersionTable.PSVersion.ToString()
        }
    }

    try { $adapters = @(Get-NRAdapters) }
    catch {
        $diagnosticErrors += '网络适配器读取失败：' + $_.Exception.Message
        $adapters = @()
    }

    try { $connections = @(Get-NRConnectionProfiles) }
    catch {
        $diagnosticErrors += 'Connection Profile 读取失败：' + $_.Exception.Message
        $connections = @()
    }

    try { $registryProfiles = @(Get-NRProfileRegistryObjects) }
    catch {
        $diagnosticErrors += '注册表 Profile 读取失败：' + $_.Exception.Message
        $registryProfiles = @()
    }

    try { $nlm = Get-NRNetworkListManagerNetworks }
    catch {
        $diagnosticErrors += 'Network List Manager 诊断失败：' + $_.Exception.Message
        $nlm = [pscustomobject]@{ Available = $false; Networks = @(); Error = $_.Exception.Message }
    }

    $activeNames = @($connections | Where-Object { $_.Name } | Select-Object -ExpandProperty Name -Unique)
    $nlmActiveNames = @()
    if ($nlm.Available) {
        try {
            $nlmActiveNames = @($nlm.Networks | Where-Object IsConnected | Select-Object -ExpandProperty Name -Unique)
        }
        catch {
            $diagnosticErrors += 'NLM 活动网络读取失败：' + $_.Exception.Message
        }
    }

    $identityCorrelations = @()
    if ($nlm.Available) {
        try { $identityCorrelations = @(Get-NRNetworkIdentityCorrelation -RegistryProfiles $registryProfiles -NlmNetworks $nlm.Networks) }
        catch { $diagnosticErrors += 'NetworkId 关联诊断失败：' + $_.Exception.Message }
    }

    try {
        $suspects = @(Get-NRSuspiciousProfiles -RegistryProfiles $registryProfiles -ActiveNames $activeNames -NlmActiveNames $nlmActiveNames -IdentityCorrelations $identityCorrelations)
    }
    catch {
        $diagnosticErrors += 'Profile 风险分析失败：' + $_.Exception.Message
        $suspects = @()
    }

    try { $ip = @(Get-NRIPDiagnostics) }
    catch {
        $diagnosticErrors += 'IP 诊断失败：' + $_.Exception.Message
        $ip = @()
    }

    $gateways = @()
    if (@($ip).Count -gt 0) {
        try { $gateways = @(Test-NRGateways -Configurations @($ip)) }
        catch { $diagnosticErrors += '网关诊断失败：' + $_.Exception.Message }
    }

    $dnsServers = @()
    if (@($ip).Count -gt 0) {
        try { $dnsServers = @(Test-NRDnsServers -Configurations @($ip)) }
        catch { $diagnosticErrors += 'DNS 服务器诊断失败：' + $_.Exception.Message }
    }

    try { $ncsi = Test-NRNcsi -Skip:$SkipConnectivityTest }
    catch {
        $diagnosticErrors += 'NCSI 诊断失败：' + $_.Exception.Message
        $ncsi = [pscustomobject]@{
            Skipped = $true
            Enabled = $null
            Dns = $null
            Http = $null
            DnsHost = $null
            WebUrl = $null
            DnsError = $_.Exception.Message
            HttpError = $null
            Configuration = $null
        }
    }

    try { $networkHealth = Get-NRNetworkHealthAssessment -Connections @($connections) -NCSI $ncsi }
    catch {
        $diagnosticErrors += '网络健康评估失败：' + $_.Exception.Message
        $networkHealth = [pscustomobject]@{
            Status = 'Unknown'
            OperationallyHealthy = $false
            Reason = '网络健康评估无法完成。'
            NCSIHealthy = $false
            NCSIKnown = $false
            InternetProfileCount = 0
        }
    }

    $safeCandidates = @($suspects | Where-Object { $_.RemediationAllowed })
    $highRisk = @($suspects | Where-Object { $_.RiskLevel -eq 'High' -or $_.RiskLevel -eq 'Caution' })
    $issueDetails = @()

    if (@($safeCandidates).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1001';Severity='Low';Message=('发现 {0} 个疑似历史/重复网络 Profile。' -f @($safeCandidates).Count)}
    }
    if (@($highRisk).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR1002';Severity='Warning';Message=('发现 {0} 个高风险或需人工确认的 Profile。' -f @($highRisk).Count)}
    }
    if (@($gateways | Where-Object { -not $_.Reachable }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2201';Severity='Warning';Message='一个或多个默认网关不可达。'}
    }
    if (@($dnsServers | Where-Object { -not $_.ResolvesNCSI }).Count -gt 0) {
        $issueDetails += [pscustomobject]@{Code='NR2101';Severity='Warning';Message='一个或多个配置的 DNS 服务器无法解析 NCSI DNS 主机。'}
    }
    if (-not $SkipConnectivityTest -and $ncsi.Enabled -eq 0) {
        $issueDetails += [pscustomobject]@{Code='NR2003';Severity='Warning';Message='NCSI 主动探测已被禁用。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Dns) {
        $issueDetails += [pscustomobject]@{Code='NR2001';Severity='Warning';Message='NCSI DNS 探测失败。'}
    }
    if (-not $SkipConnectivityTest -and -not $ncsi.Http) {
        $issueDetails += [pscustomobject]@{Code='NR2002';Severity='Warning';Message='NCSI HTTP Web 探测失败。'}
    }

    $connectivity = [pscustomobject]@{
        Skipped = $ncsi.Skipped
        DNS = $ncsi.Dns
        TCP443 = $ncsi.Http
        NCSI = $ncsi
    }

    $numberedProfiles = @($suspects | Where-Object {
        $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
    })
    $profileHygieneStatus = 'Clean'
    if (@($safeCandidates).Count -gt 0) {
        $profileHygieneStatus = 'HistoricalProfilesFound'
    } elseif (@($numberedProfiles).Count -gt 0) {
        $profileHygieneStatus = 'ProtectedNumberedProfilesPresent'
    }

    $repairRecommendation = 'InvestigateNetwork'
    if (@($safeCandidates).Count -gt 0) {
        $repairRecommendation = 'CleanHistoricalProfiles'
    } elseif ($networkHealth.Status -eq 'Healthy') {
        $repairRecommendation = 'NoAction'
    }

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Windows = $windows
        Adapters = @($adapters)
        Connections = @($connections)
        ActiveProfileNames = @($activeNames)
        NlmActiveProfileNames = @($nlmActiveNames)
        NetworkListManager = $nlm
        NetworkIdentityCorrelations = @($identityCorrelations)
        RegistryProfiles = @($registryProfiles)
        Candidates = @($suspects)
        IPConfiguration = @($ip)
        Gateways = @($gateways)
        DnsServers = @($dnsServers)
        NCSI = $ncsi
        Connectivity = $connectivity
        NetworkHealth = $networkHealth
        ProfileHygieneStatus = $profileHygieneStatus
        RepairRecommendation = $repairRecommendation
        DiagnosticsErrors = @($diagnosticErrors)
        Issues = @($issueDetails | ForEach-Object Message)
        IssueDetails = @($issueDetails)
        SafeCandidateCount = @($safeCandidates).Count
        HighRiskCount = @($highRisk).Count
    }
}

function Show-NRDiagnostics {
    param([Parameter(Mandatory)]$Diagnostics)
    Show-NRBanner
    Write-NRSection '系统'
    Write-NRLine ('Windows    : {0} {1} (Build {2})' -f $Diagnostics.Windows.Caption, $Diagnostics.Windows.Version, $Diagnostics.Windows.Build)
    Write-NRLine ('PowerShell : {0}' -f $Diagnostics.Windows.PowerShell)

    Write-NRSection '当前连接'
    if ($Diagnostics.Connections.Count -eq 0) { Write-NRLine '没有读取到活动连接 Profile。' 'Yellow' }
    else { foreach ($c in $Diagnostics.Connections) { Write-NRLine ('{0} | 网卡={1} | 类型={2} | IPv4={3} | IPv6={4}' -f $c.Name, $c.InterfaceAlias, $c.NetworkCategory, $c.IPv4Connectivity, $c.IPv6Connectivity) } }

    Write-NRSection 'Network List Manager'
    if ($Diagnostics.NetworkListManager.Available) {
        Write-NRLine ('已读取 {0} 个网络对象。' -f $Diagnostics.NetworkListManager.Networks.Count) 'Green'
        $exact = @($Diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        Write-NRLine ('Profile ↔ NetworkId 精确关联：{0} 个。' -f $exact) 'Green'
    }
    else { Write-NRLine 'Network List Manager COM 不可用，已回退到 PowerShell/注册表诊断。' 'Yellow' }

    Write-NRSection 'IP / DHCP / 网关 / DNS'
    foreach ($cfg in @($Diagnostics.IPConfiguration)) {
        Write-NRLine ('{0} | IPv4={1} | DHCPv4={2} | Gateway={3} | DNS={4}' -f $cfg.InterfaceAlias, (@($cfg.IPv4Addresses) -join ','), $cfg.IPv4Dhcp, (@($cfg.IPv4Gateway) -join ','), (@($cfg.DnsServersIPv4) -join ','))
    }

    Write-NRSection 'NCSI'
    if ($Diagnostics.NCSI.Skipped) { Write-NRLine '已跳过 NCSI 网络探测。' 'Yellow' }
    else { Write-NRLine ('DNS={0} | HTTP={1} | Probe={2}' -f $Diagnostics.NCSI.Dns, $Diagnostics.NCSI.Http, $Diagnostics.NCSI.WebUrl) $(if ($Diagnostics.NCSI.Dns -and $Diagnostics.NCSI.Http) { 'Green' } else { 'Yellow' }) }

    Write-NRSection '可疑 Profile'
    if ($Diagnostics.Candidates.Count -eq 0) { Write-NRLine '没有命中当前的安全清理规则。' 'Green' }
    else { foreach ($p in $Diagnostics.Candidates) { $color = if ($p.RemediationAllowed) { 'Yellow' } else { 'Red' }; Write-NRLine ('[{0} score={1}] {2} | Active={3} | Managed={4} | {5}' -f $p.RiskLevel, $p.RiskScore, $p.ProfileName, $p.IsActive, $p.Managed, $p.Reason) $color } }

    Write-NRSection '健康状态与修复建议'
    $healthColor = 'Red'
    if ($Diagnostics.NetworkHealth.Status -eq 'Healthy') {
        $healthColor = 'Green'
    } elseif ($Diagnostics.NetworkHealth.Status -eq 'Degraded') {
        $healthColor = 'Yellow'
    }
    Write-NRLine ('网络健康：{0} | {1}' -f $Diagnostics.NetworkHealth.Status,$Diagnostics.NetworkHealth.Reason) $healthColor
    switch ($Diagnostics.ProfileHygieneStatus) {
        'HistoricalProfilesFound' {
            Write-NRLine ('Profile 状态：发现 {0} 个可安全清理的历史编号 Profile（网络本身不一定有故障）。' -f $Diagnostics.SafeCandidateCount) 'Yellow'
        }
        'ProtectedNumberedProfilesPresent' {
            Write-NRLine 'Profile 状态：发现编号 Profile，但当前对象受到活动/Managed 等安全规则保护，不会自动删除。' 'Yellow'
        }
        default {
            Write-NRLine 'Profile 状态：未发现需要自动清理的编号历史 Profile。' 'Green'
        }
    }
    switch ($Diagnostics.RepairRecommendation) {
        'CleanHistoricalProfiles' {
            Write-NRLine '建议：网络本身健康，但存在历史编号 Profile，可进入安全清理流程。' 'Yellow'
        }
        'InvestigateNetwork' {
            Write-NRLine '建议：当前网络存在连通性问题，应优先调查网络故障。' 'Yellow'
        }
        default {
            Write-NRLine '建议：当前网络健康且没有可安全清理的历史 Profile，无需修复。' 'Green'
        }
    }

    if (@($Diagnostics.DiagnosticsErrors).Count -gt 0) {
        Write-NRSection '诊断降级提示'
        Write-NRLine ('有 {0} 个诊断阶段未能完整读取；以上结论应结合日志谨慎解读。' -f @($Diagnostics.DiagnosticsErrors).Count) 'Yellow'
        foreach ($errorItem in @($Diagnostics.DiagnosticsErrors)) {
            Write-NRLine ('[DEGRADED] {0}' -f $errorItem) 'Yellow'
        }
    }
    Write-NRSection '结论'
    if ($Diagnostics.IssueDetails.Count -eq 0) {
        Write-NRLine '当前没有发现明显网络故障。' 'Green'
    } else {
        foreach ($i in $Diagnostics.IssueDetails) {
            Write-NRLine ('[{0}] {1}' -f $i.Code, $i.Message) 'Yellow'
        }
    }
}
