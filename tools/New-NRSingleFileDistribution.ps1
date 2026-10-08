#requires -Version 5.1
<#
.SYNOPSIS
    把 NetworkRepair 封装成面向普通用户的单文件分发：压平成单个脚本，并编译成可直接双击的 exe。

.DESCRIPTION
    产出内容：
      NetworkRepair.single.ps1   压平后的单文件脚本（内容与 exe 相同，便于审计与排障）
      网络修复工具.exe            单文件可执行程序（默认带 requireAdministrator 清单）
      启动-网络修复工具.bat       备用启动器（纯 ASCII 内容，用于 exe 被安全软件拦截的情况）

    压平规则：把 NetworkRepair.ps1 中的 `. (Join-Path $Script:Src 'X.ps1')` 行替换为对应模块内容，
    语义与逐文件点源完全一致，但分发时不再依赖 src/ 目录。

.NOTES
    编译 exe 需要 ps2exe 模块与 .NET Framework 的 csc.exe。没有 ps2exe 时可加 -SkipExecutable
    只产出单文件脚本。
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$ExecutableName = '网络修复工具.exe',
    [string]$SingleScriptName = 'NetworkRepair.single.ps1',
    [string]$LauncherDirectory = '备用启动',
    [string]$LauncherName = '启动-网络修复工具.bat',
    [string]$LauncherScriptRelativePath = '..\NetworkRepair.single.ps1',
    [string]$CompanyName = 'wudicyg',
    [string]$Ps2ExeModulePath,
    [switch]$NoElevationManifest,
    [switch]$SkipExecutable,
    [switch]$PreserveOutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$entryPath = Join-Path $Root 'NetworkRepair.ps1'
$sourceDirectory = Join-Path $Root 'src'

function Get-NRDistributionVersion {
    param([Parameter(Mandatory)][string]$EntryPath)

    $content = Get-Content -LiteralPath $EntryPath -Raw -Encoding UTF8
    $match = [regex]::Match($content, '\$Script:AppVersion\s*=\s*''([^'']+)''')
    if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups[1].Value)) {
        throw 'Unable to determine NetworkRepair version from NetworkRepair.ps1.'
    }
    $match.Groups[1].Value
}

function Merge-NRSingleFileScript {
    param(
        [Parameter(Mandatory)][string]$EntryPath,
        [Parameter(Mandatory)][string]$SourceDirectory
    )

    $entryText = [IO.File]::ReadAllText($EntryPath, [Text.Encoding]::UTF8)
    $newLine = "`n"
    if ($entryText -match "`r`n") { $newLine = "`r`n" }

    # 用单引号字符串：正则需要字面量 \$，写在双引号里会被 PowerShell 吃掉转义反斜杠。
    $dotSourcePattern = '^\.\s*\(Join-Path\s+\$Script:Src ''([^'']+)''\)\s*$'
    $builder = New-Object System.Text.StringBuilder
    $inlinedModules = @()
    $missingModules = @()

    foreach ($line in ($entryText -split "`r?`n")) {
        $match = [regex]::Match($line, $dotSourcePattern)
        if (-not $match.Success) {
            [void]$builder.AppendLine($line)
            continue
        }

        $moduleName = $match.Groups[1].Value
        $modulePath = Join-Path $SourceDirectory $moduleName
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            $missingModules += $moduleName
            [void]$builder.AppendLine($line)
            continue
        }

        $inlinedModules += $moduleName
        [void]$builder.AppendLine(('# ======== {0} ========' -f $moduleName))
        $moduleText = [IO.File]::ReadAllText($modulePath, [Text.Encoding]::UTF8)
        if ($moduleText.Length -gt 0 -and $moduleText[0] -eq [char]0xFEFF) { $moduleText = $moduleText.Substring(1) }
        [void]$builder.Append($moduleText.TrimEnd())
        [void]$builder.Append($newLine)
    }

    if ($missingModules.Count -gt 0) {
        throw ('找不到需要内联的模块：{0}' -f ($missingModules -join ', '))
    }
    if ($inlinedModules.Count -eq 0) {
        throw '没有内联任何模块，入口脚本的点源结构可能已经变化。'
    }

    $header = @(
        '# =========================================================================='
        '# 本文件由 tools/New-NRSingleFileDistribution.ps1 自动生成，请勿手工修改。'
        '# 来源：NetworkRepair.ps1 + src/ 下的模块（按入口脚本的点源顺序压平）。'
        ('# 生成时间：{0}' -f (Get-Date).ToString('o'))
        '# =========================================================================='
        ''
    ) -join $newLine

    [pscustomobject]@{
        Text           = ($header + $newLine + $builder.ToString())
        InlinedModules = @($inlinedModules)
        NewLine        = $(if ($newLine -eq "`r`n") { 'CRLF' } else { 'LF' })
    }
}

