function New-RuleEstateFinding([string]$Code, [string]$Path, [string]$Message) {
    return [pscustomobject]@{ code=$Code; severity='error'; path=$Path; message=$Message }
}

function Get-RuleEstateProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-RuleEstateSafeRoot([string]$Path, [string]$Label) {
    $root=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $drive=[IO.Path]::GetPathRoot($root).TrimEnd('\','/')
    if($root.Equals($drive,[StringComparison]::OrdinalIgnoreCase)){throw ('Drive roots are not valid {0} roots.' -f $Label)}
    if(-not [IO.Directory]::Exists($root)){throw ('{0} root does not exist: {1}' -f $Label,$root)}
    return $root
}

function Test-RuleEstateReparsePath([string]$Path,[string]$BoundaryRoot) {
    $cursor=[IO.Path]::GetFullPath($Path);$boundary=[IO.Path]::GetFullPath($BoundaryRoot).TrimEnd('\','/')
    while($true){
        if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $true}}
        if($cursor.TrimEnd('\','/').Equals($boundary,[StringComparison]::OrdinalIgnoreCase)){break}
        $parent=[IO.Directory]::GetParent($cursor);if($null -eq $parent -or -not (Test-RuleDiscoveryPathWithin $parent.FullName $boundary)){break};$cursor=$parent.FullName
    }
    return $false
}

function Test-RuleEstateReviewContract($Review, [string]$ReviewRoot) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Review) { return [pscustomobject]@{ pass=$false; findings=@((New-RuleEstateFinding 'review_missing' '$' 'Reviewed change-set is required.')) } }
    if ((Get-RuleEstateProperty $Review 'schema_version') -ne 1) { $findings.Add((New-RuleEstateFinding 'review_schema_invalid' '$.schema_version' 'Only review schema version 1 is supported.')) | Out-Null }
    if ([string](Get-RuleEstateProperty $Review 'review_status') -ne 'reviewed') { $findings.Add((New-RuleEstateFinding 'review_status_invalid' '$.review_status' 'Change-set must be explicitly reviewed.')) | Out-Null }
    if ([string](Get-RuleEstateProperty $Review 'reviewed_by_type') -notin @('human','automation_policy') -or [string](Get-RuleEstateProperty $Review 'authorization_source') -notin @('user_supplied','registered_policy')) {
        $findings.Add((New-RuleEstateFinding 'review_authority_invalid' '$.reviewed_by_type' 'AI self-review is not apply authority; use a human review or registered policy.')) | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-RuleEstateProperty $Review 'reviewed_by'))) { $findings.Add((New-RuleEstateFinding 'reviewer_missing' '$.reviewed_by' 'Reviewer identity is required.')) | Out-Null }
    $authorizationRelative = [string](Get-RuleEstateProperty $Review 'authorization_receipt')
    if ([string]::IsNullOrWhiteSpace($authorizationRelative)) {
        $findings.Add((New-RuleEstateFinding 'authorization_receipt_missing' '$.authorization_receipt' 'An independently issued authorization receipt is required.')) | Out-Null
    }
    else {
        $authorizationPath = [IO.Path]::GetFullPath((Join-Path $ReviewRoot $authorizationRelative))
        if (-not (Test-RuleDiscoveryPathWithin $authorizationPath $ReviewRoot) -or -not [IO.File]::Exists($authorizationPath)) { $findings.Add((New-RuleEstateFinding 'authorization_receipt_invalid' '$.authorization_receipt' 'Authorization receipt must exist below the reviewed change-set directory.')) | Out-Null }
        elseif (Test-RuleEstateReparsePath $authorizationPath $ReviewRoot) { $findings.Add((New-RuleEstateFinding 'authorization_receipt_reparse_forbidden' '$.authorization_receipt' 'Authorization receipts reached through reparse points are not accepted.')) | Out-Null }
    }
    $changes = @(Get-RuleEstateProperty $Review 'changes')
    if ($changes.Count -eq 0) { $findings.Add((New-RuleEstateFinding 'review_changes_empty' '$.changes' 'At least one reviewed change is required.')) | Out-Null }
    if ($changes.Count -gt 128) { $findings.Add((New-RuleEstateFinding 'review_changes_limit' '$.changes' 'Reviewed change-set exceeds the 128 action safety limit.')) | Out-Null }
    for ($i=0; $i -lt $changes.Count; $i++) {
        $change = $changes[$i]; $base = '$.changes[{0}]' -f $i
        $scope = [string](Get-RuleEstateProperty $change 'target_scope')
        if ($scope -notin @('repository','global_codex','global_claude')) { $findings.Add((New-RuleEstateFinding 'target_scope_invalid' "$base.target_scope" 'Target scope is not managed by rule estate.')) | Out-Null }
        $file = [string](Get-RuleEstateProperty $change 'target_file')
        $allowed = switch ($scope) { 'global_codex' { @('AGENTS.md') }; 'global_claude' { @('CLAUDE.md') }; default { @('AGENTS.md','CLAUDE.md') } }
        if ($file -notin $allowed -or [IO.Path]::GetFileName($file) -cne $file) { $findings.Add((New-RuleEstateFinding 'target_file_forbidden' "$base.target_file" 'Only exact root rule filenames are accepted; provider, auth, model, sandbox and native host files are excluded.')) | Out-Null }
        if ($scope -eq 'repository' -and [string]::IsNullOrWhiteSpace([string](Get-RuleEstateProperty $change 'repository'))) { $findings.Add((New-RuleEstateFinding 'repository_missing' "$base.repository" 'Repository name is required.')) | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-RuleEstateProperty $change 'risk')) -and [string](Get-RuleEstateProperty $change 'risk') -notin @('low','medium','high')) { $findings.Add((New-RuleEstateFinding 'risk_invalid' "$base.risk" 'Risk must be low, medium, or high.')) | Out-Null }
        $desired = [string](Get-RuleEstateProperty $change 'desired_file')
        if ([string]::IsNullOrWhiteSpace($desired)) { $findings.Add((New-RuleEstateFinding 'desired_file_missing' "$base.desired_file" 'Reviewed desired file is required.')) | Out-Null; continue }
        $desiredPath = [IO.Path]::GetFullPath((Join-Path $ReviewRoot $desired))
        if (-not (Test-RuleDiscoveryPathWithin $desiredPath $ReviewRoot) -or -not [IO.File]::Exists($desiredPath)) { $findings.Add((New-RuleEstateFinding 'desired_file_out_of_review_root' "$base.desired_file" 'Desired files must exist below the reviewed change-set directory.')) | Out-Null }
        elseif (Test-RuleEstateReparsePath $desiredPath $ReviewRoot) { $findings.Add((New-RuleEstateFinding 'desired_file_reparse_forbidden' "$base.desired_file" 'Desired files reached through reparse points are not accepted.')) | Out-Null }
    }
    return [pscustomobject]@{ pass=($findings.Count -eq 0); findings=@($findings.ToArray()) }
}

