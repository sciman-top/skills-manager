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

function Set-SkillProfileReconciliationActions($Config, $Actions) {
    $copy = Copy-SkillsManagerConfig $Config
    Need ($copy.PSObject.Properties.Match("skill_projection").Count -gt 0 -and $null -ne $copy.skill_projection) "skill_projection is required"
    foreach ($action in @($Actions)) {
        $profileName = [string]$action.profile
        $property = $copy.skill_projection.profiles.PSObject.Properties[$profileName]
        Need ($null -ne $property) ("Unknown profile in validated action: {0}" -f $profileName)
        $before = @($property.Value.enabled_names | ForEach-Object { [string]$_ })
        $expectedBefore = @($action.before | ForEach-Object { [string]$_ })
        Need (($before -join "`n") -ceq ($expectedBefore -join "`n")) ("Profile changed after validation: {0}" -f $profileName)
        $property.Value.enabled_names = @($action.after | ForEach-Object { [string]$_ })
    }
    return $copy
}

function New-SkillProfileReconciliationApplyPlan {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)]$Proposal,
        [ValidateRange(1, 20)][int]$MaxSkillChanges = 5,
        [ValidateRange(1, 50)][int]$MaxActions = 10,
        [ValidateRange(0, 2000)][int]$MinBudgetHeadroomChars = 256
    )

    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    Need (Test-Path -LiteralPath $configFile -PathType Leaf) ("skills.json does not exist: {0}" -f $configFile)
    Need ($Config.PSObject.Properties.Match("skill_projection").Count -gt 0 -and $null -ne $Config.skill_projection) "skill_projection is required"
    $configHash = Get-FileContentHash $configFile
    $planner = New-SkillProfileReconciliationPlan $Config.skill_projection $configHash $Proposal
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($planner.findings)) { $findings.Add($finding) | Out-Null }

    $actions = if ([bool]$planner.pass) { @($planner.actions) } else { @() }
    $changedSkills = @($actions | ForEach-Object { [string]$_.skill } | Sort-Object -Unique)
    $changedProfiles = @($actions | ForEach-Object { [string]$_.profile } | Sort-Object -Unique)
    if ([bool]$planner.pass -and $actions.Count -eq 0) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "apply_actions_missing" "A canary apply requires at least one validated action.")) | Out-Null
    }
    if ($changedSkills.Count -gt $MaxSkillChanges) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "apply_skill_limit_exceeded" ("Canary changes {0} skills; limit is {1}." -f $changedSkills.Count, $MaxSkillChanges))) | Out-Null
    }
    if ($actions.Count -gt $MaxActions) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "apply_action_limit_exceeded" ("Canary has {0} actions; limit is {1}." -f $actions.Count, $MaxActions))) | Out-Null
    }
    $activeProfile = [string]$Config.skill_projection.active_profile
    foreach ($action in @($actions | Where-Object { [string]::Equals([string]$_.profile, $activeProfile, [System.StringComparison]::OrdinalIgnoreCase) })) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "active_profile_membership_change_forbidden" ("Canary apply cannot change the active profile '{0}'. Use a non-active profile and validate at a fresh-task boundary." -f $activeProfile) ([string]$action.skill) ([string]$action.profile))) | Out-Null
    }
    $profileHeadroom = New-Object System.Collections.Generic.List[object]
    foreach ($profile in $changedProfiles) {
        $budget = @($planner.proposed.profile_budgets | Where-Object { [string]::Equals([string]$_.profile, [string]$profile, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($budget.Count -ne 1) { continue }
        $headroom = [int]$budget[0].budget_limit_chars - [int]$budget[0].estimated_metadata_chars
        $profileHeadroom.Add([pscustomobject]@{ profile = [string]$profile; headroom_chars = $headroom; minimum_chars = $MinBudgetHeadroomChars }) | Out-Null
        if ($headroom -lt $MinBudgetHeadroomChars) {
            $findings.Add((New-SkillProfileReconciliationTransactionFinding "proposed_budget_headroom_insufficient" ("Canary profile '{0}' leaves {1} metadata characters; minimum automatic headroom is {2}." -f $profile, $headroom, $MinBudgetHeadroomChars) "" ([string]$profile))) | Out-Null
        }
    }

    $proposalJson = $Proposal | ConvertTo-Json -Depth 50 -Compress
    $proposalHash = Get-OperationSha256 $proposalJson
    $seed = "{0}|{1}|{2}" -f $configHash, $proposalHash, (@($actions | ForEach-Object { "{0}|{1}|{2}" -f $_.operation, $_.skill, $_.profile }) -join "|")
    $operationId = "skill-profile-{0}" -f (Get-OperationSha256 $seed).Substring(0, 16)
    $pass = @($findings | Where-Object blocking).Count -eq 0
    return [pscustomobject]([ordered]@{
            schema_version = 1
            command = "plan-skill-profile-reconciliation-apply"
            operation_id = $operationId
            decision_owner = "host_ai"
            semantic_routing_performed = $false
            pass = $pass
            apply_allowed = $pass
            writes_performed = $false
            config_path = $configFile
            config_sha256 = $configHash
            proposal_sha256 = $proposalHash
            active_profile = $activeProfile
            activation_boundary = "fresh_task"
            changed_skills = $changedSkills
            changed_profiles = $changedProfiles
            profile_headroom = @($profileHeadroom.ToArray())
            actions = $actions
            finding_count = $findings.Count
            findings = @($findings.ToArray())
        })
}

function Write-SkillProfileReconciliationReceipt([string]$Path, $Receipt) {
    Write-Utf8FileAtomic -Path $Path -Content ($Receipt | ConvertTo-Json -Depth 50)
}

function Invoke-SkillProfileReconciliationApply {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)]$Proposal,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$Token,
        [ValidateRange(1, 20)][int]$MaxSkillChanges = 5,
        [ValidateRange(1, 50)][int]$MaxActions = 10,
        [ValidateRange(0, 2000)][int]$MinBudgetHeadroomChars = 256
    )

    if ($Token -cne "APPLY_PROFILE_RECONCILIATION_CANARY") {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @((New-SkillProfileReconciliationTransactionFinding "apply_token_invalid" "Explicit canary apply token does not match.")); receipt = $null }
    }
    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    $receiptFile = [System.IO.Path]::GetFullPath($ReceiptPath)
    if (Test-Path -LiteralPath $receiptFile) {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @((New-SkillProfileReconciliationTransactionFinding "receipt_already_exists" "Receipt path already exists; use a new canary receipt.")); receipt = $null }
    }
    $plan = New-SkillProfileReconciliationApplyPlan -Config $Config -ConfigPath $configFile -Proposal $Proposal -MaxSkillChanges $MaxSkillChanges -MaxActions $MaxActions -MinBudgetHeadroomChars $MinBudgetHeadroomChars
    if (-not [bool]$plan.pass) {
        return [pscustomobject]@{ pass = $false; status = "blocked"; writes_performed = 0; findings = @($plan.findings); receipt = $null }
    }

    $lockPath = "{0}.profile-reconciliation.lock" -f $configFile
    $lockStream = $null
    $backupPath = Join-Path ([System.IO.Path]::GetDirectoryName($receiptFile)) (".skill-profile-backups\{0}.skills.json.bak" -f [string]$plan.operation_id)
    $beforeBytes = [System.IO.File]::ReadAllBytes($configFile)
    $configWritten = $false
    $receipt = $null
    try {
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        Need ((Get-FileContentHash $configFile) -eq [string]$plan.config_sha256) "skills.json changed after apply planning"
        Write-BytesAtomic -Path $backupPath -Bytes $beforeBytes
        $proposedConfig = Set-SkillProfileReconciliationActions $Config $plan.actions
        Need ([string]::Equals([string]$proposedConfig.skill_projection.active_profile, [string]$plan.active_profile, [System.StringComparison]::Ordinal)) "active_profile changed during canary apply"
        Write-Utf8FileAtomic -Path $configFile -Content ($proposedConfig | ConvertTo-Json -Depth 50)
        $configWritten = $true
        $afterHash = Get-FileContentHash $configFile
        $postPlan = New-SkillProfileReconciliationPlan $proposedConfig.skill_projection $afterHash
        Need ([bool]$postPlan.pass) ("Applied profile projection is invalid: {0}" -f (@($postPlan.findings.code) -join ", "))
        Need ([string]::Equals([string]$postPlan.current.active_profile, [string]$plan.active_profile, [System.StringComparison]::Ordinal)) "active_profile changed after canary apply"
        $now = [datetimeoffset]::UtcNow.ToString("o")
        $receipt = [pscustomobject]([ordered]@{
                schema_version = 1
                domain = "skill_profile_reconciliation"
                operation_id = [string]$plan.operation_id
                status = "canary_applied"
                started_at = $now
                completed_at = $now
                config_path = $configFile
                before_config_sha256 = [string]$plan.config_sha256
                after_config_sha256 = $afterHash
                proposal_sha256 = [string]$plan.proposal_sha256
                active_profile = [string]$plan.active_profile
                changed_skills = @($plan.changed_skills)
                changed_profiles = @($plan.changed_profiles)
                profile_headroom = @($plan.profile_headroom)
                actions = @($plan.actions)
                backup_path = [System.IO.Path]::GetFullPath($backupPath)
                replay = [pscustomobject]@{ required = $true; status = "not_run"; boundary = "fresh_ephemeral_task"; report_path = $null; report_sha256 = $null }
                live_accepted = "not_run"
            })
        Write-SkillProfileReconciliationReceipt $receiptFile $receipt
        return [pscustomobject]@{ pass = $true; status = "canary_applied"; writes_performed = 1; findings = @(); receipt = $receipt }
    }
    catch {
        if ($configWritten) { Write-BytesAtomic -Path $configFile -Bytes $beforeBytes }
        return [pscustomobject]@{ pass = $false; status = $(if ($configWritten) { "failed_rolled_back" } else { "failed" }); writes_performed = $(if ($configWritten) { 1 } else { 0 }); findings = @((New-SkillProfileReconciliationTransactionFinding "canary_apply_failed" $_.Exception.Message)); receipt = $receipt }
    }
    finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
            if (Test-Path -LiteralPath $lockPath -PathType Leaf) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
        }
    }
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

