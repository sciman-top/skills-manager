function Parse-RuleEstateAuditOptions([object[]]$Tokens) {
    $userHome = [Environment]::GetFolderPath('UserProfile')
    $result = [ordered]@{
        workspace_root = $null; exclude_names = @('external', '文档'); registry_path = $null
        codex_user_root = (Join-Path $userHome '.codex'); claude_user_root = (Join-Path $userHome '.claude')
        max_targets = 64; out_path = $null; json = $false
    }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        if ($token -eq '--json') { $result.json = $true; continue }
        if ($token -notin @('--workspace-root', '--exclude', '--registry', '--codex-user-root', '--claude-user-root', '--max-targets', '--out')) { throw ('Unknown rule-estate-audit option: {0}' -f $token) }
        if ($i + 1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) }
        $i++; $value = [string]$Tokens[$i]
        switch ($token) {
            '--workspace-root' { $result.workspace_root = $value }
            '--exclude' { $result.exclude_names += $value }
            '--registry' { $result.registry_path = $value }
            '--codex-user-root' { $result.codex_user_root = $value }
            '--claude-user-root' { $result.claude_user_root = $value }
            '--max-targets' { $result.max_targets = [int]$value }
            '--out' { $result.out_path = $value }
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.workspace_root)) { throw '--workspace-root is required.' }
    return [pscustomobject]$result
}

function Invoke-RuleEstateAuditCommand([object[]]$Tokens = @()) {
    $options = Parse-RuleEstateAuditOptions $Tokens
    $registryTargets = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$options.registry_path)) {
        $registryPath = [System.IO.Path]::GetFullPath([string]$options.registry_path)
        if (-not [System.IO.File]::Exists($registryPath)) { throw ('Registry file does not exist: {0}' -f $registryPath) }
        $registry = [System.IO.File]::ReadAllText($registryPath) | ConvertFrom-Json
        $registryTargets = @($registry.targets)
    }
    $report = Invoke-RuleEstateAudit -WorkspaceRoot $options.workspace_root -ExcludeNames $options.exclude_names -RegistryTargets $registryTargets -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root -MaxTargets $options.max_targets
    $reportRequested = -not [string]::IsNullOrWhiteSpace([string]$options.out_path)
    $pass = [bool]$report.structural_pass -and [bool]$report.semantic_coverage_pass -and [bool]$report.enforcement_verified
    $exitCode = if ($pass) { 0 } else { 2 }
    $envelope = [pscustomobject][ordered]@{
        schema_version = 1; command = 'rule-estate-audit'; pass = $pass; exit_code = $exitCode; truth_boundary = $report.truth_boundary
        report = $report; writes = $(if ($reportRequested) { 1 } else { 0 }); provider_calls = 0; native_mutations = 0
    }
    $json = $envelope | ConvertTo-Json -Depth 60 -Compress
    if ($reportRequested) {
        $protected = @($report.inventory.targets | ForEach-Object { @([string]$_.agents_path, [string]$_.claude_path) })
        if (-not [string]::IsNullOrWhiteSpace([string]$options.registry_path)) { $protected += [System.IO.Path]::GetFullPath([string]$options.registry_path) }
        $outPath = Resolve-RuleEstateControlOutput ([string]$options.out_path) ([string]$options.workspace_root) $protected
        foreach ($target in @($report.inventory.targets)) {
            if ($outPath.Equals([System.IO.Path]::GetFullPath([string]$target.agents_path), [System.StringComparison]::OrdinalIgnoreCase) -or $outPath.Equals([System.IO.Path]::GetFullPath([string]$target.claude_path), [System.StringComparison]::OrdinalIgnoreCase)) { throw '--out cannot overwrite a target rule file.' }
        }
        Write-Utf8FileAtomic -Path $outPath -Content $json
    }
    $output = if ($options.json) { $json } else { 'Rule estate audit: targets={0}, findings={1}, textual_covered={2}, semantic_gaps={3}, patch_candidates={4}' -f $report.summary.target_count, $report.summary.finding_count, $report.summary.textual_mapping_covered_count, $report.summary.semantic_gap_count, $report.summary.patch_candidate_count }
    return [pscustomobject]@{ exit_code = $exitCode; output = $output; json = [bool]$options.json; envelope = $envelope }
}