function Get-RuleEstateAuthorizationReceipt {
    param($Review,[string]$ReviewPath,[string]$WorkspaceRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot)
    $reviewRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReviewPath));$relative=[string](Get-RuleEstateProperty $Review 'authorization_receipt')
    if([string]::IsNullOrWhiteSpace($relative)){throw 'Independent authorization receipt is required.'}
    $path=[IO.Path]::GetFullPath((Join-Path $reviewRoot $relative))
    if(-not (Test-RuleDiscoveryPathWithin $path $reviewRoot) -or -not [IO.File]::Exists($path) -or (Test-RuleEstateReparsePath $path $reviewRoot)){throw 'Independent authorization receipt path is invalid.'}
    try{$raw=[IO.File]::ReadAllText($path);$receipt=$raw|ConvertFrom-Json}catch{throw ('Independent authorization receipt is invalid JSON: {0}' -f $_.Exception.Message)}
    if((Get-RuleEstateProperty $receipt 'schema_version') -ne 1 -or [string](Get-RuleEstateProperty $receipt 'domain') -ne 'rule_estate_authorization' -or [string](Get-RuleEstateProperty $receipt 'decision') -ne 'approved'){throw 'Independent authorization receipt is not an approved v1 rule estate receipt.'}
    $authorizationId=[string](Get-RuleEstateProperty $receipt 'authorization_id')
    if($authorizationId -notmatch '^rule-estate-auth-[a-f0-9]{32}$'){throw 'Independent authorization receipt identity is invalid.'}
    if([string](Get-RuleEstateProperty $receipt 'issued_by') -ne [string](Get-RuleEstateProperty $Review 'reviewed_by') -or [string](Get-RuleEstateProperty $receipt 'issued_by_type') -ne [string](Get-RuleEstateProperty $Review 'reviewed_by_type') -or [string](Get-RuleEstateProperty $receipt 'authorization_source') -ne [string](Get-RuleEstateProperty $Review 'authorization_source')){throw 'Independent authorization receipt reviewer identity does not match the review.'}
    $reviewHash=Get-OperationSha256 ([IO.File]::ReadAllText([IO.Path]::GetFullPath($ReviewPath)))
    if([string](Get-RuleEstateProperty $receipt 'review_sha256') -ne $reviewHash){throw 'Independent authorization receipt review hash does not match.'}
    $workspace=[IO.Path]::GetFullPath($WorkspaceRoot);$codex=[IO.Path]::GetFullPath($CodexUserRoot);$claude=[IO.Path]::GetFullPath($ClaudeUserRoot)
    try{$receiptWorkspace=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $receipt 'workspace_root'));$receiptCodex=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $receipt 'codex_user_root'));$receiptClaude=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $receipt 'claude_user_root'))}catch{throw 'Independent authorization receipt roots are invalid.'}
    if($receiptWorkspace -ne $workspace -or $receiptCodex -ne $codex -or $receiptClaude -ne $claude){throw 'Independent authorization receipt roots do not match the requested roots.'}
    if([int](Get-RuleEstateProperty $receipt 'approved_action_count') -ne @((Get-RuleEstateProperty $Review 'changes')).Count){throw 'Independent authorization receipt action count does not match the review.'}
    $issued=[datetimeoffset]::MinValue;$expires=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string](Get-RuleEstateProperty $receipt 'issued_at'),[ref]$issued) -or -not [datetimeoffset]::TryParse([string](Get-RuleEstateProperty $receipt 'expires_at'),[ref]$expires) -or $expires -le $issued){throw 'Independent authorization receipt validity window is invalid.'}
    if($expires -le [datetimeoffset]::UtcNow){throw 'Independent authorization receipt has expired.'}
    $applyToken=[string](Get-RuleEstateProperty $receipt 'apply_token')
    if($applyToken -cnotmatch '^APPLY_RULE_ESTATE_PATCH_[A-F0-9]{16}$'){throw 'Independent authorization receipt apply token is invalid.'}
    return [pscustomobject][ordered]@{path=$path;content_hash=Get-OperationSha256 $raw;authorization_id=$authorizationId;issued_by=[string](Get-RuleEstateProperty $receipt 'issued_by');issued_by_type=[string](Get-RuleEstateProperty $receipt 'issued_by_type');authorization_source=[string](Get-RuleEstateProperty $receipt 'authorization_source');issued_at=$issued.ToString('o');expires_at=$expires.ToString('o');review_sha256=$reviewHash;approved_action_count=[int](Get-RuleEstateProperty $receipt 'approved_action_count');apply_token=$applyToken}
}

