function Get-GlobalRuleProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-GlobalRuleFinding([string]$Code, [string]$Path, [string]$Message) {
    return [pscustomobject]@{ code=$Code; severity='error'; path=$Path; message=$Message }
}

function Assert-GlobalRuleProjectionRoot([string]$Path, [string]$Label) {
    $resolved=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $drive=[IO.Path]::GetPathRoot($resolved).TrimEnd('\','/')
    if($resolved.Equals($drive,[StringComparison]::OrdinalIgnoreCase)){throw ('Drive roots are not valid {0} roots.' -f $Label)}
    if(-not [IO.Directory]::Exists($resolved)){throw ('{0} root does not exist: {1}' -f $Label,$resolved)}
    return $resolved
}

function Test-GlobalRulePathEqual([string]$Left, [string]$Right) {
    if([string]::IsNullOrWhiteSpace($Left)-or[string]::IsNullOrWhiteSpace($Right)){return [string]::IsNullOrWhiteSpace($Left)-and[string]::IsNullOrWhiteSpace($Right)}
    return [IO.Path]::GetFullPath($Left).TrimEnd('\','/').Equals([IO.Path]::GetFullPath($Right).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)
}

function Test-GlobalRuleProjectionReparsePath([string]$Path,[string]$Root) {
    $cursor=[IO.Path]::GetFullPath($Path);$boundary=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    while($true){
        if(([IO.File]::Exists($cursor)-or[IO.Directory]::Exists($cursor))-and(([IO.File]::GetAttributes($cursor)-band[IO.FileAttributes]::ReparsePoint)-ne0)){return $true}
        if($cursor.TrimEnd('\','/').Equals($boundary,[StringComparison]::OrdinalIgnoreCase)){break}
        $parent=[IO.Directory]::GetParent($cursor);if($null-eq$parent){break};$cursor=$parent.FullName
    }
    return $false
}

function Get-GlobalRuleProjectionEntries {
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)][string]$CodexUserRoot,
        [Parameter(Mandatory=$true)][string]$ClaudeUserRoot,
        [string]$ZCodeUserRoot = ''
    )
    $repo=Assert-GlobalRuleProjectionRoot $RepoRoot 'repository'
    $codex=Assert-GlobalRuleProjectionRoot $CodexUserRoot 'Codex user'
    $claude=Assert-GlobalRuleProjectionRoot $ClaudeUserRoot 'Claude user'
    $entries = New-Object Collections.Generic.List[object]
    $entries.Add([pscustomobject][ordered]@{id='codex';source_path=(Join-Path $repo 'rules\global\codex\AGENTS.md');target_path=(Join-Path $codex 'AGENTS.md');root=$codex})|Out-Null
    $entries.Add([pscustomobject][ordered]@{id='claude';source_path=(Join-Path $repo 'rules\global\claude\CLAUDE.md');target_path=(Join-Path $claude 'CLAUDE.md');root=$claude})|Out-Null
    if (-not [string]::IsNullOrWhiteSpace($ZCodeUserRoot)) {
        $zcode=Assert-GlobalRuleProjectionRoot $ZCodeUserRoot 'ZCode user'
        $entries.Add([pscustomobject][ordered]@{id='zcode';source_path=(Join-Path $repo 'rules\global\zcode\AGENTS.md');target_path=(Join-Path $zcode 'AGENTS.md');root=$zcode})|Out-Null
    }
    return @($entries.ToArray())
}

function Get-GlobalRuleSourceEntries {
    param([Parameter(Mandatory=$true)][string]$RepoRoot)
    $repo=Assert-GlobalRuleProjectionRoot $RepoRoot 'repository'
    return @(
        [pscustomobject][ordered]@{id='codex';source_path=(Join-Path $repo 'rules\global\codex\AGENTS.md')}
        [pscustomobject][ordered]@{id='claude';source_path=(Join-Path $repo 'rules\global\claude\CLAUDE.md')}
        [pscustomobject][ordered]@{id='zcode';source_path=(Join-Path $repo 'rules\global\zcode\AGENTS.md')}
    )
}

function Get-GlobalRuleFileFacts([string]$Path) {
    $resolved=[IO.Path]::GetFullPath($Path)
    if(-not [IO.File]::Exists($resolved)){return [pscustomobject]@{exists=$false;path=$resolved;bytes=0;lines=0;bom=$false;version=$null;text=$null;hash=(Get-OperationSha256 '')}}
    $bytes=[IO.File]::ReadAllBytes($resolved);$text=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes)
    $versionMatch=[regex]::Match($text,'(?m)^\*\*版本\*\*:\s*([0-9][0-9A-Za-z_.-]*)\s*$')
    return [pscustomobject][ordered]@{
        exists=$true;path=$resolved;bytes=$bytes.Length;lines=($text -split "`r?`n").Count
        bom=($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF)
        version=$(if($versionMatch.Success){$versionMatch.Groups[1].Value}else{$null});text=$text
        hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
}

function Get-GlobalRuleSections([string]$Text) {
    $normalized=$Text.Replace("`r`n","`n")
    $matches=[regex]::Matches($normalized,'(?m)^## (1\.|A\.|B\.|C\.|D\.)[^\r\n]*$')
    if($matches.Count -ne 5){return $null}
    $expected=@('1.','A.','B.','C.','D.')
    $sections=[ordered]@{}
    for($i=0;$i -lt $matches.Count;$i++){
        if($matches[$i].Groups[1].Value -cne $expected[$i]){return $null}
        $start=$matches[$i].Index;$end=if($i+1-lt$matches.Count){$matches[$i+1].Index}else{$normalized.Length}
        $sections[$expected[$i].TrimEnd('.').ToLowerInvariant()]=$normalized.Substring($start,$end-$start)
    }
    return [pscustomobject]$sections
}

function Test-GlobalRuleSourceFamily {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot,[string]$ZCodeUserRoot='')
    $findings=New-Object Collections.Generic.List[object];$observations=New-Object Collections.Generic.List[object]
    $entries=Get-GlobalRuleProjectionEntries $RepoRoot $CodexUserRoot $ClaudeUserRoot $ZCodeUserRoot
    $sourceEntries=Get-GlobalRuleSourceEntries $RepoRoot;$facts=@{};$sections=@{}
    foreach($entry in $sourceEntries){
        if(Test-GlobalRuleProjectionReparsePath $entry.source_path ([IO.Path]::GetFullPath($RepoRoot))){$findings.Add((New-GlobalRuleFinding 'source_reparse_forbidden' $entry.source_path 'Global rule sources must not cross reparse points.'))|Out-Null}
        try{$fact=Get-GlobalRuleFileFacts $entry.source_path}catch{$findings.Add((New-GlobalRuleFinding 'source_encoding_invalid' $entry.source_path $_.Exception.Message))|Out-Null;continue}
        $facts[$entry.id]=$fact
        if(-not $fact.exists){$findings.Add((New-GlobalRuleFinding 'source_missing' $entry.source_path 'Global rule source is missing.'))|Out-Null;continue}
        if($fact.bom){$findings.Add((New-GlobalRuleFinding 'source_bom_forbidden' $entry.source_path 'Global rules must be UTF-8 without BOM.'))|Out-Null}
        if($fact.bytes -gt 16384){$findings.Add((New-GlobalRuleFinding 'source_byte_budget_exceeded' $entry.source_path 'Global rule exceeds 16 KiB.'))|Out-Null}
        if($fact.lines -gt 130){$findings.Add((New-GlobalRuleFinding 'source_line_budget_exceeded' $entry.source_path 'Global rule exceeds 130 lines.'))|Out-Null}
        $ratio=[Math]::Max($fact.bytes/16384.0,$fact.lines/130.0)
        if($ratio-ge .95){$observations.Add([pscustomobject]@{code='source_budget_addition_blocked';path=$entry.source_path;usage_ratio=[Math]::Round($ratio,4)})|Out-Null}
        elseif($ratio-ge .85){$observations.Add([pscustomobject]@{code='source_budget_warning';path=$entry.source_path;usage_ratio=[Math]::Round($ratio,4)})|Out-Null}
        if([string]::IsNullOrWhiteSpace([string]$fact.version)){$findings.Add((New-GlobalRuleFinding 'source_version_missing' $entry.source_path 'Global rule version is missing.'))|Out-Null}
        $sections[$entry.id]=Get-GlobalRuleSections $fact.text
        if($null-eq$sections[$entry.id]){$findings.Add((New-GlobalRuleFinding 'source_structure_invalid' $entry.source_path 'Global rules require exactly one ordered 1/A/B/C/D section family.'))|Out-Null}
    }
    foreach($entry in $entries){if(Test-GlobalRuleProjectionReparsePath $entry.target_path $entry.root){$findings.Add((New-GlobalRuleFinding 'target_reparse_forbidden' $entry.target_path 'Global rule targets must be ordinary files below the user root.'))|Out-Null}}
    if($facts.ContainsKey('codex')-and$facts.ContainsKey('claude')-and$facts.codex.exists-and$facts.claude.exists){
        if($facts.codex.version-ne$facts.claude.version){$findings.Add((New-GlobalRuleFinding 'source_version_mismatch' '$' 'Codex and Claude global rule versions differ.'))|Out-Null}
        $c=$sections['codex'];$h=$sections['claude']
        if($null-ne$c-and$null-ne$h){
            $codexPlatformBody=[regex]::Replace($c.b,'^[^\n]*\n?','').Trim();$claudePlatformBody=[regex]::Replace($h.b,'^[^\n]*\n?','').Trim()
            if([string]::IsNullOrWhiteSpace($codexPlatformBody)-or[string]::IsNullOrWhiteSpace($claudePlatformBody)){$findings.Add((New-GlobalRuleFinding 'source_platform_section_empty' '$.B' 'Codex and Claude B sections must both be non-empty.'))|Out-Null}
            if($c.b-ceq$h.b){$findings.Add((New-GlobalRuleFinding 'source_platform_sections_identical' '$.B' 'Codex and Claude B sections must express distinct platform deltas.'))|Out-Null}
            if($c.a-cne$h.a-or$c.c-cne$h.c-or$c.d-cne$h.d){$findings.Add((New-GlobalRuleFinding 'source_common_sections_drift' '$' 'Codex and Claude A/C/D common sections must be byte-equivalent after newline normalization.'))|Out-Null}
        }
    }
    if($facts.ContainsKey('zcode')-and$facts.zcode.exists-and$sections.ContainsKey('zcode')-and$null-ne$sections.zcode){
        $zcodePlatformBody=[regex]::Replace($sections.zcode.b,'^[^\n]*\n?','').Trim()
        if([string]::IsNullOrWhiteSpace($zcodePlatformBody)){$findings.Add((New-GlobalRuleFinding 'source_platform_section_empty' '$.B' 'ZCode B section must be non-empty.'))|Out-Null}
    }
    return [pscustomobject][ordered]@{pass=($findings.Count-eq0);findings=@($findings.ToArray());observations=@($observations.ToArray());entries=$entries;source_entries=$sourceEntries;facts=$facts}
}

