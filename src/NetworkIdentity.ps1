function Normalize-NRGuidKey {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return $Value.Trim().Trim('{}').ToLowerInvariant()
}

function Get-NRNetworkIdentityCorrelation {
    param(
        [Parameter(Mandatory)][object[]]$RegistryProfiles,
        [Parameter(Mandatory)][object[]]$NlmNetworks
    )
    $index=@{}
    foreach($n in @($NlmNetworks)){
        $key=Normalize-NRGuidKey -Value $n.NetworkId
        if($key){$index[$key]=$n}
    }
    foreach($p in @($RegistryProfiles)){
        $key=Normalize-NRGuidKey -Value $p.KeyName
        $n=$null
        if($key -and $index.ContainsKey($key)){$n=$index[$key]}
        [pscustomobject]@{
            ProfileKeyName=$p.KeyName
            ProfileName=$p.ProfileName
            NetworkId=if($n){$n.NetworkId}else{$null}
            NetworkName=if($n){$n.Name}else{$null}
            NlmIsConnected=if($n){$n.IsConnected}else{$false}
            NlmIsConnectedToInternet=if($n){$n.IsConnectedToInternet}else{$false}
            NlmConnectionCount=if($n){$n.ConnectionCount}else{0}
            Correlation=if($n){'ExactNetworkId'}else{'None'}
        }
    }
}

function Test-NRNetworkName {
    param([Parameter(Mandatory)][AllowNull()][string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){return [pscustomobject]@{Valid=$false;Reason='网络名称不能为空或只能包含空白字符。'}}
    if($Name.Length -gt 128){return [pscustomobject]@{Valid=$false;Reason='网络名称不能超过 128 个字符。'}}
    if($Name -match '[	\/:*?"<>|]'){return [pscustomobject]@{Valid=$false;Reason='网络名称包含 Windows 不允许的字符。'}}
    [pscustomobject]@{Valid=$true;Reason=$null}
}

function Find-NRNetworkById {
    param([Parameter(Mandatory)][string]$NetworkId)
    $normalized=Normalize-NRGuidKey -Value $NetworkId
    if(-not $normalized){throw 'NetworkId 必须是有效的 GUID。'}
    $all=Get-NRNetworkListManagerNetworks
    if(-not $all.Available){throw 'Network List Manager 当前不可用。'}
    $match=@($all.Networks | Where-Object { (Normalize-NRGuidKey -Value $_.NetworkId) -eq $normalized })
    if($match.Count -ne 1){throw ('未能唯一找到 NetworkId={0} 对应的网络对象。' -f $NetworkId)}
    $match[0]
}

function Rename-NRNetworkName {
    param(
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][string]$NewName,
        [switch]$AssumeYes
    )
    $check=Test-NRNetworkName -Name $NewName
    if(-not $check.Valid){throw $check.Reason}
    $network=Find-NRNetworkById -NetworkId $NetworkId
    if($network.Name -eq $NewName){return [pscustomobject]@{Success=$true;Changed=$false;NetworkId=$NetworkId;OldName=$network.Name;NewName=$NewName}}
    if(-not (Confirm-NRAction -Message ('将网络“{0}”重命名为“{1}”。继续？' -f $network.Name,$NewName) -AssumeYes:$AssumeYes)){
        return [pscustomobject]@{Success=$false;Changed=$false;Cancelled=$true;NetworkId=$NetworkId;OldName=$network.Name;NewName=$NewName}
    }
    $manager=New-Object -ComObject NetworkListManager
    $target=$null
    try {
        foreach($candidate in @($manager.GetNetworks(3))){
            if((Normalize-NRGuidKey -Value $candidate.NetworkId) -eq (Normalize-NRGuidKey -Value $NetworkId)){$target=$candidate;break}
        }
        if($null -eq $target){throw '目标网络对象未找到。'}
        Write-NRLog ('Renaming network {0} ({1}) -> {2}' -f $target.Name,$NetworkId,$NewName)
        $target.SetName($NewName)
    } finally { if($manager){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($manager)} }
    $verify=Find-NRNetworkById -NetworkId $NetworkId
    if($verify.Name -ne $NewName){throw '网络名称修改后验证失败。'}
    [pscustomobject]@{Success=$true;Changed=$true;NetworkId=$NetworkId;OldName=$network.Name;NewName=$verify.Name}
}