function Get-RuleEstateTargetSetSnapshot([string]$WorkspaceRoot, [string[]]$ExcludeNames=@('external','文档')) {
    $inventory = Get-RuleEstateTargets -WorkspaceRoot $WorkspaceRoot -ExcludeNames $ExcludeNames
    $paths = @($inventory.targets | ForEach-Object { [IO.Path]::GetFullPath([string]$_.path).ToLowerInvariant() } | Sort-Object -Unique)
    return [pscustomobject][ordered]@{ paths=$paths; hash=(Get-OperationSha256 ($paths -join "`n")); count=$paths.Count }
}

function Get-RuleEstateRepositoryDirtyPaths([string]$Root) {
    $output = @(& git -C $Root status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) { throw ('Unable to inspect repository status: {0}' -f $Root) }
    return @($output | ForEach-Object { [string]$_ } | Sort-Object)
}

function New-RuleEstatePlan {
    param([Parameter(Mandatory=$true)][string]$ReviewPath,[Parameter(Mandatory=$true)][string]$WorkspaceRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot,[string[]]$ExcludeNames=@('external','文档'))
    $reviewFile = [IO.Path]::GetFullPath($ReviewPath)
    if (-not [IO.File]::Exists($reviewFile)) { throw 'Reviewed change-set does not exist.' }
    $reviewRoot = [IO.Path]::GetDirectoryName($reviewFile)
    $review = [IO.File]::ReadAllText($reviewFile) | ConvertFrom-Json
    $validation = Test-RuleEstateReviewContract $review $reviewRoot
    if (-not $validation.pass) { throw ('Reviewed change-set is invalid: {0}' -f ((@($validation.findings.code) -join ', '))) }
    $workspace = Assert-RuleEstateSafeRoot $WorkspaceRoot 'workspace'
    $codex = Assert-RuleEstateSafeRoot $CodexUserRoot 'Codex user'
    $claude = Assert-RuleEstateSafeRoot $ClaudeUserRoot 'Claude user'
    $authorization = Get-RuleEstateAuthorizationReceipt -Review $review -ReviewPath $reviewFile -WorkspaceRoot $workspace -CodexUserRoot $codex -ClaudeUserRoot $claude
    $inventory = Get-RuleEstateTargets -WorkspaceRoot $workspace -ExcludeNames $ExcludeNames
    $repoByName = @{}
    foreach ($target in @($inventory.targets)) { $repoByName[[string]$target.name] = [string]$target.path }
    $actions = New-Object System.Collections.Generic.List[object]
    $plannedTargets = @{}
    foreach ($change in @(Get-RuleEstateProperty $review 'changes')) {
        $scope = [string](Get-RuleEstateProperty $change 'target_scope')
        $root = switch ($scope) {
            'global_codex' { $codex }
            'global_claude' { $claude }
            default {
                $name = [string](Get-RuleEstateProperty $change 'repository')
                if (-not $repoByName.ContainsKey($name)) { throw ('Reviewed repository is not a current direct Git target: {0}' -f $name) }
                [string]$repoByName[$name]
            }
        }
        $targetPath = Join-Path $root ([string](Get-RuleEstateProperty $change 'target_file'))
        if(Test-RuleEstateReparsePath $targetPath $root){throw ('Reparse points are not accepted by rule estate: {0}' -f $targetPath)}
        $targetKey = [IO.Path]::GetFullPath($targetPath).ToLowerInvariant()
        if ($plannedTargets.ContainsKey($targetKey)) { throw ('Reviewed change-set contains duplicate target: {0}' -f $targetPath) }
        $plannedTargets[$targetKey] = $true
        $desiredPath = [IO.Path]::GetFullPath((Join-Path $reviewRoot ([string](Get-RuleEstateProperty $change 'desired_file'))))
        $exists = [IO.File]::Exists($targetPath)
        $allowCreate = [bool](Get-RuleEstateProperty $change 'allow_create')
        if (-not $exists -and -not $allowCreate) { throw ('Target does not exist and allow_create is false: {0}' -f $targetPath) }
        if ($exists -and $allowCreate) { throw ('allow_create requires an absent target: {0}' -f $targetPath) }
        $current = if ($exists) { [IO.File]::ReadAllText($targetPath) } else { '' }
        $desired = [IO.File]::ReadAllText($desiredPath)
        if ($current -ceq $desired) { throw ('Reviewed target has no changes: {0}' -f $targetPath) }
        $identity = '{0}|{1}|{2}' -f $scope,$targetPath.ToLowerInvariant(),(Get-OperationSha256 $desired)
        $dirtyPaths = if ($scope -eq 'repository') { @(Get-RuleEstateRepositoryDirtyPaths $root) } else { @() }
        $actions.Add([pscustomobject][ordered]@{
            action_id=('estate-{0}' -f (Get-OperationSha256 $identity).Substring(0,16)); target_scope=$scope
            repository=$(if($scope -eq 'repository'){[string](Get-RuleEstateProperty $change 'repository')}else{$null})
            authorized_root=$root; target_path=[IO.Path]::GetFullPath($targetPath); operation=$(if($exists){'update'}else{'create'})
            before_hash=Get-OperationSha256 $current; desired_hash=Get-OperationSha256 $desired; desired_text=$desired
            risk=$(if([string]::IsNullOrWhiteSpace([string](Get-RuleEstateProperty $change 'risk'))){'medium'}else{[string](Get-RuleEstateProperty $change 'risk')})
            evidence_refs=@(Get-RuleEstateProperty $change 'evidence_refs')
            dirty_paths_at_plan=@($dirtyPaths)
        }) | Out-Null
    }
    $targetSet = Get-RuleEstateTargetSetSnapshot $workspace $ExcludeNames
    $planSeed = '{0}|{1}|{2}' -f $workspace,$targetSet.hash,(@($actions | ForEach-Object action_id) -join '|')
    return [pscustomobject][ordered]@{
        schema_version=1; operation_id=('rule-estate-{0}' -f (Get-OperationSha256 $planSeed).Substring(0,16)); domain='rule_estate'; mode='plan'
        generated_at=[datetimeoffset]::UtcNow.ToString('o'); workspace_root=$workspace; exclude_names=@($ExcludeNames); codex_user_root=$codex; claude_user_root=$claude
        review=[pscustomobject]@{ path=$reviewFile; content_hash=Get-OperationSha256 ([IO.File]::ReadAllText($reviewFile)); reviewed_by=[string](Get-RuleEstateProperty $review 'reviewed_by'); reviewed_by_type=[string](Get-RuleEstateProperty $review 'reviewed_by_type'); authorization_source=[string](Get-RuleEstateProperty $review 'authorization_source') }
        authorization=$authorization
        target_set=$targetSet; actions=@($actions.ToArray()); execution='preflight_all_then_apply_one_by_one_fail_fast'
        apply=[pscustomobject]@{ required_token=[string]$authorization.apply_token; dirty_worktree='observe_preserve_unrelated'; target_file_freshness='fail_closed'; target_set_drift='fail_closed'; rollback_scope='per_target' }
        verification=[pscustomobject]@{ repo_verified='not_run'; host_loaded='not_run'; live_accepted='not_run' }
        provider_calls=0; native_mutations=0
    }
}

