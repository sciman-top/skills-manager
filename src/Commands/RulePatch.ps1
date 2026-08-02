function Parse-RulePatchCliOptions([object[]]$Tokens, [ValidateSet('plan', 'apply')][string]$Mode) {
    $result = [ordered]@{ target=$null; desired_file=$null; fixture_root=$null; plan_path=$null; token=$null; out_path=$null; json=$false }
    for($i=0;$i -lt @($Tokens).Count;$i++) {
        $token=[string]$Tokens[$i]
        if($token -eq '--json') { $result.json=$true; continue }
        if($token -notin @('--target','--desired-file','--fixture-root','--plan','--token','--out')) { throw ('Unknown rule-{0} option: {1}' -f $Mode,$token) }
        if($i+1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) };$i++;$value=[string]$Tokens[$i]
        switch($token) { '--target'{$result.target=$value};'--desired-file'{$result.desired_file=$value};'--fixture-root'{$result.fixture_root=$value};'--plan'{$result.plan_path=$value};'--token'{$result.token=$value};'--out'{$result.out_path=$value} }
    }
    if([string]::IsNullOrWhiteSpace($result.fixture_root)) { throw '--fixture-root is required.' }
    if($Mode -eq 'plan' -and ([string]::IsNullOrWhiteSpace($result.target) -or [string]::IsNullOrWhiteSpace($result.desired_file))) { throw 'rule-plan requires --target and --desired-file.' }
    if($Mode -eq 'apply' -and ([string]::IsNullOrWhiteSpace($result.plan_path) -or [string]::IsNullOrWhiteSpace($result.token))) { throw 'rule-apply requires --plan and --token.' }
    return [pscustomobject]$result
}

function Assert-RulePatchFixtureRoot([string]$FixtureRoot) {
    $root=[IO.Path]::GetFullPath($FixtureRoot)
    if(-not [IO.Directory]::Exists($root) -or -not [IO.File]::Exists((Join-Path $root '.skills-manager-fixture'))) { throw 'Fixture root must exist and contain .skills-manager-fixture.' }
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
    $options=Parse-RulePatchCliOptions $Tokens plan;$fixture=Assert-RulePatchFixtureRoot $options.fixture_root
    $target=[IO.Path]::GetFullPath($options.target);$desiredFile=[IO.Path]::GetFullPath($options.desired_file)
    if(-not (Test-RuleDiscoveryPathWithin $target $fixture) -or -not (Test-RuleDiscoveryPathWithin $desiredFile $fixture)) { throw 'Target and desired file must remain inside fixture root.' }
    $outPath=Resolve-RulePatchOutputPath $options.out_path $fixture @($target,$desiredFile)
    $plan=New-RulePatchPlan -TargetPath $target -AuthorizedRoot $fixture -CurrentText ([IO.File]::ReadAllText($target)) -DesiredText ([IO.File]::ReadAllText($desiredFile)) -DesiredSource reviewed_file
    $validation=Test-RulePatchPlanContract $plan;$exit=if($validation.pass){0}else{2}
    $envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-plan';pass=$validation.pass;exit_code=$exit;truth_boundary='fixture_only';plan=$plan;findings=@($validation.findings);target_writes=0;host_writes=0;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 40 -Compress
    if($null -ne $outPath){Write-Utf8FileAtomic -Path $outPath -Content $json}
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule plan: pass={0}, changes={1}' -f $envelope.pass,$plan.diff.has_changes});envelope=$envelope}
}

function Invoke-RuleApplyCommand([object[]]$Tokens=@()) {
    $options=Parse-RulePatchCliOptions $Tokens apply;$fixture=Assert-RulePatchFixtureRoot $options.fixture_root
    $planPath=[IO.Path]::GetFullPath($options.plan_path);if(-not (Test-RuleDiscoveryPathWithin $planPath $fixture)){throw 'Plan file must remain inside fixture root.'}
    $planDocument=[IO.File]::ReadAllText($planPath)|ConvertFrom-Json
    $plan=if([string](Get-OperationObjectProperty $planDocument 'command') -eq 'rule-plan'){Get-OperationObjectProperty $planDocument 'plan'}else{$planDocument}
    $targetPath=[string](Get-OperationObjectProperty (Get-OperationObjectProperty $plan 'target') 'path')
    $outPath=Resolve-RulePatchOutputPath $options.out_path $fixture @($planPath,$targetPath)
    $result=Invoke-RulePatchApply $plan $fixture $options.token;$exit=if($result.pass){0}else{2}
    $envelope=[pscustomobject][ordered]@{schema_version=1;command='rule-apply';pass=$result.pass;exit_code=$exit;truth_boundary='fixture_only';result=$result;host_writes=0;provider_calls=0;native_mutations=0}
    $json=$envelope|ConvertTo-Json -Depth 40 -Compress
    if($null -ne $outPath){Write-Utf8FileAtomic -Path $outPath -Content $json}
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{'Rule apply: status={0}' -f $result.status});envelope=$envelope}
}
