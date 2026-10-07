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
function Get-NRDiagnostics {
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