function Get-RuleEstateLockPath($Action) {
    return Join-Path ([string](Get-RuleEstateProperty $Action 'authorized_root')) '.skills-manager-rule-estate.lock'
}

function Get-RuleEstateTextHashAtPath([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return Get-OperationSha256 '' }
    return Get-OperationSha256 ([IO.File]::ReadAllText($Path))
}

function Get-RuleEstateBytesHash([byte[]]$Bytes) {
    if ($null -eq $Bytes) { $Bytes = [byte[]]@() }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Test-RuleEstateApplyPreflight {
    param($Plan,[string]$WorkspaceRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot,[string[]]$CompletedActionIds=@(),[switch]$IgnoreLocks)
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan -or (Get-RuleEstateProperty $Plan 'schema_version') -ne 1 -or [string](Get-RuleEstateProperty $Plan 'domain') -ne 'rule_estate') { return [pscustomobject]@{ pass=$false; findings=@((New-RuleEstateFinding 'plan_invalid' '$' 'Rule estate plan is invalid.')) } }
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot); $codex=[IO.Path]::GetFullPath($CodexUserRoot); $claude=[IO.Path]::GetFullPath($ClaudeUserRoot)
    if ($workspace -ne [IO.Path]::GetFullPath([string](Get-RuleEstateProperty $Plan 'workspace_root')) -or $codex -ne [IO.Path]::GetFullPath([string](Get-RuleEstateProperty $Plan 'codex_user_root')) -or $claude -ne [IO.Path]::GetFullPath([string](Get-RuleEstateProperty $Plan 'claude_user_root'))) { $findings.Add((New-RuleEstateFinding 'authorization_root_mismatch' '$' 'CLI roots must exactly match the plan roots.')) | Out-Null }
    $freshSet = Get-RuleEstateTargetSetSnapshot $workspace @(Get-RuleEstateProperty $Plan 'exclude_names')
    if ($freshSet.hash -ne [string](Get-RuleEstateProperty (Get-RuleEstateProperty $Plan 'target_set') 'hash')) { $findings.Add((New-RuleEstateFinding 'target_set_drift' '$.target_set' 'Workspace direct Git target set changed after planning.')) | Out-Null }
    $review=Get-RuleEstateProperty $Plan 'review';$reviewPath=[string](Get-RuleEstateProperty $review 'path');$reviewDocument=$null
    if(-not [IO.File]::Exists($reviewPath) -or (Get-OperationSha256 ([IO.File]::ReadAllText($reviewPath))) -ne [string](Get-RuleEstateProperty $review 'content_hash')){$findings.Add((New-RuleEstateFinding 'review_stale' '$.review' 'Reviewed change-set changed or disappeared after planning.'))|Out-Null}
    else {
        try{$reviewDocument=[IO.File]::ReadAllText($reviewPath)|ConvertFrom-Json;$reviewValidation=Test-RuleEstateReviewContract $reviewDocument ([IO.Path]::GetDirectoryName($reviewPath));if(-not $reviewValidation.pass){throw ((@($reviewValidation.findings.code))-join ',')}}catch{$findings.Add((New-RuleEstateFinding 'review_stale' '$.review' ('Reviewed change-set is no longer valid: {0}' -f $_.Exception.Message)))|Out-Null}
    }
    $authorization=Get-RuleEstateProperty $Plan 'authorization';$authorizationPath=[string](Get-RuleEstateProperty $authorization 'path');$expires=[datetimeoffset]::MinValue
    if([string]::IsNullOrWhiteSpace($authorizationPath) -or -not [IO.File]::Exists($authorizationPath) -or (Get-OperationSha256 ([IO.File]::ReadAllText($authorizationPath))) -ne [string](Get-RuleEstateProperty $authorization 'content_hash')){$findings.Add((New-RuleEstateFinding 'authorization_receipt_stale' '$.authorization' 'Authorization receipt changed or disappeared after planning.'))|Out-Null}
    elseif(-not [datetimeoffset]::TryParse([string](Get-RuleEstateProperty $authorization 'expires_at'),[ref]$expires) -or $expires -le [datetimeoffset]::UtcNow){$findings.Add((New-RuleEstateFinding 'authorization_receipt_expired' '$.authorization.expires_at' 'Authorization receipt is expired or invalid.'))|Out-Null}
    elseif($null -ne $reviewDocument){
        try {
            $freshAuthorization=Get-RuleEstateAuthorizationReceipt -Review $reviewDocument -ReviewPath $reviewPath -WorkspaceRoot $workspace -CodexUserRoot $codex -ClaudeUserRoot $claude
            if([string]$freshAuthorization.content_hash -ne [string](Get-RuleEstateProperty $authorization 'content_hash') -or [string]$freshAuthorization.authorization_id -ne [string](Get-RuleEstateProperty $authorization 'authorization_id') -or [string]$freshAuthorization.apply_token -ne [string](Get-RuleEstateProperty (Get-RuleEstateProperty $Plan 'apply') 'required_token')){throw 'authorization fields differ from the independently issued receipt'}
        } catch {$findings.Add((New-RuleEstateFinding 'authorization_receipt_invalid' '$.authorization' $_.Exception.Message))|Out-Null}
    }
    if($null -ne $reviewDocument){
        $actions=@(Get-RuleEstateProperty $Plan 'actions');$changes=@(Get-RuleEstateProperty $reviewDocument 'changes')
        if($actions.Count -ne $changes.Count){$findings.Add((New-RuleEstateFinding 'plan_review_binding_mismatch' '$.actions' 'Plan action count does not match the authorized review.'))|Out-Null}
        $actionByTarget=@{}
        foreach($candidate in $actions){$candidatePath=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $candidate 'target_path')).ToLowerInvariant();if($actionByTarget.ContainsKey($candidatePath)){$actionByTarget[$candidatePath]=$null}else{$actionByTarget[$candidatePath]=$candidate}}
        foreach($change in $changes){
            $scope=[string](Get-RuleEstateProperty $change 'target_scope');$repository=[string](Get-RuleEstateProperty $change 'repository')
            $expectedRoot=switch($scope){'global_codex'{$codex};'global_claude'{$claude};default{[IO.Path]::GetFullPath((Join-Path $workspace $repository))}}
            if([string]::IsNullOrWhiteSpace($expectedRoot)){continue}
            $expectedTarget=[IO.Path]::GetFullPath((Join-Path $expectedRoot ([string](Get-RuleEstateProperty $change 'target_file'))));$desiredPath=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($reviewPath)) ([string](Get-RuleEstateProperty $change 'desired_file'))));$desired=[IO.File]::ReadAllText($desiredPath);$desiredHash=Get-OperationSha256 $desired;$identity='{0}|{1}|{2}' -f $scope,$expectedTarget.ToLowerInvariant(),$desiredHash;$expectedId='estate-{0}' -f (Get-OperationSha256 $identity).Substring(0,16)
            $boundAction=if($actionByTarget.ContainsKey($expectedTarget.ToLowerInvariant())){$actionByTarget[$expectedTarget.ToLowerInvariant()]}else{$null}
            if($null -eq $boundAction -or [string](Get-RuleEstateProperty $boundAction 'target_scope') -ne $scope -or ($scope -eq 'repository' -and [string](Get-RuleEstateProperty $boundAction 'repository') -ne $repository) -or [string](Get-RuleEstateProperty $boundAction 'action_id') -ne $expectedId -or [string](Get-RuleEstateProperty $boundAction 'desired_hash') -ne $desiredHash -or [string](Get-RuleEstateProperty $boundAction 'desired_text') -cne $desired){$findings.Add((New-RuleEstateFinding 'plan_review_binding_mismatch' '$.actions' ('Plan action is not an exact projection of the authorized review target: {0}' -f $expectedTarget)))|Out-Null}
        }
    }
    foreach ($action in @(Get-RuleEstateProperty $Plan 'actions')) {
        $id=[string](Get-RuleEstateProperty $action 'action_id'); $done=$id -in @($CompletedActionIds)
        $path=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $action 'target_path')); $root=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $action 'authorized_root')); $scope=[string](Get-RuleEstateProperty $action 'target_scope')
        $expectedRoot = switch($scope){'global_codex'{$codex};'global_claude'{$claude};default{$root}}
        $allowedName = switch($scope){'global_codex'{'AGENTS.md'};'global_claude'{'CLAUDE.md'};default{[IO.Path]::GetFileName($path)}}
        if ($root -ne $expectedRoot -or -not (Test-RuleDiscoveryPathWithin $path $root) -or [IO.Path]::GetFileName($path) -cne $allowedName -or ($scope -eq 'repository' -and [IO.Path]::GetFileName($path) -notin @('AGENTS.md','CLAUDE.md'))) { $findings.Add((New-RuleEstateFinding 'target_out_of_scope' '$.actions' 'Plan target is outside the exact managed rule allowlist.')) | Out-Null }
        if(Test-RuleEstateReparsePath $path $root){$findings.Add((New-RuleEstateFinding 'target_reparse_forbidden' $path 'Reparse points are not accepted by rule estate.'))|Out-Null}
        $currentHash=Get-RuleEstateTextHashAtPath $path; $expectedHash=if($done){[string](Get-RuleEstateProperty $action 'desired_hash')}else{[string](Get-RuleEstateProperty $action 'before_hash')}
        if ($currentHash -ne $expectedHash) { $findings.Add((New-RuleEstateFinding 'target_hash_stale' $path 'Target content no longer matches the planned state.')) | Out-Null }
        if((Get-OperationSha256 ([string](Get-RuleEstateProperty $action 'desired_text'))) -ne [string](Get-RuleEstateProperty $action 'desired_hash')){$findings.Add((New-RuleEstateFinding 'desired_hash_mismatch' '$.actions' 'Desired text does not match the planned hash.'))|Out-Null}
        if (-not $IgnoreLocks -and [IO.File]::Exists((Get-RuleEstateLockPath $action))) { $findings.Add((New-RuleEstateFinding 'target_locked' (Get-RuleEstateLockPath $action) 'Another rule estate writer holds this target lock.')) | Out-Null }
    }
    return [pscustomobject]@{ pass=($findings.Count -eq 0); findings=@($findings.ToArray()) }
}

