function Get-McpSyncManagedTargetSpecs {
    param(
        $Roots = @(),
        $CandidatePaths = @(),
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $specs = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $flatRoots = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($Roots)) {
        foreach ($value in @($entry)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $flatRoots.Add([string]$value) | Out-Null }
        }
    }

    function Add-McpTargetSpec([string]$Path, [string]$Kind, [string]$Root) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $key = Normalize-OperationPathKey $Path
        if (-not $seen.Add($key)) { return }
        $specs.Add([pscustomobject][ordered]@{
                path = $Path
                kind = $Kind
                root = $Root
            }) | Out-Null
    }

    foreach ($root in @($flatRoots.ToArray() | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root '.mcp.json') 'generic_json' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.gemini', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'settings.json') 'gemini_settings' $root
    }
    foreach ($root in @(Resolve-GeminiAntigravityRootsFromCandidates $CandidatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'settings.json') 'gemini_antigravity_settings' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.codex', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'config.toml') 'codex_toml' $root
    }
    $traeRoots = @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.trae', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)
    foreach ($root in $traeRoots) {
        Add-McpTargetSpec (Join-Path $root 'mcp.json') 'trae_json' $root
    }
    if ($traeRoots.Count -gt 0) {
        Add-McpTargetSpec (Get-TraeProjectMcpConfigPath $RepoRoot) 'trae_project_json' $RepoRoot
    }

    return @($specs.ToArray())
}

function Get-McpExistingStateValue($ExistingStates, [string]$Path) {
    if ($null -eq $ExistingStates) {
        return [pscustomobject]@{ exists = $false; content = '' }
    }
    $key = Normalize-OperationPathKey $Path
    if ($ExistingStates -is [System.Collections.IDictionary] -and $ExistingStates.Contains($key)) {
        return $ExistingStates[$key]
    }
    if ($ExistingStates -is [pscustomobject]) {
        $property = @($ExistingStates.PSObject.Properties | Where-Object { $_.Name -eq $key } | Select-Object -First 1)
        if ($property.Count -eq 1) { return $property[0].Value }
    }
    return [pscustomobject]@{ exists = $false; content = '' }
}

function New-McpSyncDesiredState {
    param(
        [object[]]$Specs = @(),
        [object[]]$Servers = @(),
        [object[]]$ActiveServers = @(),
        [string[]]$ProfileDisabledNames = @(),
        [string[]]$PruneNames = @(),
        $ExistingStates = $null
    )

    $desired = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @($Specs)) {
        $path = [string]$spec.path
        $state = Get-McpExistingStateValue $ExistingStates $path
        $existing = if ($null -eq $state -or $null -eq $state.content) { '' } else { [string]$state.content }
        $content = $null

        switch ([string]$spec.kind) {
            'generic_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload @($PruneNames + $ProfileDisabledNames)
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'gemini_settings' {
                $payload = Build-GeminiSettingsPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'gemini_antigravity_settings' {
                $payload = Build-GeminiSettingsPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'codex_toml' {
                $content = Build-CodexConfigToml $existing $Servers
            }
            'trae_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'trae_project_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            default { throw ('Unsupported MCP managed target kind: {0}' -f [string]$spec.kind) }
        }

        $beforeHash = if ([bool]$state.exists) { Get-OperationSha256 $existing } else { $null }
        $desiredHash = Get-OperationSha256 ([string]$content)
        $desired.Add([pscustomobject][ordered]@{
                target_ref = 'mcp-target-{0}' -f (Get-OperationSha256 (Normalize-OperationPathKey $path)).Substring(0, 16)
                path = $path
                kind = [string]$spec.kind
                root = [string]$spec.root
                owner = 'skills-manager:mcp:{0}' -f [string]$spec.kind
                existed = [bool]$state.exists
                before_hash = $beforeHash
                desired_hash = $desiredHash
                changed = ($beforeHash -ne $desiredHash)
                desired_content = [string]$content
            }) | Out-Null
    }
    return @($desired.ToArray() | Sort-Object target_ref)
}

function New-McpSyncOperationPlanResult {
    param(
        [object[]]$DesiredState = @(),
        [Parameter(Mandatory = $true)][string]$CreatedAt,
        [string]$SourceRevision
    )

    $targets = New-Object System.Collections.Generic.List[object]
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($target in @($DesiredState)) {
        $targets.Add([pscustomobject][ordered]@{
                target_ref = [string]$target.target_ref
                path = [string]$target.path
                before_hash = $target.before_hash
                desired_hash = [string]$target.desired_hash
                owner = [string]$target.owner
            }) | Out-Null
        if ([bool]$target.changed) {
            $verb = if ([bool]$target.existed) { 'Update' } else { 'Create' }
            $actions.Add([pscustomobject][ordered]@{
                    type = if ([bool]$target.existed) { 'update' } else { 'create' }
                    target_ref = [string]$target.target_ref
                    summary = ('{0} managed MCP target ({1})' -f $verb, [string]$target.kind)
                    risk = 'medium'
                    metadata = [pscustomobject]@{ target_kind = [string]$target.kind }
                }) | Out-Null
        }
    }

    $orderedTargets = @($targets.ToArray() | Sort-Object target_ref)
    $orderedActions = @($actions.ToArray() | Sort-Object target_ref, type)
    $fingerprint = Get-OperationSha256 (($orderedTargets | ConvertTo-Json -Depth 20 -Compress) + '|' + [string]$SourceRevision)
    $plan = New-OperationPlan `
        -OperationId ('mcp-sync-{0}' -f $fingerprint.Substring(0, 16)) `
        -Domain 'mcp' `
        -Mode 'dry_run' `
        -CreatedAt $CreatedAt `
        -SourceRevision $SourceRevision `
        -Targets $orderedTargets `
        -Actions $orderedActions `
        -Preconditions @('skills.json contract valid', 'managed target roots resolved') `
        -Verification @('repo target hashes only; host loading and live acceptance are not claimed') `
        -Rollback @('plan mode performs no managed target or native mutation')

    return [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'mcp_sync_plan'
        operation_plan = $plan
        summary = [pscustomobject][ordered]@{
            managed_target_count = @($DesiredState).Count
            changed_target_count = @($DesiredState | Where-Object changed).Count
            unchanged_target_count = @($DesiredState | Where-Object { -not [bool]$_.changed }).Count
            native_mutation_planned = $false
            profile_changed = $false
            host_loaded = 'not_run'
            live_accepted = 'not_run'
        }
    }
}
function New-McpPlanReceiptSkeleton {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [string]$StartedAt = [datetimeoffset]::UtcNow.ToString('o'),
        [string]$CompletedAt = [datetimeoffset]::UtcNow.ToString('o')
    )
    $validation = Test-OperationPlanContract $Plan
    return New-OperationReceipt -OperationId ([string](Get-OperationObjectProperty $Plan 'operation_id')) -Status dry_run -StartedAt $StartedAt -CompletedAt $CompletedAt -Actions @((Get-OperationObjectProperty $Plan 'actions') | ForEach-Object { [pscustomobject]@{ action_id=[string]$_.action_id; status='not_run'; target_ref=[string]$_.target_ref } }) -Verification ([pscustomobject]@{static_validated=$(if($validation.pass){'pass'}else{'fail'});repo_gates_passed='not_run';host_loaded='not_run';live_accepted='not_run'}) -Rollback @('not_run')
}
