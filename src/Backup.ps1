function New-NRBackup {
    param([ValidateSet('Manual','PreRepair','PreRestore')][string]$Level='Manual')
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff';$dir=Join-Path $Script:Backups $stamp;New-Item -ItemType Directory -Path $dir -Force|Out-Null
    $reg=Join-Path $dir 'NetworkList.reg'
    $profilesReg=Join-Path $dir 'NetworkList-Profiles.reg'
    $newNetworksReg=Join-Path $dir 'NetworkList-NewNetworks.reg'
    $diag=Join-Path $dir 'diagnostic.json';$meta=Join-Path $dir 'manifest.json'
    Write-NRLog ('Creating backup: {0}'-f $dir)
    & reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList' $reg /y|Out-Null
    $regExit=$LASTEXITCODE
    if($regExit -ne 0 -or -not(Test-Path -LiteralPath $reg)){Write-NRLog ('Registry export failed with exit code {0}.'-f $regExit) 'ERROR';Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue;throw ('注册表备份失败，reg.exe exit code={0}'-f $regExit)}
    & reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' $profilesReg /y|Out-Null
    $profilesExit=$LASTEXITCODE
    if($profilesExit -ne 0 -or -not(Test-Path -LiteralPath $profilesReg)){Write-NRLog ('Profiles registry export failed with exit code {0}.'-f $profilesExit) 'ERROR';Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue;throw ('Profiles 注册表备份失败，reg.exe exit code={0}'-f $profilesExit)}
    $newNetworksPath='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\NewNetworks'
    if(Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\NewNetworks'){
        & reg.exe export $newNetworksPath $newNetworksReg /y|Out-Null
        $newNetworksExit=$LASTEXITCODE
        if($newNetworksExit -ne 0 -or -not(Test-Path -LiteralPath $newNetworksReg)){Write-NRLog ('NewNetworks registry export failed with exit code {0}.'-f $newNetworksExit) 'ERROR';Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue;throw ('NewNetworks 注册表备份失败，reg.exe exit code={0}'-f $newNetworksExit)}
    } else {
        $newNetworksReg=$null
        Write-NRLog 'NewNetworks registry key not present; scoped backup skipped.' 'WARN'
    }
    $d=Get-NRDiagnostics -SkipConnectivityTest;$d|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $diag -Encoding UTF8
    [pscustomobject]@{App=$Script:AppName;Version=$Script:AppVersion;Level=$Level;Pinned=$false;Timestamp=(Get-Date).ToString('o');RegistryBackup=$reg;ProfilesBackup=$profilesReg;NewNetworksBackup=$newNetworksReg;DiagnosticSnapshot=$diag;ComputerName=$env:COMPUTERNAME}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $meta -Encoding UTF8
    if(Get-Command Get-NRRestorePoints -ErrorAction SilentlyContinue){$pointCount=@(Get-NRRestorePoints).Count;if($pointCount -gt 20){Write-NRLog ('Restore point count {0} exceeds the warning threshold of 20; consider running restore point pruning.'-f $pointCount) 'WARN'}}
    Write-NRLog ('Backup complete: {0}'-f $dir);[pscustomobject]@{Success=$true;Path=$dir;Level=$Level;RegistryBackup=$reg;ProfilesBackup=$profilesReg;NewNetworksBackup=$newNetworksReg;Manifest=$meta;Diagnostic=$diag}
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

function Resolve-NRScopedBackupFile {
    param(
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][string]$ScopeName
    )
    $full=(Resolve-Path -LiteralPath $BackupPath -ErrorAction Stop).Path
    $dir=$full
    if(-not (Get-Item -LiteralPath $full).PSIsContainer){
        $dir=Split-Path -Parent $full
    }
    $candidate=Join-Path $dir ('NetworkList-{0}.reg'-f $ScopeName)
    if(-not (Test-Path -LiteralPath $candidate)){
        return $null
    }
    $candidate
}

