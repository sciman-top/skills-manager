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

function Move-NativeAgentBridgeLegacyBackups([string]$TargetRoot, [string]$BackupRoot) {
    $target = [IO.Path]::GetFullPath($TargetRoot)
    $legacyRoot = Join-Path $target 'skills-manager-backups'
    $destinationRoot = [IO.Path]::GetFullPath($BackupRoot)
    $migrations = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $legacyRoot)) { return @() }

    $legacyItem = Get-Item -LiteralPath $legacyRoot -Force -ErrorAction Stop
    if (-not $legacyItem.PSIsContainer -or [bool]($legacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ('legacy native agent backup root is not a regular directory: {0}' -f $legacyRoot)
    }
    if (Test-NativeAgentBridgeWithin $destinationRoot $target) { throw 'native agent backup destination must stay outside the host agent discovery root.' }

    foreach ($legacyFile in @(Get-ChildItem -LiteralPath $legacyRoot -File -Filter '*.toml' -Force | Sort-Object Name)) {
        $content = Get-Content -LiteralPath $legacyFile.FullName -Raw -Encoding UTF8
        if ($content -notmatch '(?m)^# skills-manager-native-agent-bridge: v1\s*$') { continue }
        $nameMatch = [regex]::Match($content, '(?m)^name\s*=\s*"([^"]+)"\s*$')
        if (-not $nameMatch.Success) { throw ('legacy native agent backup lacks a role name: {0}' -f $legacyFile.FullName) }
        Get-NativeAgentBridgeTemplate $legacyFile.FullName $nameMatch.Groups[1].Value | Out-Null

        if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) { New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null }
        $destinationPath = Join-Path $destinationRoot $legacyFile.Name
        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            if (-not [string]::Equals((Get-NativeAgentBridgeSha256 $legacyFile.FullName), (Get-NativeAgentBridgeSha256 $destinationPath), [StringComparison]::OrdinalIgnoreCase)) {
                throw ('legacy native agent backup destination conflicts: {0}' -f $destinationPath)
            }
            Remove-Item -LiteralPath $legacyFile.FullName -Force
        }
        else { Move-Item -LiteralPath $legacyFile.FullName -Destination $destinationPath -ErrorAction Stop }
        $migrations.Add([pscustomobject][ordered]@{ source_path = $legacyFile.FullName; destination_path = $destinationPath }) | Out-Null
    }

    if (@(Get-ChildItem -LiteralPath $legacyRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $legacyRoot -Force }
    return @($migrations.ToArray())
}

function Get-NativeAgentBridgeTemplate($SourcePath, [string]$Name) {
    $content = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
    if ($content -notmatch '(?m)^# skills-manager-native-agent-bridge: v1\s*$') { throw ("native agent template lacks ownership marker: {0}" -f $SourcePath) }
    if ($content -notmatch ('(?m)^name\s*=\s*"{0}"\s*$' -f [regex]::Escape($Name))) { throw ("native agent template name mismatch: {0}" -f $SourcePath) }
    foreach ($field in @('description', 'developer_instructions')) {
        if ($content -notmatch ('(?m)^{0}\s*=' -f $field)) { throw ("native agent template lacks {0}: {1}" -f $field, $SourcePath) }
    }
    return $content
}

