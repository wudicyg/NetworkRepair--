function Get-NRNetworkListManagerNetworks {
    try {
        $manager = New-Object -ComObject NetworkListManager
        # NLM_ENUM_NETWORK_ALL = CONNECTED (1) | DISCONNECTED (2)
        $networks = @($manager.GetNetworks(3))
        $result = foreach ($network in $networks) {
            $category = $null
            $connectivity = $null
            $connections = @()
            try { $category = $network.GetCategory() } catch { Write-NRLog ('NLM GetCategory failed: {0}' -f $_.Exception.Message) 'WARN' }
            try { $connectivity = $network.GetConnectivity() } catch { Write-NRLog ('NLM GetConnectivity failed: {0}' -f $_.Exception.Message) 'WARN' }
            try { $connections = @($network.GetNetworkConnections()) } catch { Write-NRLog ('NLM GetNetworkConnections failed: {0}' -f $_.Exception.Message) 'WARN' }
            [pscustomobject]@{
                NetworkId = [string]$network.NetworkId
                Name = [string]$network.Name
                Description = [string]$network.Description
                IsConnected = [bool]$network.IsConnected
                IsConnectedToInternet = [bool]$network.IsConnectedToInternet
                Category = $category
                Connectivity = $connectivity
                ConnectionCount = $connections.Count
                ConnectionDetails = @($connections | ForEach-Object {
                    [pscustomobject]@{
                        ConnectionId = [string]$_.NetworkAdapterId
                        AdapterName = $null
                        Connected = $null
                    }
                })
            }
        }
        [pscustomobject]@{ Available = $true; Networks = @($result); Error = $null }
    }
    catch {
        Write-NRLog ('Network List Manager COM unavailable: {0}' -f $_.Exception.Message) 'WARN'
        [pscustomobject]@{ Available = $false; Networks = @(); Error = $_.Exception.Message }
    }
}

function Get-NRActiveNetworkNames {
    $n = Get-NRNetworkListManagerNetworks
    if (-not $n.Available) { return @() }
    @($n.Networks | Where-Object { $_.IsConnected -and $_.Name } | Select-Object -ExpandProperty Name -Unique)
}