function Write-RuleEstateReceipt([string]$Path, $Receipt) {
    Write-Utf8FileAtomic -Path $Path -Content ($Receipt | ConvertTo-Json -Depth 40)
}

function Invoke-RuleEstateApply {
    param($Plan,[string]$WorkspaceRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot,[string]$Token,[string]$ReceiptPath,[string]$ResumeReceiptPath=$null,[string]$TestFailBeforeActionId=$null,[scriptblock]$TestHookAfterLocksAcquired=$null)
    $expectedToken=[string](Get-RuleEstateProperty (Get-RuleEstateProperty $Plan 'apply') 'required_token')
    if ([string]::IsNullOrWhiteSpace($expectedToken) -or $Token -cne $expectedToken) { return [pscustomobject]@{ pass=$false; status='blocked'; findings=@((New-RuleEstateFinding 'apply_token_invalid' '$.apply.required_token' 'Explicit estate apply token does not match the independent authorization receipt.')); writes=0; receipt=$null } }
    $receiptFile=[IO.Path]::GetFullPath($ReceiptPath); $existing=$null
    if (-not [string]::IsNullOrWhiteSpace($ResumeReceiptPath)) {
        $resumeFile=[IO.Path]::GetFullPath($ResumeReceiptPath)
        if (-not [IO.File]::Exists($resumeFile)) { throw 'Resume receipt does not exist.' }
        $existing=[IO.File]::ReadAllText($resumeFile)|ConvertFrom-Json
        if ([string](Get-RuleEstateProperty $existing 'operation_id') -ne [string](Get-RuleEstateProperty $Plan 'operation_id')) { throw 'Resume receipt belongs to another plan.' }
    }
    $completedIds=@()
    if($null -ne $existing){$completedIds=@(Get-RuleEstateProperty $existing 'actions'|Where-Object{[string](Get-RuleEstateProperty $_ 'status') -eq 'applied'}|ForEach-Object{[string](Get-RuleEstateProperty $_ 'action_id')})}
    $preflight=Test-RuleEstateApplyPreflight $Plan $WorkspaceRoot $CodexUserRoot $ClaudeUserRoot $completedIds
    if(-not $preflight.pass){return [pscustomobject]@{pass=$false;status='blocked';findings=@($preflight.findings);writes=0;receipt=$existing}}
    $receipt=if($null -ne $existing){$existing}else{[pscustomobject][ordered]@{schema_version=1;operation_id=[string](Get-RuleEstateProperty $Plan 'operation_id');status='in_progress';started_at=[datetimeoffset]::UtcNow.ToString('o');completed_at=$null;workspace_root=[string](Get-RuleEstateProperty $Plan 'workspace_root');codex_user_root=[string](Get-RuleEstateProperty $Plan 'codex_user_root');claude_user_root=[string](Get-RuleEstateProperty $Plan 'claude_user_root');actions=@();verification=[pscustomobject]@{repo_verified='not_run';host_loaded='not_run';live_accepted='not_run'}}}
    $actionResults=New-Object System.Collections.Generic.List[object]
    foreach($old in @(Get-RuleEstateProperty $receipt 'actions')){$actionResults.Add($old)|Out-Null}
    $lockStreams=New-Object System.Collections.Generic.List[object];$writes=0
    try {
        $lockPaths=@(Get-RuleEstateProperty $Plan 'actions'|ForEach-Object{Get-RuleEstateLockPath $_}|Sort-Object -Unique)
        foreach($lockPath in $lockPaths){
            $stream=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$lockStreams.Add([pscustomobject]@{stream=$stream;path=$lockPath})|Out-Null
        }
        if($null -ne $TestHookAfterLocksAcquired){& $TestHookAfterLocksAcquired}
        $lockedPreflight=Test-RuleEstateApplyPreflight $Plan $WorkspaceRoot $CodexUserRoot $ClaudeUserRoot $completedIds -IgnoreLocks
        if(-not $lockedPreflight.pass){throw ('post_lock_preflight_failed:{0}' -f ((@($lockedPreflight.findings.code)-join ',')))}
        foreach($action in @(Get-RuleEstateProperty $Plan 'actions')){
            $id=[string](Get-RuleEstateProperty $action 'action_id')
            if($id -in $completedIds){continue}
            if(-not [string]::IsNullOrWhiteSpace($TestFailBeforeActionId) -and $id -eq $TestFailBeforeActionId){throw ('test_fail_before_action:{0}' -f $id)}
            $target=[string](Get-RuleEstateProperty $action 'target_path');$operation=[string](Get-RuleEstateProperty $action 'operation')
            $backupRoot=Join-Path ([IO.Path]::GetDirectoryName($receiptFile)) ('.rule-estate-backups\{0}' -f [string](Get-RuleEstateProperty $Plan 'operation_id'))
            New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null
            $backup=Join-Path $backupRoot ('{0}.bak' -f $id)
            [byte[]]$beforeBytes=$null
            if([IO.File]::Exists($target)){$beforeBytes=[IO.File]::ReadAllBytes($target)}else{$beforeBytes=[byte[]]::new(0)}
            [IO.File]::WriteAllBytes($backup,$beforeBytes)
            $backupHash=Get-RuleEstateBytesHash $beforeBytes
            Write-Utf8FileAtomic -Path $target -Content ([string](Get-RuleEstateProperty $action 'desired_text'))
            if((Get-RuleEstateTextHashAtPath $target) -ne [string](Get-RuleEstateProperty $action 'desired_hash')){throw ('desired_hash_not_applied:{0}' -f $id)}
            $writes++
            $actionResults.Add([pscustomobject][ordered]@{action_id=$id;status='applied';target_path=$target;target_scope=[string](Get-RuleEstateProperty $action 'target_scope');authorized_root=[string](Get-RuleEstateProperty $action 'authorized_root');operation=$operation;before_hash=[string](Get-RuleEstateProperty $action 'before_hash');desired_hash=[string](Get-RuleEstateProperty $action 'desired_hash');dirty_paths_at_plan=@(Get-RuleEstateProperty $action 'dirty_paths_at_plan');backup_path=$backup;backup_sha256=$backupHash;backup_length=[long]$beforeBytes.LongLength;applied_at=[datetimeoffset]::UtcNow.ToString('o')})|Out-Null
            $receipt.actions=@($actionResults.ToArray());Write-RuleEstateReceipt $receiptFile $receipt
        }
        $receipt.status='applied';$receipt.completed_at=[datetimeoffset]::UtcNow.ToString('o');$receipt.actions=@($actionResults.ToArray());Write-RuleEstateReceipt $receiptFile $receipt
        return [pscustomobject]@{pass=$true;status='applied';findings=@();writes=$writes;receipt=$receipt}
    } catch {
        $receipt.status='failed';$receipt.completed_at=[datetimeoffset]::UtcNow.ToString('o');$receipt.actions=@($actionResults.ToArray());$receipt | Add-Member -NotePropertyName failure -NotePropertyValue $_.Exception.Message -Force;Write-RuleEstateReceipt $receiptFile $receipt
        return [pscustomobject]@{pass=$false;status='failed';findings=@((New-RuleEstateFinding 'estate_apply_failed' '$.actions' $_.Exception.Message));writes=$writes;receipt=$receipt}
    } finally {
        foreach($lock in $lockStreams.ToArray()){$lock.stream.Dispose();if([IO.File]::Exists($lock.path)){[IO.File]::Delete($lock.path)}}
    }
}

