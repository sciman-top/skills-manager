$nativeMetadataPlannerRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . (Join-Path $nativeMetadataPlannerRepoRoot 'src\Domain\OperationPlan.ps1') }

function Get-NativeMetadataPlannerProperty {
    param($Object, [string[]]$Names)

    foreach ($name in @($Names)) {
        if (Test-OperationObjectProperty $Object $name) { return Get-OperationObjectProperty $Object $name }
    }
    return $null
}

function Get-DefaultNativeMetadataPolicy {
    return [pscustomobject][ordered]@{
        schema_version = 1
        context_ratio = 0.02
        headroom_ratio = 0.20
        unknown_context_character_ceiling = 8000
        estimated_tokens_per_utf8_byte = 0.25
        max_compacted_description_characters = 160
        min_compacted_description_characters = 24
    }
}

function Get-NativeMetadataPolicyValue {
    param($Policy, [string]$Name, $Default)

    $value = Get-NativeMetadataPlannerProperty $Policy @($Name)
    if ($null -eq $value) { return $Default }
    return $value
}

function Get-NativeMetadataSnapshotFact {
    param($Snapshot, [string]$Name)

    $capabilities = Get-NativeMetadataPlannerProperty $Snapshot @('capabilities')
    $raw = Get-NativeMetadataPlannerProperty $capabilities @($Name)
    if ($null -eq $raw) {
        return [pscustomobject]@{ value = $null; source = 'unknown_fallback'; freshness = 'unknown'; unknown_reason = ('{0}_missing' -f $Name) }
    }
    if (Test-OperationObjectProperty $raw 'value') {
        return [pscustomobject]@{
            value = Get-OperationObjectProperty $raw 'value'
            source = [string]$(if (Test-OperationObjectProperty $raw 'source') { Get-OperationObjectProperty $raw 'source' } else { 'unknown_fallback' })
            freshness = [string]$(if (Test-OperationObjectProperty $raw 'freshness') { Get-OperationObjectProperty $raw 'freshness' } else { 'unknown' })
            unknown_reason = [string]$(if (Test-OperationObjectProperty $raw 'unknown_reason') { Get-OperationObjectProperty $raw 'unknown_reason' } else { '' })
        }
    }
    return [pscustomobject]@{ value = $raw; source = 'unknown_fallback'; freshness = 'unknown'; unknown_reason = ('{0}_unwrapped' -f $Name) }
}

function ConvertTo-NativeMetadataPositiveInteger {
    param($Value, [bool]$AllowZero = $false)

    $number = 0L
    if ($null -eq $Value -or -not [long]::TryParse([string]$Value, [ref]$number)) { return $null }
    if ($AllowZero) {
        if ($number -lt 0) { return $null }
    }
    elseif ($number -le 0) { return $null }
    return [long]$number
}

