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

function Convert-NRRegSnapshotToCanonicalLines {
    param([Parameter(Mandatory)][string]$Path)
    $lines=Get-Content -LiteralPath $Path -ErrorAction Stop
    $canonical=New-Object System.Collections.Generic.List[string]
    $pending=''
    foreach($raw in @($lines)){
        $line=[string]$raw
        if($line.Length -gt 0 -and $line[0] -eq [char]0xFEFF){$line=$line.Substring(1)}
        $line=$line.Trim()
        if([string]::IsNullOrWhiteSpace($line)){continue}
        if($line -match '^Windows Registry Editor Version 5\.00$'){continue}
        if($line.StartsWith(';')){continue}
        if($pending){$pending+=($line.TrimEnd('\').Trim())}else{$pending=$line.TrimEnd('\').Trim()}
        if($line.EndsWith('\')){continue}
        if($pending -match '^\[(.+)\]$'){[void]$canonical.Add(('K|{0}'-f $Matches[1].ToLowerInvariant()))}
        else {$eq=$pending.IndexOf('=');if($eq -gt 0){$name=$pending.Substring(0,$eq).Trim().ToLowerInvariant();$value=$pending.Substring($eq+1).Trim();[void]$canonical.Add(('V|{0}={1}'-f $name,$value))}}
        $pending=''
    }
    if($pending){throw ('REG 快照存在未完成的续行：{0}'-f $pending)}
    @($canonical | Sort-Object)
}

function Get-NRRegSnapshotHash {
    param([Parameter(Mandatory)][string[]]$CanonicalLines)
    $text=[string]::Join("`n",@($CanonicalLines))
    $bytes=[Text.Encoding]::UTF8.GetBytes($text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
}

function Compare-NRRegSnapshotFiles {
    param([Parameter(Mandatory)][string]$ExpectedPath,[Parameter(Mandatory)][string]$ActualPath)
    $expected=@(Convert-NRRegSnapshotToCanonicalLines -Path $ExpectedPath)
    $actual=@(Convert-NRRegSnapshotToCanonicalLines -Path $ActualPath)
    $expectedHash=Get-NRRegSnapshotHash -CanonicalLines $expected
    $actualHash=Get-NRRegSnapshotHash -CanonicalLines $actual
    $differences=@()
    if($expectedHash -ne $actualHash){$differences=@(Compare-Object -ReferenceObject $expected -DifferenceObject $actual)}
    [pscustomobject]@{Match=($expectedHash -eq $actualHash);ExpectedHash=$expectedHash;ActualHash=$actualHash;ExpectedCount=$expected.Count;ActualCount=$actual.Count;Differences=$differences}
}

function Test-NRRegistrySnapshotMatch {
    param([Parameter(Mandatory)][string]$ExpectedRegistryFile)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_verify_{0}.reg'-f [guid]::NewGuid().ToString('N'))
    try {
        & reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList' $temp /y|Out-Null
        $exitCode=$LASTEXITCODE
        if($exitCode -ne 0 -or -not(Test-Path -LiteralPath $temp)){return [pscustomobject]@{Success=$false;Match=$false;Error=('当前 NetworkList 导出失败，reg.exe exit code={0}'-f $exitCode);ExpectedPath=$ExpectedRegistryFile}}
        $comparison=Compare-NRRegSnapshotFiles -ExpectedPath $ExpectedRegistryFile -ActualPath $temp
        [pscustomobject]@{Success=$true;Match=$comparison.Match;Error=$null;Comparison=$comparison;ExpectedPath=$ExpectedRegistryFile}
    } catch {[pscustomobject]@{Success=$false;Match=$false;Error=$_.Exception.Message;ExpectedPath=$ExpectedRegistryFile}}
    finally {Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
}

function Invoke-NRRestoreSafetyRollback {
    param([Parameter(Mandatory)]$SafetyBackup)
    try {
        Write-NRLog ('Restoring pre-restore safety backup: {0}'-f $SafetyBackup.Path) 'WARN'
        & reg.exe import $SafetyBackup.RegistryBackup|Out-Null
        $exitCode=$LASTEXITCODE
        if($exitCode -ne 0){throw ('安全备份导入失败，reg.exe exit code={0}'-f $exitCode)}
        Restart-NRNetworkServices
        $verification=Test-NRRegistrySnapshotMatch -ExpectedRegistryFile $SafetyBackup.RegistryBackup
        if(-not $verification.Success){throw ('安全备份回滚后的快照校验无法执行：{0}'-f $verification.Error)}
        if(-not $verification.Match){throw '安全备份回滚后的注册表快照与安全备份不一致。'}
        [pscustomobject]@{Success=$true;Verified=$true;Error=$null;Verification=$verification;SafetyBackup=$SafetyBackup.Path}
    } catch {[pscustomobject]@{Success=$false;Verified=$false;Error=$_.Exception.Message;Verification=$null;SafetyBackup=$SafetyBackup.Path}}
}

function Restore-NRBackup {
    param([Parameter(Mandatory)][string]$BackupPath,[switch]$AssumeYes)
    $reg=Resolve-NRBackupRegistryFile -Path $BackupPath
    if(!(Confirm-NRAction -Message ('即将导入备份 {0}，这会覆盖当前 NetworkList 配置。继续？'-f $reg) -AssumeYes:$AssumeYes)){return [pscustomobject]@{Success=$false;Cancelled=$true;Path=$reg}}
    $preRestore=New-NRBackup;Write-NRLog ('Restore safety backup created: {0}'-f $preRestore.Path)
    & reg.exe import $reg|Out-Null
    if($LASTEXITCODE -ne 0){$rollback=Invoke-NRRestoreSafetyRollback -SafetyBackup $preRestore;return [pscustomobject]@{Success=$false;Cancelled=$false;Path=$reg;Error='reg.exe import failed';Rollback=$rollback;SafetyBackup=$preRestore.Path}}
    Restart-NRNetworkServices
    $snapshotVerification=Test-NRRegistrySnapshotMatch -ExpectedRegistryFile $reg
    if(-not $snapshotVerification.Success -or -not $snapshotVerification.Match){
        $reason=if(-not $snapshotVerification.Success){$snapshotVerification.Error}else{'恢复后的 NetworkList 快照与所选备份不一致。'}
        Write-NRLog ('Restore snapshot verification failed: {0}'-f $reason) 'ERROR'
        $rollback=Invoke-NRRestoreSafetyRollback -SafetyBackup $preRestore
        return [pscustomobject]@{Success=$false;Cancelled=$false;Path=$reg;Error=$reason;SnapshotVerification=$snapshotVerification;Rollback=$rollback;SafetyBackup=$preRestore.Path}
    }
    $validation=Get-NRDiagnostics -SkipConnectivityTest
    Write-NRLog 'Restore completed, snapshot verified, and state re-read.'
    [pscustomobject]@{Success=$true;Path=$reg;SafetyBackup=$preRestore.Path;SnapshotVerification=$snapshotVerification;Validation=$validation}
}