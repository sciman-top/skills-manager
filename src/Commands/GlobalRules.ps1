function Parse-GlobalRuleOptions([object[]]$Tokens,[ValidateSet('check','plan','apply','rollback')][string]$Mode) {
    $userProfile=[Environment]::GetFolderPath('UserProfile')
    $codexFromEnv=-not[string]::IsNullOrWhiteSpace($env:CODEX_HOME)
    $result=[ordered]@{
        repo_root=$Root
        codex_user_root=$(if($codexFromEnv){$env:CODEX_HOME}else{Join-Path $userProfile '.codex'})
        codex_user_root_source=$(if($codexFromEnv){'CODEX_HOME'}else{'default'})
        claude_user_root=(Join-Path $userProfile '.claude')
        claude_user_root_source='default'
        plan=$null;receipt=$null;token=$null;out_path=$null;json=$false;resume=$false
    }
    for($i=0;$i-lt@($Tokens).Count;$i++){
        $token=[string]$Tokens[$i]
        if($token-eq'--json'){$result.json=$true;continue}
        if($token-eq'--resume'){$result.resume=$true;continue}
        if($token-notin@('--repo-root','--codex-user-root','--claude-user-root','--plan','--receipt','--token','--out')){throw('Unknown global-rules-{0} option: {1}'-f$Mode,$token)}
        if($i+1-ge@($Tokens).Count){throw('{0} requires a value.'-f$token)};$i++;$value=[string]$Tokens[$i]
        switch($token){
            '--repo-root'{$result.repo_root=$value}
            '--codex-user-root'{$result.codex_user_root=$value;$result.codex_user_root_source='cli'}
            '--claude-user-root'{$result.claude_user_root=$value;$result.claude_user_root_source='cli'}
            '--plan'{$result.plan=$value}
            '--receipt'{$result.receipt=$value}
            '--token'{$result.token=$value}
            '--out'{$result.out_path=$value}
        }
    }
    if($Mode-ne'apply'-and$result.resume){throw('--resume is only valid for global-rules-apply.')}
    if($Mode-eq'plan'-and[string]::IsNullOrWhiteSpace($result.out_path)){throw 'global-rules-plan requires --out.'}
    if($Mode-eq'apply'-and(@($result.plan,$result.token,$result.out_path)|Where-Object{[string]::IsNullOrWhiteSpace([string]$_)}).Count-gt0){throw 'global-rules-apply requires --plan, --token, and --out.'}
    if($Mode-eq'rollback'-and(@($result.receipt,$result.token)|Where-Object{[string]::IsNullOrWhiteSpace([string]$_)}).Count-gt0){throw 'global-rules-rollback requires --receipt and --token.'}
    return [pscustomobject]$result
}

function Resolve-GlobalRuleControlPath([string]$Path,[string]$RepoRoot,[switch]$MustExist) {
    $resolved=[IO.Path]::GetFullPath($Path);$repo=[IO.Path]::GetFullPath($RepoRoot)
    $controlRoot=Join-Path $repo 'reports\global-rule-projection';$backupRoot=Join-Path $controlRoot 'backups'
    if(-not(Test-OperationPathWithinRoot $resolved $controlRoot)-or(Test-OperationPathWithinRoot $resolved $backupRoot)){throw 'Global rule plans and receipts must stay below reports/global-rule-projection and outside its backups directory.'}
    if(Test-GlobalRuleProjectionReparsePath $resolved $repo){throw 'Global rule control paths must not cross reparse points.'}
    if($MustExist-and-not[IO.File]::Exists($resolved)){throw('Global rule control input does not exist: {0}'-f$resolved)}
    return $resolved
}

function Get-GlobalRuleRootEnvelope($Options) {
    return [pscustomobject][ordered]@{
        repo_root=[IO.Path]::GetFullPath($Options.repo_root)
        codex_user_root=[IO.Path]::GetFullPath($Options.codex_user_root)
        codex_user_root_source=$Options.codex_user_root_source
        claude_user_root=[IO.Path]::GetFullPath($Options.claude_user_root)
        claude_user_root_source=$Options.claude_user_root_source
    }
}

