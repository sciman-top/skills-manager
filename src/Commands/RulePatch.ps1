function Parse-RulePatchCliOptions([object[]]$Tokens, [ValidateSet('plan', 'apply')][string]$Mode) {
    $result = [ordered]@{ target=$null; desired_file=$null; fixture_root=$null; repo_root=$null; allow_create=$false; plan_path=$null; token=$null; out_path=$null; json=$false }
    for($i=0;$i -lt @($Tokens).Count;$i++) {
        $token=[string]$Tokens[$i]
        if($token -eq '--json') { $result.json=$true; continue }
        if($token -eq '--allow-create') { $result.allow_create=$true; continue }
        if($token -notin @('--target','--desired-file','--fixture-root','--repo-root','--plan','--token','--out')) { throw ('Unknown rule-{0} option: {1}' -f $Mode,$token) }
        if($i+1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) };$i++;$value=[string]$Tokens[$i]
        switch($token) { '--target'{$result.target=$value};'--desired-file'{$result.desired_file=$value};'--fixture-root'{$result.fixture_root=$value};'--repo-root'{$result.repo_root=$value};'--plan'{$result.plan_path=$value};'--token'{$result.token=$value};'--out'{$result.out_path=$value} }
    }
    $hasFixture = -not [string]::IsNullOrWhiteSpace($result.fixture_root); $hasRepo = -not [string]::IsNullOrWhiteSpace($result.repo_root)
    if($hasFixture -eq $hasRepo) { throw 'Specify exactly one of --fixture-root or --repo-root.' }
    if($Mode -eq 'plan' -and ([string]::IsNullOrWhiteSpace($result.target) -or [string]::IsNullOrWhiteSpace($result.desired_file))) { throw 'rule-plan requires --target and --desired-file.' }
    if($Mode -eq 'apply' -and ([string]::IsNullOrWhiteSpace($result.plan_path) -or [string]::IsNullOrWhiteSpace($result.token))) { throw 'rule-apply requires --plan and --token.' }
    return [pscustomobject]$result
}

function Assert-RulePatchFixtureRoot([string]$FixtureRoot) {
    $root=[IO.Path]::GetFullPath($FixtureRoot)
    if(-not [IO.Directory]::Exists($root) -or -not [IO.File]::Exists((Join-Path $root '.skills-manager-fixture'))) { throw 'Fixture root must exist and contain .skills-manager-fixture.' }
    return $root
}

function Assert-RulePatchRepoRoot([string]$RepoRoot) {
    $root=[IO.Path]::GetFullPath($RepoRoot)
    if(-not [IO.Directory]::Exists($root) -or (-not [IO.Directory]::Exists((Join-Path $root '.git')) -and -not [IO.File]::Exists((Join-Path $root '.git')))) { throw 'Repository root must exist and contain a .git marker.' }
    return $root
}

function Resolve-RulePatchOutputPath([string]$OutPath, [string]$FixtureRoot, [string[]]$ProtectedPaths = @()) {
    if ([string]::IsNullOrWhiteSpace($OutPath)) { return $null }
    $resolved = [IO.Path]::GetFullPath($OutPath)
    if (-not (Test-RuleDiscoveryPathWithin $resolved $FixtureRoot)) { throw 'Output file must remain inside fixture root.' }
    foreach ($protected in @($ProtectedPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($protected) -and $resolved.Equals([IO.Path]::GetFullPath($protected), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Output file must not overwrite a rule patch input or target.'
        }
    }
    return $resolved
}

function Invoke-RulePlanCommand([object[]]$Tokens=@()) {
    $options=Parse-RulePatchCliOptions $Tokens plan
    $scope=if(-not [string]::IsNullOrWhiteSpace($options.repo_root)){'repository'}else{'fixture'}
    $boundary=if($scope -eq 'repository'){Assert-RulePatchRepoRoot $options.repo_root}else{Assert-RulePatchFixtureRoot $options.fixture_root}
    $target=[IO.Path]::GetFullPath($options.target);$desiredFile=[IO.Path]::GetFullPath($options.desired_file)
    if(-not (Test-RuleDiscoveryPathWithin $target $boundary) -or -not (Test-RuleDiscoveryPathWithin $desiredFile $boundary)) { throw 'Target and desired file must remain inside the authorized root.' }
    if(-not [IO.File]::Exists($desiredFile)){throw 'Desired file does not exist.'}
    $operation=if($options.allow_create){'create'}else{'update'}
    if($operation -eq 'create' -and [IO.File]::Exists($target)){throw '--allow-create requires an absent target.'}
    if($operation -eq 'update' -and -not [IO.File]::Exists($target)){throw 'Update target does not exist; use --allow-create for a reviewed new rule file.'}
    $outPath=Resolve-RulePatchOutputPath $options.out_path $boundary @($target,$desiredFile)
    $currentText=if($operation -eq 'create'){''}else{[IO.File]::ReadAllText($target)}
    $plan=New-RulePatchPlan -TargetPath $target -AuthorizedRoot $boundary -CurrentText $currentText -DesiredText ([IO.File]::ReadAllText($desiredFile)) -DesiredSource reviewed_file -AuthorizationScope $scope -TargetOperation $operation
    $validation=Test-RulePatchPlanContract $plan;$exit=if($validation.pass){0}else{2}
    $envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-plan';pass=$validation.pass;exit_code=$exit;truth_boundary=$(if($scope -eq 'fixture'){'fixture_only'}else{'single_repository'});plan=$plan;findings=@($validation.findings);target_writes=0;host_writes=0;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 40 -Compress
    if($null -ne $outPath){Write-Utf8FileAtomic -Path $outPath -Content $json}
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule plan: pass={0}, changes={1}' -f $envelope.pass,$plan.diff.has_changes});envelope=$envelope}
}

function Invoke-RuleApplyCommand([object[]]$Tokens=@()) {
    $options=Parse-RulePatchCliOptions $Tokens apply
    $scope=if(-not [string]::IsNullOrWhiteSpace($options.repo_root)){'repository'}else{'fixture'}
    $boundary=if($scope -eq 'repository'){Assert-RulePatchRepoRoot $options.repo_root}else{Assert-RulePatchFixtureRoot $options.fixture_root}
    $planPath=[IO.Path]::GetFullPath($options.plan_path);if(-not (Test-RuleDiscoveryPathWithin $planPath $boundary)){throw 'Plan file must remain inside the authorized root.'}
    $planDocument=[IO.File]::ReadAllText($planPath)|ConvertFrom-Json
    $plan=if([string](Get-OperationObjectProperty $planDocument 'command') -eq 'rule-plan'){Get-OperationObjectProperty $planDocument 'plan'}else{$planDocument}
    $targetPath=[string](Get-OperationObjectProperty (Get-OperationObjectProperty $plan 'target') 'path')
    $planScope=[string](Get-OperationObjectProperty (Get-OperationObjectProperty $plan 'apply') 'boundary_scope');if($planScope -ne $scope){throw 'CLI authorization root type does not match the plan.'}
    $outPath=Resolve-RulePatchOutputPath $options.out_path $boundary @($planPath,$targetPath)
    $result=Invoke-RulePatchApply $plan $boundary $options.token;$exit=if($result.pass){0}else{2}
    $envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-apply';pass=$result.pass;exit_code=$exit;truth_boundary=$(if($scope -eq 'fixture'){'fixture_only'}else{'single_repository'});result=$result;host_writes=0;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 40 -Compress
    if($null -ne $outPath){Write-Utf8FileAtomic -Path $outPath -Content $json}
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule apply: status={0}' -f $result.status});envelope=$envelope}
}
