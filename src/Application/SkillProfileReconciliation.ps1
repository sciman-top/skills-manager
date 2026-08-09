function Get-SkillProfileReconciliationProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-SkillProfileReconciliationTransactionFinding([string]$Code, [string]$Message, [string]$Skill = "", [string]$Profile = "") {
    return [pscustomobject]([ordered]@{
            code = $Code
            message = $Message
            blocking = $true
            skill = $Skill
            profile = $Profile
        })
}

function Copy-SkillsManagerConfig($Config) {
    Need ($null -ne $Config) "skills-manager config is required"
    return (($Config | ConvertTo-Json -Depth 50) | ConvertFrom-Json)
}

function Write-SkillProfileReconciliationReceipt([string]$Path, $Receipt) {
    Write-Utf8FileAtomic -Path $Path -Content ($Receipt | ConvertTo-Json -Depth 50)
}

function Invoke-SkillProfileReconciliationRollback {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$Token
    )

    if ($Token -cne "ROLLBACK_PROFILE_RECONCILIATION_CANARY") {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @((New-SkillProfileReconciliationTransactionFinding "rollback_token_invalid" "Explicit canary rollback token does not match.")) }
    }
    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    $receiptFile = [System.IO.Path]::GetFullPath($ReceiptPath)
    if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) { throw "Canary receipt does not exist: $receiptFile" }
    $receipt = Get-Content -LiteralPath $receiptFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $findings = New-Object System.Collections.Generic.List[object]
    if ([int](Get-SkillProfileReconciliationProperty $receipt "schema_version") -ne 1 -or [string](Get-SkillProfileReconciliationProperty $receipt "domain") -ne "skill_profile_reconciliation") {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "rollback_receipt_invalid" "Receipt is not a supported skill profile reconciliation receipt.")) | Out-Null
    }
    if ([string](Get-SkillProfileReconciliationProperty $receipt "status") -notin @("canary_applied", "accepted", "replay_failed")) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "rollback_status_invalid" "Receipt is not in a rollback-eligible state.")) | Out-Null
    }
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string]$receipt.config_path), $configFile, [System.StringComparison]::OrdinalIgnoreCase)) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "rollback_target_invalid" "Receipt config path does not match the requested skills.json.")) | Out-Null
    }
    if ((Get-FileContentHash $configFile) -ne [string]$receipt.after_config_sha256) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "rollback_target_stale" "skills.json changed after canary apply; automatic rollback is blocked.")) | Out-Null
    }
    $expectedBackup = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetDirectoryName($receiptFile)) (".skill-profile-backups\{0}.skills.json.bak" -f [string]$receipt.operation_id)))
    $backupPath = [System.IO.Path]::GetFullPath([string]$receipt.backup_path)
    if (-not [string]::Equals($backupPath, $expectedBackup, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-FileContentHash $backupPath) -ne [string]$receipt.before_config_sha256) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "rollback_backup_invalid" "Canary backup is missing, stale, or outside the receipt backup path.")) | Out-Null
    }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @($findings.ToArray()) } }

    Write-BytesAtomic -Path $configFile -Bytes ([System.IO.File]::ReadAllBytes($backupPath))
    Need ((Get-FileContentHash $configFile) -eq [string]$receipt.before_config_sha256) "Canary rollback did not restore the original skills.json hash."
    $receipt.status = "rolled_back"
    $receipt | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue ([datetimeoffset]::UtcNow.ToString("o")) -Force
    Write-SkillProfileReconciliationReceipt $receiptFile $receipt
    return [pscustomobject]@{ pass = $true; status = "rolled_back"; writes_performed = 1; findings = @(); receipt = $receipt }
}

function New-SkillProfileMigrationFinding([string]$Code, [string]$Message, [bool]$Blocking = $true) {
    return [pscustomobject][ordered]@{
        code = $Code
        message = $Message
        blocking = $Blocking
    }
}

