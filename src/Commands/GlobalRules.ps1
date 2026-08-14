function Parse-GlobalRuleOptions([object[]]$Tokens,[ValidateSet('check','plan','apply','rollback')][string]$Mode) {
    $userProfile=[Environment]::GetFolderPath('UserProfile')
    $result=[ordered]@{repo_root=$Root;codex_user_root=(Join-Path $userProfile '.codex');claude_user_root=(Join-Path $userProfile '.claude');plan=$null;receipt=$null;token=$null;out_path=$null;json=$false}
    for($i=0;$i -lt @($Tokens).Count;$i++){
        $token=[string]$Tokens[$i]
        if($token -eq '--json'){$result.json=$true;continue}
        if($token -notin @('--repo-root','--codex-user-root','--claude-user-root','--plan','--receipt','--token','--out')){throw ('Unknown global-rules-{0} option: {1}' -f $Mode,$token)}
        if($i+1 -ge @($Tokens).Count){throw ('{0} requires a value.' -f $token)};$i++;$value=[string]$Tokens[$i]
        switch($token){'--repo-root'{$result.repo_root=$value};'--codex-user-root'{$result.codex_user_root=$value};'--claude-user-root'{$result.claude_user_root=$value};'--plan'{$result.plan=$value};'--receipt'{$result.receipt=$value};'--token'{$result.token=$value};'--out'{$result.out_path=$value}}
    }
    if($Mode -eq 'plan' -and [string]::IsNullOrWhiteSpace($result.out_path)){throw 'global-rules-plan requires --out.'}
    if($Mode -eq 'apply' -and (@($result.plan,$result.token,$result.out_path)|Where-Object {[string]::IsNullOrWhiteSpace(([string]$_))}).Count -gt 0){throw 'global-rules-apply requires --plan, --token, and --out.'}
    if($Mode -eq 'rollback' -and (@($result.receipt,$result.token)|Where-Object {[string]::IsNullOrWhiteSpace(([string]$_))}).Count -gt 0){throw 'global-rules-rollback requires --receipt and --token.'}
    return [pscustomobject]$result
}

function Resolve-GlobalRuleControlOutput([string]$Path,[string]$RepoRoot) {
    $resolved=[IO.Path]::GetFullPath($Path);$repo=[IO.Path]::GetFullPath($RepoRoot)
    if(-not (Test-RuleDiscoveryPathWithin $resolved $repo)){throw 'Global rule plan and receipt outputs must stay inside the repository.'}
    if(Test-RuleEstateReparsePath $resolved $repo){throw 'Global rule control outputs must not cross reparse points.'}
    return $resolved
}

function Invoke-GlobalRuleCommand([ValidateSet('check','plan','apply','rollback')][string]$Mode,[object[]]$Tokens=@()) {
    $options=Parse-GlobalRuleOptions $Tokens $Mode
    switch($Mode){
        'check'{$result=Test-GlobalRuleProjection $options.repo_root $options.codex_user_root $options.claude_user_root;$exit=if($result.pass){0}else{2};$envelope=[pscustomobject][ordered]@{schema_version=1;command='global-rules-check';pass=$result.pass;exit_code=$exit;result=$result;writes=0;provider_calls=0;native_mutations=0}}
        'plan'{$plan=New-GlobalRuleProjectionPlan $options.repo_root $options.codex_user_root $options.claude_user_root;$out=Resolve-GlobalRuleControlOutput $options.out_path $options.repo_root;$envelope=[pscustomobject][ordered]@{schema_version=1;command='global-rules-plan';pass=$true;exit_code=0;plan=$plan;writes=1;host_writes=0;provider_calls=0;native_mutations=0};Write-Utf8FileAtomic -Path $out -Content ($envelope|ConvertTo-Json -Depth 20 -Compress);$exit=0}
        'apply'{$planPath=[IO.Path]::GetFullPath($options.plan);if(-not [IO.File]::Exists($planPath)){throw 'Global rule plan does not exist.'};$document=[IO.File]::ReadAllText($planPath)|ConvertFrom-Json;$plan=if($document.command -eq 'global-rules-plan'){$document.plan}else{$document};$out=Resolve-GlobalRuleControlOutput $options.out_path $options.repo_root;$backupRoot=Join-Path ([IO.Path]::GetFullPath($options.repo_root)) 'reports\global-rule-projection\backups';$receipt=Invoke-GlobalRuleProjectionApply $plan $options.token $backupRoot $out;$envelope=[pscustomobject][ordered]@{schema_version=1;command='global-rules-apply';pass=$true;exit_code=0;receipt=$receipt;provider_calls=0;native_mutations=0};$exit=0}
        'rollback'{$result=Invoke-GlobalRuleProjectionRollback $options.receipt $options.token;$envelope=[pscustomobject][ordered]@{schema_version=1;command='global-rules-rollback';pass=$result.pass;exit_code=0;result=$result;provider_calls=0;native_mutations=0};$exit=0}
    }
    $json=$envelope|ConvertTo-Json -Depth 30 -Compress
    $summary=switch($Mode){'check'{'Global rules check: pass={0}, findings={1}' -f $envelope.pass,@($envelope.result.findings).Count};'plan'{'Global rules plan: actions={0}, token={1}' -f @($envelope.plan.actions).Count,$envelope.plan.apply.required_token};'apply'{'Global rules apply: writes={0}, boundary={1}' -f $envelope.receipt.writes,$envelope.receipt.truth_boundary};'rollback'{'Global rules rollback: writes={0}' -f $envelope.result.writes}}
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{$summary});envelope=$envelope}
}
