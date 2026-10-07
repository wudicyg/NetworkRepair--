$Script:NcsiRegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'

function Get-NRNcsiConfiguration {
    $item = Get-ItemProperty -LiteralPath $Script:NcsiRegistryPath -ErrorAction SilentlyContinue
    [pscustomobject]@{
        RegistryPath = $Script:NcsiRegistryPath
        EnableActiveProbing = if ($null -eq $item) { $null } else { $item.EnableActiveProbing }
        ActiveDnsProbeHost = if ($null -eq $item) { $null } else { [string]$item.ActiveDnsProbeHost }
        ActiveDnsProbeContent = if ($null -eq $item) { $null } else { [string]$item.ActiveDnsProbeContent }
        ActiveWebProbeHost = if ($null -eq $item) { $null } else { [string]$item.ActiveWebProbeHost }
        ActiveWebProbePath = if ($null -eq $item) { $null } else { [string]$item.ActiveWebProbePath }
        ActiveWebProbeContent = if ($null -eq $item) { $null } else { [string]$item.ActiveWebProbeContent }
    }
}

function Test-NRNcsi {
    param([switch]$Skip)
    if ($Skip) {
        return [pscustomobject]@{ Skipped = $true; Enabled = $null; Dns = $null; Http = $null; DnsHost = $null; WebUrl = $null; DnsError = $null; HttpError = $null; Configuration = $null }
    }

    $config = Get-NRNcsiConfiguration
    $dnsHost = if ($config.ActiveDnsProbeHost) { $config.ActiveDnsProbeHost } else { 'dns.msftncsi.com' }
    $webHost = if ($config.ActiveWebProbeHost) { $config.ActiveWebProbeHost } else { 'www.msftconnecttest.com' }
    $webPath = if ($config.ActiveWebProbePath) { $config.ActiveWebProbePath.TrimStart('/') } else { 'connecttest.txt' }
    $expected = if ($config.ActiveWebProbeContent) { $config.ActiveWebProbeContent } else { 'Microsoft Connect Test' }
    $dnsOk = $false
    $httpOk = $false
    $dnsError = $null
    $httpError = $null

    try { Resolve-DnsName -Name $dnsHost -ErrorAction Stop | Out-Null; $dnsOk = $true }
    catch { $dnsError = $_.Exception.Message }

    $url = 'http://{0}/{1}' -f $webHost, $webPath
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $body = [string]$response.Content
        $httpOk = ($response.StatusCode -eq 200 -and $body -like ('*' + $expected + '*'))
        if (-not $httpOk) { $httpError = 'HTTP 探测响应与预期内容不匹配。' }
    }
    catch { $httpError = $_.Exception.Message }

    [pscustomobject]@{
        Skipped = $false
        Enabled = $config.EnableActiveProbing
        Dns = $dnsOk
        Http = $httpOk
        DnsHost = $dnsHost
        WebUrl = $url
        DnsError = $dnsError
        HttpError = $httpError
        Configuration = $config
    }
}
