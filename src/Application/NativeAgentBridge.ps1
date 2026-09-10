$nativeAgentBridgeRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }

function Get-NativeAgentBridgeValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-NativeAgentBridgeSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return ([string](Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash).ToLowerInvariant()
}

function Get-NativeAgentBridgeBytesSha256([byte[]]$Bytes) {
    if ($null -eq $Bytes) { return '' }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-NativeAgentBridgeItem([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'native agent bridge path is required.' }
    try { return Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch {
        if ($_.Exception -is [System.Management.Automation.ItemNotFoundException]) { return $null }
        throw
    }
}

function Get-NativeAgentBridgeFileState([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $item = Get-NativeAgentBridgeItem $fullPath
    if ($null -eq $item) {
        return [pscustomobject][ordered]@{
            path = $fullPath
            exists = $false
            kind = 'missing'
            hash = ''
            bytes = [byte[]]@()
        }
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        return [pscustomobject][ordered]@{
            path = $fullPath
            exists = $true
            kind = 'reparse'
            hash = ''
            bytes = [byte[]]@()
        }
    }
    if ($item.PSIsContainer) {
        return [pscustomobject][ordered]@{
            path = $fullPath
            exists = $true
            kind = 'directory'
            hash = ''
            bytes = [byte[]]@()
        }
    }
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    return [pscustomobject][ordered]@{
        path = $fullPath
        exists = $true
        kind = 'file'
        hash = Get-NativeAgentBridgeBytesSha256 $bytes
        bytes = $bytes
    }
}

function Test-NativeAgentBridgeFileStateEquivalent($Expected, $Actual) {
    if ($null -eq $Expected -or $null -eq $Actual) { return $false }
    foreach ($field in @('exists', 'kind', 'hash')) {
        if (-not [string]::Equals([string]$Expected.$field, [string]$Actual.$field, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

function Get-NativeAgentBridgeTextFromBytes([byte[]]$Bytes, [string]$Path) {
    try { return ([System.Text.UTF8Encoding]::new($false, $true)).GetString($Bytes).TrimStart([char]0xFEFF) }
    catch { throw ('native agent bridge file is not valid UTF-8: {0}' -f $Path) }
}

function Resolve-NativeAgentBridgePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'native_agent_bridge path is required.' }
    $resolved = $Path.Trim()
    if ($resolved.StartsWith('~')) { $resolved = $resolved -replace '^~', [Environment]::GetFolderPath('UserProfile') }
    if (-not [IO.Path]::IsPathRooted($resolved)) { $resolved = Join-Path $Root $resolved }
    return [IO.Path]::GetFullPath($resolved)
}

function Test-NativeAgentBridgeWithin([string]$Path, [string]$RootPath) {
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    return $candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith(($root + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Get-NativeAgentBridgeBackupRoot([string]$TargetRoot) {
    if ([string]::IsNullOrWhiteSpace($TargetRoot)) { throw 'native agent target root is required for backup placement.' }
    $target = [IO.Path]::GetFullPath($TargetRoot)
    $codexRoot = Split-Path -Parent $target
    if ([string]::IsNullOrWhiteSpace($codexRoot)) { throw 'native agent backup root cannot be resolved.' }
    $backupRoot = [IO.Path]::GetFullPath((Join-Path $codexRoot 'skills-manager-agent-backups'))
    if (Test-NativeAgentBridgeWithin $backupRoot $target) { throw 'native agent backups must stay outside the host agent discovery root.' }
    return $backupRoot
}

function Move-NativeAgentBridgeLegacyBackups([string]$TargetRoot, [string]$BackupRoot, [System.Collections.Generic.List[object]]$MigrationLog) {
    $target = [IO.Path]::GetFullPath($TargetRoot)
    $legacyRoot = Join-Path $target 'skills-manager-backups'
    $destinationRoot = [IO.Path]::GetFullPath($BackupRoot)
    # 账本可穿越异常：传入调用方持有的 List 时逐条落账，中途 throw 时已迁移
    # 条目仍在账上，回滚循环才能把部分迁移如实搬回；缺省行为保持不变。
    # 注意必须直接赋值：`$x = if (...) { $list }` 会把 List 按管线展开，
    # 空 List 会把 $x 置为 null，后续 .Add 直接炸。
    $migrations = $MigrationLog
    if ($null -eq $migrations) { $migrations = New-Object System.Collections.Generic.List[object] }
    $legacyItem = Get-NativeAgentBridgeItem $legacyRoot
    if ($null -eq $legacyItem) { return @($migrations.ToArray()) }
    if (-not $legacyItem.PSIsContainer -or [bool]($legacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ('legacy native agent backup root is not a regular directory: {0}' -f $legacyRoot)
    }
    if (Test-NativeAgentBridgeWithin $destinationRoot $target) { throw 'native agent backup destination must stay outside the host agent discovery root.' }

    Assert-NativeSkillProjectionPathHasNoReparseAncestor $legacyRoot ([IO.Path]::GetPathRoot($target))
    Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $destinationRoot) ([IO.Path]::GetPathRoot($destinationRoot))
    $destinationItem = Get-NativeAgentBridgeItem $destinationRoot
    if ($null -ne $destinationItem -and (-not $destinationItem.PSIsContainer -or [bool]($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        throw ('native agent backup destination is not a regular directory: {0}' -f $destinationRoot)
    }

    $newMigrations = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-ChildItem -LiteralPath $legacyRoot -Force -ErrorAction Stop | Sort-Object Name)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('legacy native agent backup contains a reparse point: {0}' -f $entry.FullName)
        }
        if ($entry.PSIsContainer -or $entry.Extension -ne '.toml') { continue }
        $legacyFile = Get-NativeAgentBridgeFileState $entry.FullName
        Need ($legacyFile.kind -eq 'file') ('legacy native agent backup is not a regular file: {0}' -f $entry.FullName)
        $content = Get-NativeAgentBridgeTextFromBytes $legacyFile.bytes $entry.FullName
        if ($content -notmatch '(?m)^# skills-manager-native-agent-bridge: v1\s*$') { continue }
        $nameMatch = [regex]::Match($content, '(?m)^name\s*=\s*"([^"]+)"\s*$')
        if (-not $nameMatch.Success) { throw ('legacy native agent backup lacks a role name: {0}' -f $legacyFile.path) }
        $template = Get-NativeAgentBridgeTemplateRecord $legacyFile.path $nameMatch.Groups[1].Value
        Need ([string]::Equals([string]$template.sha256, [string]$legacyFile.hash, [StringComparison]::OrdinalIgnoreCase)) ('legacy native agent backup changed while it was being validated: {0}' -f $legacyFile.path)

        if ($null -eq (Get-NativeAgentBridgeItem $destinationRoot)) {
            New-Item -ItemType Directory -Path $destinationRoot -Force -ErrorAction Stop | Out-Null
            $destinationItem = Get-NativeAgentBridgeItem $destinationRoot
            if ($null -eq $destinationItem -or -not $destinationItem.PSIsContainer -or [bool]($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw ('native agent backup destination was not created as a regular directory: {0}' -f $destinationRoot)
            }
        }
        $destinationPath = Join-Path $destinationRoot (Split-Path -Leaf $legacyFile.path)
        $destinationState = Get-NativeAgentBridgeFileState $destinationPath
        $destinationPreexisted = [bool]$destinationState.exists
        if ($destinationPreexisted) {
            if ($destinationState.kind -ne 'file' -or -not [string]::Equals([string]$legacyFile.hash, [string]$destinationState.hash, [StringComparison]::OrdinalIgnoreCase)) {
                throw ('legacy native agent backup destination conflicts: {0}' -f $destinationPath)
            }
            Need (Test-NativeAgentBridgeFileStateEquivalent $legacyFile (Get-NativeAgentBridgeFileState $legacyFile.path)) ('legacy native agent backup changed before migration: {0}' -f $legacyFile.path)
            Remove-Item -LiteralPath $legacyFile.path -Force -ErrorAction Stop
        }
        else {
            Need (Test-NativeAgentBridgeFileStateEquivalent $legacyFile (Get-NativeAgentBridgeFileState $legacyFile.path)) ('legacy native agent backup changed before migration: {0}' -f $legacyFile.path)
            Need (Test-NativeAgentBridgeFileStateEquivalent $destinationState (Get-NativeAgentBridgeFileState $destinationPath)) ('legacy native agent backup destination appeared during migration: {0}' -f $destinationPath)
            Move-Item -LiteralPath $legacyFile.path -Destination $destinationPath -ErrorAction Stop
        }
        $destinationAfter = Get-NativeAgentBridgeFileState $destinationPath
        Need ($destinationAfter.kind -eq 'file' -and [string]::Equals([string]$destinationAfter.hash, [string]$legacyFile.hash, [StringComparison]::OrdinalIgnoreCase)) ('legacy native agent backup migration verification failed: {0}' -f $destinationPath)
        Need ((Get-NativeAgentBridgeFileState $legacyFile.path).kind -eq 'missing') ('legacy native agent backup source remains after migration: {0}' -f $legacyFile.path)
        $migration = [pscustomobject][ordered]@{
            source_path = $legacyFile.path
            destination_path = $destinationPath
            destination_preexisted = $destinationPreexisted
            content_sha256 = [string]$legacyFile.hash
            source_removed = $true
            legacy_root_removed = $false
        }
        $migrations.Add($migration) | Out-Null
        $newMigrations.Add($migration) | Out-Null
    }

    if (@(Get-ChildItem -LiteralPath $legacyRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $legacyRoot -Force -ErrorAction Stop
        foreach ($migration in $newMigrations) { $migration.legacy_root_removed = $true }
    }
    return @($migrations.ToArray())
}

function Restore-NativeAgentBridgeLegacyMigration($Migration) {
    $sourcePath = [string]$Migration.source_path
    $destinationPath = [string]$Migration.destination_path
    $legacyRoot = Split-Path -Parent $sourcePath
    $destinationRoot = Split-Path -Parent $destinationPath
    $expectedHash = if ($Migration.PSObject.Properties.Match('content_sha256').Count -gt 0) { [string]$Migration.content_sha256 } elseif ($Migration.PSObject.Properties.Match('source_sha256').Count -gt 0) { [string]$Migration.source_sha256 } else { '' }
    Need ($expectedHash -match '^[a-f0-9]{64}$') ('legacy native agent migration lacks a valid content hash: {0}' -f $sourcePath)
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $legacyRoot ([IO.Path]::GetPathRoot($sourcePath))
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $destinationRoot ([IO.Path]::GetPathRoot($destinationPath))

    $destination = Get-NativeAgentBridgeFileState $destinationPath
    Need ($destination.kind -eq 'file' -and [string]::Equals([string]$destination.hash, $expectedHash, [StringComparison]::OrdinalIgnoreCase)) ('legacy native agent migration destination changed concurrently: {0}' -f $destinationPath)
    $source = Get-NativeAgentBridgeFileState $sourcePath
    if ($source.kind -eq 'reparse' -or $source.kind -eq 'directory') {
        throw ('legacy native agent migration source is not a regular file: {0}' -f $sourcePath)
    }
    if ($source.kind -eq 'file') {
        Need ([string]::Equals([string]$source.hash, $expectedHash, [StringComparison]::OrdinalIgnoreCase)) ('legacy native agent migration source already exists with different content: {0}' -f $sourcePath)
        Need ([bool]$Migration.destination_preexisted) ('legacy native agent migration source appeared while destination was transaction-owned: {0}' -f $sourcePath)
    }
    else {
        $legacyItem = Get-NativeAgentBridgeItem $legacyRoot
        if ($null -eq $legacyItem) {
            New-Item -ItemType Directory -Path $legacyRoot -Force -ErrorAction Stop | Out-Null
            $legacyItem = Get-NativeAgentBridgeItem $legacyRoot
        }
        if ($null -eq $legacyItem -or -not $legacyItem.PSIsContainer -or [bool]($legacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw ('legacy native agent migration source parent is not a regular directory: {0}' -f $legacyRoot)
        }
        if ([bool]$Migration.destination_preexisted) {
            Write-BytesAtomic -Path $sourcePath -Bytes ([byte[]]$destination.bytes)
        }
        else {
            Move-Item -LiteralPath $destinationPath -Destination $sourcePath -ErrorAction Stop
        }
    }

    $restoredSource = Get-NativeAgentBridgeFileState $sourcePath
    Need ($restoredSource.kind -eq 'file' -and [string]::Equals([string]$restoredSource.hash, $expectedHash, [StringComparison]::OrdinalIgnoreCase)) ('legacy native agent migration source was not restored: {0}' -f $sourcePath)
    $restoredDestination = Get-NativeAgentBridgeFileState $destinationPath
    if ([bool]$Migration.destination_preexisted) {
        Need ($restoredDestination.kind -eq 'file' -and [string]::Equals([string]$restoredDestination.hash, $expectedHash, [StringComparison]::OrdinalIgnoreCase)) ('legacy native agent migration pre-existing destination changed during restore: {0}' -f $destinationPath)
    }
    else {
        Need ($restoredDestination.kind -eq 'missing') ('legacy native agent migration destination remains after restore: {0}' -f $destinationPath)
    }
}

function Assert-NativeAgentBridgeTemplateContent([string]$Content, [string]$SourcePath, [string]$Name) {
    $content = $Content.TrimStart([char]0xFEFF)
    if ($content -notmatch '(?m)^# skills-manager-native-agent-bridge: v1\s*$') { throw ("native agent template lacks ownership marker: {0}" -f $SourcePath) }
    if ($content -notmatch ('(?m)^name\s*=\s*"{0}"\s*$' -f [regex]::Escape($Name))) { throw ("native agent template name mismatch: {0}" -f $SourcePath) }
    foreach ($field in @('description', 'developer_instructions')) {
        if ($content -notmatch ('(?m)^{0}\s*=' -f $field)) { throw ("native agent template lacks {0}: {1}" -f $field, $SourcePath) }
    }
}

function Get-NativeAgentBridgeTemplateRecord($SourcePath, [string]$Name) {
    $state = Get-NativeAgentBridgeFileState $SourcePath
    Need ($state.kind -eq 'file') ("native agent template is not a regular file: {0}" -f $SourcePath)
    $content = Get-NativeAgentBridgeTextFromBytes $state.bytes $SourcePath
    Assert-NativeAgentBridgeTemplateContent $content $SourcePath $Name
    return [pscustomobject][ordered]@{
        path = [string]$state.path
        content = $content.TrimStart([char]0xFEFF)
        bytes = [byte[]]$state.bytes
        sha256 = [string]$state.hash
    }
}

function Get-NativeAgentBridgeTemplate($SourcePath, [string]$Name) {
    return [string](Get-NativeAgentBridgeTemplateRecord $SourcePath $Name).content
}

function Sync-NativeAgentBridge($Config, $PromotionContext = $null, [switch]$SkipLock) {
    if (-not $SkipLock -and -not $DryRun) {
        return (Invoke-WithSkillManagerProjectionLock -ScriptBlock {
            Sync-NativeAgentBridge $Config $PromotionContext -SkipLock
        })
    }

    $bridge = Get-NativeAgentBridgeValue (Get-NativeAgentBridgeValue $Config 'skill_projection') 'native_agent_bridge'
    if ($null -eq $bridge -or -not [bool](Get-NativeAgentBridgeValue $bridge 'enabled')) {
        return [pscustomobject]@{ enabled = $false; persisted = $false; changed_names = @(); receipt_path = ''; truth_boundary = 'not_configured' }
    }

    $sourceRoot = Resolve-NativeAgentBridgePath ([string](Get-NativeAgentBridgeValue $bridge 'source_root'))
    $targetRoot = Resolve-NativeAgentBridgePath ([string](Get-NativeAgentBridgeValue $bridge 'target_root'))
    $receiptPath = Resolve-NativeAgentBridgePath ([string](Get-NativeAgentBridgeValue $bridge 'receipt_path'))
    $managedRoot = [IO.Path]::GetFullPath($AgentDir)
    if (-not (Test-NativeAgentBridgeWithin $sourceRoot $managedRoot)) { throw 'native_agent_bridge.source_root must stay under generated agent/.' }
    $expectedTargetRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\agents'))
    if (-not [string]::Equals($targetRoot, $expectedTargetRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'native_agent_bridge.target_root must be ~/.codex/agents.' }
    $backupRoot = Get-NativeAgentBridgeBackupRoot $targetRoot
    $codexRoot = Split-Path -Parent $targetRoot
    $receiptRoot = Join-Path $Root 'reports\native-agent-bridge'
    if (-not (Test-NativeAgentBridgeWithin $receiptPath $receiptRoot) -or [string]::Equals($receiptPath, [IO.Path]::GetFullPath($receiptRoot), [StringComparison]::OrdinalIgnoreCase)) { throw 'native_agent_bridge.receipt_path must be a file under reports/native-agent-bridge/.' }
    if (-not $DryRun -and ($null -eq $PromotionContext -or -not [bool](Get-NativeAgentBridgeValue $PromotionContext 'required'))) {
        throw 'native_agent_bridge host write requires a verified host projection promotion context.'
    }
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $sourceRoot $managedRoot
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $targetRoot ([Environment]::GetFolderPath('UserProfile'))
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $backupRoot $codexRoot
    Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $receiptPath) $receiptRoot
    $receiptItem = Get-NativeAgentBridgeItem $receiptPath
    if ($null -ne $receiptItem) {
        if ($receiptItem.PSIsContainer -or [bool]($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'native agent bridge receipt must be a regular file.' }
    }

    $names = @((Get-NativeAgentBridgeValue $bridge 'definitions') | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($names.Count -eq 0) { throw 'native_agent_bridge.definitions must not be empty.' }
    $planned = New-Object System.Collections.Generic.List[object]
    foreach ($name in $names) {
        if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$') { throw ("native_agent_bridge definition is invalid: {0}" -f $name) }
        $sourcePath = Join-Path $sourceRoot ($name + '.toml')
        $template = Get-NativeAgentBridgeTemplateRecord $sourcePath $name
        $planned.Add([pscustomobject][ordered]@{
                name = $name
                source_path = $sourcePath
                target_path = (Join-Path $targetRoot ($name + '.toml'))
                content = [string]$template.content
                bytes = [byte[]]$template.bytes
                source_sha256 = [string]$template.sha256
            }) | Out-Null
    }

    if ($DryRun) {
        return [pscustomobject]@{ enabled = $true; persisted = $false; changed_names = @($planned | ForEach-Object name); receipt_path = $receiptPath; truth_boundary = 'planned'; definitions = @($planned | Select-Object name, source_path, target_path, source_sha256) }
    }

    $targetRootItem = Get-NativeAgentBridgeItem $targetRoot
    $targetRootExisted = $null -ne $targetRootItem
    if ($targetRootExisted -and (-not $targetRootItem.PSIsContainer -or [bool]($targetRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        throw ('native agent target root is not a regular directory: {0}' -f $targetRoot)
    }
    $targetRootCreationClaimed = -not $targetRootExisted
    $before = @{}
    $after = @{}
    $changed = New-Object System.Collections.Generic.List[string]
    $backups = New-Object System.Collections.Generic.List[string]
    $backupRecords = New-Object System.Collections.Generic.List[object]
    $legacyBackupMigrations = @()
    $legacyMigrationLog = New-Object System.Collections.Generic.List[object]
    try {
        if ($targetRootCreationClaimed) {
            New-Item -ItemType Directory -Path $targetRoot -Force -ErrorAction Stop | Out-Null
            $targetRootItem = Get-NativeAgentBridgeItem $targetRoot
            if ($null -eq $targetRootItem -or -not $targetRootItem.PSIsContainer -or [bool]($targetRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw ('native agent target root was not created as a regular directory: {0}' -f $targetRoot)
            }
        }
        Assert-NativeSkillProjectionPathHasNoReparseAncestor $targetRoot ([Environment]::GetFolderPath('UserProfile'))
        $legacyBackupMigrations = @(Move-NativeAgentBridgeLegacyBackups $targetRoot $backupRoot $legacyMigrationLog)
        foreach ($definition in $planned.ToArray()) {
            $targetPath = [string]$definition.target_path
            Need (Test-NativeAgentBridgeWithin $targetPath $targetRoot) ("native agent target escaped its owned root: {0}" -f $targetPath)
            Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $targetPath) $targetRoot

            $sourceState = Get-NativeAgentBridgeFileState ([string]$definition.source_path)
            Need ($sourceState.kind -eq 'file' -and [string]::Equals([string]$sourceState.hash, [string]$definition.source_sha256, [StringComparison]::OrdinalIgnoreCase)) ("native agent template changed after planning: {0}" -f $definition.source_path)
            $current = Get-NativeAgentBridgeFileState $targetPath
            $before[$targetPath] = $current
            if ($current.kind -eq 'reparse' -or $current.kind -eq 'directory') { throw ("native agent target must be a regular file: {0}" -f $targetPath) }
            if ($current.kind -eq 'file') {
                $existing = Get-NativeAgentBridgeTextFromBytes $current.bytes $targetPath
                if ($existing -notmatch '(?m)^# skills-manager-native-agent-bridge: v1\s*$') { throw ("native agent target is not owned by skills-manager: {0}" -f $targetPath) }
            }
            if ($current.kind -eq 'file' -and [string]::Equals([string]$current.hash, [string]$definition.source_sha256, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $beforeWrite = Get-NativeAgentBridgeFileState $targetPath
            Need (Test-NativeAgentBridgeFileStateEquivalent $current $beforeWrite) ("native agent target changed while it was being planned: {0}" -f $targetPath)
            if ($current.kind -eq 'file') {
                $backupRootItem = Get-NativeAgentBridgeItem $backupRoot
                if ($null -eq $backupRootItem) {
                    New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
                    $backupRootItem = Get-NativeAgentBridgeItem $backupRoot
                }
                if (-not $backupRootItem.PSIsContainer -or [bool]($backupRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('native agent backup root is not a regular directory: {0}' -f $backupRoot) }
                $backupPath = Join-Path $backupRoot ('{0}.{1}.{2}.toml' -f $definition.name, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N')))
                Write-BytesAtomic -Path $backupPath -Bytes ([byte[]]$current.bytes)
                $backupState = Get-NativeAgentBridgeFileState $backupPath
                Need ($backupState.kind -eq 'file' -and [string]::Equals([string]$backupState.hash, [string]$current.hash, [StringComparison]::OrdinalIgnoreCase)) ("native agent backup verification failed: {0}" -f $backupPath)
                $backups.Add($backupPath) | Out-Null
                $backupRecords.Add([pscustomobject][ordered]@{ path = $backupPath; sha256 = [string]$current.hash }) | Out-Null
            }
            Write-BytesAtomic -Path $targetPath -Bytes ([byte[]]$definition.bytes)
            $written = Get-NativeAgentBridgeFileState $targetPath
            Need ($written.kind -eq 'file' -and [string]::Equals([string]$written.hash, [string]$definition.source_sha256, [StringComparison]::OrdinalIgnoreCase)) ("native agent target verification failed: {0}" -f $targetPath)
            $after[$targetPath] = $written
            $changed.Add([string]$definition.name) | Out-Null
        }
        Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $receiptPath) $receiptRoot
        $receipt = [ordered]@{
            schema_version = 1
            status = 'applied'
            owner = [string](Get-NativeAgentBridgeValue $bridge 'owner')
            applied_at = [DateTimeOffset]::UtcNow.ToString('o')
            source_root = $sourceRoot
            target_root = $targetRoot
            source_revision = if ($null -ne $PromotionContext) { [string](Get-NativeAgentBridgeValue $PromotionContext 'source_revision') } else { '' }
            source_worktree_dirty = if ($null -ne $PromotionContext) { [bool](Get-NativeAgentBridgeValue $PromotionContext 'source_worktree_dirty') } else { $false }
            source_git_state = if ($null -ne $PromotionContext) { [string](Get-NativeAgentBridgeValue $PromotionContext 'source_git_state') } else { 'not_evaluated_dry_run' }
            promotion_mode = if ($null -ne $PromotionContext) { [string](Get-NativeAgentBridgeValue $PromotionContext 'promotion_mode') } else { 'dry_run' }
            changed_names = @($changed.ToArray() | Sort-Object)
            backup_root = $backupRoot
            backup_paths = @($backups.ToArray())
            legacy_backup_migrations = @($legacyBackupMigrations)
            definitions = @($planned | ForEach-Object {
                    $targetState = Get-NativeAgentBridgeFileState ([string]$_.target_path)
                    $beforeState = if ($before.ContainsKey([string]$_.target_path)) { $before[[string]$_.target_path] } else { $null }
                    [ordered]@{
                        name = $_.name
                        source_sha256 = $_.source_sha256
                        before_sha256 = if ($null -eq $beforeState) { '' } else { [string]$beforeState.hash }
                        target_sha256 = [string]$targetState.hash
                    }
                })
            provider_calls = 0
            native_mutations = $changed.Count + $legacyBackupMigrations.Count
            writes = $changed.Count + $legacyBackupMigrations.Count
            truth_boundary = 'filesystem_projected'
        }
        $receiptDirectory = Split-Path -Parent $receiptPath
        $receiptDirectoryItem = Get-NativeAgentBridgeItem $receiptDirectory
        if ($null -eq $receiptDirectoryItem) {
            New-Item -ItemType Directory -Path $receiptDirectory -Force -ErrorAction Stop | Out-Null
            $receiptDirectoryItem = Get-NativeAgentBridgeItem $receiptDirectory
        }
        if ($null -eq $receiptDirectoryItem -or -not $receiptDirectoryItem.PSIsContainer -or [bool]($receiptDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('native agent bridge receipt directory is not a regular directory: {0}' -f $receiptDirectory) }
        Write-Utf8FileAtomic -Path $receiptPath -Content ($receipt | ConvertTo-Json -Depth 12)
        $persistedReceipt = Get-NativeAgentBridgeFileState $receiptPath
        Need ($persistedReceipt.kind -eq 'file') ('native agent bridge receipt was not persisted: {0}' -f $receiptPath)
        $persistedReceiptObject = Get-NativeAgentBridgeTextFromBytes $persistedReceipt.bytes $receiptPath | ConvertFrom-Json
        Need ([string]$persistedReceiptObject.status -eq 'applied') ('native agent bridge receipt verification failed: {0}' -f $receiptPath)
    }
    catch {
        $failure = $_
        $rollbackErrors = New-Object System.Collections.Generic.List[string]
        foreach ($definition in @($planned | Sort-Object target_path -Descending)) {
            $targetPath = [string]$definition.target_path
            if (-not $before.ContainsKey($targetPath)) { continue }
            try {
                $previous = $before[$targetPath]
                $current = Get-NativeAgentBridgeFileState $targetPath
                if (Test-NativeAgentBridgeFileStateEquivalent $previous $current) { continue }
                Need ($after.ContainsKey($targetPath)) ("native agent target changed without an expected after-state: {0}" -f $targetPath)
                Need (Test-NativeAgentBridgeFileStateEquivalent $after[$targetPath] $current) ("native agent target changed concurrently; rollback refused: {0}" -f $targetPath)
                Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $targetPath) $targetRoot
                if ($previous.kind -eq 'missing') {
                    Need ($current.kind -eq 'file') ("refusing to remove unexpected native agent target during rollback: {0}" -f $targetPath)
                    Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
                }
                else {
                    Need ($previous.kind -eq 'file') ("refusing to restore a non-file native agent target: {0}" -f $targetPath)
                    Write-BytesAtomic -Path $targetPath -Bytes ([byte[]]$previous.bytes)
                }
                Need (Test-NativeAgentBridgeFileStateEquivalent $previous (Get-NativeAgentBridgeFileState $targetPath)) ('native agent target rollback verification failed: {0}' -f $targetPath)
            }
            catch { $rollbackErrors.Add(('target:{0} => {1}' -f $targetPath, $_.Exception.Message)) | Out-Null }
        }

        # 用可穿越异常的账本（含部分迁移）回滚，而不是只看已赋值的完整返回值。
        foreach ($migration in @($legacyMigrationLog.ToArray() | Sort-Object destination_path -Descending)) {
            try {
                Restore-NativeAgentBridgeLegacyMigration $migration
            }
            catch { $rollbackErrors.Add(('legacy:{0} => {1}' -f [string]$migration.source_path, $_.Exception.Message)) | Out-Null }
        }

        # Recovery material remains available whenever any rollback step failed.
        # If cleanup is safe, compare the recorded hash before deleting each
        # backup so a concurrent edit is never silently discarded.
        if ($rollbackErrors.Count -eq 0) {
            foreach ($backup in @($backupRecords.ToArray())) {
                try {
                    $backupState = Get-NativeAgentBridgeFileState ([string]$backup.path)
                    Need ($backupState.kind -eq 'file' -and [string]::Equals([string]$backupState.hash, [string]$backup.sha256, [StringComparison]::OrdinalIgnoreCase)) ('native agent backup changed concurrently: {0}' -f [string]$backup.path)
                    Remove-Item -LiteralPath ([string]$backup.path) -Force -ErrorAction Stop
                    Need ((Get-NativeAgentBridgeFileState ([string]$backup.path)).kind -eq 'missing') ('native agent backup remains after cleanup: {0}' -f [string]$backup.path)
                }
                catch { $rollbackErrors.Add(('backup:{0} => {1}' -f [string]$backup.path, $_.Exception.Message)) | Out-Null }
            }
        }

        if ($targetRootCreationClaimed) {
            try {
                $rootItem = Get-NativeAgentBridgeItem $targetRoot
                if ($null -ne $rootItem) {
                    Need $rootItem.PSIsContainer ('created native agent target root is no longer a directory')
                    Need (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) ('created native agent target root is no longer a regular directory')
                    Need (@(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction Stop).Count -eq 0) ('created native agent target root is not empty after rollback')
                    Remove-Item -LiteralPath $targetRoot -Force -ErrorAction Stop
                    Need ($null -eq (Get-NativeAgentBridgeItem $targetRoot)) ('created native agent target root remains after cleanup')
                }
            }
            catch { $rollbackErrors.Add(('target-root:{0} => {1}' -f $targetRoot, $_.Exception.Message)) | Out-Null }
        }

        $rollbackStatus = if ($rollbackErrors.Count -eq 0) { 'rolled_back' } else { 'rollback_failed' }
        $recoveryReceipt = [ordered]@{
            schema_version = 1
            status = $rollbackStatus
            owner = [string](Get-NativeAgentBridgeValue $bridge 'owner')
            applied_at = [DateTimeOffset]::UtcNow.ToString('o')
            source_root = $sourceRoot
            target_root = $targetRoot
            backup_root = $backupRoot
            backup_paths = @($backups.ToArray())
            legacy_backup_migrations = @($legacyMigrationLog.ToArray())
            changed_names = @($changed.ToArray() | Sort-Object)
            failure_message = $failure.Exception.Message
            rollback_errors = @($rollbackErrors.ToArray())
            recovery_required = ($rollbackErrors.Count -gt 0)
            truth_boundary = if ($rollbackErrors.Count -eq 0) { 'filesystem_projected' } else { 'recovery_required' }
        }
        $receiptWritten = $false
        try {
            Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $receiptPath) $receiptRoot
            $receiptDirectory = Split-Path -Parent $receiptPath
            $receiptDirectoryItem = Get-NativeAgentBridgeItem $receiptDirectory
            if ($null -eq $receiptDirectoryItem) { New-Item -ItemType Directory -Path $receiptDirectory -Force -ErrorAction Stop | Out-Null; $receiptDirectoryItem = Get-NativeAgentBridgeItem $receiptDirectory }
            if ($null -eq $receiptDirectoryItem -or -not $receiptDirectoryItem.PSIsContainer -or [bool]($receiptDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('native agent bridge recovery receipt directory is not a regular directory: {0}' -f $receiptDirectory) }
            Write-Utf8FileAtomic -Path $receiptPath -Content ($recoveryReceipt | ConvertTo-Json -Depth 16)
            Need ((Get-NativeAgentBridgeFileState $receiptPath).kind -eq 'file') ('native agent bridge recovery receipt was not persisted: {0}' -f $receiptPath)
            $receiptWritten = $true
        }
        catch { $rollbackErrors.Add(('receipt:{0} => {1}' -f $receiptPath, $_.Exception.Message)) | Out-Null }

        if ($rollbackErrors.Count -gt 0) {
            # 收据写失败时如实声明未落盘，不得让最终报错引用一个不存在的收据。
            $receiptNote = if ($receiptWritten) { ('receipt: {0}' -f $receiptPath) } else { ('receipt NOT persisted: {0}' -f $receiptPath) }
            throw ('Native agent bridge failed: {0}; rollback/recovery required: {1}; {2}' -f $failure.Exception.Message, ($rollbackErrors -join ' | '), $receiptNote)
        }
        throw $failure
    }

    return [pscustomobject]@{ enabled = $true; persisted = $true; changed_names = @($changed.ToArray() | Sort-Object); receipt_path = $receiptPath; truth_boundary = 'filesystem_projected'; receipt = $receipt }
}