function Parse-RuleEstateMutationOptions([object[]]$Tokens, [ValidateSet('plan','apply','rollback')][string]$Mode) {
    $userHome=[Environment]::GetFolderPath('UserProfile')
    $result=[ordered]@{review=$null;plan=$null;workspace_root=$null;codex_user_root=(Join-Path $userHome '.codex');claude_user_root=(Join-Path $userHome '.claude');exclude_names=@('external','文档');token=$null;out_path=$null;resume=$null;receipt=$null;action_id=$null;json=$false}
    for($i=0;$i -lt @($Tokens).Count;$i++){
        $token=[string]$Tokens[$i]
        if($token -eq '--json'){$result.json=$true;continue}
        if($token -notin @('--review','--plan','--workspace-root','--codex-user-root','--claude-user-root','--exclude','--token','--out','--resume','--receipt','--action-id')){throw ('Unknown rule-estate-{0} option: {1}' -f $Mode,$token)}
        if($i+1 -ge @($Tokens).Count){throw ('{0} requires a value.' -f $token)};$i++;$value=[string]$Tokens[$i]
        switch($token){'--review'{$result.review=$value};'--plan'{$result.plan=$value};'--workspace-root'{$result.workspace_root=$value};'--codex-user-root'{$result.codex_user_root=$value};'--claude-user-root'{$result.claude_user_root=$value};'--exclude'{$result.exclude_names+=$value};'--token'{$result.token=$value};'--out'{$result.out_path=$value};'--resume'{$result.resume=$value};'--receipt'{$result.receipt=$value};'--action-id'{$result.action_id=$value}}
    }
    if($Mode -eq 'plan' -and ([string]::IsNullOrWhiteSpace($result.review) -or [string]::IsNullOrWhiteSpace($result.workspace_root) -or [string]::IsNullOrWhiteSpace($result.out_path))){throw 'rule-estate-plan requires --review, --workspace-root, and --out.'}
    if($Mode -eq 'apply' -and ([string]::IsNullOrWhiteSpace($result.plan) -or [string]::IsNullOrWhiteSpace($result.workspace_root) -or [string]::IsNullOrWhiteSpace($result.token) -or [string]::IsNullOrWhiteSpace($result.out_path))){throw 'rule-estate-apply requires --plan, --workspace-root, --token, and --out.'}
    if($Mode -eq 'rollback' -and ([string]::IsNullOrWhiteSpace($result.receipt) -or [string]::IsNullOrWhiteSpace($result.action_id) -or [string]::IsNullOrWhiteSpace($result.token) -or [string]::IsNullOrWhiteSpace($result.workspace_root))){throw 'rule-estate-rollback requires --receipt, --action-id, --workspace-root, and --token.'}
    return [pscustomobject]$result
}

function Resolve-RuleEstateControlOutput([string]$Path,[string]$WorkspaceRoot,[string[]]$Protected=@()){
    $resolved=[IO.Path]::GetFullPath($Path);$workspace=[IO.Path]::GetFullPath($WorkspaceRoot)
    if(-not (Test-RuleDiscoveryPathWithin $resolved $workspace)){throw 'Estate control outputs must remain inside the explicit workspace root.'}
    if(Test-RuleEstateReparsePath $resolved $workspace){throw 'Estate control outputs must not cross a reparse point inside the explicit workspace root.'}
    foreach($item in @($Protected)){if(-not [string]::IsNullOrWhiteSpace($item) -and $resolved.Equals([IO.Path]::GetFullPath($item),[StringComparison]::OrdinalIgnoreCase)){throw 'Estate output cannot overwrite an input file.'}}
    return $resolved
}