function New-NRLauncherScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ScriptRelativePath
    )

    # 启动器内容保持纯 ASCII：批处理对中文文件名与代码页很敏感，中文只出现在文件名上。
    $lines = @(
        '@echo off'
        'setlocal'
        'set "SCRIPT=%~dp0{0}"' -f $ScriptRelativePath
        'if not exist "%SCRIPT%" ('
        '  echo [ERROR] NetworkRepair single-file script not found: "%SCRIPT%"'
        '  echo [ERROR] Please keep this launcher inside the original package folder.'
        '  pause'
        '  exit /b 1'
        ')'
        'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*'
        'if errorlevel 1 ('
        '  echo.'
        '  echo [INFO] NetworkRepair exited with code %errorlevel%.'
        '  pause'
        ')'
        'endlocal'
    )
    [IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}

function Get-NRPs2ExeModule {
    param([string]$ModulePath)

    if ($ModulePath) {
        $manifest = Join-Path $ModulePath 'ps2exe.psd1'
        if (-not (Test-Path -LiteralPath $manifest)) { throw ('指定的 ps2exe 目录中没有 ps2exe.psd1：{0}' -f $ModulePath) }
        return $manifest
    }

    $available = Get-Module -ListAvailable -Name ps2exe | Sort-Object Version -Descending | Select-Object -First 1
    if ($available) { return $available.Path }

    $candidates = @(
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules\ps2exe')
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\ps2exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            $found = Get-ChildItem -LiteralPath $candidate -Recurse -Filter 'ps2exe.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    $null
}

function Test-NRExecutableEmbeddedManifest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Marker
    )

    # 编译产物是二进制，这里直接在字节流中查找 ASCII 标记，用于证明清单确实被嵌入。
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $text.Contains($Marker)
}

$version = Get-NRDistributionVersion -EntryPath $entryPath
Write-Verbose ('NetworkRepair version: {0}' -f $version)

if ((Test-Path -LiteralPath $OutputDirectory) -and -not $PreserveOutputDirectory) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$merge = Merge-NRSingleFileScript -EntryPath $entryPath -SourceDirectory $sourceDirectory
$singleScriptPath = Join-Path $OutputDirectory $SingleScriptName
[IO.File]::WriteAllText($singleScriptPath, $merge.Text, (New-Object Text.UTF8Encoding($true)))

$launcherPath = $null
if ($LauncherName) {
    $launcherFolder = $OutputDirectory
    if ($LauncherDirectory) {
        $launcherFolder = Join-Path $OutputDirectory $LauncherDirectory
        New-Item -ItemType Directory -Path $launcherFolder -Force | Out-Null
    }
    $launcherPath = Join-Path $launcherFolder $LauncherName
    New-NRLauncherScript -Path $launcherPath -ScriptRelativePath $LauncherScriptRelativePath
}

$executablePath = $null
$executableManifestVerified = $null
$executableError = $null
if (-not $SkipExecutable) {
    try {
        $ps2exeManifest = Get-NRPs2ExeModule -ModulePath $Ps2ExeModulePath
        if (-not $ps2exeManifest) {
            throw '未找到 ps2exe 模块。请先安装（Install-Module ps2exe -Scope CurrentUser），或使用 -SkipExecutable 只产出单文件脚本。'
        }
        Import-Module $ps2exeManifest -Force

        $executablePath = Join-Path $OutputDirectory $ExecutableName
        $compileArguments = @{
            InputFile   = $singleScriptPath
            OutputFile  = $executablePath
            Title       = 'NetworkRepair'
            Description = 'Windows 网络配置诊断与修复工具'
            Product     = 'NetworkRepair'
            Version     = ('{0}.0' -f $version)
            Company     = $CompanyName
        }
        if (-not $NoElevationManifest) { $compileArguments.RequireAdmin = $true }

        Invoke-ps2exe @compileArguments | Out-Null
        if (-not (Test-Path -LiteralPath $executablePath)) { throw 'exe 编译未产出文件。' }

        if (-not $NoElevationManifest) {
            $executableManifestVerified = Test-NRExecutableEmbeddedManifest -Path $executablePath -Marker 'requireAdministrator'
            if (-not $executableManifestVerified) {
                throw 'exe 中未找到 requireAdministrator 清单标记，提权清单未被嵌入。'
            }
        }
    } catch {
        $executableError = $_.Exception.Message
        if (-not (Test-Path -LiteralPath $executablePath)) { $executablePath = $null }
    }
}

[pscustomobject]@{
    Success               = ($null -eq $executableError)
    Version               = $version
    OutputDirectory       = $OutputDirectory
    SingleScript          = $singleScriptPath
    SingleScriptBytes     = (Get-Item -LiteralPath $singleScriptPath).Length
    InlinedModules        = $merge.InlinedModules
    InlinedModuleCount    = @($merge.InlinedModules).Count
    Launcher              = $launcherPath
    Executable            = $executablePath
    ExecutableBytes       = $(if ($executablePath) { (Get-Item -LiteralPath $executablePath).Length } else { 0 })
    ElevationManifest     = $(if ($NoElevationManifest) { 'none' } else { 'requireAdministrator' })
    ElevationVerified     = $executableManifestVerified
    ExecutableError       = $executableError
} | ConvertTo-Json -Depth 5
