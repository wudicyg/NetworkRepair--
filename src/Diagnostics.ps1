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
function Get-NRSuspiciousProfiles {
    param([Parameter(Mandatory)][object[]]$RegistryProfiles,[Parameter(Mandatory)][string[]]$ActiveNames)
    $activeSet=@{};foreach($n in $ActiveNames){if($n){$activeSet[$n.ToLowerInvariant()]=$true}}
    foreach($p in $RegistryProfiles){
        if([string]::IsNullOrWhiteSpace($p.ProfileName)){continue}
        $name=$p.ProfileName.Trim();$numbered=$name -match '^(网络|Network)\s+\d+$';$isActive=$activeSet.ContainsKey($name.ToLowerInvariant());$risk='None';$reason='正常或未命中安全清理规则'
        if($p.Managed -eq 1 -or $p.Managed -eq $true){$risk='High';$reason='网络配置标记为 Managed；不自动修改'}
        elseif($numbered -and $isActive){$risk='High';$reason='名称符合重复网络模式，但当前仍为活动连接；禁止自动删除'}
        elseif($numbered -and -not $isActive){$risk='Low';$reason='疑似历史/重复网络名称，且不是当前活动连接'}
        [pscustomobject]@{KeyName=$p.KeyName;ProfileName=$p.ProfileName;Category=$p.Category;Managed=$p.Managed;IsActive=$isActive;Risk=$risk;Reason=$reason;RegistryPath=$p.RegistryPath;LastWrite=$p.LastWrite}
    }
}
function Get-NRLegacyDiagnostics {
    param([switch]$SkipConnectivityTest)
    $windows=Get-NRWindowsInfo;$adapters=Get-NRAdapters;$connections=Get-NRConnectionProfiles;$registryProfiles=Get-NRProfileRegistryObjects;$activeNames=Get-NRActiveProfileNames
    $suspects=@(Get-NRSuspiciousProfiles -RegistryProfiles $registryProfiles -ActiveNames $activeNames);$connectivity=Test-NRInternetConnectivity -Skip:$SkipConnectivityTest
    $issues=New-Object System.Collections.Generic.List[string];$safe=@($suspects|Where-Object Risk -eq 'Low');$high=@($suspects|Where-Object Risk -eq 'High')
    if($safe.Count){[void]$issues.Add(('发现 {0} 个疑似历史/重复网络 Profile。'-f $safe.Count))}
    if($high.Count){[void]$issues.Add(('发现 {0} 个高风险或当前活动 Profile，默认不会删除。'-f $high.Count))}
    if(-not $SkipConnectivityTest -and -not $connectivity.DNS){[void]$issues.Add('DNS 解析测试失败。')}
    if(-not $SkipConnectivityTest -and -not $connectivity.TCP443){[void]$issues.Add('TCP/443 Internet 连通性测试失败。')}
    [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Windows=$windows;Adapters=@($adapters);Connections=@($connections);ActiveProfileNames=@($activeNames);RegistryProfiles=@($registryProfiles);Candidates=@($suspects);Connectivity=$connectivity;Issues=@($issues);SafeCandidateCount=$safe.Count;HighRiskCount=$high.Count}
}
function Show-NRDiagnostics {
    param([Parameter(Mandatory)]$Diagnostics)
    Show-NRBanner;Write-NRSection '系统';Write-NRLine ('Windows: {0} {1} (Build {2})'-f $Diagnostics.Windows.Caption,$Diagnostics.Windows.Version,$Diagnostics.Windows.Build);Write-NRLine ('PowerShell: {0}'-f $Diagnostics.Windows.PowerShell)
    Write-NRSection '当前连接';if(!$Diagnostics.Connections.Count){Write-NRLine '没有读取到活动连接 Profile。' 'Yellow'}else{foreach($c in $Diagnostics.Connections){Write-NRLine ('{0} | 网卡={1} | 类型={2} | IPv4={3} | IPv6={4}'-f $c.Name,$c.InterfaceAlias,$c.NetworkCategory,$c.IPv4Connectivity,$c.IPv6Connectivity)}}
    Write-NRSection '可疑 Profile';if(!$Diagnostics.Candidates.Count){Write-NRLine '没有命中当前的安全清理规则。' 'Green'}else{foreach($p in $Diagnostics.Candidates){$color=if($p.Risk -eq 'Low'){'Yellow'}else{'Red'};Write-NRLine ('[{0}] {1} | Active={2} | Reason={3}'-f $p.Risk,$p.ProfileName,$p.IsActive,$p.Reason) $color}}
    Write-NRSection '连通性';if($Diagnostics.Connectivity.Skipped){Write-NRLine '已跳过 Internet/DNS 测试。' 'Yellow'}else{Write-NRLine ('DNS={0} | TCP443={1}'-f $Diagnostics.Connectivity.DNS,$Diagnostics.Connectivity.TCP443) $(if($Diagnostics.Connectivity.DNS -and $Diagnostics.Connectivity.TCP443){'Green'}else{'Yellow'})}
    Write-NRSection '结论';if(!$Diagnostics.Issues.Count){Write-NRLine '当前没有发现明显问题。' 'Green'}else{foreach($i in $Diagnostics.Issues){Write-NRLine ('- '+$i) 'Yellow'}}
}
function Invoke-NRScan { param([switch]$SkipConnectivityTest);Write-NRLog 'Starting diagnostic scan.';$d=Get-NRDiagnostics -SkipConnectivityTest:$SkipConnectivityTest;if(-not $Json){Show-NRDiagnostics -Diagnostics $d};Write-NRLog ('Diagnostic scan complete. SafeCandidates={0}, HighRisk={1}'-f $d.SafeCandidateCount,$d.HighRiskCount);$d }
function Export-NRReport {
    param([string]$Path,[switch]$SkipConnectivityTest)
    if(!$Path){$Path=Join-Path $Script:Reports ('NetworkRepair_Report_{0}.json'-f (Get-Date -Format 'yyyyMMdd_HHmmss'))}
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
            if ($cfg.IPv4DefaultGateway) { $gateway = @($cfg.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop -First 1) }
            $rows += [pscustomobject]@{
                InterfaceAlias = $cfg.InterfaceAlias
                InterfaceIndex = $index
                IPv4Addresses = @($cfg.IPv4Address | ForEach-Object { [string]$_.IPv4Address })
                IPv6Addresses = @($cfg.IPv6Address | ForEach-Object { [string]$_.IPv6Address })
                IPv4Gateway = @($gateway)
                IPv4Dhcp = if ($ipv4Interface) { [string]$ipv4Interface.Dhcp } else { $null }
                IPv6Dhcp = if ($ipv6Interface) { [string]$ipv6Interface.Dhcp } else { $null }
                DnsServersIPv4 = @($dns4)
                DnsServersIPv6 = @($dns6)
            }
        }
    } catch {
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
        [Parameter(Mandatory)][string[]]$ActiveNames,
        [string[]]$NlmActiveNames = @()
    )
    $activeSet = @{}
    foreach ($n in @($ActiveNames + $NlmActiveNames)) { if ($n) { $activeSet[$n.ToLowerInvariant()] = $true } }

    foreach ($p in $RegistryProfiles) {
        if ([string]::IsNullOrWhiteSpace($p.ProfileName)) { continue }
        $name = $p.ProfileName.Trim()
        $numbered = $name -match '^(网络|Network)\s+\d+$'
        $isActive = $activeSet.ContainsKey($name.ToLowerInvariant())
        $managed = ($p.Managed -eq 1 -or $p.Managed -eq $true)
        $score = 0
        $codes = New-Object System.Collections.Generic.List[string]
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($numbered) { $score += 20; [void]$codes.Add('NR1001'); [void]$reasons.Add('名称符合编号网络模式') }
        if ($numbered -and -not $isActive) { $score += 10; [void]$reasons.Add('当前不是活动连接') }
        if ($p.LastWrite -and ((Get-Date) - [datetime]$p.LastWrite).TotalDays -ge 30 -and $numbered) { $score += 10; [void]$reasons.Add('记录已超过 30 天未修改') }
        if ($managed) { $score += 80; [void]$codes.Add('NR1003'); [void]$reasons.Add('Managed Profile，禁止自动修改') }
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
            Reason = if ($reasons.Count) { $reasons -join '；' } else { '正常或未命中安全清理规则' }
            RegistryPath = $p.RegistryPath
            LastWrite = $p.LastWrite
        }
    }
}