function Get-SkillProfileCompatibilityView {
    param(
        [Parameter(Mandatory = $true)]$ProjectionConfig
    )

    Need ($null -ne $ProjectionConfig) "skill_projection config is required"
    $directProfilesProperty = $ProjectionConfig.PSObject.Properties["profiles"]
    $compatibilityProperty = $ProjectionConfig.PSObject.Properties["profile_compatibility"]
    $directActiveProperty = $ProjectionConfig.PSObject.Properties["active_profile"]
    $directCurrentProperty = $ProjectionConfig.PSObject.Properties["current_profile"]

    if ($null -eq $directProfilesProperty -and $null -eq $compatibilityProperty -and $null -eq $directActiveProperty -and $null -eq $directCurrentProperty) {
        return [pscustomobject][ordered]@{
            schema_version = 1
            kind = "ProfileCompatibilityView"
            status = "absent"
            source_schema = "none"
            source_fields = @()
            reachability_authority = "none"
            active_profile = ""
            current_profile = ""
            profiles = [pscustomobject]@{}
            writes_performed = $false
            provider_calls = 0
            native_mutations = 0
        }
    }

    $source = if ($null -ne $compatibilityProperty -and $null -eq $directProfilesProperty) { "profile_compatibility" } else { "legacy_skill_projection" }
    $sourceObject = if ($source -eq "profile_compatibility") { $compatibilityProperty.Value } else { $ProjectionConfig }
    Need ($null -ne $sourceObject) "Profile compatibility source is required"

    $activeProfile = ([string]$sourceObject.active_profile).Trim()
    $currentProfile = ([string]$sourceObject.current_profile).Trim()
    if ([string]::IsNullOrWhiteSpace($activeProfile)) { $activeProfile = $currentProfile }
    if (-not [string]::IsNullOrWhiteSpace($activeProfile) -and -not [string]::IsNullOrWhiteSpace($currentProfile)) {
        Need ([string]::Equals($activeProfile, $currentProfile, [System.StringComparison]::OrdinalIgnoreCase)) "active_profile and current_profile disagree"
    }

    $profiles = $sourceObject.PSObject.Properties["profiles"]
    Need ($null -ne $profiles -and $null -ne $profiles.Value) "Profile compatibility data must contain profiles"
    $profilesCopy = Copy-SkillsManagerConfig $profiles.Value
    foreach ($property in @($profilesCopy.PSObject.Properties)) {
        Need ($null -ne $property.Value -and $property.Value.PSObject.Properties.Match("enabled_names").Count -gt 0) ("Profile '{0}' is missing enabled_names" -f [string]$property.Name)
        $property.Value.enabled_names = @($property.Value.enabled_names | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return [pscustomobject][ordered]@{
        schema_version = 1
        kind = "ProfileCompatibilityView"
        status = "read_only"
        source_schema = if ($source -eq "profile_compatibility") { "profile_compatibility.v1" } else { "skill_projection.profile_fields.v1" }
        source_fields = if ($source -eq "profile_compatibility") { @("profile_compatibility") } else { @("active_profile", "current_profile", "profiles") | Where-Object { $null -ne $ProjectionConfig.PSObject.Properties[$_] } }
        reachability_authority = "none"
        active_profile = $activeProfile
        current_profile = $currentProfile
        profiles = $profilesCopy
        writes_performed = $false
        provider_calls = 0
        native_mutations = 0
    }
}

function New-SkillProfileMigrationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        $findings.Add((New-SkillProfileMigrationFinding "config_missing" ("skills.json does not exist: {0}" -f $configFile))) | Out-Null
        return [pscustomobject][ordered]@{ schema_version = 1; command = "migrate-skill-profile-config"; status = "blocked"; pass = $false; migration_required = $false; writes_performed = $false; findings = @($findings.ToArray()) }
    }
    if ($null -eq $Config -or $null -eq $Config.PSObject.Properties["skill_projection"] -or $null -eq $Config.skill_projection) {
        $findings.Add((New-SkillProfileMigrationFinding "skill_projection_missing" "Config must contain skill_projection.")) | Out-Null
        return [pscustomobject][ordered]@{ schema_version = 1; command = "migrate-skill-profile-config"; status = "blocked"; pass = $false; migration_required = $false; writes_performed = $false; findings = @($findings.ToArray()) }
    }

    $projection = $Config.skill_projection
    $directFieldNames = @("active_profile", "current_profile", "profiles")
    $directFieldPresent = @($directFieldNames | Where-Object { $null -ne $projection.PSObject.Properties[$_] })
    $compatibilityPresent = $null -ne $projection.PSObject.Properties["profile_compatibility"]
    $view = $null
    try { $view = Get-SkillProfileCompatibilityView $projection }
    catch { $findings.Add((New-SkillProfileMigrationFinding "legacy_profile_invalid" $_.Exception.Message)) | Out-Null }

    if ($directFieldPresent.Count -gt 0 -and $compatibilityPresent) {
        $findings.Add((New-SkillProfileMigrationFinding "mixed_profile_schema" "Legacy profile fields and profile_compatibility cannot coexist during migration.")) | Out-Null
    }

    $targetConfig = Copy-SkillsManagerConfig $Config
    $migrationRequired = $directFieldPresent.Count -gt 0
    $status = if ($migrationRequired) { "ready" } elseif ($compatibilityPresent) { "already_migrated" } else { "not_applicable" }
    if ($migrationRequired -and $null -ne $view) {
        foreach ($field in $directFieldNames) {
            if ($null -ne $targetConfig.skill_projection.PSObject.Properties[$field]) { $targetConfig.skill_projection.PSObject.Properties.Remove($field) }
        }
        $targetConfig.skill_projection | Add-Member -NotePropertyName profile_compatibility -NotePropertyValue $view -Force
    }

    $beforeHash = Get-FileContentHash $configFile
    $targetJson = $targetConfig | ConvertTo-Json -Depth 50
    $targetHash = Get-OperationSha256 $targetJson
    $operationId = "profile-migration-{0}" -f (Get-OperationSha256 ("{0}|{1}|profile-compatibility-v1" -f $beforeHash, $targetHash)).Substring(0, 16)
    $activeProfile = if ($null -eq $view) { "" } else { [string]$view.active_profile }
    $profileCount = if ($null -eq $view) { 0 } else { @($view.profiles.PSObject.Properties).Count }
    if ($findings.Count -gt 0) { $status = "blocked" }

    return [pscustomobject][ordered]@{
        schema_version = 1
        command = "migrate-skill-profile-config"
        operation_id = $operationId
        status = $status
        pass = ($findings.Count -eq 0)
        migration_required = $migrationRequired
        config_path = $configFile
        before_config_sha256 = $beforeHash
        target_config_sha256 = $targetHash
        active_profile = $activeProfile
        legacy_profile_count = $profileCount
        compatibility_view = $view
        migrated_config = $targetConfig
        rollback = [pscustomobject][ordered]@{
            required = $migrationRequired
            status = if ($migrationRequired) { "available" } else { "not_required" }
            source = "migration_receipt.backup_path"
        }
        decision_owner = "deterministic_migration"
        host_mutation = $false
        provider_calls = 0
        native_mutations = 0
        writes_performed = $false
        finding_count = $findings.Count
        findings = @($findings.ToArray())
    }
}

