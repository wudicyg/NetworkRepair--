# 更新检查：查询 GitHub 发布页的最新版本，并与当前版本比较。
#
# 设计约束：
#   1. **只检查、只告知**。不自动下载、不自动替换自身——自替换会引入提权、代码签名与回滚风险，
#      与项目「先诊断、先备份、可回滚」的安全姿态不符。用户自己决定是否下载新版本。
#   2. 网络失败绝不致命：统一返回结构化结果，由调用方决定怎么提示。
#   3. 版本解析与比较是纯函数，可在无网络环境下单元测试。
#   4. 只访问 GitHub 公开的发布信息，不上报任何本机数据。
#
# 数据源选择（实测结论）：
#   * 首选 releases.atom：公开、无需令牌、**没有速率限制**。
#   * 后备 REST API：信息更全（附件、预发布标记），但匿名调用每个 IP 每小时仅 60 次，
#     实测在共享出口 IP 上会直接返回 403——所以只能当后备，绝不能当唯一路径。

function ConvertTo-NRVersionParts {
    <#
        把 'v1.2.0' / '1.2.0' / '1.2.0-beta.1' 解析成可比较的结构；无法解析时返回 $null。
    #>
    param([AllowNull()][AllowEmptyString()][string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }

    $text = $Version.Trim()
    if ($text.StartsWith('v') -or $text.StartsWith('V')) { $text = $text.Substring(1) }

    $match = [regex]::Match($text, '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.\-]+))?$')
    if (-not $match.Success) { return $null }

    [pscustomobject]@{
        Major      = [int]$match.Groups[1].Value
        Minor      = [int]$match.Groups[2].Value
        Patch      = [int]$match.Groups[3].Value
        PreRelease = $(if ($match.Groups[4].Success) { [string]$match.Groups[4].Value } else { $null })
    }
}

function Compare-NRVersion {
    <#
        比较两个版本号：左侧较旧返回 -1，相同返回 0，左侧较新返回 1；无法解析返回 $null。
        规则遵循语义化版本：主/次/修订号逐位比较；数字相同时，有预发布后缀的一方更旧。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Left,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Right
    )

    $l = ConvertTo-NRVersionParts -Version $Left
    $r = ConvertTo-NRVersionParts -Version $Right
    if (-not $l -or -not $r) { return $null }

    foreach ($field in @('Major', 'Minor', 'Patch')) {
        if ($l.$field -lt $r.$field) { return -1 }
        if ($l.$field -gt $r.$field) { return 1 }
    }

    $leftPre = [string]$l.PreRelease
    $rightPre = [string]$r.PreRelease
    if (-not $leftPre -and -not $rightPre) { return 0 }
    if (-not $leftPre -and $rightPre) { return 1 }    # 正式版 > 同号预发布
    if ($leftPre -and -not $rightPre) { return -1 }

    $comparison = [string]::Compare($leftPre, $rightPre, [StringComparison]::OrdinalIgnoreCase)
    if ($comparison -lt 0) { return -1 }
    if ($comparison -gt 0) { return 1 }
    0
}

function Get-NRCurrentVersion {
    [string](Get-Variable -Name 'AppVersion' -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
}

function Enable-NRModernTls {
    <#
        Windows PowerShell 5.1 的默认安全协议可能只含 TLS 1.0/1.1，而 GitHub 只接受 TLS 1.2+。
        这里只做「加法」：未启用 TLS 1.2 时补上它。若当前是 SystemDefault 就交给操作系统决定
        （把 SystemDefault 改写成「仅 TLS 1.2」反而会劣化现代系统上的表现——实测过）。
        返回原值，由调用方负责恢复。
    #>
    $original = [Net.ServicePointManager]::SecurityProtocol
    $tls12 = [Net.SecurityProtocolType]::Tls12
    if ($original -ne [Net.SecurityProtocolType]::SystemDefault -and ([int]$original -band [int]$tls12) -ne [int]$tls12) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]([int]$original -bor [int]$tls12)
        Write-NRSafeLog 'TLS 1.2 has been enabled for the update check.' 'INFO'
    }
    $original
}

function Get-NRReleaseFromAtomFeed {
    <#
        从 releases.atom 读取最新发布。返回 @{ TagName; Version; Url; PublishedAt; Name } 或 $null。
        默认跳过预发布（按语义化版本后缀判断）。
    #>
    param(
        [string]$Repository = 'wudicyg/netmedic',
        [int]$TimeoutSeconds = 10,
        [switch]$IncludePrerelease
    )

    $uri = 'https://github.com/{0}/releases.atom' -f $Repository
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSeconds
    $xml = [xml]$response.Content

    foreach ($entry in @($xml.feed.entry)) {
        $href = [string]$entry.link.href

        # 标签名优先从链接取（/releases/tag/v1.2.0）：标题是发布者自定义的，链接才可靠。
        $tag = $null
        $linkMatch = [regex]::Match($href, '/releases/tag/([^/?#]+)')
        if ($linkMatch.Success) { $tag = $linkMatch.Groups[1].Value }
        if (-not $tag) {
            $titleMatch = [regex]::Match([string]$entry.title, 'v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.\-]+)?')
            if ($titleMatch.Success) { $tag = $titleMatch.Value }
        }
        if (-not $tag) { continue }

        $parts = ConvertTo-NRVersionParts -Version $tag
        if (-not $parts) { continue }
        if ($parts.PreRelease -and -not $IncludePrerelease) { continue }

        $version = $tag
        if ($version.StartsWith('v') -or $version.StartsWith('V')) { $version = $version.Substring(1) }

        return [pscustomobject]@{
            TagName     = $tag
            Version     = $version
            Url         = $href
            PublishedAt = [string]$entry.updated
            Name        = [string]$entry.title
        }
    }

    $null
}