function Invoke-GlobalRuleCommand([ValidateSet('check','plan','apply','rollback')][string]$Mode,[object[]]$Tokens=@()) {
    $options=Parse-GlobalRuleOptions $Tokens $Mode;$roots=Get-GlobalRuleRootEnvelope $options
    switch($Mode){
        'check'{
            $result=Test-GlobalRuleProjection $options.repo_root $options.codex_user_root $options.claude_user_root;$exit=if($result.pass){0}else{2}
            $envelope=[pscustomobject][ordered]@{schema_version=2;command='global-rules-check';pass=$result.pass;exit_code=$exit;roots=$roots;result=$result;writes=0;provider_calls=0;native_mutations=0}
        }
        'plan'{
            $out=Resolve-GlobalRuleControlPath $options.out_path $options.repo_root
            $plan=New-GlobalRuleProjectionPlan $options.repo_root $options.codex_user_root $options.claude_user_root
            $envelope=[pscustomobject][ordered]@{schema_version=2;command='global-rules-plan';pass=$true;exit_code=0;roots=$roots;plan=$plan;writes=1;host_writes=0;provider_calls=0;native_mutations=0}
            Write-Utf8FileAtomic -Path $out -Content ($envelope|ConvertTo-Json -Depth 30 -Compress);$exit=0
        }
        'apply'{
            $planPath=Resolve-GlobalRuleControlPath $options.plan $options.repo_root -MustExist;$out=Resolve-GlobalRuleControlPath $options.out_path $options.repo_root
            if(Test-GlobalRulePathEqual $planPath $out){throw 'Global rule apply receipt path must differ from the plan path.'}
            $document=[IO.File]::ReadAllText($planPath)|ConvertFrom-Json;$plan=if($document.command-eq'global-rules-plan'){$document.plan}else{$document}
            $backupRoot=Join-Path ([IO.Path]::GetFullPath($options.repo_root)) 'reports\global-rule-projection\backups'
            $receipt=Invoke-GlobalRuleProjectionApply -Plan $plan -Token $options.token -BackupRoot $backupRoot -ReceiptPath $out -RepoRoot $options.repo_root -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root -Resume:$options.resume
            $envelope=[pscustomobject][ordered]@{schema_version=2;command='global-rules-apply';pass=$true;exit_code=0;roots=$roots;receipt=$receipt;provider_calls=0;native_mutations=0};$exit=0
        }
        'rollback'{
            $receiptPath=Resolve-GlobalRuleControlPath $options.receipt $options.repo_root -MustExist
            $backupRoot=Join-Path ([IO.Path]::GetFullPath($options.repo_root)) 'reports\global-rule-projection\backups'
            $result=Invoke-GlobalRuleProjectionRollback -ReceiptPath $receiptPath -Token $options.token -RepoRoot $options.repo_root -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root -BackupRoot $backupRoot
            $envelope=[pscustomobject][ordered]@{schema_version=2;command='global-rules-rollback';pass=$result.pass;exit_code=0;roots=$roots;result=$result;provider_calls=0;native_mutations=0};$exit=0
        }
    }
    $json=$envelope|ConvertTo-Json -Depth 30 -Compress
    $summary=switch($Mode){
        'check'{'Global rules check: pass={0}, findings={1}'-f$envelope.pass,@($envelope.result.findings).Count}
        'plan'{'Global rules plan: actions={0}, token={1}'-f@($envelope.plan.actions).Count,$envelope.plan.apply.required_token}
        'apply'{'Global rules apply: writes={0}, boundary={1}'-f$envelope.receipt.writes,$envelope.receipt.truth_boundary}
        'rollback'{'Global rules rollback: writes={0}'-f$envelope.result.writes}
    }
    return [pscustomobject]@{exit_code=$exit;json=[bool]$options.json;output=$(if($options.json){$json}else{$summary});envelope=$envelope}
}