function Invoke-SkillProfileMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$Token
    )

    if ($Token -cne "MIGRATE_SKILL_PROFILE_CONFIG") {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @((New-SkillProfileMigrationFinding "migration_token_invalid" "Explicit profile migration token does not match.")) }
    }
    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    $receiptFile = [System.IO.Path]::GetFullPath($ReceiptPath)
    if (Test-Path -LiteralPath $receiptFile -PathType Leaf) {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @((New-SkillProfileMigrationFinding "receipt_already_exists" "Receipt path already exists; use a new migration receipt.")) }
    }

    $beforeBytes = $null
    $configWritten = $false
    $lockStream = $null
    try {
        Need (Test-Path -LiteralPath $configFile -PathType Leaf) ("skills.json does not exist: {0}" -f $configFile)
        $beforeBytes = [System.IO.File]::ReadAllBytes($configFile)
        $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = New-SkillProfileMigrationPlan -Config $config -ConfigPath $configFile
        if (-not [bool]$plan.pass) { return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @($plan.findings); plan = $plan } }
        if (-not [bool]$plan.migration_required) { return [pscustomobject]@{ pass = $true; status = "noop"; writes_performed = 0; findings = @(); plan = $plan; receipt = $null } }

        $lockPath = "{0}.profile-migration.lock" -f $configFile
        $backupPath = Join-Path ([System.IO.Path]::GetDirectoryName($receiptFile)) (".skill-profile-migration-backups\{0}.skills.json.bak" -f [string]$plan.operation_id)
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        Need ((Get-FileContentHash $configFile) -eq [string]$plan.before_config_sha256) "skills.json changed after migration planning"
        Write-BytesAtomic -Path $backupPath -Bytes $beforeBytes
        Write-Utf8FileAtomic -Path $configFile -Content ($plan.migrated_config | ConvertTo-Json -Depth 50)
        $configWritten = $true
        $afterHash = Get-FileContentHash $configFile
        $afterConfig = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $postPlan = New-SkillProfileMigrationPlan -Config $afterConfig -ConfigPath $configFile
        Need ([bool]$postPlan.pass -and -not [bool]$postPlan.migration_required) "Migrated skills.json did not enter compatibility-only form"
        Need ([string]::Equals([string]$postPlan.active_profile, [string]$plan.active_profile, [System.StringComparison]::OrdinalIgnoreCase)) "active_profile changed during profile migration"
        $now = [datetimeoffset]::UtcNow.ToString("o")
        $receipt = [pscustomobject][ordered]@{
            schema_version = 1
            domain = "skill_profile_migration"
            operation_id = [string]$plan.operation_id
            status = "migrated"
            started_at = $now
            completed_at = $now
            config_path = $configFile
            before_config_sha256 = [string]$plan.before_config_sha256
            after_config_sha256 = $afterHash
            active_profile = [string]$plan.active_profile
            legacy_profile_count = [int]$plan.legacy_profile_count
            backup_path = [System.IO.Path]::GetFullPath($backupPath)
            compatibility_view = $plan.compatibility_view
            rollback = [pscustomobject]@{ status = "available"; token = "ROLLBACK_SKILL_PROFILE_CONFIG" }
            host_mutation = $false
            provider_calls = 0
            native_mutations = 0
            writes = 1
        }
        Write-Utf8FileAtomic -Path $receiptFile -Content ($receipt | ConvertTo-Json -Depth 50)
        return [pscustomobject]@{ pass = $true; status = "migrated"; writes_performed = 1; findings = @(); receipt = $receipt; receipt_path = $receiptFile; plan = $plan }
    }
    catch {
        if ($configWritten -and $null -ne $beforeBytes) { Write-BytesAtomic -Path $configFile -Bytes $beforeBytes }
        return [pscustomobject]@{ pass = $false; status = if ($configWritten) { "failed_rolled_back" } else { "failed" }; writes_performed = if ($configWritten) { 1 } else { 0 }; findings = @((New-SkillProfileMigrationFinding "migration_failed" $_.Exception.Message)); receipt = $null }
    }
    finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
            $lockPath = "{0}.profile-migration.lock" -f $configFile
            if (Test-Path -LiteralPath $lockPath -PathType Leaf) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Invoke-SkillProfileMigrationRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$Token
    )

    if ($Token -cne "ROLLBACK_SKILL_PROFILE_CONFIG") {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @((New-SkillProfileMigrationFinding "rollback_token_invalid" "Explicit profile migration rollback token does not match.")) }
    }
    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    $receiptFile = [System.IO.Path]::GetFullPath($ReceiptPath)
    if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) { throw "Profile migration receipt does not exist: $receiptFile" }
    $receipt = Get-Content -LiteralPath $receiptFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $findings = New-Object System.Collections.Generic.List[object]
    if ([int]$receipt.schema_version -ne 1 -or [string]$receipt.domain -ne "skill_profile_migration") { $findings.Add((New-SkillProfileMigrationFinding "rollback_receipt_invalid" "Receipt is not a supported profile migration receipt.")) | Out-Null }
    if ([string]$receipt.status -ne "migrated") { $findings.Add((New-SkillProfileMigrationFinding "rollback_status_invalid" "Receipt is not in a rollback-eligible state.")) | Out-Null }
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string]$receipt.config_path), $configFile, [System.StringComparison]::OrdinalIgnoreCase)) { $findings.Add((New-SkillProfileMigrationFinding "rollback_target_invalid" "Receipt config path does not match the requested skills.json.")) | Out-Null }
    if ((Get-FileContentHash $configFile) -ne [string]$receipt.after_config_sha256) { $findings.Add((New-SkillProfileMigrationFinding "rollback_target_stale" "skills.json changed after profile migration; automatic rollback is blocked.")) | Out-Null }
    $expectedBackup = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetDirectoryName($receiptFile)) (".skill-profile-migration-backups\{0}.skills.json.bak" -f [string]$receipt.operation_id)))
    $backupPath = [System.IO.Path]::GetFullPath([string]$receipt.backup_path)
    if (-not [string]::Equals($backupPath, $expectedBackup, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-FileContentHash $backupPath) -ne [string]$receipt.before_config_sha256) { $findings.Add((New-SkillProfileMigrationFinding "rollback_backup_invalid" "Migration backup is missing, stale, or outside the receipt backup path.")) | Out-Null }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @($findings.ToArray()); receipt = $receipt } }

    Write-BytesAtomic -Path $configFile -Bytes ([System.IO.File]::ReadAllBytes($backupPath))
    Need ((Get-FileContentHash $configFile) -eq [string]$receipt.before_config_sha256) "Profile migration rollback did not restore the original skills.json hash."
    $receipt.status = "rolled_back"
    $receipt | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue ([datetimeoffset]::UtcNow.ToString("o")) -Force
    Write-Utf8FileAtomic -Path $receiptFile -Content ($receipt | ConvertTo-Json -Depth 50)
    return [pscustomobject]@{ pass = $true; status = "rolled_back"; writes_performed = 1; findings = @(); receipt = $receipt }
}