function Invoke-RuleEstateRollback {
    param([string]$ReceiptPath,[string]$ActionId,[string]$Token,[string]$WorkspaceRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot)
    if($Token -cne 'ROLLBACK_RULE_ESTATE_PATCH'){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_token_invalid' '$' 'Explicit rollback token does not match.'));writes=0}}
    $receiptFile=[IO.Path]::GetFullPath($ReceiptPath);if(-not [IO.File]::Exists($receiptFile)){throw 'Receipt does not exist.'}
    $receipt=[IO.File]::ReadAllText($receiptFile)|ConvertFrom-Json
    $workspace=[IO.Path]::GetFullPath($WorkspaceRoot);$codex=[IO.Path]::GetFullPath($CodexUserRoot);$claude=[IO.Path]::GetFullPath($ClaudeUserRoot)
    if($workspace -ne [IO.Path]::GetFullPath([string](Get-RuleEstateProperty $receipt 'workspace_root')) -or $codex -ne [IO.Path]::GetFullPath([string](Get-RuleEstateProperty $receipt 'codex_user_root')) -or $claude -ne [IO.Path]::GetFullPath([string](Get-RuleEstateProperty $receipt 'claude_user_root'))){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_root_mismatch' '$' 'Rollback roots must exactly match the receipt.'));writes=0}}
    $action=@(Get-RuleEstateProperty $receipt 'actions'|Where-Object{[string](Get-RuleEstateProperty $_ 'action_id') -eq $ActionId})|Select-Object -First 1
    if($null -eq $action -or [string](Get-RuleEstateProperty $action 'status') -ne 'applied'){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_action_invalid' '$.actions' 'Action is not an applied receipt target.'));writes=0}}
    $target=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $action 'target_path'));$root=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $action 'authorized_root'));$scope=[string](Get-RuleEstateProperty $action 'target_scope')
    $expectedRoot=switch($scope){'global_codex'{$codex};'global_claude'{$claude};'repository'{$root};default{''}}
    $allowedName=switch($scope){'global_codex'{'AGENTS.md'};'global_claude'{'CLAUDE.md'};default{[IO.Path]::GetFileName($target)}}
    $repoValid=$scope -ne 'repository' -or (([IO.Directory]::GetParent($root)).FullName.TrimEnd('\','/') -eq $workspace.TrimEnd('\','/') -and ([IO.Directory]::Exists((Join-Path $root '.git')) -or [IO.File]::Exists((Join-Path $root '.git'))) -and [IO.Path]::GetFileName($target) -in @('AGENTS.md','CLAUDE.md'))
    if([string]::IsNullOrWhiteSpace($expectedRoot) -or $root -ne $expectedRoot -or -not $repoValid -or -not (Test-RuleDiscoveryPathWithin $target $root) -or [IO.Path]::GetFileName($target) -cne $allowedName -or (Test-RuleEstateReparsePath $target $root)){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_target_out_of_scope' $target 'Receipt target is outside the exact managed rule allowlist.'));writes=0}}
    if((Get-RuleEstateTextHashAtPath $target) -ne [string](Get-RuleEstateProperty $action 'desired_hash')){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_target_stale' $target 'Target changed after apply.'));writes=0}}
    $operationId=[string](Get-RuleEstateProperty $receipt 'operation_id');if($operationId -notmatch '^rule-estate-[a-f0-9]{16}$' -or $ActionId -notmatch '^estate-[a-f0-9]{16}$'){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_identity_invalid' '$' 'Receipt operation or action identity is invalid.'));writes=0}}
    $expectedBackup=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($receiptFile)) ('.rule-estate-backups\{0}\{1}.bak' -f $operationId,$ActionId)));$backup=[IO.Path]::GetFullPath([string](Get-RuleEstateProperty $action 'backup_path'))
    if($backup -ne $expectedBackup -or -not [IO.File]::Exists($backup)){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_backup_invalid' $backup 'Per-target backup path is missing or outside the receipt backup directory.'));writes=0}}
    $backupBytes=[IO.File]::ReadAllBytes($backup);$expectedBackupHash=[string](Get-RuleEstateProperty $action 'backup_sha256');$expectedBackupLength=[long](Get-RuleEstateProperty $action 'backup_length')
    if([string]::IsNullOrWhiteSpace($expectedBackupHash) -or $backupBytes.LongLength -ne $expectedBackupLength -or (Get-RuleEstateBytesHash $backupBytes) -ne $expectedBackupHash){return [pscustomobject]@{pass=$false;status='blocked';findings=@((New-RuleEstateFinding 'rollback_backup_stale' $backup 'Per-target backup content no longer matches the apply receipt.'));writes=0}}
    if([string](Get-RuleEstateProperty $action 'operation') -eq 'create'){[IO.File]::Delete($target)}else{Write-BytesAtomic -Path $target -Bytes $backupBytes}
    $action.status='rolled_back';$action | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue ([datetimeoffset]::UtcNow.ToString('o')) -Force;Write-RuleEstateReceipt $receiptFile $receipt
    return [pscustomobject]@{pass=$true;status='rolled_back';findings=@();writes=1;action_id=$ActionId}
}