function Get-RuleEstateReviewControlInputs([string]$ReviewPath) {
    $inputs=New-Object System.Collections.Generic.List[string]
    if([string]::IsNullOrWhiteSpace($ReviewPath)){return @()}
    $reviewFile=[IO.Path]::GetFullPath($ReviewPath);$inputs.Add($reviewFile)|Out-Null
    if(-not [IO.File]::Exists($reviewFile)){return @($inputs.ToArray())}
    try{$review=[IO.File]::ReadAllText($reviewFile)|ConvertFrom-Json}catch{return @($inputs.ToArray())}
    $reviewRoot=[IO.Path]::GetDirectoryName($reviewFile)
    foreach($change in @(Get-RuleEstateProperty $review 'changes')){
        $desired=[string](Get-RuleEstateProperty $change 'desired_file')
        if([string]::IsNullOrWhiteSpace($desired)){continue}
        try{$inputs.Add([IO.Path]::GetFullPath((Join-Path $reviewRoot $desired)))|Out-Null}catch{}
    }
    return @($inputs.ToArray()|Sort-Object -Unique)
}

function Get-RuleEstatePlanControlInputs($Plan) {
    $inputs=New-Object System.Collections.Generic.List[string]
    $review=Get-RuleEstateProperty $Plan 'review';$reviewPath=[string](Get-RuleEstateProperty $review 'path')
    foreach($path in @(Get-RuleEstateReviewControlInputs $reviewPath)){if(-not [string]::IsNullOrWhiteSpace($path)){$inputs.Add($path)|Out-Null}}
    foreach($action in @(Get-RuleEstateProperty $Plan 'actions')){
        $targetPath=[string](Get-RuleEstateProperty $action 'target_path')
        if(-not [string]::IsNullOrWhiteSpace($targetPath)){$inputs.Add([IO.Path]::GetFullPath($targetPath))|Out-Null}
    }
    return @($inputs.ToArray()|Sort-Object -Unique)
}

function Invoke-RuleEstatePlanCommand([object[]]$Tokens=@()){
    $options=Parse-RuleEstateMutationOptions $Tokens plan
    $plan=New-RuleEstatePlan -ReviewPath $options.review -WorkspaceRoot $options.workspace_root -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root -ExcludeNames $options.exclude_names
    $out=Resolve-RuleEstateControlOutput $options.out_path $options.workspace_root @(Get-RuleEstatePlanControlInputs $plan)
    $envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-estate-plan';pass=$true;exit_code=0;truth_boundary='reviewed_multi_target_plan';plan=$plan;writes=1;target_writes=0;host_writes=0;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 60 -Compress;Write-Utf8FileAtomic -Path $out -Content $json
    return [pscustomobject]@{exit_code=0;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule estate plan: actions={0}, target_set={1}' -f $plan.actions.Count,$plan.target_set.count});envelope=$envelope}
}

function Invoke-RuleEstateApplyCommand([object[]]$Tokens=@()){
    $options=Parse-RuleEstateMutationOptions $Tokens apply
    $planPath=[IO.Path]::GetFullPath($options.plan);if(-not [IO.File]::Exists($planPath)){throw 'Estate plan does not exist.'}
    $document=[IO.File]::ReadAllText($planPath)|ConvertFrom-Json;$plan=if([string](Get-RuleEstateProperty $document 'command') -eq 'rule-estate-plan'){Get-RuleEstateProperty $document 'plan'}else{$document}
    $protected=@($planPath)+@(Get-RuleEstatePlanControlInputs $plan)
    $out=Resolve-RuleEstateControlOutput $options.out_path $options.workspace_root $protected
    $result=Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $options.workspace_root -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root -Token $options.token -ReceiptPath $out -ResumeReceiptPath $options.resume
    $exit=if($result.pass){0}else{2};$envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-estate-apply';pass=$result.pass;exit_code=$exit;truth_boundary='filesystem_applied_not_host_loaded';result=$result;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 60 -Compress
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule estate apply: status={0}, writes={1}' -f $result.status,$result.writes});envelope=$envelope}
}

function Invoke-RuleEstateRollbackCommand([object[]]$Tokens=@()){
    $options=Parse-RuleEstateMutationOptions $Tokens rollback
    $result=Invoke-RuleEstateRollback -ReceiptPath $options.receipt -ActionId $options.action_id -Token $options.token -WorkspaceRoot $options.workspace_root -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root
    $exit=if($result.pass){0}else{2};$envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-estate-rollback';pass=$result.pass;exit_code=$exit;truth_boundary='single_target_filesystem_rollback';result=$result;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 30 -Compress
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule estate rollback: status={0}' -f $result.status});envelope=$envelope}
}