function Get-GlobalRulePlanIdentity([string]$RepoRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot,[object[]]$Actions,[string]$ZCodeUserRoot='') {
    $parts=New-Object Collections.Generic.List[string]
    $parts.Add([IO.Path]::GetFullPath($RepoRoot).ToLowerInvariant())|Out-Null
    $parts.Add([IO.Path]::GetFullPath($CodexUserRoot).ToLowerInvariant())|Out-Null
    $parts.Add([IO.Path]::GetFullPath($ClaudeUserRoot).ToLowerInvariant())|Out-Null
    if(-not[string]::IsNullOrWhiteSpace($ZCodeUserRoot)){$parts.Add([IO.Path]::GetFullPath($ZCodeUserRoot).ToLowerInvariant())|Out-Null}
    foreach($action in @($Actions|Sort-Object id)){
        $parts.Add(('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f [string](Get-GlobalRuleProperty $action 'id'),([IO.Path]::GetFullPath([string](Get-GlobalRuleProperty $action 'source_path')).ToLowerInvariant()),([IO.Path]::GetFullPath([string](Get-GlobalRuleProperty $action 'target_path')).ToLowerInvariant()),[string](Get-GlobalRuleProperty $action 'source_hash'),[bool](Get-GlobalRuleProperty $action 'before_exists'),[string](Get-GlobalRuleProperty $action 'before_hash'),[string](Get-GlobalRuleProperty $action 'operation')))|Out-Null
    }
    $hash=Get-OperationSha256 ($parts.ToArray()-join "`n")
    return [pscustomobject]@{plan_hash=$hash;operation_id=('global-rules-{0}'-f$hash.Substring(0,16));apply_token=('APPLY_GLOBAL_RULES_{0}'-f(Get-OperationSha256("apply|$hash")).Substring(0,16).ToUpperInvariant());rollback_token=('ROLLBACK_GLOBAL_RULES_{0}'-f(Get-OperationSha256("rollback|$hash")).Substring(0,16).ToUpperInvariant())}
}

function New-GlobalRuleProjectionPlan {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot,[string]$ZCodeUserRoot='')
    $validation=Test-GlobalRuleSourceFamily $RepoRoot $CodexUserRoot $ClaudeUserRoot $ZCodeUserRoot
    if(-not$validation.pass){throw('Global rule sources are invalid: {0}'-f(@($validation.findings.code)-join', '))}
    $actions=foreach($entry in $validation.entries){
        $source=$validation.facts[$entry.id];$target=Get-GlobalRuleFileFacts $entry.target_path
        [pscustomobject][ordered]@{id=$entry.id;source_path=[IO.Path]::GetFullPath($entry.source_path);target_path=[IO.Path]::GetFullPath($entry.target_path);source_hash=$source.hash;before_exists=[bool]$target.exists;before_hash=$target.hash;operation=$(if(-not$target.exists){'create'}elseif($source.hash-eq$target.hash){'unchanged'}else{'update'})}
    }
    $repo=[IO.Path]::GetFullPath($RepoRoot);$codex=[IO.Path]::GetFullPath($CodexUserRoot);$claude=[IO.Path]::GetFullPath($ClaudeUserRoot)
    $zcode=$(if([string]::IsNullOrWhiteSpace($ZCodeUserRoot)){''}else{[IO.Path]::GetFullPath($ZCodeUserRoot)})
    $identity=Get-GlobalRulePlanIdentity $repo $codex $claude $actions $zcode
    return [pscustomobject][ordered]@{schema_version=2;domain='global_rule_projection';operation_id=$identity.operation_id;plan_hash=$identity.plan_hash;generated_at=[datetimeoffset]::UtcNow.ToString('o');repo_root=$repo;codex_user_root=$codex;claude_user_root=$claude;zcode_user_root=$zcode;actions=@($actions);apply=[pscustomobject]@{required_token=$identity.apply_token;freshness='canonical_sources_and_targets';resume='explicit';rollback='operation_bound_receipt'};observations=@($validation.observations);truth_boundary='planned_not_applied';provider_calls=0;native_mutations=0}
}

function Test-GlobalRulePlanBinding {
    param($Plan,[string]$RepoRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot,[string]$ZCodeUserRoot='',[switch]$AllowAppliedTargets)
    $findings=New-Object Collections.Generic.List[object]
    if($null-eq$Plan-or(Get-GlobalRuleProperty $Plan 'schema_version')-ne2-or[string](Get-GlobalRuleProperty $Plan 'domain')-ne'global_rule_projection'){
        return [pscustomobject]@{pass=$false;findings=@((New-GlobalRuleFinding 'plan_schema_invalid' '$' 'Only global rule projection plan schema version 2 is supported; generate a new plan.'))}
    }
    $repo=[IO.Path]::GetFullPath($RepoRoot);$codex=[IO.Path]::GetFullPath($CodexUserRoot);$claude=[IO.Path]::GetFullPath($ClaudeUserRoot)
    foreach($pair in @(@('repo_root',$repo),@('codex_user_root',$codex),@('claude_user_root',$claude))){if(-not(Test-GlobalRulePathEqual ([string](Get-GlobalRuleProperty $Plan $pair[0])) $pair[1])){$findings.Add((New-GlobalRuleFinding 'authorization_root_mismatch' ('$.'+$pair[0]) 'CLI roots must exactly match the plan roots.'))|Out-Null}}
    $zcode=$(if([string]::IsNullOrWhiteSpace($ZCodeUserRoot)){''}else{[IO.Path]::GetFullPath($ZCodeUserRoot)})
    if(-not(Test-GlobalRulePathEqual ([string](Get-GlobalRuleProperty $Plan 'zcode_user_root')) $zcode)){$findings.Add((New-GlobalRuleFinding 'authorization_root_mismatch' '$.zcode_user_root' 'CLI ZCode root must exactly match the plan root.'))|Out-Null}
    $canonical=Get-GlobalRuleProjectionEntries $repo $codex $claude $zcode;$actions=@(Get-GlobalRuleProperty $Plan 'actions')
    if($actions.Count-ne$canonical.Count){$findings.Add((New-GlobalRuleFinding 'plan_action_set_invalid' '$.actions' 'Plan must contain exactly the canonical host actions.'))|Out-Null}
    $byId=@{};foreach($action in $actions){$id=[string](Get-GlobalRuleProperty $action 'id');if($byId.ContainsKey($id)){$byId[$id]=$null}else{$byId[$id]=$action}}
    foreach($entry in $canonical){
        $action=if($byId.ContainsKey($entry.id)){$byId[$entry.id]}else{$null}
        if($null-eq$action-or-not(Test-GlobalRulePathEqual ([string](Get-GlobalRuleProperty $action 'source_path')) $entry.source_path)-or-not(Test-GlobalRulePathEqual ([string](Get-GlobalRuleProperty $action 'target_path')) $entry.target_path)){$findings.Add((New-GlobalRuleFinding 'plan_action_binding_mismatch' '$.actions' ('Plan is not bound to the canonical {0} action.'-f$entry.id)))|Out-Null;continue}
        $source=Get-GlobalRuleFileFacts $entry.source_path
        if(-not$source.exists-or$source.hash-ne[string](Get-GlobalRuleProperty $action 'source_hash')){$findings.Add((New-GlobalRuleFinding 'source_hash_stale' $entry.source_path 'Global rule source changed after planning.'))|Out-Null}
        $beforeExists=[bool](Get-GlobalRuleProperty $action 'before_exists');$beforeHash=[string](Get-GlobalRuleProperty $action 'before_hash');$operation=[string](Get-GlobalRuleProperty $action 'operation')
        $expectedOperation=if(-not$beforeExists){'create'}elseif($beforeHash-eq[string](Get-GlobalRuleProperty $action 'source_hash')){'unchanged'}else{'update'}
        if($operation-ne$expectedOperation){$findings.Add((New-GlobalRuleFinding 'plan_operation_invalid' '$.actions' 'Plan operation does not match its bound hashes.'))|Out-Null}
        if(-not$AllowAppliedTargets){$target=Get-GlobalRuleFileFacts $entry.target_path;if($target.exists-ne$beforeExists-or$target.hash-ne$beforeHash){$findings.Add((New-GlobalRuleFinding 'target_hash_stale' $entry.target_path 'Global rule target changed after planning.'))|Out-Null}}
    }
    if($actions.Count-eq$canonical.Count){
        try{$identity=Get-GlobalRulePlanIdentity $repo $codex $claude $actions $zcode;if([string](Get-GlobalRuleProperty $Plan 'plan_hash')-cne$identity.plan_hash-or[string](Get-GlobalRuleProperty $Plan 'operation_id')-cne$identity.operation_id-or[string](Get-GlobalRuleProperty (Get-GlobalRuleProperty $Plan 'apply') 'required_token')-cne$identity.apply_token){$findings.Add((New-GlobalRuleFinding 'plan_identity_invalid' '$' 'Plan identity or token is not canonical.'))|Out-Null}}catch{$findings.Add((New-GlobalRuleFinding 'plan_identity_invalid' '$' $_.Exception.Message))|Out-Null}
    }
    return [pscustomobject]@{pass=($findings.Count-eq0);findings=@($findings.ToArray())}
}

function Write-GlobalRuleReceipt([string]$Path,$Receipt) {
    $Receipt.updated_at=[datetimeoffset]::UtcNow.ToString('o')
    Write-Utf8FileAtomic -Path $Path -Content ($Receipt|ConvertTo-Json -Depth 30 -Compress)
}

function Test-GlobalRuleReceiptBinding {
    param($Receipt,$Plan,[string]$RepoRoot,[string]$CodexUserRoot,[string]$ClaudeUserRoot,[string]$BackupRoot,[string]$ZCodeUserRoot='')
    $findings=New-Object Collections.Generic.List[object]
    if($null-eq$Receipt-or(Get-GlobalRuleProperty $Receipt 'schema_version')-ne2-or[string](Get-GlobalRuleProperty $Receipt 'domain')-ne'global_rule_projection'){
        return [pscustomobject]@{pass=$false;findings=@((New-GlobalRuleFinding 'receipt_schema_invalid' '$' 'Only global rule projection receipt schema version 2 is supported.'))}
    }
    if([string](Get-GlobalRuleProperty $Receipt 'operation_id')-cne[string](Get-GlobalRuleProperty $Plan 'operation_id')-or[string](Get-GlobalRuleProperty $Receipt 'plan_hash')-cne[string](Get-GlobalRuleProperty $Plan 'plan_hash')){$findings.Add((New-GlobalRuleFinding 'receipt_plan_mismatch' '$' 'Receipt is not bound to the supplied plan.'))|Out-Null}
    $identity=Get-GlobalRulePlanIdentity $RepoRoot $CodexUserRoot $ClaudeUserRoot @(Get-GlobalRuleProperty $Plan 'actions') $ZCodeUserRoot
    if([string](Get-GlobalRuleProperty (Get-GlobalRuleProperty $Receipt 'rollback') 'required_token')-cne$identity.rollback_token){$findings.Add((New-GlobalRuleFinding 'receipt_rollback_token_invalid' '$.rollback.required_token' 'Receipt rollback token is not operation-bound.'))|Out-Null}
    foreach($pair in @(@('repo_root',$RepoRoot),@('codex_user_root',$CodexUserRoot),@('claude_user_root',$ClaudeUserRoot),@('zcode_user_root',$ZCodeUserRoot))){if(-not(Test-GlobalRulePathEqual ([string](Get-GlobalRuleProperty $Receipt $pair[0])) $pair[1])){$findings.Add((New-GlobalRuleFinding 'receipt_root_mismatch' ('$.'+$pair[0]) 'Receipt roots do not match the authorized roots.'))|Out-Null}}
    $planActions=@(Get-GlobalRuleProperty $Plan 'actions');$receiptActions=@(Get-GlobalRuleProperty $Receipt 'actions')
    if($receiptActions.Count-ne$planActions.Count){$findings.Add((New-GlobalRuleFinding 'receipt_action_set_invalid' '$.actions' 'Receipt must contain exactly the plan actions.'))|Out-Null}
    $receiptById=@{};foreach($item in $receiptActions){$id=[string](Get-GlobalRuleProperty $item 'id');if($receiptById.ContainsKey($id)){$receiptById[$id]=$null}else{$receiptById[$id]=$item}}
    foreach($action in $planActions){
        $id=[string](Get-GlobalRuleProperty $action 'id');$item=if($receiptById.ContainsKey($id)){$receiptById[$id]}else{$null}
        if($null-eq$item){$findings.Add((New-GlobalRuleFinding 'receipt_action_binding_mismatch' '$.actions' ('Receipt action is missing: {0}'-f$id)))|Out-Null;continue}
        foreach($field in @('source_path','target_path')){if(-not(Test-GlobalRulePathEqual ([string](Get-GlobalRuleProperty $item $field)) ([string](Get-GlobalRuleProperty $action $field)))){$findings.Add((New-GlobalRuleFinding 'receipt_action_binding_mismatch' '$.actions' ('Receipt {0} differs from the plan.'-f$field)))|Out-Null}}
        foreach($field in @('source_hash','before_hash','operation')){if([string](Get-GlobalRuleProperty $item $field)-cne[string](Get-GlobalRuleProperty $action $field)){$findings.Add((New-GlobalRuleFinding 'receipt_action_binding_mismatch' '$.actions' ('Receipt {0} differs from the plan.'-f$field)))|Out-Null}}
        if([bool](Get-GlobalRuleProperty $item 'before_exists')-ne[bool](Get-GlobalRuleProperty $action 'before_exists')){$findings.Add((New-GlobalRuleFinding 'receipt_action_binding_mismatch' '$.actions' 'Receipt before_exists differs from the plan.'))|Out-Null}
        $status=[string](Get-GlobalRuleProperty $item 'status');$operation=[string](Get-GlobalRuleProperty $item 'operation')
        if($status-notin@('pending','prepared','applied','unchanged','rolled_back')){$findings.Add((New-GlobalRuleFinding 'receipt_action_status_invalid' '$.actions' 'Receipt action status is invalid.'))|Out-Null}
        if(($operation-eq'unchanged'-and$status-ne'unchanged')-or($operation-ne'unchanged'-and$status-eq'unchanged')){$findings.Add((New-GlobalRuleFinding 'receipt_action_status_invalid' '$.actions' 'Receipt action status does not match its operation.'))|Out-Null}
        $backup=[string](Get-GlobalRuleProperty $item 'backup_path')
        $backupRequired=([bool](Get-GlobalRuleProperty $item 'before_exists')-and$status-in@('prepared','applied','rolled_back'))
        if($backupRequired-and[string]::IsNullOrWhiteSpace($backup)){$findings.Add((New-GlobalRuleFinding 'receipt_backup_missing' '$.actions' 'Prepared or completed update action requires its canonical backup.'))|Out-Null}
        if(-not[string]::IsNullOrWhiteSpace($backup)){
            $expected=Join-Path (Join-Path ([IO.Path]::GetFullPath($BackupRoot)) ([string](Get-GlobalRuleProperty $Plan 'operation_id'))) ("$id.bak")
            if(-not(Test-GlobalRulePathEqual $backup $expected)){$findings.Add((New-GlobalRuleFinding 'receipt_backup_path_invalid' '$.actions' 'Receipt backup path is not canonical.'))|Out-Null}
            elseif(-not[IO.File]::Exists($backup)){$findings.Add((New-GlobalRuleFinding 'receipt_backup_missing' '$.actions' 'Receipt backup does not exist.'))|Out-Null}
            else{$bytes=[IO.File]::ReadAllBytes($backup);$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant();if($bytes.Length-ne[int64](Get-GlobalRuleProperty $item 'backup_length')-or$hash-cne[string](Get-GlobalRuleProperty $item 'backup_sha256')-or$hash-cne[string](Get-GlobalRuleProperty $item 'before_hash')){$findings.Add((New-GlobalRuleFinding 'receipt_backup_integrity_invalid' '$.actions' 'Receipt backup hash or length is invalid.'))|Out-Null}}
        }
    }
    return [pscustomobject]@{pass=($findings.Count-eq0);findings=@($findings.ToArray())}
}

function Invoke-GlobalRuleProjectionApply {
    param($Plan,[Parameter(Mandatory=$true)][string]$Token,[Parameter(Mandatory=$true)][string]$BackupRoot,[Parameter(Mandatory=$true)][string]$ReceiptPath,[Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot,[switch]$Resume,[string]$ZCodeUserRoot='')
    $binding=Test-GlobalRulePlanBinding $Plan $RepoRoot $CodexUserRoot $ClaudeUserRoot $ZCodeUserRoot -AllowAppliedTargets:$Resume
    if(-not$binding.pass){throw('Global rule projection plan is invalid or stale: {0}'-f(@($binding.findings.code)-join', '))}
    if($Token-cne[string](Get-GlobalRuleProperty (Get-GlobalRuleProperty $Plan 'apply') 'required_token')){throw 'Global rule projection token does not match the plan.'}
    $receiptFile=[IO.Path]::GetFullPath($ReceiptPath);$exists=[IO.File]::Exists($receiptFile)
    if($exists-and-not$Resume){throw 'Global rule receipt already exists; use --resume only for an interrupted matching operation.'}
    if($Resume-and-not$exists){throw 'Global rule resume requires an existing receipt.'}
    $backupBase=Join-Path ([IO.Path]::GetFullPath($BackupRoot)) ([string](Get-GlobalRuleProperty $Plan 'operation_id'))
    if($Resume){
        $receipt=[IO.File]::ReadAllText($receiptFile)|ConvertFrom-Json
        $receiptBinding=Test-GlobalRuleReceiptBinding $receipt $Plan $RepoRoot $CodexUserRoot $ClaudeUserRoot $BackupRoot $ZCodeUserRoot
        if(-not$receiptBinding.pass){throw('Global rule receipt is invalid: {0}'-f(@($receiptBinding.findings.code)-join', '))}
        if([string](Get-GlobalRuleProperty $receipt 'status')-notin@('in_progress','recovery_required')){throw 'Global rule receipt is not resumable.'}
        if(@($receipt.actions|Where-Object {$_.status-eq'rolled_back'}).Count-gt0){throw 'Global rule receipt contains rolled-back actions and is not resumable for apply.'}
    }else{
        [IO.Directory]::CreateDirectory($backupBase)|Out-Null
        $receiptActions=foreach($action in @(Get-GlobalRuleProperty $Plan 'actions')){[pscustomobject][ordered]@{id=$action.id;source_path=$action.source_path;target_path=$action.target_path;source_hash=$action.source_hash;before_exists=[bool]$action.before_exists;before_hash=$action.before_hash;operation=$action.operation;status=$(if($action.operation-eq'unchanged'){'unchanged'}else{'pending'});backup_path=$null;backup_sha256=$null;backup_length=$null}}
        $identity=Get-GlobalRulePlanIdentity $RepoRoot $CodexUserRoot $ClaudeUserRoot @(Get-GlobalRuleProperty $Plan 'actions') $ZCodeUserRoot
        $receipt=[pscustomobject][ordered]@{schema_version=2;domain='global_rule_projection';operation_id=$Plan.operation_id;plan_hash=$Plan.plan_hash;status='in_progress';started_at=[datetimeoffset]::UtcNow.ToString('o');updated_at=$null;completed_at=$null;repo_root=[IO.Path]::GetFullPath($RepoRoot);codex_user_root=[IO.Path]::GetFullPath($CodexUserRoot);claude_user_root=[IO.Path]::GetFullPath($ClaudeUserRoot);zcode_user_root=$(if([string]::IsNullOrWhiteSpace($ZCodeUserRoot)){''}else{[IO.Path]::GetFullPath($ZCodeUserRoot)});actions=@($receiptActions);writes=0;last_error=$null;rollback=[pscustomobject]@{required_token=$identity.rollback_token};truth_boundary='filesystem_apply_in_progress_not_host_loaded'}
        Write-GlobalRuleReceipt $receiptFile $receipt
    }
    foreach($field in @('updated_at','completed_at','last_error','truth_boundary')){if($null-eq$receipt.PSObject.Properties[$field]){$receipt|Add-Member -NotePropertyName $field -NotePropertyValue $null}}
    if($null-eq$receipt.PSObject.Properties['writes']){$receipt|Add-Member -NotePropertyName writes -NotePropertyValue 0}
    $receipt.writes=@($receipt.actions|Where-Object {$_.status-eq'applied'}).Count
    try{
        foreach($action in @($receipt.actions)){
            if($action.status-in@('unchanged','applied')){
                if((Get-GlobalRuleFileFacts $action.target_path).hash-ne[string]$action.source_hash){throw('Completed target drift blocks resume: {0}'-f$action.target_path)}
                continue
            }
            $target=Get-GlobalRuleFileFacts $action.target_path
            if($action.status-eq'prepared'){
                if($target.exists-and$target.hash-eq[string]$action.source_hash){$action.status='applied';$receipt.writes=[int]$receipt.writes+1;Write-GlobalRuleReceipt $receiptFile $receipt;continue}
                if($target.exists-ne[bool]$action.before_exists-or$target.hash-ne[string]$action.before_hash){throw('Prepared target drift blocks resume: {0}'-f$action.target_path)}
            }elseif($target.exists-ne[bool]$action.before_exists-or$target.hash-ne[string]$action.before_hash){throw('Target drift blocks apply: {0}'-f$action.target_path)}
            if($action.status-eq'pending'){
                if([bool]$action.before_exists){
                    $backup=Join-Path $backupBase ("$($action.id).bak");$bytes=[IO.File]::ReadAllBytes([string]$action.target_path);Write-BytesAtomic -Path $backup -Bytes $bytes
                    $action.backup_path=$backup;$action.backup_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant();$action.backup_length=$bytes.Length
                }
                $action.status='prepared';Write-GlobalRuleReceipt $receiptFile $receipt
            }
            Write-BytesAtomic -Path ([string]$action.target_path) -Bytes ([IO.File]::ReadAllBytes([string]$action.source_path))
            $action.status='applied';$receipt.writes=[int]$receipt.writes+1;Write-GlobalRuleReceipt $receiptFile $receipt
        }
        $receipt.status='applied';$receipt.completed_at=[datetimeoffset]::UtcNow.ToString('o');$receipt.last_error=$null;$receipt.truth_boundary='filesystem_applied_not_host_loaded';Write-GlobalRuleReceipt $receiptFile $receipt
        return $receipt
    }catch{
        $receipt.status='recovery_required';$receipt.last_error=$_.Exception.Message;$receipt.truth_boundary='filesystem_apply_incomplete_not_host_loaded';Write-GlobalRuleReceipt $receiptFile $receipt
        throw
    }
}

function Test-GlobalRuleProjection {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot,[string]$ZCodeUserRoot='')
    $source=Test-GlobalRuleSourceFamily $RepoRoot $CodexUserRoot $ClaudeUserRoot $ZCodeUserRoot;$findings=New-Object Collections.Generic.List[object]
    foreach($finding in @($source.findings)){$findings.Add($finding)|Out-Null}
    if($source.pass){foreach($entry in $source.entries){$target=Get-GlobalRuleFileFacts $entry.target_path;if(-not$target.exists){$findings.Add((New-GlobalRuleFinding 'target_missing' $entry.target_path 'Projected global rule is missing.'))|Out-Null}elseif($target.hash-ne$source.facts[$entry.id].hash){$findings.Add((New-GlobalRuleFinding 'target_source_drift' $entry.target_path 'Projected global rule differs from its source.'))|Out-Null}}}
    return [pscustomobject][ordered]@{pass=($findings.Count-eq0);findings=@($findings.ToArray());observations=@($source.observations);truth_boundary=$(if($findings.Count-eq0){'filesystem_projected_not_host_loaded'}else{'projection_not_verified'})}
}

function Invoke-GlobalRuleProjectionRollback {
    param([Parameter(Mandatory=$true)][string]$ReceiptPath,[Parameter(Mandatory=$true)][string]$Token,[Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot,[Parameter(Mandatory=$true)][string]$BackupRoot,[string]$ZCodeUserRoot='')
    $receiptFile=[IO.Path]::GetFullPath($ReceiptPath);if(-not[IO.File]::Exists($receiptFile)){throw 'Global rule receipt does not exist.'}
    $receipt=[IO.File]::ReadAllText($receiptFile)|ConvertFrom-Json
    if((Get-GlobalRuleProperty $receipt 'schema_version')-ne2-or[string](Get-GlobalRuleProperty $receipt 'domain')-ne'global_rule_projection'){throw 'Only global rule projection receipt schema version 2 is supported; schema v1 receipts cannot be rolled back.'}
    $plan=[pscustomobject]@{schema_version=2;domain='global_rule_projection';operation_id=$receipt.operation_id;plan_hash=$receipt.plan_hash;repo_root=$receipt.repo_root;codex_user_root=$receipt.codex_user_root;claude_user_root=$receipt.claude_user_root;zcode_user_root=$receipt.zcode_user_root;actions=@($receipt.actions|ForEach-Object{[pscustomobject]@{id=$_.id;source_path=$_.source_path;target_path=$_.target_path;source_hash=$_.source_hash;before_exists=[bool]$_.before_exists;before_hash=$_.before_hash;operation=$_.operation}});apply=[pscustomobject]@{required_token=$null}}
    $identity=Get-GlobalRulePlanIdentity $RepoRoot $CodexUserRoot $ClaudeUserRoot $plan.actions $ZCodeUserRoot;$plan.apply.required_token=$identity.apply_token
    $planBinding=Test-GlobalRulePlanBinding $plan $RepoRoot $CodexUserRoot $ClaudeUserRoot $ZCodeUserRoot -AllowAppliedTargets
    if(-not$planBinding.pass-or$plan.plan_hash-cne$identity.plan_hash-or$plan.operation_id-cne$identity.operation_id){throw('Global rule receipt canonical binding is invalid: {0}'-f(@($planBinding.findings.code)-join', '))}
    $receiptBinding=Test-GlobalRuleReceiptBinding $receipt $plan $RepoRoot $CodexUserRoot $ClaudeUserRoot $BackupRoot $ZCodeUserRoot
    if(-not$receiptBinding.pass){throw('Global rule receipt is invalid: {0}'-f(@($receiptBinding.findings.code)-join', '))}
    if($Token-cne[string]$receipt.rollback.required_token-or$Token-cne$identity.rollback_token){throw 'Global rule rollback token is invalid.'}
    if([string]$receipt.status-notin@('applied','rollback_in_progress')){throw 'Global rule receipt is not rollback eligible.'}
    foreach($action in @($receipt.actions|Where-Object {$_.operation -ne 'unchanged'})){
        if([bool]$action.before_exists){
            if(-not[IO.File]::Exists([string]$action.backup_path)){throw('Global rule backup is missing: {0}'-f$action.backup_path)}
            $bytes=[IO.File]::ReadAllBytes([string]$action.backup_path);$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            if($bytes.Length-ne[int64]$action.backup_length-or$hash-cne[string]$action.backup_sha256-or$hash-cne[string]$action.before_hash){throw('Global rule backup integrity check failed: {0}'-f$action.backup_path)}
        }elseif(-not[string]::IsNullOrWhiteSpace([string]$action.backup_path)){throw 'Create actions must not carry a backup path.'}
        $target=Get-GlobalRuleFileFacts $action.target_path;$alreadyBefore=($target.exists-eq[bool]$action.before_exists-and$target.hash-eq[string]$action.before_hash)
        $isDesired=($target.exists-and$target.hash-eq[string]$action.source_hash)
        if(-not$alreadyBefore-and-not$isDesired){throw('Global rule target drift blocks rollback: {0}'-f$action.target_path)}
    }
    $receipt.status='rollback_in_progress';Write-GlobalRuleReceipt $receiptFile $receipt
    $writes=0;$reverse=@($receipt.actions|Where-Object {$_.operation -ne 'unchanged'});[array]::Reverse($reverse)
    foreach($action in $reverse){
        $target=Get-GlobalRuleFileFacts $action.target_path
        if($target.exists-eq[bool]$action.before_exists-and$target.hash-eq[string]$action.before_hash){$action.status='rolled_back';continue}
        if([bool]$action.before_exists){Write-BytesAtomic -Path $action.target_path -Bytes ([IO.File]::ReadAllBytes([string]$action.backup_path))}elseif([IO.File]::Exists([string]$action.target_path)){Remove-Item -LiteralPath $action.target_path -Force}
        $action.status='rolled_back';$writes++;Write-GlobalRuleReceipt $receiptFile $receipt
    }
    $receipt.status='rolled_back';$receipt.completed_at=[datetimeoffset]::UtcNow.ToString('o');$receipt.truth_boundary='filesystem_rolled_back';Write-GlobalRuleReceipt $receiptFile $receipt
    return [pscustomobject]@{pass=$true;status='rolled_back';writes=$writes;truth_boundary='filesystem_rolled_back'}
}