function Sync-NativeAgentBridge($Config, $PromotionContext = $null) {
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

    $names = @((Get-NativeAgentBridgeValue $bridge 'definitions') | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($names.Count -eq 0) { throw 'native_agent_bridge.definitions must not be empty.' }
    $planned = New-Object System.Collections.Generic.List[object]
    foreach ($name in $names) {
        if ($name -notmatch '^[a-z0-9][a-z0-9-]*$') { throw ("native_agent_bridge definition is invalid: {0}" -f $name) }
        $sourcePath = Join-Path $sourceRoot ($name + '.toml')
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ("native agent template is missing: {0}" -f $sourcePath) }
        $content = Get-NativeAgentBridgeTemplate $sourcePath $name
        $planned.Add([pscustomobject]@{ name = $name; source_path = $sourcePath; target_path = (Join-Path $targetRoot ($name + '.toml')); content = $content; source_sha256 = Get-NativeAgentBridgeSha256 $sourcePath }) | Out-Null
    }

    if ($DryRun) {
        return [pscustomobject]@{ enabled = $true; persisted = $false; changed_names = @($planned | ForEach-Object name); receipt_path = $receiptPath; truth_boundary = 'planned'; definitions = @($planned | Select-Object name, source_path, target_path, source_sha256) }
    }

    if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) { New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null }
    $before = @{}
    $changed = New-Object System.Collections.Generic.List[string]
    $backups = New-Object System.Collections.Generic.List[string]
    $legacyBackupMigrations = @()
    try {
        $legacyBackupMigrations = @(Move-NativeAgentBridgeLegacyBackups $targetRoot $backupRoot)
        foreach ($definition in $planned.ToArray()) {
            $targetPath = [string]$definition.target_path
            $existingItem = if (Test-Path -LiteralPath $targetPath -PathType Leaf) { Get-Item -LiteralPath $targetPath -Force } else { $null }
            if ($null -ne $existingItem -and ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ("native agent target must not be a reparse point: {0}" -f $targetPath) }
            $existing = if ($null -ne $existingItem) { Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 } else { $null }
            $before[$targetPath] = $existing
            if ($null -ne $existing -and $existing -notmatch '(?m)^# skills-manager-native-agent-bridge: v1\s*$') { throw ("native agent target is not owned by skills-manager: {0}" -f $targetPath) }
            if ($null -ne $existing -and [string]::Equals($existing, [string]$definition.content, [StringComparison]::Ordinal)) { continue }
            if ($null -ne $existing) {
                if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
                $backupPath = Join-Path $backupRoot ('{0}.{1}.toml' -f $definition.name, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
                Write-Utf8FileAtomic -Path $backupPath -Content $existing
                $backups.Add($backupPath) | Out-Null
            }
            Write-Utf8FileAtomic -Path $targetPath -Content ([string]$definition.content)
            $changed.Add([string]$definition.name) | Out-Null
        }
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
            definitions = @($planned | ForEach-Object { [ordered]@{ name = $_.name; source_sha256 = $_.source_sha256; target_sha256 = Get-NativeAgentBridgeSha256 $_.target_path } })
            provider_calls = 0
            native_mutations = $changed.Count + $legacyBackupMigrations.Count
            writes = $changed.Count + $legacyBackupMigrations.Count
            truth_boundary = 'filesystem_projected'
        }
        $receiptDirectory = Split-Path -Parent $receiptPath
        if (-not (Test-Path -LiteralPath $receiptDirectory -PathType Container)) { New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null }
        Write-Utf8FileAtomic -Path $receiptPath -Content ($receipt | ConvertTo-Json -Depth 12)
    }
    catch {
        $failure = $_
        foreach ($definition in @($planned | Sort-Object target_path -Descending)) {
            $targetPath = [string]$definition.target_path
            if (-not $before.ContainsKey($targetPath)) { continue }
            $previous = $before[$targetPath]
            if ($null -eq $previous) {
                if (Test-Path -LiteralPath $targetPath -PathType Leaf) { Remove-Item -LiteralPath $targetPath -Force }
            }
            else { Write-Utf8FileAtomic -Path $targetPath -Content ([string]$previous) }
        }
        foreach ($backupPath in @($backups.ToArray())) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
        foreach ($migration in @($legacyBackupMigrations | Sort-Object destination_path -Descending)) {
            $sourcePath = [string]$migration.source_path
            $destinationPath = [string]$migration.destination_path
            if ((Test-Path -LiteralPath $destinationPath -PathType Leaf) -and -not (Test-Path -LiteralPath $sourcePath)) {
                $legacyRoot = Split-Path -Parent $sourcePath
                if (-not (Test-Path -LiteralPath $legacyRoot -PathType Container)) { New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null }
                Move-Item -LiteralPath $destinationPath -Destination $sourcePath -ErrorAction SilentlyContinue
            }
        }
        throw $failure
    }

    return [pscustomobject]@{ enabled = $true; persisted = $true; changed_names = @($changed.ToArray() | Sort-Object); receipt_path = $receiptPath; truth_boundary = 'filesystem_projected'; receipt = $receipt }
}