function Get-NRReleaseFromApi {
    <#
        从 REST API 读取最新发布（信息更全，但匿名调用有速率限制，只作后备）。
    #>
    param(
        [string]$Repository = 'wudicyg/netmedic',
        [string]$ApiUrl = 'https://api.github.com',
        [int]$TimeoutSeconds = 10
    )

    $uri = '{0}/repos/{1}/releases/latest' -f $ApiUrl.TrimEnd('/'), $Repository
    $headers = @{
        Accept       = 'application/vnd.github+json'
        'User-Agent' = 'NetMedic-UpdateCheck'
    }
    $release = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec $TimeoutSeconds

    $tag = [string]$release.tag_name
    $version = $tag
    if ($version.StartsWith('v') -or $version.StartsWith('V')) { $version = $version.Substring(1) }

    [pscustomobject]@{
        TagName      = $tag
        Version      = $version
        Url          = [string]$release.html_url
        PublishedAt  = [string]$release.published_at
        Name         = [string]$release.name
        Assets       = @($release.assets | ForEach-Object { [string]$_.name })
        IsPrerelease = [bool]$release.prerelease
    }
}

function Get-NRLatestRelease {
    <#
        查询最新发布版本。先试 releases.atom，失败再试 REST API。
        返回结构化结果；两个数据源都失败时 Success=$false 且带 Error，绝不抛异常。
    #>
    param(
        [string]$Repository = 'wudicyg/netmedic',
        [string]$ApiUrl = 'https://api.github.com',
        [string]$CurrentVersion,
        [int]$TimeoutSeconds = 10,
        [switch]$IncludePrerelease
    )

    if ([string]::IsNullOrWhiteSpace($CurrentVersion)) { $CurrentVersion = Get-NRCurrentVersion }

    $result = [pscustomobject]@{
        Success        = $false
        Source         = $null
        CurrentVersion = $CurrentVersion
        Version        = $null
        TagName        = $null
        Name           = $null
        Url            = $null
        PublishedAt    = $null
        Assets         = @()
        IsPrerelease   = $false
        Comparison     = $null
        IsNewer        = $false
        Error          = $null
    }

    $originalProtocol = Enable-NRModernTls
    try {
        $errors = New-Object System.Collections.Generic.List[string]

        # 数据源 1：releases.atom（公开、无速率限制）
        try {
            $feed = Get-NRReleaseFromAtomFeed -Repository $Repository -TimeoutSeconds $TimeoutSeconds -IncludePrerelease:$IncludePrerelease
            if ($feed) {
                $result.Success = $true
                $result.Source = 'atom'
                $result.TagName = $feed.TagName
                $result.Version = $feed.Version
                $result.Name = $feed.Name
                $result.Url = $feed.Url
                $result.PublishedAt = $feed.PublishedAt
            } else {
                [void]$errors.Add('releases.atom 未返回可解析的正式发布')
            }
        } catch {
            [void]$errors.Add(('releases.atom: {0}' -f $_.Exception.Message))
        }

        # 数据源 2：REST API（信息更全；匿名有速率限制，因此只作后备）
        if (-not $result.Success) {
            try {
                $api = Get-NRReleaseFromApi -Repository $Repository -ApiUrl $ApiUrl -TimeoutSeconds $TimeoutSeconds
                if ($api -and -not [string]::IsNullOrWhiteSpace($api.TagName)) {
                    $result.Success = $true
                    $result.Source = 'api'
                    $result.TagName = $api.TagName
                    $result.Version = $api.Version
                    $result.Name = $api.Name
                    $result.Url = $api.Url
                    $result.PublishedAt = $api.PublishedAt
                    $result.Assets = @($api.Assets)
                    $result.IsPrerelease = $api.IsPrerelease
                } else {
                    [void]$errors.Add('REST API 未返回可解析的发布')
                }
            } catch {
                [void]$errors.Add(('REST API: {0}' -f $_.Exception.Message))
            }
        }

        if ($result.Success) {
            $comparison = Compare-NRVersion -Left $CurrentVersion -Right $result.Version
            $result.Comparison = $comparison
            $result.IsNewer = ($null -ne $comparison -and $comparison -lt 0)
        } else {
            $result.Error = ($errors -join '；')
            Write-NRSafeLog ('Update check failed: {0}' -f $result.Error) 'WARN'
        }
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalProtocol
    }

    $result
}

function Get-NRUpdateCheckMessage {
    <#
        把检查结果转成一句中文结论，供命令行与界面复用。
    #>
    param([Parameter(Mandatory)]$Result)

    if (-not $Result.Success) {
        return ('无法检查更新：{0}（当前版本 {1}）' -f $Result.Error, $Result.CurrentVersion)
    }
    if ($Result.IsNewer) {
        return ('发现新版本 {0}（当前 {1}），下载地址：{2}' -f $Result.Version, $Result.CurrentVersion, $Result.Url)
    }
    if ($null -eq $Result.Comparison) {
        return ('最新版本 {0}；当前版本 {1} 无法解析比较，请手动确认。' -f $Result.Version, $Result.CurrentVersion)
    }
    return ('已是最新版本 {0}（最新发布 {1}）。' -f $Result.CurrentVersion, $Result.Version)
}
