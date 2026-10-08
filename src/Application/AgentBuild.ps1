function 清空Agent目录 {
    if (Test-PathEntry $AgentDir) {
        Invoke-RemoveItemWithRetry $AgentDir -Recurse | Out-Null
    }
    EnsureDir $AgentDir
}

function Resolve-SourceBase([string]$vendorName, $cfg) {
    if ($vendorName -eq "manual") { return $null }
    $v = $cfg.vendors | Where-Object { $_.name -eq $vendorName } | Select-Object -First 1
    if (-not $v) { throw "白名单引用了不存在的 vendor：$vendorName" }
    return (VendorPath $v.name)
}

function Get-SkillNameConflictBuckets([string]$agentRoot) {
    $nameToPaths = @{}
    foreach ($skillFile in (Get-ChildItem $agentRoot -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)) {
        $declaredName = $null
        foreach ($line in (Get-Content $skillFile.FullName -TotalCount 80 -ErrorAction SilentlyContinue)) {
            if ($line -match "^\s*name:\s*(.+?)\s*$") {
                $declaredName = $Matches[1].Trim().Trim("'`"")
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($declaredName)) { continue }
        if (-not $nameToPaths.ContainsKey($declaredName)) {
            $nameToPaths[$declaredName] = New-Object System.Collections.Generic.List[string]
        }
        $nameToPaths[$declaredName].Add($skillFile.FullName) | Out-Null
    }
    return $nameToPaths
}

function Test-SkillNameDuplicateContentAllowed([string[]]$paths) {
    if ($null -eq $paths -or $paths.Count -le 1) { return $true }
    $hashes = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $paths) {
        $hash = Get-FileContentHash $path
        if ([string]::IsNullOrWhiteSpace($hash)) { return $false }
        $hashes.Add($hash) | Out-Null
    }
    return ($hashes.Count -le 1)
}

function Test-SkillNameSystemOverrideAllowed([string[]]$paths) {
    if ($null -eq $paths -or $paths.Count -le 1) { return $false }
    $hasSystemPath = $false
    $hasNonSystemPath = $false
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path -match "[\\/]\.system[\\/]") { $hasSystemPath = $true }
        else { $hasNonSystemPath = $true }
    }
    return ($hasSystemPath -and $hasNonSystemPath)
}
function New-AgentMappingResolveContext {
    return @{
        vendor_base = @{}
        manual_source = @{}
        skill_dir_validity = @{}
    }
}
function Resolve-AgentMappingForAgent($cfg, $mapping, [hashtable]$context) {
    if ($null -eq $mapping) { return $null }
    if ($null -eq $context) { $context = New-AgentMappingResolveContext }

    $vendor = [string]$mapping.vendor
    $from = [string]$mapping.from
    $to = [string]$mapping.to
    if (-not (Should-SyncMappingToAgent $mapping)) {
        return [pscustomobject]@{
            sync = $false
            vendor = $vendor
            from = $from
            to = $to
        }
    }

    Need (Test-SafeRelativePath $from -AllowDot) ("非法 mapping.from：{0}" -f $from)
    Need (Test-SafeRelativePath $to) ("非法 mapping.to：{0}" -f $to)

    $src = $null
    $containmentRoot = $null
    if ($vendor -eq "manual") {
        $manualSourceCache = [hashtable]$context["manual_source"]
        if ($manualSourceCache.ContainsKey($from)) {
            $src = [string]$manualSourceCache[$from]
        }
        else {
            $src = [string](Resolve-ManualImportSkillPath $cfg $from -AllowLegacyFallback)
            $manualSourceCache[$from] = $src
        }
        if ([string]::IsNullOrWhiteSpace($src)) {
            return [pscustomobject]@{
                sync = $true
                source_valid = $false
                reason = ("manual 导入不存在或无效：{0}" -f $from)
                vendor = $vendor
                from = $from
                to = $to
            }
        }
        $import = @($cfg.imports | Where-Object { [string]$_.name -eq $from -and [string]$_.mode -eq 'manual' } | Select-Object -First 1)
        $importRoot = if ($import.Count -eq 1) { Join-Path $ImportDir ([string]$import[0].name) } else { '' }
        $containmentRoot = if (-not [string]::IsNullOrWhiteSpace($importRoot) -and (Is-PathInsideOrEqual $src $importRoot)) {
            $importRoot
        }
        else {
            $src
        }
    }
    else {
        $vendorBaseCache = [hashtable]$context["vendor_base"]
        if ($vendorBaseCache.ContainsKey($vendor)) {
            $base = [string]$vendorBaseCache[$vendor]
        }
        else {
            $base = [string](Resolve-SourceBase $vendor $cfg)
            $vendorBaseCache[$vendor] = $base
        }
        $src = Join-Path $base $from
        Need (Is-PathInsideOrEqual $src $base) ("mapping.from 越界：{0}" -f $from)
        $containmentRoot = $base
    }

    $srcFull = [System.IO.Path]::GetFullPath($src)
    $canonicalName = Get-CanonicalSkillTargetName $srcFull $to
    $versionInfo = Get-CfgSchemaVersionInfo $cfg
    Need ($versionInfo.errors.Count -eq 0) (($versionInfo.errors | Select-Object -First 1) -join '')
    if ([int]$versionInfo.effective_version -ge 2) {
        Need ([string]::Equals($to, $canonicalName, [StringComparison]::Ordinal)) `
            ("schema v2 要求 mapping.to 与 SKILL.md name 一致：{0} -> {1}" -f $to, $canonicalName)
    }
    $effectiveTargetName = if ([int]$versionInfo.effective_version -ge 2) { $canonicalName } else { $to }
    $dst = Join-Path $AgentDir $effectiveTargetName
    Need (Is-PathInsideOrEqual $dst $AgentDir) ("mapping.to 越界：{0}" -f $effectiveTargetName)

    return [pscustomobject]@{
        sync = $true
        source_valid = $true
        vendor = $vendor
        from = $from
        to = $effectiveTargetName
        configured_to = $to
        src = [string]$src
        src_full = $srcFull
        src_key = $srcFull.ToLowerInvariant()
        containment_root = [IO.Path]::GetFullPath($containmentRoot)
        dst = $dst
    }
}
function Test-ResolvedAgentMappingSkillDir($resolved, [hashtable]$context) {
    if ($null -eq $resolved -or -not [bool]$resolved.sync -or -not [bool]$resolved.source_valid) { return $false }
    if ($null -eq $context) { $context = New-AgentMappingResolveContext }

    $skillDirValidityCache = [hashtable]$context["skill_dir_validity"]
    $srcKey = [string]$resolved.src_key
    if ($skillDirValidityCache.ContainsKey($srcKey)) {
        return [bool]$skillDirValidityCache[$srcKey]
    }

    $isSkillDir = Test-IsSkillDir ([string]$resolved.src_full)
    $skillDirValidityCache[$srcKey] = $isSkillDir
    return $isSkillDir
}
function Get-ResolvedAgentMappingInvalidReason($resolved) {
    $src = if ($null -ne $resolved -and $resolved.PSObject.Properties.Match("src_full").Count -gt 0) { [string]$resolved.src_full } else { "" }
    if (-not (Test-Path -LiteralPath $src -PathType Container)) { return "源目录不存在" }
    return "缺少标记文件"
}
function Start-BuildTransaction {
    $txnRoot = Join-Path $Root ".txn"
    $txnId = [Guid]::NewGuid().ToString("N").Substring(0, 10)
    $path = Join-Path $txnRoot ("build-{0}" -f $txnId)
    $backupAgent = Join-Path $path "agent.backup"
    $state = [ordered]@{
        path = $path
        backup_agent = $backupAgent
        has_backup_agent = $false
        backup_error = $null
        backup_agent_fingerprint = ''
        agent_before_fingerprint = 'missing'
        agent_after_fingerprint = ''
        agent_after_fingerprint_error = ''
        # 三态区分：absent=构建前无 agent/；backed_up=已挪入事务备份；
        # present_no_backup=备份挪动失败但构建前 agent/ 仍在（回滚必须 fail closed）。
        agent_before_state = "absent"
        config_path = if (-not [string]::IsNullOrWhiteSpace([string]$CfgPath)) { [IO.Path]::GetFullPath($CfgPath) } else { '' }
        config_before_exists = $false
        config_before_bytes = [byte[]]::new(0)
        config_before_hash = ''
        config_after_hash = ''
        manual_migrations = [System.Collections.Generic.List[object]]::new()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$state.config_path) -and (Test-Path -LiteralPath $state.config_path -PathType Leaf)) {
        $state.config_before_exists = $true
        $state.config_before_bytes = [IO.File]::ReadAllBytes($state.config_path)
        $state.config_before_hash = (Get-FileHash -LiteralPath $state.config_path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($DryRun) { return [pscustomobject]$state }
    $agentParent = [IO.Directory]::GetParent([IO.Path]::GetFullPath($AgentDir))
    Need ($null -ne $agentParent -and -not (Test-AncestorChainHasReparse $agentParent.FullName)) ("构建 agent/ 的物理父级链不允许存在 reparse point：{0}" -f $AgentDir)
    $txnParent = [IO.Directory]::GetParent([IO.Path]::GetFullPath($txnRoot))
    Need ($null -ne $txnParent -and -not (Test-AncestorChainHasReparse $txnParent.FullName)) ("构建事务的物理父级链不允许存在 reparse point：{0}" -f $txnRoot)
    $txnRootItem = Get-ExistingFileSystemItem $txnRoot
    if ($null -ne $txnRootItem) {
        Need $txnRootItem.PSIsContainer ("构建事务根必须是目录：{0}" -f $txnRoot)
        Need (($txnRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) ("构建事务根不允许是 reparse point：{0}" -f $txnRoot)
    }
    EnsureDir $txnRoot
    EnsureDir $path
    $txnPathItem = Get-ExistingFileSystemItem $path
    Need ($null -ne $txnPathItem -and $txnPathItem.PSIsContainer -and ($txnPathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) ("构建事务目录不是普通目录：{0}" -f $path)
    $agentItem = Get-ExistingFileSystemItem $AgentDir
    if ($null -ne $agentItem) {
        Need $agentItem.PSIsContainer ("构建前 agent/ 必须是目录：{0}" -f $AgentDir)
        Need (($agentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) ("构建前 agent/ 不允许是 reparse point：{0}" -f $AgentDir)
        $state.agent_before_fingerprint = Get-DirectoryFingerprint $AgentDir
        $state.agent_before_state = "present_no_backup"
        try {
            Invoke-MoveItem $AgentDir $backupAgent
            $state.has_backup_agent = $true
            $state.agent_before_state = "backed_up"
            try {
                $state.backup_agent_fingerprint = Get-DirectoryFingerprint $backupAgent
            }
            catch {
                # The move already succeeded. Preserve the backup and mark the
                # transaction unusable for normal completion; rollback can then
                # retain it instead of deleting the only known copy.
                $state.backup_error = $_.Exception.Message
                Log ("agent/ 已移入事务备份，但备份指纹读取失败；保留备份并阻断本次构建：{0}" -f $_.Exception.Message) "ERROR"
            }
        }
        catch {
            $state.backup_error = $_.Exception.Message
            Log ("旧 agent/ 无法安全挪入事务备份；保留事务现场并阻断本次构建：{0}" -f $_.Exception.Message) "ERROR"
        }
    }
    return [pscustomobject]$state
}

function Restore-BuildConfigAndManualMigration($txn) {
    if ($null -eq $txn) { return }
    $errors = [System.Collections.Generic.List[string]]::new()
    $records = if ($txn.PSObject.Properties.Match('manual_migrations').Count -gt 0) { @($txn.manual_migrations) } else { @() }
    foreach ($record in @($records | Sort-Object backup -Descending)) {
        $source = [string]$record.source
        $backup = [string]$record.backup
        try {
            if (Test-Path -LiteralPath $source) {
                if (Test-Path -LiteralPath $backup) { throw ("manual migration rollback conflict: source and backup both exist: {0}" -f $source) }
                continue
            }
            if (-not (Test-Path -LiteralPath $backup -PathType Container)) { throw ("manual migration backup missing: {0}" -f $backup) }
            $parent = Split-Path -Parent $source
            if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
            Invoke-MoveItem $backup $source
        }
        catch { $errors.Add($_.Exception.Message) | Out-Null }
    }

    $configPath = if ($txn.PSObject.Properties.Match('config_path').Count -gt 0) { [string]$txn.config_path } else { '' }
    $beforeHash = if ($txn.PSObject.Properties.Match('config_before_hash').Count -gt 0) { [string]$txn.config_before_hash } else { '' }
    $afterHash = if ($txn.PSObject.Properties.Match('config_after_hash').Count -gt 0) { [string]$txn.config_after_hash } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($configPath) -and $txn.PSObject.Properties.Match('config_before_exists').Count -gt 0 -and [bool]$txn.config_before_exists) {
        try {
            $currentExists = Test-Path -LiteralPath $configPath -PathType Leaf
            $currentHash = if ($currentExists) { (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
            if ($currentHash -eq $beforeHash) { }
            elseif (-not [string]::IsNullOrWhiteSpace($afterHash) -and $currentHash -eq $afterHash) {
                Write-BytesAtomic -Path $configPath -Bytes ([byte[]]$txn.config_before_bytes)
            }
            else { throw ("构建事务配置已发生并发漂移，拒绝覆盖：{0}" -f $configPath) }
        }
        catch { $errors.Add($_.Exception.Message) | Out-Null }
    }
    if ($errors.Count -gt 0) { throw (($errors | Select-Object -First 10) -join '; ') }
}

function Get-BuildTransactionRecoveryHint($txn) {
    $txnPath = if ($null -ne $txn -and $txn.PSObject.Properties.Match('path').Count -gt 0) { [string]$txn.path } else { '(未知事务目录)' }
    $backupPath = if ($null -ne $txn -and $txn.PSObject.Properties.Match('backup_agent').Count -gt 0) { [string]$txn.backup_agent } else { '' }
    $backupItem = $null
    if (-not [string]::IsNullOrWhiteSpace($backupPath) -and $null -ne $txn -and
        $txn.PSObject.Properties.Match('has_backup_agent').Count -gt 0 -and [bool]$txn.has_backup_agent) {
        try { $backupItem = Get-ExistingFileSystemItem $backupPath }
        catch { $backupItem = $null }
    }
    $backupAvailable = $null -ne $backupItem -and $backupItem.PSIsContainer -and
        (($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
    if ($backupAvailable) {
        return ("事务目录已保留（agent/ 备份目录仍在，恢复前请核验指纹）：{0}" -f $txnPath)
    }
    return ("事务目录已保留（没有可确认的 agent/ 备份；请勿清理事务目录或 agent/ 现场，先人工核查）：{0}" -f $txnPath)
}

function Rollback-BuildTransaction($txn) {
    if ($DryRun -or $null -eq $txn) { return $true }
    $restored = $false
    $restoreError = $null
    # Cold-discovery catalog 阶段会在构建完成后向 agent/ 写入 catalog 文件，
    # 其快照必须先于 agent/ 指纹 CAS 还原：agent_after_fingerprint 采集于
    # 构建完成时刻，带着 catalog 写入比对会被误判为并发漂移。
    $catalogTransaction = if ($txn.PSObject.Properties.Match('catalog_transaction').Count -gt 0) { $txn.catalog_transaction } else { $null }
    $catalogRestoreError = $null
    $configMigrationRestoreError = $null
    try { Restore-BuildConfigAndManualMigration $txn }
    catch { $configMigrationRestoreError = $_.Exception.Message }
    if ($null -ne $catalogTransaction) {
        foreach ($snapshot in @($catalogTransaction.file_snapshots | Sort-Object path -Descending)) {
            try { Restore-SkillProjectionFileTransactionSnapshot $snapshot }
            catch {
                $catalogError = ('cold-discovery catalog rollback failed: {0}' -f $_.Exception.Message)
                $catalogRestoreError = if ([string]::IsNullOrWhiteSpace([string]$catalogRestoreError)) { $catalogError } else { '{0}; {1}' -f $catalogRestoreError, $catalogError }
            }
        }
    }
    try {
        if ([string]$txn.agent_before_state -eq "present_no_backup") {
            # The backup move failed before construction began. If the original
            # directory still matches its pre-build fingerprint, it never left
            # place and needs no restoration; otherwise retain it and the txn.
            $currentItem = Get-ExistingFileSystemItem $AgentDir
            if ($null -eq $currentItem) {
                $restoreError = "构建前 agent/ 未能备份且当前目录已缺失；没有可验证的副本可恢复"
            }
            elseif (-not $currentItem.PSIsContainer -or (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
                $restoreError = "构建前 agent/ 未能备份且当前路径已变为非普通目录；保留现场并拒绝清理"
            }
            else {
                try {
                    $currentFingerprint = Get-DirectoryFingerprint $AgentDir
                    if ([string]::Equals([string]$currentFingerprint, [string]$txn.agent_before_fingerprint, [StringComparison]::OrdinalIgnoreCase)) {
                        $restored = $true
                        Write-Host "旧 agent/ 未发生变化；备份移动失败后无需恢复。" -ForegroundColor Yellow
                    }
                    else {
                        $restoreError = ("构建前 agent/ 未能备份且当前内容已发生变化；保留现场并拒绝清理：expected={0}, actual={1}" -f [string]$txn.agent_before_fingerprint, $currentFingerprint)
                    }
                }
                catch { $restoreError = ("构建前 agent/ 未能备份且无法核对当前指纹；保留现场并拒绝清理：{0}" -f $_.Exception.Message) }
            }
        }
        else {
            $hasFingerprintContract = @('agent_before_fingerprint', 'agent_after_fingerprint', 'agent_after_fingerprint_error') | ForEach-Object {
                $txn.PSObject.Properties.Match($_).Count -gt 0
            } | Where-Object { -not $_ } | Measure-Object | Select-Object -ExpandProperty Count
            if ($hasFingerprintContract -gt 0) {
                $restoreError = '构建事务缺少 agent/ 指纹合同；拒绝删除现场'
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$txn.agent_after_fingerprint_error)) {
                $restoreError = ("构建后 agent/ 指纹不可用：{0}" -f [string]$txn.agent_after_fingerprint_error)
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$txn.agent_after_fingerprint)) {
                $restoreError = '构建事务缺少可靠的构建后 agent/ 指纹；拒绝删除现场'
            }
            else {
                $currentFingerprint = ''
                try {
                    $currentItem = Get-Item -LiteralPath $AgentDir -Force -ErrorAction SilentlyContinue
                    if ($null -ne $currentItem -and (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $currentItem.PSIsContainer)) {
                        throw '当前 agent/ 不是普通目录'
                    }
                    $currentFingerprint = Get-DirectoryFingerprint $AgentDir
                }
                catch {
                    $restoreError = ("无法读取构建后 agent/ 指纹：{0}" -f $_.Exception.Message)
                }
                if ($null -eq $restoreError -and -not [string]::Equals([string]$currentFingerprint, [string]$txn.agent_after_fingerprint, [StringComparison]::OrdinalIgnoreCase)) {
                    $restoreError = ("构建后 agent/ 已发生并发漂移，拒绝覆盖：expected={0}, actual={1}" -f [string]$txn.agent_after_fingerprint, $currentFingerprint)
                }
            }

            # Validate recovery material before moving or deleting the current
            # build. Keep it in the transaction until restoration is verified.
            if ($null -eq $restoreError -and $txn.has_backup_agent) {
                try {
                    $backupItem = Get-Item -LiteralPath $txn.backup_agent -Force -ErrorAction Stop
                    if (-not $backupItem.PSIsContainer -or (Test-AncestorChainHasReparse $txn.backup_agent)) { throw 'agent/ backup is not a regular physical directory' }
                    $backupFingerprint = Get-DirectoryFingerprint $txn.backup_agent
                    if ($txn.PSObject.Properties.Match('backup_agent_fingerprint').Count -eq 0 -or
                        -not [string]::Equals($backupFingerprint, [string]$txn.backup_agent_fingerprint, [StringComparison]::OrdinalIgnoreCase) -or
                        -not [string]::Equals($backupFingerprint, [string]$txn.agent_before_fingerprint, [StringComparison]::OrdinalIgnoreCase)) {
                        throw 'agent/ backup fingerprint drifted; current build was preserved'
                    }
                }
                catch { $restoreError = $_.Exception.Message }
            }
            elseif ($null -eq $restoreError -and ([string]$txn.agent_before_state -ne 'absent' -or [string]$txn.agent_before_fingerprint -ne 'missing')) {
                $restoreError = 'Pre-build agent existed but no verified backup is available'
            }
            $heldAgent = Join-Path $txn.path 'agent.rollback-current'
            $heldCurrent = $false
            if ($null -eq $restoreError -and (Test-PathEntry $AgentDir)) {
                $currentItem = Get-Item -LiteralPath $AgentDir -Force -ErrorAction Stop
                if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $currentItem.PSIsContainer) {
                    $restoreError = '当前 agent/ 在删除前变为非普通目录，拒绝递归删除'
                }
                else {
                    try {
                        if ($txn.has_backup_agent) {
                            if (Test-AncestorChainHasReparse $txn.path) { throw 'Build transaction path crosses a reparse point' }
                            [IO.Directory]::Move($AgentDir, $heldAgent)
                            $heldCurrent = $true
                        }
                        else {
                            $removed = Invoke-RemoveItemWithRetry $AgentDir -Recurse -IgnoreFailure -SilentIgnore
                            if (-not $removed -or (Test-PathEntry $AgentDir)) { $restoreError = '当前 agent/ 未能清空，备份恢复被阻止' }
                        }
                    }
                    catch { $restoreError = $_.Exception.Message }
                }
            }

            if ($null -eq $restoreError -and $txn.has_backup_agent) {
                if (-not (Test-Path -LiteralPath $txn.backup_agent -PathType Container)) {
                    $restoreError = "agent/ 备份不存在"
                }
                elseif (Test-PathEntry $AgentDir) {
                    $restoreError = "当前 agent/ 未能清空，备份恢复被阻止"
                }
                else {
                    try {
                        $backupItem = Get-Item -LiteralPath $txn.backup_agent -Force -ErrorAction Stop
                        if (($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'agent/ 事务备份是 reparse point' }
                        $backupFingerprint = Get-DirectoryFingerprint $txn.backup_agent
                        if ($txn.PSObject.Properties.Match('backup_agent_fingerprint').Count -eq 0 -or
                            -not [string]::Equals([string]$backupFingerprint, [string]$txn.backup_agent_fingerprint, [StringComparison]::OrdinalIgnoreCase)) {
                            throw ("agent/ 事务备份已发生并发漂移：expected={0}, actual={1}" -f [string]$txn.backup_agent_fingerprint, $backupFingerprint)
                        }
                        Invoke-MoveItem $txn.backup_agent $AgentDir
                        $restoredFingerprint = Get-DirectoryFingerprint $AgentDir
                        if (-not [string]::Equals([string]$restoredFingerprint, [string]$txn.agent_before_fingerprint, [StringComparison]::OrdinalIgnoreCase)) {
                            throw ("恢复后的 agent/ 指纹不匹配：expected={0}, actual={1}" -f [string]$txn.agent_before_fingerprint, $restoredFingerprint)
                        }
                        $restored = $true
                        Write-Host "已回滚 agent/ 到构建前状态。" -ForegroundColor Yellow
                    }
                    catch { $restoreError = $_.Exception.Message }
                }
            }
            elseif ($null -eq $restoreError) {
                # 构建前没有 agent/（无备份可恢复）：CAS 清理成功后即回到缺失状态。
                $restored = [string]::Equals([string]$txn.agent_before_fingerprint, 'missing', [StringComparison]::OrdinalIgnoreCase) -and -not (Test-PathEntry $AgentDir)
                if (-not $restored) { $restoreError = '构建前 agent/ 状态不是缺失，拒绝无备份回滚' }
            }
            if (-not $restored -and $heldCurrent -and -not (Test-PathEntry $AgentDir)) {
                try { [IO.Directory]::Move($heldAgent, $AgentDir) }
                catch { $restoreError = '{0}; current build retained at {1}: {2}' -f $restoreError, $heldAgent, $_.Exception.Message }
            }
        }
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace([string]$catalogRestoreError)) {
            $restoreError = if ([string]::IsNullOrWhiteSpace([string]$restoreError)) { $catalogRestoreError } else { '{0}; {1}' -f $restoreError, $catalogRestoreError }
            $restored = $false
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$configMigrationRestoreError)) {
            $restoreError = if ([string]::IsNullOrWhiteSpace([string]$restoreError)) { $configMigrationRestoreError } else { '{0}; {1}' -f $restoreError, $configMigrationRestoreError }
            $restored = $false
        }
        # 仅在恢复成功后清理事务目录；恢复失败时保留目录（含 agent/ 备份）供人工恢复。
        if ($restored -and (Test-PathEntry $txn.path)) {
            $txnRemoved = Invoke-RemoveItemWithRetry $txn.path -Recurse -IgnoreFailure -SilentIgnore
            if (-not $txnRemoved -or (Test-PathEntry $txn.path)) {
                $restored = $false
                $restoreError = '构建事务目录清理未完成，已保留现场'
            }
        }
    }
    if (-not $restored) {
        Log ("构建事务回滚未完成；{0}；原因：{1}" -f (Get-BuildTransactionRecoveryHint $txn), $restoreError) "ERROR"
    }
    return $restored
}

function Complete-BuildTransaction($txn) {
    if ($DryRun -or $null -eq $txn) { return }
    $txnPath = [IO.Path]::GetFullPath([string]$txn.path)
    $txnRoot = [IO.Path]::GetFullPath((Join-Path $Root '.txn'))
    Need (Is-PathInsideOrEqual $txnPath $txnRoot -and -not [string]::Equals($txnPath, $txnRoot, [StringComparison]::OrdinalIgnoreCase)) ("构建事务清理路径越界：{0}" -f $txnPath)
    $txnParent = [IO.Directory]::GetParent($txnPath)
    Need ($null -ne $txnParent -and -not (Test-AncestorChainHasReparse $txnParent.FullName)) ("构建事务清理路径的物理父级链不安全：{0}" -f $txnPath)
    $txnItem = Get-ExistingFileSystemItem $txnPath
    if ($null -eq $txnItem) { return }
    Need $txnItem.PSIsContainer ("构建事务清理目标不是目录：{0}" -f $txnPath)
    Need (($txnItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) ("构建事务清理目标不允许是 reparse point：{0}" -f $txnPath)
    $removed = Invoke-RemoveItemWithRetry $txnPath -Recurse -IgnoreFailure
    Need ($removed -and $null -eq (Get-ExistingFileSystemItem $txnPath)) ("构建事务目录清理未完成：{0}" -f $txnPath)
}

function 构建Agent($cfg = $null, [switch]$SkipPreflight, $Txn = $null, [switch]$SkipLock) {
    if (-not $SkipLock) {
        return (Invoke-WithSkillManagerProjectionLock -ScriptBlock {
            构建Agent $cfg -SkipPreflight:$SkipPreflight -Txn $Txn -SkipLock
        })
    }
    return (& {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        # 备份失败时旧目录可能仍是唯一副本；必须在清空或覆盖之前停止。
        if ($null -ne $Txn -and $Txn.PSObject.Properties.Match('backup_error').Count -gt 0 -and
            -not [string]::IsNullOrWhiteSpace([string]$Txn.backup_error)) {
            return @("build-txn:agent-backup => $($Txn.backup_error)")
        }
        Log "开始构建 Agent..."
        $reusedExistingAgent = $false
        $cleanAgentError = $null
        try {
            清空Agent目录
        }
        catch {
            $reusedExistingAgent = $true
            $cleanAgentError = $_.Exception.Message
            EnsureDir $AgentDir
            Log ("清空 agent/ 失败，将在现有目录上继续覆盖构建：{0}" -f $_.Exception.Message)
        }
        $failures = New-Object System.Collections.Generic.List[string]
        $invalidMappings = New-Object System.Collections.Generic.List[object]
        $stats = [pscustomobject]@{ mirrored = 0; reused = $reusedExistingAgent }
        $resolveContext = New-AgentMappingResolveContext

        foreach ($m in $cfg.mappings) {
            try {
                $resolved = Resolve-AgentMappingForAgent $cfg $m $resolveContext
                if ($null -eq $resolved) { continue }
                if (-not [bool]$resolved.sync) {
                    Log ("跳过 vendor 根映射（不参与同步）：{0}/{1}" -f [string]$resolved.vendor, [string]$resolved.from)
                    continue
                }

                if (-not [bool]$resolved.source_valid) {
                    $invalidMappings.Add([pscustomobject]@{
                            vendor = [string]$resolved.vendor
                            from = [string]$resolved.from
                            to = [string]$resolved.to
                            src = ""
                            reason = [string]$resolved.reason
                        }) | Out-Null
                    continue
                }
                if (-not (Test-ResolvedAgentMappingSkillDir $resolved $resolveContext)) {
                    $invalidReason = Get-ResolvedAgentMappingInvalidReason $resolved
                    Write-Host ("⚠️ 跳过无效技能（{0}）：{1}" -f $invalidReason, [string]$resolved.src_full) -ForegroundColor Yellow
                    $invalidMappings.Add([pscustomobject]@{
                            vendor = [string]$resolved.vendor
                            from = [string]$resolved.from
                            to = [string]$resolved.to
                            src = [string]$resolved.src_full
                            reason = $invalidReason
                        }) | Out-Null
                    continue
                }
                Assert-SkillPackageSafe -Path ([string]$resolved.src_full) -ContainmentRoot ([string]$resolved.containment_root) -Label ("mapping:{0}/{1}" -f [string]$resolved.vendor, [string]$resolved.from) | Out-Null
                RoboMirror ([string]$resolved.src_full) ([string]$resolved.dst)
                $expanded = Expand-RelativeSkillPlaceholders ([string]$resolved.dst)
                if ($expanded -gt 0) { Log ("已展开相对路径 SKILL 占位文件：{0} 项" -f $expanded) }
                $stats.mirrored++
            }
            catch {
                Write-Host ("❌ 处理技能失败 [{0}/{1}]: {2}" -f $m.vendor, $m.from, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("mapping:{0}/{1} => {2}" -f $m.vendor, $m.from, $_.Exception.Message)) | Out-Null
            }
        }

        $manualItems = 收集ManualSkills $cfg
        if ($manualItems.Count -gt 0) {
            $manualMapped = New-Object System.Collections.Generic.HashSet[string]
            foreach ($m in @($cfg.mappings)) {
                if ($m.vendor -eq "manual") { $manualMapped.Add([string]$m.from) | Out-Null }
            }
            $unmappedManual = @($manualItems | Where-Object { -not $manualMapped.Contains([string]$_.from) })
            if ($unmappedManual.Count -gt 0) {
                Log ("检测到 {0} 个 manual imports 未映射；按白名单策略不会进入 agent（可通过【安装】写入 mapping 后生效）。" -f $unmappedManual.Count) "WARN"
            }
        }
        # overrides 覆盖层（可选）：同名目录将覆盖 agent 中对应技能
        foreach ($d in (Get-OverridesDirs)) {
            try {
                Assert-SkillPackageSafe -Path $d.FullName -ContainmentRoot $OverridesDir -Label ("override:{0}" -f $d.Name) | Out-Null
                $targetName = Get-CanonicalSkillTargetName $d.FullName $d.Name
                $dst = Join-Path $AgentDir $targetName
                RoboMirror $d.FullName $dst
                $expanded = Expand-RelativeSkillPlaceholders $dst
                if ($expanded -gt 0) { Log ("已展开相对路径 SKILL 占位文件：{0} 项" -f $expanded) }
                $stats.mirrored++
                Log ("应用覆盖层: {0}" -f $d.Name)
            }
            catch {
                Write-Host ("❌ 应用覆盖层失败 [{0}]: {1}" -f $d.Name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("override:{0} => {1}" -f $d.Name, $_.Exception.Message)) | Out-Null
            }
        }
        $routerScripts = Join-Path $AgentDir 'capability-router/scripts'
        if (-not $DryRun -and (Test-Path -LiteralPath $routerScripts -PathType Container)) {
            Write-Utf8FileAtomic -Path (Join-Path $routerScripts 'execution-admission.ps1') -Content (Get-ExecutionAdmissionRuntimeContent)
        }
        $removedVendorRoots = Remove-VendorRootMappingOutputsFromAgent $cfg
        if ($removedVendorRoots -gt 0) {
            Log ("已剔除 {0} 个 vendor 根映射目录（不参与同步）。" -f $removedVendorRoots)
        }

        $skillMdRepair = Repair-AgentSkillMarkdownFiles $AgentDir
        if ($skillMdRepair.normalized -gt 0) {
            Log ("已归一化 SKILL.md 编码（移除 UTF-8 BOM）：{0} 项" -f $skillMdRepair.normalized)
        }
        if ($skillMdRepair.removed -gt 0) {
            Log ("已清理无效 SKILL.md（缺少 YAML frontmatter）：{0} 项" -f $skillMdRepair.removed) "WARN"
        }
        if ($skillMdRepair.failed -gt 0) {
            foreach ($path in $skillMdRepair.failed_paths) {
                $failures.Add(("build-skill-md-repair:{0}" -f $path)) | Out-Null
            }
        }

        $nameToPaths = Get-SkillNameConflictBuckets $AgentDir
        foreach ($name in $nameToPaths.Keys | Sort-Object) {
            $paths = @($nameToPaths[$name])
            if ($paths.Count -le 1) { continue }
            if (Test-SkillNameDuplicateContentAllowed $paths) {
                Log ("检测到同名同内容技能别名，已跳过冲突：{0}" -f $name)
                continue
            }
            if (Test-SkillNameSystemOverrideAllowed $paths) {
                Log ("检测到系统技能与普通技能同名，已保留系统技能优先：{0}" -f $name)
                continue
            }
            Write-Host ("❌ 技能名冲突：{0}" -f $name) -ForegroundColor Red
            foreach ($p in $paths) { Write-Host ("   - {0}" -f $p) -ForegroundColor Red }
            $failures.Add(("skill-name-conflict:{0} => {1}" -f $name, ($paths -join " | "))) | Out-Null
        }
        if ($stats.reused) {
            Log "本次构建未能清空旧 agent/，已按目录增量覆盖；若仍有陈旧技能残留，可在释放相关文件占用后重试。"
            Write-Host "❌ 检测到在旧 agent/ 上增量覆盖构建，已升级为失败。" -ForegroundColor Red
            Write-Host "   建议：先执行【解除关联】并关闭占用进程，再重试【构建生效】。" -ForegroundColor Red
            if ([string]::IsNullOrWhiteSpace($cleanAgentError)) { $cleanAgentError = "unknown error" }
            $failures.Add(("build-agent-reused-existing-dir => {0}" -f $cleanAgentError)) | Out-Null
        }
        if ($invalidMappings.Count -gt 0) {
            # 部分产物也不能晋级：投影会据此摘除源暂时不可用的既有技能。
            $failures.Add(("build-agent-invalid-mappings => {0} 条映射源无效，拒绝投影不完整产物" -f $invalidMappings.Count)) | Out-Null
            Log ("检测到 {0} 条失效 mappings（源目录不存在或缺少标记文件），建议清理 skills.json。" -f $invalidMappings.Count) "WARN"
            Write-Host ("⚠️ 检测到 {0} 条失效 mappings（未参与同步）。" -f $invalidMappings.Count) -ForegroundColor Yellow
            $preview = @($invalidMappings | Select-Object -First 10)
            foreach ($item in $preview) {
                Write-Host ("   - [{0}] {1} -> {2} ({3})" -f [string]$item.vendor, [string]$item.from, [string]$item.to, [string]$item.reason) -ForegroundColor Yellow
            }
            if ($invalidMappings.Count -gt $preview.Count) {
                Write-Host ("   ... 另有 {0} 条未显示" -f ($invalidMappings.Count - $preview.Count)) -ForegroundColor Yellow
            }
            Write-Host "   建议：删除上述 mappings 后再执行【构建生效】。" -ForegroundColor Yellow
        }
        if ($null -ne $Txn -and -not $DryRun) {
            try {
                $agentItem = Get-Item -LiteralPath $AgentDir -Force -ErrorAction SilentlyContinue
                if ($null -ne $agentItem -and (($agentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $agentItem.PSIsContainer)) {
                    throw '构建后 agent/ 不是普通目录'
                }
                $Txn.agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
                $Txn.agent_after_fingerprint_error = ''
            }
            catch {
                $Txn.agent_after_fingerprint = ''
                $Txn.agent_after_fingerprint_error = $_.Exception.Message
                $failures.Add(("build-txn:agent-after-fingerprint => {0}" -f $_.Exception.Message)) | Out-Null
            }
        }
        $count = @((Get-ChildItem -LiteralPath $AgentDir -Directory -ErrorAction SilentlyContinue)).Count
        Log ("构建完成：agent/ (共 {0} 项技能)" -f $count)
        # mappings 非空却产出零技能说明整条供给链失效；只 WARN 会让空 agent/ 一路
        # 投影到宿主并摘除既有技能。零 mappings 配置（custom-only）不在此列。
        $effectiveMappings = @(@($cfg.mappings) | Where-Object { $null -ne $_ })
        if ($count -eq 0 -and $effectiveMappings.Count -gt 0) {
            Write-Host "❌ 构建产物为空：skills.json 存在 mappings，但 agent/ 未产出任何技能，已升级为失败。" -ForegroundColor Red
            $failures.Add("build-agent-empty => mappings 非空但 agent/ 零技能；请检查上方失效 mappings 与构建 WARN 日志") | Out-Null
        }
        return $failures.ToArray()
    })
}