function ConvertTo-NativeMetadataRatio {
    param($Value, [double]$Default)

    $number = 0.0
    if ($null -eq $Value -or -not [double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $Default }
    if ($number -lt 0.0 -or $number -ge 1.0) { return $Default }
    return $number
}

function Get-NativeMetadataInventoryEntries {
    param($Inventory)

    if ($null -eq $Inventory) { return @() }
    $rawEntries = if (Test-OperationObjectProperty $Inventory 'entries') {
        Get-OperationObjectProperty $Inventory 'entries'
    }
    elseif (Test-OperationObjectProperty $Inventory 'skills') {
        Get-OperationObjectProperty $Inventory 'skills'
    }
    else { $Inventory }

    return @($rawEntries | Where-Object {
            $null -ne $_ -and
            ((-not (Test-OperationObjectProperty $_ 'enabled')) -or [bool](Get-OperationObjectProperty $_ 'enabled'))
        } | Sort-Object @{ Expression = { ([string](Get-NativeMetadataPlannerProperty $_ @('name', 'id'))).ToLowerInvariant() } }, path)
}

function Compress-NativeMetadataDescription {
    param(
        [string]$Description,
        [int]$MaximumCharacters,
        [int]$MinimumCharacters
    )

    $normalized = ([regex]::Replace([string]$Description, '\s+', ' ')).Trim()
    if ($normalized.Length -le $MaximumCharacters) { return $normalized }
    $limit = [Math]::Max(3, $MaximumCharacters)
    $prefixLength = [Math]::Max(1, $limit - 1)
    $prefix = $normalized.Substring(0, [Math]::Min($prefixLength, $normalized.Length)).TrimEnd()
    if ($prefix.Length -lt [Math]::Min($MinimumCharacters, $prefix.Length)) { return $normalized.Substring(0, [Math]::Min($limit, $normalized.Length)).TrimEnd() }
    return ($prefix + '…')
}

function Get-NativeMetadataCost {
    param(
        $Entry,
        [string]$Description,
        [double]$TokensPerUtf8Byte
    )

    $name = [string](Get-NativeMetadataPlannerProperty $Entry @('name', 'id'))
    $path = [string](Get-NativeMetadataPlannerProperty $Entry @('path'))
    $payload = ('{0}`n{1}`n{2}' -f $name, $Description, $path)
    $characterCount = [Text.Encoding]::UTF8.GetByteCount($payload)
    $provided = Get-NativeMetadataPlannerProperty $Entry @('token_estimate', 'estimated_tokens', 'tokens')
    $providedNumber = ConvertTo-NativeMetadataPositiveInteger $provided $true
    if ($null -ne $providedNumber) {
        return [pscustomobject]@{ character_count = [long]$characterCount; token_estimate = [long]$providedNumber; token_estimate_source = 'provided' }
    }
    $estimated = [long][Math]::Ceiling($characterCount * $TokensPerUtf8Byte)
    return [pscustomobject]@{ character_count = [long]$characterCount; token_estimate = [long]$estimated; token_estimate_source = 'utf8_byte_estimate' }
}

function ConvertTo-NativeMetadataItem {
    param(
        $Entry,
        [double]$TokensPerUtf8Byte,
        [int]$MaximumDescriptionCharacters,
        [int]$MinimumDescriptionCharacters,
        [bool]$Compact
    )

    $name = [string](Get-NativeMetadataPlannerProperty $Entry @('name', 'id'))
    $description = [string](Get-NativeMetadataPlannerProperty $Entry @('description'))
    $finalDescription = if ($Compact) { Compress-NativeMetadataDescription $description $MaximumDescriptionCharacters $MinimumDescriptionCharacters } else { $description }
    $cost = Get-NativeMetadataCost $Entry $finalDescription $TokensPerUtf8Byte
    return [pscustomobject][ordered]@{
        kind = [string]$(if (Test-OperationObjectProperty $Entry 'kind') { Get-OperationObjectProperty $Entry 'kind' } else { 'skill' })
        name = $name
        planned_description = $finalDescription
        path = [string](Get-NativeMetadataPlannerProperty $Entry @('path'))
        content_hash = Get-NativeMetadataPlannerProperty $Entry @('content_hash', 'entrypoint_sha256')
        metadata_hash = Get-NativeMetadataPlannerProperty $Entry @('metadata_hash')
        character_count = $cost.character_count
        token_estimate = $cost.token_estimate
        token_estimate_source = $cost.token_estimate_source
        compacted = ($finalDescription -ne $description)
    }
}

function Get-NativeMetadataMeasuredCost {
    param($Items, [string]$Mode)

    if ($Mode -eq 'tokens') { return [long]((@($Items | ForEach-Object { [long]$_.token_estimate } | Measure-Object -Sum).Sum)) }
    return [long]((@($Items | ForEach-Object { [long]$_.character_count } | Measure-Object -Sum).Sum))
}

function Plan-NativeMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Inventory,
        [Parameter(Mandatory = $true)]$Snapshot,
        $Policy = $null
    )

    if ($null -eq $Policy) { $Policy = Get-DefaultNativeMetadataPolicy }
    $contextRatio = ConvertTo-NativeMetadataRatio (Get-NativeMetadataPolicyValue $Policy 'context_ratio' 0.02) 0.02
    $headroomRatio = ConvertTo-NativeMetadataRatio (Get-NativeMetadataPolicyValue $Policy 'headroom_ratio' 0.20) 0.20
    $tokensPerByte = [double](Get-NativeMetadataPolicyValue $Policy 'estimated_tokens_per_utf8_byte' 0.25)
    if ($tokensPerByte -le 0) { $tokensPerByte = 0.25 }
    $fallbackCharacters = [int](Get-NativeMetadataPolicyValue $Policy 'unknown_context_character_ceiling' 8000)
    if ($fallbackCharacters -le 0) { $fallbackCharacters = 8000 }
    $maxDescriptionCharacters = [int](Get-NativeMetadataPolicyValue $Policy 'max_compacted_description_characters' 160)
    if ($maxDescriptionCharacters -le 0) { $maxDescriptionCharacters = 160 }
    $minDescriptionCharacters = [int](Get-NativeMetadataPolicyValue $Policy 'min_compacted_description_characters' 24)
    if ($minDescriptionCharacters -le 0) { $minDescriptionCharacters = 24 }
    $minDescriptionCharacters = [Math]::Min($minDescriptionCharacters, $maxDescriptionCharacters)

    $contextFact = Get-NativeMetadataSnapshotFact $Snapshot 'context_window'
    $metadataBudgetFact = Get-NativeMetadataSnapshotFact $Snapshot 'metadata_budget'
    $contextValue = if ([string]$contextFact.freshness -eq 'fresh') { ConvertTo-NativeMetadataPositiveInteger $contextFact.value $false } else { $null }
    $hostBudget = if ([string]$metadataBudgetFact.freshness -eq 'fresh') { ConvertTo-NativeMetadataPositiveInteger $metadataBudgetFact.value $true } else { $null }
    $mode = 'character_fallback'
    $budgetSource = 'unknown_fallback'
    $formula = 'unknown_context_character_fallback'
    $tokenCeiling = $null
    $characterCeiling = [long]$fallbackCharacters
    $hostCeilingApplied = $false

    if ($null -ne $contextValue) {
        $tokenCeiling = [long][Math]::Floor($contextValue * $contextRatio)
        $mode = 'tokens'
        $budgetSource = [string]$contextFact.source
        $formula = 'floor(context_window * context_ratio)'
        if ($null -ne $hostBudget -and $hostBudget -lt $tokenCeiling) {
            $tokenCeiling = [long]$hostBudget
            $budgetSource = [string]$metadataBudgetFact.source
            $formula = 'min(floor(context_window * context_ratio), host_metadata_budget)'
            $hostCeilingApplied = $true
        }
    }
    elseif ($null -ne $hostBudget) {
        $mode = 'tokens'
        $tokenCeiling = [long]$hostBudget
        $budgetSource = [string]$metadataBudgetFact.source
        $formula = 'host_metadata_budget_without_context_window'
        $hostCeilingApplied = $true
    }

    $headroom = if ($mode -eq 'tokens') { [long][Math]::Floor($tokenCeiling * $headroomRatio) } else { [long][Math]::Floor($characterCeiling * $headroomRatio) }
    $usableTokens = if ($mode -eq 'tokens') { [long][Math]::Max(0, $tokenCeiling - $headroom) } else { $null }
    $usableCharacters = if ($mode -eq 'character_fallback') { [long][Math]::Max(0, $characterCeiling - $headroom) } else { $null }
    $usableCost = if ($mode -eq 'tokens') { $usableTokens } else { $usableCharacters }

    $enabledEntries = @(Get-NativeMetadataInventoryEntries $Inventory)
    $rawItems = @($enabledEntries | ForEach-Object { ConvertTo-NativeMetadataItem $_ $tokensPerByte $maxDescriptionCharacters $minDescriptionCharacters $false })
    $rawCost = Get-NativeMetadataMeasuredCost $rawItems $mode
    $compactionAttempted = $rawCost -gt $usableCost
    $finalItems = $rawItems
    $compactionChanged = @()
    $finalDescriptionCharacters = $maxDescriptionCharacters
    if ($compactionAttempted) {
        $finalItems = @($enabledEntries | ForEach-Object { ConvertTo-NativeMetadataItem $_ $tokensPerByte $maxDescriptionCharacters $minDescriptionCharacters $true })
        $compactedCost = Get-NativeMetadataMeasuredCost $finalItems $mode
        if ($compactedCost -gt $usableCost -and $minDescriptionCharacters -lt $maxDescriptionCharacters) {
            $minimumItems = @($enabledEntries | ForEach-Object { ConvertTo-NativeMetadataItem $_ $tokensPerByte $minDescriptionCharacters $minDescriptionCharacters $true })
            $minimumCost = Get-NativeMetadataMeasuredCost $minimumItems $mode
            if ($minimumCost -le $usableCost) {
                $bestItems = $minimumItems
                $bestLimit = $minDescriptionCharacters
                $low = $minDescriptionCharacters + 1
                $high = $maxDescriptionCharacters - 1
                while ($low -le $high) {
                    $mid = [int][Math]::Floor(($low + $high) / 2)
                    $candidateItems = @($enabledEntries | ForEach-Object { ConvertTo-NativeMetadataItem $_ $tokensPerByte $mid $minDescriptionCharacters $true })
                    $candidateCost = Get-NativeMetadataMeasuredCost $candidateItems $mode
                    if ($candidateCost -le $usableCost) {
                        $bestItems = $candidateItems
                        $bestLimit = $mid
                        $low = $mid + 1
                    }
                    else { $high = $mid - 1 }
                }
                $finalItems = $bestItems
                $finalDescriptionCharacters = $bestLimit
            }
            else {
                $finalItems = $minimumItems
                $finalDescriptionCharacters = $minDescriptionCharacters
            }
        }
        $compactionChanged = @($finalItems | Where-Object compacted | ForEach-Object name)
    }
    $finalCost = Get-NativeMetadataMeasuredCost $finalItems $mode
    $pass = $finalCost -le $usableCost
    $enabledNames = @($enabledEntries | ForEach-Object { [string](Get-NativeMetadataPlannerProperty $_ @('name', 'id')) })
    $keptItems = if ($pass) { @($finalItems) } else { @() }
    $keptNames = @($keptItems | ForEach-Object name)
    $omittedNames = if ($pass) { @() } else { @($enabledNames) }
    $offenders = if ($pass) { @() } else {
        @($finalItems | ForEach-Object {
                [pscustomobject][ordered]@{
                    name = [string]$_.name
                    required = if ($mode -eq 'tokens') { [long]$_.token_estimate } else { [long]$_.character_count }
                    token_estimate = [long]$_.token_estimate
                    character_count = [long]$_.character_count
                    token_estimate_source = [string]$_.token_estimate_source
                }
            })
    }
    $totalTokens = [long]((@($finalItems | ForEach-Object { [long]$_.token_estimate } | Measure-Object -Sum).Sum))
    $totalCharacters = [long]((@($finalItems | ForEach-Object { [long]$_.character_count } | Measure-Object -Sum).Sum))
    $identity = [ordered]@{
        mode = $mode
        token_ceiling = $tokenCeiling
        character_ceiling = $characterCeiling
        usable_cost = $usableCost
        entries = @($finalItems | ForEach-Object { [ordered]@{ name = $_.name; token_estimate = $_.token_estimate; character_count = $_.character_count; planned_description = $_.planned_description } })
    }
    $planId = 'nmp-{0}' -f (Get-OperationSha256 ($identity | ConvertTo-Json -Depth 20 -Compress)).Substring(0, 16)
    $findings = New-Object System.Collections.Generic.List[object]
    if (-not $pass) { $findings.Add((New-OperationFinding 'metadata_budget_overflow' 'error' '$.metadata' 'All enabled metadata could not fit after deterministic compaction.')) | Out-Null }

    return [pscustomobject][ordered]@{
        schema_version = 1
        plan_id = $planId
        projection_effect = 'plan_only'
        pass_scope = 'advisory_planning_contract'
        pass = $pass
        status = if ($pass) { 'ready' } else { 'blocked' }
        block_reason = if ($pass) { $null } else { 'metadata_budget_overflow' }
        budget = [ordered]@{
            mode = $mode
            unit = if ($mode -eq 'tokens') { 'tokens' } else { 'characters' }
            source = $budgetSource
            formula = $formula
            context_window = $contextValue
            context_window_source = [string]$contextFact.source
            context_window_freshness = [string]$contextFact.freshness
            metadata_budget = $hostBudget
            metadata_budget_source = [string]$metadataBudgetFact.source
            metadata_budget_freshness = [string]$metadataBudgetFact.freshness
            host_budget_status = if ($null -ne $hostBudget) { 'observed' } else { 'unknown' }
            host_budget_pass = if ($null -ne $hostBudget) { ($totalTokens -le [long][Math]::Max(0, [Math]::Floor($hostBudget * (1.0 - $headroomRatio)))) } else { $null }
            host_ceiling_applied = $hostCeilingApplied
            context_ratio = $contextRatio
            headroom_ratio = $headroomRatio
            headroom = $headroom
            token_ceiling = $tokenCeiling
            ceiling_tokens = $tokenCeiling
            character_ceiling = if ($mode -eq 'character_fallback') { $characterCeiling } else { $null }
            usable_tokens = $usableTokens
            usable_characters = $usableCharacters
            provenance = [ordered]@{
                context_window_source = [string]$contextFact.source
                metadata_budget_source = [string]$metadataBudgetFact.source
                unknown_reason = if ($mode -eq 'character_fallback') { if ([string]::IsNullOrWhiteSpace([string]$contextFact.unknown_reason)) { 'context_window_unknown' } else { [string]$contextFact.unknown_reason } } else { $null }
            }
        }
        measurement = [ordered]@{
            unit = if ($mode -eq 'tokens') { 'tokens' } else { 'characters' }
            token_estimate_used = ($mode -eq 'tokens')
            estimator = if ($mode -eq 'tokens') { 'provided_or_utf8_byte_estimate' } else { 'not_used_for_budget' }
            character_count_is_not_token_count = $true
        }
        enabled = [object[]]@($enabledNames)
        kept = [object[]]@($keptNames)
        omitted = [object[]]@($omittedNames)
        metadata = [object[]]@($keptItems)
        enabled_total = $enabledEntries.Count
        kept_total = $keptItems.Count
        omitted_total = $omittedNames.Count
        disabled_total = @($Inventory.entries | Where-Object { (Test-OperationObjectProperty $_ 'enabled') -and -not [bool](Get-OperationObjectProperty $_ 'enabled') }).Count
        truncated = (-not $pass)
        token_estimate = if ($mode -eq 'tokens') { $totalTokens } else { $null }
        estimated_token_total = $totalTokens
        character_count = $totalCharacters
        compaction = [ordered]@{
            attempted = $compactionAttempted
            applied = ($compactionChanged.Count -gt 0)
            changed_names = @($compactionChanged)
            before_cost = $rawCost
            after_cost = $finalCost
            maximum_description_characters = $maxDescriptionCharacters
            final_maximum_description_characters = $finalDescriptionCharacters
            minimum_description_characters = $minDescriptionCharacters
        }
        overflow = [ordered]@{
            offenders = [object[]]@($offenders)
            required = if ($pass) { 0 } else { $finalCost }
            available = $usableCost
            unit = if ($mode -eq 'tokens') { 'tokens' } else { 'characters' }
        }
        findings = [object[]]@($findings.ToArray())
        decision_owner = 'deterministic_planner'
        semantic_selection_applied = $false
        profile_filter_applied = $false
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Test-NativeMetadataPlanContract {
    param($Plan)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan) { return New-OperationValidationResult @((New-OperationFinding 'metadata_plan_missing' 'error' '$' 'Native metadata plan is required.')) }
    if ((Get-OperationObjectProperty $Plan 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only NativeMetadataPlan schema version 1 is supported.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Plan 'plan_id') -notmatch '^nmp-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'plan_id_invalid' 'error' '$.plan_id' 'Metadata plan id must be deterministic.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Plan 'projection_effect') -ne 'plan_only') { $findings.Add((New-OperationFinding 'projection_effect_invalid' 'error' '$.projection_effect' 'Metadata descriptions are advisory plan-only values.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Plan 'pass_scope') -ne 'advisory_planning_contract') { $findings.Add((New-OperationFinding 'pass_scope_invalid' 'error' '$.pass_scope' 'Metadata plan pass cannot claim host materialization or host budget acceptance.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Plan 'decision_owner') -ne 'deterministic_planner') { $findings.Add((New-OperationFinding 'decision_owner_invalid' 'error' '$.decision_owner' 'Metadata planning is deterministic and cannot own semantic selection.')) | Out-Null }
    foreach ($field in @('semantic_selection_applied', 'profile_filter_applied')) {
        if ((Get-OperationObjectProperty $Plan $field) -ne $false) { $findings.Add((New-OperationFinding 'semantic_boundary_breached' 'error' ('$.{0}' -f $field) 'Metadata planner cannot apply semantic selection or profile filtering.')) | Out-Null }
    }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-OperationObjectProperty $Plan $field) -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Metadata planning must be zero-side-effect.')) | Out-Null }
    }
    foreach ($field in @('enabled', 'kept', 'omitted', 'metadata', 'findings')) {
        if (-not (Test-OperationArray (Get-OperationObjectProperty $Plan $field))) { $findings.Add((New-OperationFinding 'array_field_invalid' 'error' ('$.{0}' -f $field) 'Metadata plan arrays are required.')) | Out-Null }
    }
    foreach ($item in @((Get-OperationObjectProperty $Plan 'metadata'))) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $item 'planned_description'))) { $findings.Add((New-OperationFinding 'planned_description_missing' 'error' '$.metadata' 'Each retained item requires an advisory planned_description.')) | Out-Null }
        if (Test-OperationObjectProperty $item 'description') { $findings.Add((New-OperationFinding 'materialization_claim_forbidden' 'error' '$.metadata.description' 'Generic description would imply the advisory value was materialized.')) | Out-Null }
    }
    $enabledTotal = [int](Get-OperationObjectProperty $Plan 'enabled_total')
    $keptTotal = [int](Get-OperationObjectProperty $Plan 'kept_total')
    $omittedTotal = [int](Get-OperationObjectProperty $Plan 'omitted_total')
    if ($enabledTotal -ne @((Get-OperationObjectProperty $Plan 'enabled')).Count) { $findings.Add((New-OperationFinding 'enabled_count_invalid' 'error' '$.enabled_total' 'enabled_total must match enabled names.')) | Out-Null }
    if ($keptTotal -ne @((Get-OperationObjectProperty $Plan 'kept')).Count) { $findings.Add((New-OperationFinding 'kept_count_invalid' 'error' '$.kept_total' 'kept_total must match kept names.')) | Out-Null }
    if ($omittedTotal -ne @((Get-OperationObjectProperty $Plan 'omitted')).Count) { $findings.Add((New-OperationFinding 'omitted_count_invalid' 'error' '$.omitted_total' 'omitted_total must match omitted names.')) | Out-Null }
    $pass = [bool](Get-OperationObjectProperty $Plan 'pass')
    if ($pass -and ($keptTotal -ne $enabledTotal -or $omittedTotal -ne 0 -or (Get-OperationObjectProperty $Plan 'truncated') -ne $false)) { $findings.Add((New-OperationFinding 'complete_projection_invalid' 'error' '$' 'A passing plan must keep every enabled item without truncation.')) | Out-Null }
    if (-not $pass -and ($omittedTotal -eq 0 -or (Get-OperationObjectProperty $Plan 'truncated') -ne $true)) { $findings.Add((New-OperationFinding 'blocked_projection_invalid' 'error' '$' 'A blocked plan must expose explicit omission and truncation.')) | Out-Null }
    $budget = Get-OperationObjectProperty $Plan 'budget'
    $mode = [string](Get-OperationObjectProperty $budget 'mode')
    if ($mode -notin @('tokens', 'character_fallback')) { $findings.Add((New-OperationFinding 'budget_mode_invalid' 'error' '$.budget.mode' 'Budget mode is invalid.')) | Out-Null }
    $hostBudgetStatus = [string](Get-OperationObjectProperty $budget 'host_budget_status')
    if ($hostBudgetStatus -notin @('observed', 'unknown')) { $findings.Add((New-OperationFinding 'host_budget_status_invalid' 'error' '$.budget.host_budget_status' 'Host metadata budget status must be explicit.')) | Out-Null }
    if ($hostBudgetStatus -eq 'unknown' -and $null -ne (Get-OperationObjectProperty $budget 'host_budget_pass')) { $findings.Add((New-OperationFinding 'unknown_host_budget_pass_forbidden' 'error' '$.budget.host_budget_pass' 'Unknown host metadata budget cannot be reported as pass or fail.')) | Out-Null }
    $measurement = Get-OperationObjectProperty $Plan 'measurement'
    if ([string](Get-OperationObjectProperty $measurement 'unit') -ne $(if ($mode -eq 'tokens') { 'tokens' } else { 'characters' })) { $findings.Add((New-OperationFinding 'measurement_unit_invalid' 'error' '$.measurement.unit' 'Measurement unit must match budget mode.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