function Get-NRDiagnostics {
    param([switch]$SkipConnectivityTest)

    $windows = Get-NRWindowsInfo
    $adapters = Get-NRAdapters
    $connections = Get-NRConnectionProfiles
    $registryProfiles = Get-NRProfileRegistryObjects

    $nlm = Get-NRNetworkListManagerNetworks
    $activeNames = @(Get-NRActiveProfileNames)
    $nlmActiveNames = if ($nlm.Available) { @($nlm.Networks | Where-Object IsConnected | Select-Object -ExpandProperty Name -Unique) } else { @() }
    $suspects = @(Get-NRSuspiciousProfiles -RegistryProfiles $registryProfiles -ActiveNames $activeNames -NlmActiveNames $nlmActiveNames)

    $ip = Get-NRIPDiagnostics
    $gateways = @(Test-NRGateways -Configurations $ip)
    $dnsServers = @(Test-NRDnsServers -Configurations $ip)
    $ncsi = Test-NRNcsi -Skip:$SkipConnectivityTest

    $safeCandidates = @($suspects | Where-Object RemediationAllowed)
    $highRisk = @($suspects | Where-Object RiskLevel -in @('High','Caution'))
    $issueDetails = New-Object System.Collections.Generic.List[object]

    if ($safeCandidates.Count) { [void]$issueDetails.Add([pscustomobject]@{Code='NR1001';Severity='Low';Message=('发现 {0} 个疑似历史/重复网络 Profile。' -f $safeCandidates.Count)}) }
    if ($highRisk.Count) { [void]$issueDetails.Add([pscustomobject]@{Code='NR1002';Severity='Warning';Message=('发现 {0} 个高风险或需人工确认的 Profile。' -f $highRisk.Count)}) }
    if (@($gateways | Where-Object { -not $_.Reachable }).Count) { [void]$issueDetails.Add([pscustomobject]@{Code='NR2201';Severity='Warning';Message='一个或多个默认网关不可达。'}) }
    if (@($dnsServers | Where-Object { -not $_.ResolvesNCSI }).Count) { [void]$issueDetails.Add([pscustomobject]@{Code='NR2101';Severity='Warning';Message='一个或多个配置的 DNS 服务器无法解析 NCSI DNS 主机。'}) }
    if (-not $SkipConnectivityTest -and $ncsi.Enabled -eq 0) { [void]$issueDetails.Add([pscustomobject]@{Code='NR2003';Severity='Warning';Message='NCSI 主动探测已被禁用。'}) }
    if (-not $SkipConnectivityTest -and -not $ncsi.Dns) { [void]$issueDetails.Add([pscustomobject]@{Code='NR2001';Severity='Warning';Message='NCSI DNS 探测失败。'}) }
    if (-not $SkipConnectivityTest -and -not $ncsi.Http) { [void]$issueDetails.Add([pscustomobject]@{Code='NR2002';Severity='Warning';Message='NCSI HTTP Web 探测失败。'}) }

    $connectivity = [pscustomobject]@{
        Skipped = $ncsi.Skipped
        DNS = $ncsi.Dns
        TCP443 = $ncsi.Http
        NCSI = $ncsi
    }

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Windows = $windows
        Adapters = @($adapters)
        Connections = @($connections)
        ActiveProfileNames = @($activeNames)
        NlmActiveProfileNames = @($nlmActiveNames)
        NetworkListManager = $nlm
        RegistryProfiles = @($registryProfiles)
        Candidates = @($suspects)
        IPConfiguration = @($ip)
        Gateways = @($gateways)
        DnsServers = @($dnsServers)
        NCSI = $ncsi
        Connectivity = $connectivity
        Issues = @($issueDetails | ForEach-Object Message)
        IssueDetails = @($issueDetails)
        SafeCandidateCount = $safeCandidates.Count
        HighRiskCount = $highRisk.Count
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
    if ($Diagnostics.NetworkListManager.Available) { Write-NRLine ('已读取 {0} 个网络对象。' -f $Diagnostics.NetworkListManager.Networks.Count) 'Green' }
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

    Write-NRSection '结论'
    if ($Diagnostics.IssueDetails.Count -eq 0) { Write-NRLine '当前没有发现明显问题。' 'Green' }
    else { foreach ($i in $Diagnostics.IssueDetails) { Write-NRLine ('[{0}] {1}' -f $i.Code, $i.Message) 'Yellow' } }
}

