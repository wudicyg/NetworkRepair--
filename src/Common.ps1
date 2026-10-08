function Initialize-NRPaths {
    foreach ($p in @($Script:Backups, $Script:Logs, $Script:Reports)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}
function New-NRLogFile { Join-Path $Script:Logs ('NetworkRepair_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff')) }
function Write-NRLog {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    Add-Content -LiteralPath $Script:LogFile -Value ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level,$Message) -Encoding UTF8
}
function Write-NRLine { param([string]$Message,[string]$Color='Gray'); if ($NoColor) { Write-Host $Message } else { Write-Host $Message -ForegroundColor $Color } }
function Write-NRSection { param([Parameter(Mandatory)][string]$Title); Write-NRLine ''; Write-NRLine ('--- {0} ---' -f $Title) 'Cyan'; Write-NRLog $Title }
function Assert-NRAdministrator {
    param([string]$RelaunchArguments)
    $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $principal=New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ([string]::IsNullOrWhiteSpace($RelaunchArguments)) { $RelaunchArguments='-Mode Menu' }
        $scriptPath=Join-Path $Script:Root 'NetworkRepair.ps1'
        $argText='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $scriptPath,$RelaunchArguments
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argText -Verb RunAs | Out-Null
        exit 0
    }
    Write-NRLog 'Administrator privileges confirmed.'
}
function Confirm-NRAction { param([Parameter(Mandatory)][string]$Message,[switch]$AssumeYes); if ($AssumeYes) { return $true }; (Read-Host ('{0} [Y/N]' -f $Message)) -match '^(?i)(y|yes|是|确认)$' }
function Get-NRPropertyValue {
    param(
        [object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $InputObject) { return $null }
    try {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    } catch { }
    return $null
}
function Get-NRRegistryRoot { 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList' }
function Get-NRProfileRegistryObjects {
    $base=Join-Path (Get-NRRegistryRoot) 'Profiles'; if (-not (Test-Path -LiteralPath $base)) { return @() }
    $result=foreach($item in Get-ChildItem -LiteralPath $base -ErrorAction Stop){
        $props=Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction SilentlyContinue
        $lastWrite=$null
        try {
            $lastWriteProperty=$item.PSObject.Properties['LastWriteTime']
            if ($null -ne $lastWriteProperty) {
                $lastWrite=$lastWriteProperty.Value
            }
        } catch {
            $lastWrite=$null
        }
        [pscustomobject]@{KeyName=$item.PSChildName;ProfileName=[string](Get-NRPropertyValue -InputObject $props -Name 'ProfileName');Description=[string](Get-NRPropertyValue -InputObject $props -Name 'Description');Category=Get-NRPropertyValue -InputObject $props -Name 'Category';Managed=Get-NRPropertyValue -InputObject $props -Name 'Managed';RegistryPath=$item.PSPath;LastWrite=$lastWrite}
    }; @($result)
}
function Get-NRActiveProfileNames { try { @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object Name | Select-Object -ExpandProperty Name -Unique) } catch { Write-NRLog ('Get-NetConnectionProfile failed: {0}' -f $_.Exception.Message) 'WARN'; @() } }
function Get-NRWindowsInfo { $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; [pscustomobject]@{Caption=$os.Caption;Version=$os.Version;Build=$os.BuildNumber;Architecture=$os.OSArchitecture;PowerShell=$PSVersionTable.PSVersion.ToString()} }