function Test-SkillProfileReconciliationReplay {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)]$Report,
        [Parameter(Mandatory = $true)]$Corpus
    )

    $findings = New-Object System.Collections.Generic.List[object]
    if ([string]$Receipt.status -ne "canary_applied") { $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_receipt_status_invalid" "Replay requires a canary_applied receipt.")) | Out-Null }
    if ([int]$Report.schema_version -ne 1 -or [string]$Report.execution_boundary -ne "fresh_ephemeral_task") { $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_boundary_invalid" "Replay report must come from fresh_ephemeral_task execution.")) | Out-Null }
    if (-not [string]::Equals([string]$Report.original_profile, [string]$Receipt.active_profile, [System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$Report.restored_profile, [string]$Receipt.active_profile, [System.StringComparison]::OrdinalIgnoreCase)) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_profile_not_restored" "Replay must start from and restore the receipt active_profile.")) | Out-Null
    }
    $results = @($Report.results)
    if ($results.Count -eq 0) { $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_results_missing" "Replay report has no results.")) | Out-Null }
    foreach ($result in @($results | Where-Object { -not [bool]$_.expectation_pass -or [int]$_.exit_code -ne 0 -or -not [bool]$_.parse_ok })) {
        $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_expectation_failed" ("Replay failed for profile '{0}', case '{1}'." -f [string]$result.profile, [string]$result.case_id) "" ([string]$result.profile))) | Out-Null
    }

    $corpusCases = @($Corpus.cases)
    foreach ($profile in @($Receipt.changed_profiles)) {
        $profileResults = @($results | Where-Object { [string]::Equals([string]$_.profile, [string]$profile, [System.StringComparison]::OrdinalIgnoreCase) })
        if (@($profileResults.case_id | Sort-Object -Unique).Count -lt 4) {
            $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_case_coverage_insufficient" ("Profile '{0}' requires at least four distinct replay cases." -f $profile) "" ([string]$profile))) | Out-Null
        }
        foreach ($action in @($Receipt.actions | Where-Object { [string]::Equals([string]$_.profile, [string]$profile, [System.StringComparison]::OrdinalIgnoreCase) })) {
            $skill = [string]$action.skill
            $requiredCases = @($corpusCases | Where-Object {
                    $expectation = $_.expectations.PSObject.Properties[[string]$profile]
                    $null -ne $expectation -and $skill -in @($expectation.Value.required)
                } | ForEach-Object { [string]$_.id })
            $forbiddenCases = @($corpusCases | Where-Object {
                    $expectation = $_.expectations.PSObject.Properties[[string]$profile]
                    $null -ne $expectation -and $skill -in @($expectation.Value.forbidden)
                } | ForEach-Object { [string]$_.id })
            if ([string]$action.operation -eq "add" -and @($profileResults | Where-Object { [string]$_.case_id -in $requiredCases }).Count -eq 0) {
                $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_positive_coverage_missing" ("Added skill '{0}' has no direct/indirect positive replay in profile '{1}'." -f $skill, $profile) $skill ([string]$profile))) | Out-Null
            }
            if (@($profileResults | Where-Object { [string]$_.case_id -in $forbiddenCases }).Count -eq 0) {
                $findings.Add((New-SkillProfileReconciliationTransactionFinding "replay_negative_coverage_missing" ("Changed skill '{0}' has no negative replay in profile '{1}'." -f $skill, $profile) $skill ([string]$profile))) | Out-Null
            }
        }
    }
    return [pscustomobject]@{ pass = ($findings.Count -eq 0); host_replay_status = $(if ($findings.Count -eq 0) { "host_evaluation_partial_pass" } else { "host_evaluation_partial_fail" }); findings = @($findings.ToArray()) }
}

function Complete-SkillProfileReconciliationCanary {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ReplayReportPath,
        [Parameter(Mandatory = $true)][string]$CorpusPath,
        [Parameter(Mandatory = $true)][string]$Token,
        [switch]$RollbackOnFailure
    )

    if ($Token -cne "ACCEPT_PROFILE_RECONCILIATION_CANARY") {
        return [pscustomobject]@{ pass = $false; status = "blocked"; replay_status = "not_run"; rollback_performed = $false; findings = @((New-SkillProfileReconciliationTransactionFinding "accept_token_invalid" "Explicit canary acceptance token does not match.")) }
    }
    $configFile = [System.IO.Path]::GetFullPath($ConfigPath)
    $receiptFile = [System.IO.Path]::GetFullPath($ReceiptPath)
    $reportFile = [System.IO.Path]::GetFullPath($ReplayReportPath)
    $corpusFile = [System.IO.Path]::GetFullPath($CorpusPath)
    foreach ($file in @($receiptFile, $reportFile, $corpusFile)) { Need (Test-Path -LiteralPath $file -PathType Leaf) ("Required canary file does not exist: {0}" -f $file) }
    $receipt = Get-Content -LiteralPath $receiptFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $report = Get-Content -LiteralPath $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $corpus = Get-Content -LiteralPath $corpusFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $validation = Test-SkillProfileReconciliationReplay -Receipt $receipt -Report $report -Corpus $corpus
    if (-not [bool]$validation.pass) {
        if ($RollbackOnFailure) {
            $receipt.status = "replay_failed"
            $receipt.replay.status = [string]$validation.host_replay_status
            $receipt.replay.report_path = $reportFile
            $receipt.replay.report_sha256 = Get-FileContentHash $reportFile
            Write-SkillProfileReconciliationReceipt $receiptFile $receipt
            $rollback = Invoke-SkillProfileReconciliationRollback -ConfigPath $configFile -ReceiptPath $receiptFile -Token "ROLLBACK_PROFILE_RECONCILIATION_CANARY"
            return [pscustomobject]@{ pass = $false; status = [string]$rollback.status; replay_status = [string]$validation.host_replay_status; rollback_performed = [bool]$rollback.pass; findings = @($validation.findings); receipt = $rollback.receipt }
        }
        return [pscustomobject]@{ pass = $false; status = "replay_failed"; replay_status = [string]$validation.host_replay_status; rollback_performed = $false; findings = @($validation.findings); receipt = $receipt }
    }
    if ((Get-FileContentHash $configFile) -ne [string]$receipt.after_config_sha256) {
        return [pscustomobject]@{ pass = $false; status = "blocked"; replay_status = "host_evaluation_partial_pass"; rollback_performed = $false; findings = @((New-SkillProfileReconciliationTransactionFinding "accept_target_stale" "skills.json changed after canary apply; acceptance is blocked.")); receipt = $receipt }
    }
    $receipt.status = "accepted"
    $receipt.replay.status = [string]$validation.host_replay_status
    $receipt.replay.report_path = $reportFile
    $receipt.replay.report_sha256 = Get-FileContentHash $reportFile
    $receipt | Add-Member -NotePropertyName accepted_at -NotePropertyValue ([datetimeoffset]::UtcNow.ToString("o")) -Force
    Write-SkillProfileReconciliationReceipt $receiptFile $receipt
    return [pscustomobject]@{ pass = $true; status = "accepted"; replay_status = [string]$validation.host_replay_status; rollback_performed = $false; findings = @(); receipt = $receipt }
}
