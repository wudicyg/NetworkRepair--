function New-NRBackup {
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff';$dir=Join-Path $Script:Backups $stamp;New-Item -ItemType Directory -Path $dir -Force|Out-Null
    $reg=Join-Path $dir 'NetworkList.reg';$diag=Join-Path $dir 'diagnostic.json';$meta=Join-Path $dir 'manifest.json'
    Write-NRLog ('Creating backup: {0}'-f $dir);& reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList' $reg /y|Out-Null;$regExit=$LASTEXITCODE
    if($regExit -ne 0 -or -not(Test-Path -LiteralPath $reg)){Write-NRLog ('Registry export failed with exit code {0}.'-f $regExit) 'ERROR';Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue;throw ('注册表备份失败，reg.exe exit code={0}'-f $regExit)}
    $d=Get-NRDiagnostics -SkipConnectivityTest;$d|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $diag -Encoding UTF8
    [pscustomobject]@{App=$Script:AppName;Version=$Script:AppVersion;Timestamp=(Get-Date).ToString('o');RegistryBackup=$reg;DiagnosticSnapshot=$diag;ComputerName=$env:COMPUTERNAME}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $meta -Encoding UTF8
    Write-NRLog ('Backup complete: {0}'-f $dir);[pscustomobject]@{Success=$true;Path=$dir;RegistryBackup=$reg;Manifest=$meta;Diagnostic=$diag}
}
function Resolve-NRBackupRegistryFile {
    param([Parameter(Mandatory)][string]$Path)
    $full=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if((Get-Item -LiteralPath $full).PSIsContainer){$candidate=Join-Path $full 'NetworkList.reg';if(!(Test-Path -LiteralPath $candidate)){throw '备份目录中未找到 NetworkList.reg。'};return $candidate}
    if([IO.Path]::GetExtension($full).ToLowerInvariant() -ne '.reg'){throw 'Restore 目前仅接受包含 NetworkList.reg 的备份目录或 .reg 文件。'};$full
}
function Restore-NRBackup {
    param([Parameter(Mandatory)][string]$BackupPath,[switch]$AssumeYes)
    $reg=Resolve-NRBackupRegistryFile -Path $BackupPath
    if(!(Confirm-NRAction -Message ('即将导入备份 {0}，这会覆盖当前 NetworkList 配置。继续？'-f $reg) -AssumeYes:$AssumeYes)){return [pscustomobject]@{Success=$false;Cancelled=$true;Path=$reg}}
    $preRestore=New-NRBackup;Write-NRLog ('Restore safety backup created: {0}'-f $preRestore.Path)
    & reg.exe import $reg|Out-Null
    if($LASTEXITCODE -ne 0){
        Write-NRLog ('Registry import failed with exit code {0}; attempting rollback.'-f $LASTEXITCODE) 'ERROR'
        try{& reg.exe import $preRestore.RegistryBackup|Out-Null;Restart-NRNetworkServices;return [pscustomobject]@{Success=$false;Cancelled=$false;Path=$reg;Error='reg.exe import failed';Rollback=$true;SafetyBackup=$preRestore.Path}}
        catch{return [pscustomobject]@{Success=$false;Cancelled=$false;Path=$reg;Error='reg.exe import failed and rollback failed';Rollback=$false;SafetyBackup=$preRestore.Path}}
    }
    Restart-NRNetworkServices;$validation=Get-NRDiagnostics -SkipConnectivityTest;Write-NRLog 'Restore completed and state re-read.'
    [pscustomobject]@{Success=$true;Path=$reg;SafetyBackup=$preRestore.Path;Validation=$validation}
}
