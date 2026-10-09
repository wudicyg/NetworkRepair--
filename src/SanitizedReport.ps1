# 脱敏诊断包：只保留排障所需的非敏感摘要，供用户公开发布到 Issue / Discussions。
#
# 与 `Export-NRReport`（`src/Diagnostics.ps1`，完整诊断 JSON）严格区分：
#   * 完整报告包含 MAC 地址、IP 地址、网关、DNS 与 NetworkId，**不能直接公开分享**。
#   * 本模块产出的是脱敏版本：显式排除机器名、MAC、IP、注册表路径、NetworkId、URL 与凭据。
#
# 调用方：
#   * 图形界面「导出诊断报告」按钮走这里（对普通用户是安全默认）。
#   * 命令行 `tools\Export-NRSanitizedDiagnosticBundle.ps1` 走这里（脚本方式的入口）。
#   * 命令行 `-Mode Report` 仍然产出完整报告，但会在控制台打印敏感数据警告。

function ConvertTo-NRSanitizedCandidate {
    <#
        把单个 Profile 候选裁剪成不含任何标识信息的形态：只保留分类、风险与判定结果。
    #>
    param([Parameter(Mandatory)]$Candidate)

    $profileClass = 'Other'
    if ($Candidate.ProfileName -and ([string]$Candidate.ProfileName).Trim() -match '^网络\s+\d+$') {
        $profileClass = 'ChineseNumbered'
    } elseif ($Candidate.ProfileName -and ([string]$Candidate.ProfileName).Trim() -match '^Network\s+\d+$') {
        $profileClass = 'EnglishNumbered'
    }

    [pscustomobject]@{
        ProfileClass       = $profileClass
        Managed            = [bool]$Candidate.Managed
        IsActive           = [bool]$Candidate.IsActive
        RiskScore          = $Candidate.RiskScore
        RiskLevel          = $Candidate.RiskLevel
        RemediationAllowed = [bool]$Candidate.RemediationAllowed
        DiagnosticCodes    = @($Candidate.DiagnosticCodes)
        NetworkCorrelation = [string]$Candidate.NetworkCorrelation
        NlmIsConnected     = [bool]$Candidate.NlmIsConnected
    }
}

