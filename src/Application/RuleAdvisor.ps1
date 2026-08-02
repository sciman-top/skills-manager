function Get-RuleAdvisorSurface([string]$NeedKind) {
    switch ($NeedKind) {
        'task_local' { return 'prompt_or_thread' }
        'repeatable_workflow' { return 'skill' }
        'installable_bundle' { return 'plugin' }
        'external_data_or_action' { return 'mcp_or_connector' }
        'deterministic_enforcement' { return 'hook_config_script_or_ci' }
        default { return 'AGENTS.md' }
    }
}

function Invoke-RuleAdvisor {
    param([object[]]$Documents = @(), [object[]]$Constraints = @())
    $semantic = New-Object System.Collections.Generic.List[object]
    foreach ($document in @($Documents)) {
        $scope = [string]$document.scope; $responsibility = [string]$document.responsibility
        $misplaced = ($scope -eq 'global' -and $responsibility -eq 'project_action') -or ($scope -in @('repo', 'subtree') -and $responsibility -eq 'common')
        if ($misplaced) { $semantic.Add((New-RuleFinding -Kind semantic -Code responsibility_scope_mismatch -Severity warning -Path ([string]$document.path) -Message ('Responsibility {0} is misplaced at scope {1}.' -f $responsibility, $scope) -Disposition adapt -Confidence 0.8)) | Out-Null }
    }
    $coverage = New-Object System.Collections.Generic.List[object]
    $recommendations = New-Object System.Collections.Generic.List[object]
    foreach ($constraint in @($Constraints)) {
        $id = [string](Get-OperationObjectProperty $constraint 'constraint_id')
        $commonIntent = [string](Get-OperationObjectProperty $constraint 'common_intent')
        $platformDeltas = @((Get-OperationObjectProperty $constraint 'platform_deltas'))
        $projectActions = @((Get-OperationObjectProperty $constraint 'project_actions'))
        $enforcementRefs = @((Get-OperationObjectProperty $constraint 'enforcement_refs'))
        $recovery = [string](Get-OperationObjectProperty $constraint 'recovery_condition')
        $declaredNotApplicable = [bool](Get-OperationObjectProperty $constraint 'not_applicable')
        $conflict = [bool](Get-OperationObjectProperty $constraint 'conflict')
        $allRefs = @($platformDeltas + $projectActions + $enforcementRefs | ForEach-Object { [string]$_ })
        $hasDuplicates = @($allRefs | Group-Object | Where-Object Count -gt 1).Count -gt 0
        $state = if ($declaredNotApplicable) { 'not_applicable' } elseif ($conflict) { 'conflict' } elseif ([string]::IsNullOrWhiteSpace($commonIntent) -or $projectActions.Count -eq 0) { 'gap' } elseif ($hasDuplicates) { 'duplicated' } else { 'covered' }
        $item = New-RuleResponsibility -ConstraintId $id -CommonIntent $(if ([string]::IsNullOrWhiteSpace($commonIntent)) { 'unspecified' } else { $commonIntent }) -PlatformDeltas $platformDeltas -ProjectActions $projectActions -EnforcementRefs $enforcementRefs -Coverage $state -Evidence @((Get-OperationObjectProperty $constraint 'evidence')) -Confidence $(if ($state -eq 'covered') { 1.0 } else { 0.75 }) -RecoveryCondition $recovery
        $coverage.Add($item) | Out-Null
        $disposition = if ($state -eq 'covered') { 'adopt' } elseif ($state -eq 'not_applicable' -and [string]::IsNullOrWhiteSpace($recovery)) { 'defer' } else { 'adapt' }
        $recommendations.Add([pscustomobject][ordered]@{ constraint_id = $id; disposition = $disposition; surface = Get-RuleAdvisorSurface ([string](Get-OperationObjectProperty $constraint 'need_kind')); evidence = @((Get-OperationObjectProperty $constraint 'evidence')); confidence = $item.confidence; truth_boundary = 'recommendation_only'; blocking = $false }) | Out-Null
    }
    return [pscustomobject][ordered]@{ schema_version = 1; coverage = @($coverage.ToArray()); findings = @($semantic.ToArray() | Sort-Object finding_id); recommendations = @($recommendations.ToArray() | Sort-Object constraint_id); blocking_count = 0; provider_calls = 0; writes = 0 }
}