function Test-NRRegistryScopeSnapshotMatch {
    param(
        [Parameter(Mandatory)][string]$ExpectedRegistryFile,
        [Parameter(Mandatory)][string]$RegistryPath
    )
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('NetworkRepair_verify_{0}.reg'-f [guid]::NewGuid().ToString('N'))
    try {
        & reg.exe export $RegistryPath $temp /y|Out-Null
        $exitCode=$LASTEXITCODE
        if($exitCode -ne 0 -or -not(Test-Path -LiteralPath $temp)){
            return [pscustomobject]@{Success=$false;Match=$false;Error=('注册表范围导出失败，reg.exe exit code={0}'-f $exitCode);ExpectedPath=$ExpectedRegistryFile}
        }
        $comparison=Compare-NRRegSnapshotFiles -ExpectedPath $ExpectedRegistryFile -ActualPath $temp
        [pscustomobject]@{Success=$true;Match=$comparison.Match;Error=$null;Comparison=$comparison;ExpectedPath=$ExpectedRegistryFile}
    } catch {
        [pscustomobject]@{Success=$false;Match=$false;Error=$_.Exception.Message;ExpectedPath=$ExpectedRegistryFile}
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NRRestoreSafetyRollback {
    param([Parameter(Mandatory)]$SafetyBackup)
    $scopeMap=@(
        [pscustomobject]@{Name='Profiles';RegistryPath='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles'}
        [pscustomobject]@{Name='NewNetworks';RegistryPath='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\NewNetworks'}
    )
    $results=@()
    $serviceRefresh=$null
    try {
        Write-NRLog ('Restoring pre-restore safety backup: {0}'-f $SafetyBackup.Path) 'WARN'
        foreach($scope in $scopeMap){
            $file=if($scope.Name -eq 'Profiles'){$SafetyBackup.ProfilesBackup}else{$SafetyBackup.NewNetworksBackup}
            if(-not $file -or -not(Test-Path -LiteralPath $file)){continue}
            & reg.exe import $file|Out-Null
            if($LASTEXITCODE -ne 0){throw ('安全备份导入失败，scope={0}，reg.exe exit code={1}'-f $scope.Name,$LASTEXITCODE)}
        }
        $serviceRefresh=Invoke-NRServiceRefresh -Scope 'NetworkList'
        foreach($scope in $scopeMap){
            $file=if($scope.Name -eq 'Profiles'){$SafetyBackup.ProfilesBackup}else{$SafetyBackup.NewNetworksBackup}
            if(-not $file -or -not(Test-Path -LiteralPath $file)){continue}
            $verification=Test-NRRegistryScopeSnapshotMatch -ExpectedRegistryFile $file -RegistryPath $scope.RegistryPath
            $results += [pscustomobject]@{Scope=$scope.Name;Verification=$verification}
            if(-not $verification.Success -or -not $verification.Match){throw ('安全备份回滚后的 {0} 快照与安全备份不一致。'-f $scope.Name)}
        }
        [pscustomobject]@{Success=$true;Verified=$true;Error=$null;Verification=@($results);SafetyBackup=$SafetyBackup.Path;ServiceRefresh=$serviceRefresh}
    } catch {
        [pscustomobject]@{Success=$false;Verified=$false;Error=$_.Exception.Message;Verification=@($results);SafetyBackup=$SafetyBackup.Path;ServiceRefresh=$serviceRefresh}
    }
}

function Restore-NRBackup {
    param([string]$BackupPath,[int]$RestorePointIndex=0,[switch]$AssumeYes)
    if($RestorePointIndex -gt 0){$selected=Resolve-NRRestorePoint -RestorePoints @(Get-NRRestorePoints) -Index $RestorePointIndex;$BackupPath=$selected.Path;Write-NRLog ('Restore point selected: [{0}] {1} ({2})'-f $selected.Index,$selected.Path,$selected.Level)}
    if([string]::IsNullOrWhiteSpace($BackupPath)){throw 'Restore 需要提供 -BackupPath 或 -RestorePointIndex。'}
    $reg=Resolve-NRBackupRegistryFile -Path $BackupPath
    $profilesReg=Resolve-NRScopedBackupFile -BackupPath $reg -ScopeName 'Profiles'
    $newNetworksReg=Resolve-NRScopedBackupFile -BackupPath $reg -ScopeName 'NewNetworks'
    if(-not $profilesReg){
        throw '该备份由旧版本生成，缺少 NetworkList-Profiles.reg。请先用当前版本重新创建备份后再执行 Restore。'
    }
    if(!(Confirm-NRAction -Message ('即将恢复 NetworkRepair 管理的 Profiles/NewNetworks 范围，原始完整备份仍保留。继续？'-f $reg) -AssumeYes:$AssumeYes)){return [pscustomobject]@{Success=$false;Cancelled=$true;Path=$reg}}

    $preRestore=New-NRBackup -Level 'PreRestore'
    try {
        Write-NRLog ('Restore safety backup created: {0}'-f $preRestore.Path)
        & reg.exe import $profilesReg|Out-Null
        if($LASTEXITCODE -ne 0){throw ('Profiles restore failed, reg.exe exit code={0}'-f $LASTEXITCODE)}
        if($newNetworksReg){
            & reg.exe import $newNetworksReg|Out-Null
            if($LASTEXITCODE -ne 0){throw ('NewNetworks restore failed, reg.exe exit code={0}'-f $LASTEXITCODE)}
        }
        $serviceRefresh=Invoke-NRServiceRefresh -Scope 'NetworkList'
        $scopeMap=@(
            [pscustomobject]@{Name='Profiles';File=$profilesReg;RegistryPath='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles'}
            [pscustomobject]@{Name='NewNetworks';File=$newNetworksReg;RegistryPath='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\NewNetworks'}
        )
        $verificationResults=@()
        foreach($scope in $scopeMap){
            if(-not $scope.File){continue}
            $verification=Test-NRRegistryScopeSnapshotMatch -ExpectedRegistryFile $scope.File -RegistryPath $scope.RegistryPath
            $verificationResults += [pscustomobject]@{Scope=$scope.Name;Verification=$verification}
            if(-not $verification.Success -or -not $verification.Match){throw ('恢复后的 {0} 快照与所选备份不一致。'-f $scope.Name)}
        }
        $validation=Get-NRDiagnostics -SkipConnectivityTest
        Write-NRLog 'Restore completed, scoped snapshots verified, and state re-read.'
        return [pscustomobject]@{Success=$true;Path=$reg;SafetyBackup=$preRestore.Path;ScopeVerification=@($verificationResults);Validation=$validation;ServiceRefresh=$serviceRefresh}
    } catch {
        $errorMessage=$_.Exception.Message
        Write-NRLog ('Restore failed: {0}'-f $errorMessage) 'ERROR'
        $rollback=Invoke-NRRestoreSafetyRollback -SafetyBackup $preRestore
        return [pscustomobject]@{Success=$false;Cancelled=$false;Path=$reg;Error=$errorMessage;Rollback=$rollback;SafetyBackup=$preRestore.Path}
    }
}