function New-NRSanitizedDiagnosticBundle {
    <#
        构建脱敏诊断包对象。只做数据裁剪，不落盘。
    #>
    param(
        [string]$Application = $(if ($Script:AppName) { $Script:AppName } else { 'NetMedic' }),
        [string]$ApplicationVersion = $(if ($Script:AppVersion) { $Script:AppVersion } else { '0.0.0' })
    )

    $diagnostics = Get-NRDiagnostics

    [pscustomobject]@{
        SchemaVersion      = '1.0'
        Sanitized          = $true
        ReadOnly           = $true
        GeneratedAt        = (Get-Date).ToString('o')
        Application        = $Application
        ApplicationVersion = $ApplicationVersion
        Windows            = [pscustomobject]@{
            Caption      = [string]$diagnostics.Windows.Caption
            Version      = [string]$diagnostics.Windows.Version
            Build        = [string]$diagnostics.Windows.Build
            Architecture = [string]$diagnostics.Windows.Architecture
            PowerShell   = [string]$diagnostics.Windows.PowerShell
        }
        NetworkHealth          = $diagnostics.NetworkHealth
        ProfileHygieneStatus   = [string]$diagnostics.ProfileHygieneStatus
        RepairRecommendation   = [string]$diagnostics.RepairRecommendation
        SafeCandidateCount     = [int]$diagnostics.SafeCandidateCount
        HighRiskCount          = [int]$diagnostics.HighRiskCount
        NumberedProfileCount   = @($diagnostics.Candidates | Where-Object {
            $_.ProfileName -and ([string]$_.ProfileName).Trim() -match '^(网络|Network)\s+\d+$'
        }).Count
        CurrentConnections     = @($diagnostics.Connections | ForEach-Object {
            [pscustomobject]@{
                NetworkCategory  = $_.NetworkCategory
                IPv4Connectivity = $_.IPv4Connectivity
                IPv6Connectivity = $_.IPv6Connectivity
            }
        })
        Adapters               = @($diagnostics.Adapters | ForEach-Object {
            [pscustomobject]@{
                Status    = $_.Status
                LinkSpeed = $_.LinkSpeed
                MediaType = $_.MediaType
                Virtual   = $_.Virtual
            }
        })
        NetworkListManager     = [pscustomobject]@{
            Available                     = [bool]$diagnostics.NetworkListManager.Available
            NetworkCount                  = if ($diagnostics.NetworkListManager.Available) { @($diagnostics.NetworkListManager.Networks).Count } else { 0 }
            ExactNetworkIdCorrelationCount = @($diagnostics.NetworkIdentityCorrelations | Where-Object Correlation -eq 'ExactNetworkId').Count
        }
        Candidates             = @($diagnostics.Candidates | ForEach-Object {
            ConvertTo-NRSanitizedCandidate -Candidate $_
        })
        IPConfiguration        = @($diagnostics.IPConfiguration | ForEach-Object {
            [pscustomobject]@{
                InterfaceIndex      = $_.InterfaceIndex
                IPv4AddressCount    = @($_.IPv4Addresses).Count
                IPv6AddressCount    = @($_.IPv6Addresses).Count
                HasIPv4Gateway      = @($_.IPv4Gateway).Count -gt 0
                IPv4Dhcp            = $_.IPv4Dhcp
                IPv6Dhcp            = $_.IPv6Dhcp
                DnsServerIPv4Count  = @($_.DnsServersIPv4).Count
                DnsServerIPv6Count  = @($_.DnsServersIPv6).Count
            }
        })
        GatewayDiagnostics     = [pscustomobject]@{
            TestedCount = @($diagnostics.Gateways).Count
            FailedCount = @($diagnostics.Gateways | Where-Object { -not $_.Reachable }).Count
        }
        DnsDiagnostics         = [pscustomobject]@{
            TestedCount = @($diagnostics.DnsServers).Count
            FailedCount = @($diagnostics.DnsServers | Where-Object { -not $_.ResolvesNCSI }).Count
        }
        NCSI                   = [pscustomobject]@{
            Skipped = [bool]$diagnostics.NCSI.Skipped
            Enabled = $diagnostics.NCSI.Enabled
            Dns     = $diagnostics.NCSI.Dns
            Http    = $diagnostics.NCSI.Http
        }
        IssueDetails           = @($diagnostics.IssueDetails | Select-Object Code, Severity, Message)
        DiagnosticErrorCount   = @($diagnostics.DiagnosticsErrors).Count
        Redaction              = [pscustomobject]@{
            ComputerName = $true
            MacAddress   = $true
            IPAddress    = $true
            RegistryPath = $true
            NetworkId    = $true
            NetworkUrl   = $true
            Credentials  = $true
        }
    }
}

function Export-NRSanitizedDiagnosticBundle {
    <#
        生成脱敏诊断包 zip。返回结构化结果，失败时抛异常由调用方处理。
    #>
    param([string]$Path)

    $bundle = New-NRSanitizedDiagnosticBundle
    $json = $bundle | ConvertTo-Json -Depth 12

    if (-not $Path) {
        $reportsDirectory = if ($Script:Reports) { $Script:Reports } else { [IO.Path]::GetTempPath() }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = Join-Path $reportsDirectory ('NetMedic_Sanitized_{0}.zip' -f $stamp)
    }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('NetMedic_Sanitized_{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $jsonPath = Join-Path $tempDir 'diagnostic.json'
        $readmePath = Join-Path $tempDir 'README.txt'
        $json | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        @(
            'NetMedic sanitized diagnostic bundle'
            ''
            'This bundle is read-only diagnostic evidence.'
            'It intentionally excludes computer name, MAC addresses, IP addresses, registry paths, NetworkId values, URLs, and credentials.'
        ) | Set-Content -LiteralPath $readmePath -Encoding UTF8

        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $Path -Force
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Success             = $true
        Path                = $Path
        Sanitized           = $true
        ReadOnly            = $true
        SafeCandidateCount  = $bundle.SafeCandidateCount
        ProfileHygieneStatus = $bundle.ProfileHygieneStatus
        NetworkHealth       = $bundle.NetworkHealth.Status
    }
}
