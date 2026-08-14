function Assert-GlobalRuleProjectionRoot([string]$Path,[string]$Label) {
    $resolved=[IO.Path]::GetFullPath($Path).TrimEnd('\','/');$drive=[IO.Path]::GetPathRoot($resolved).TrimEnd('\','/')
    if($resolved.Equals($drive,[StringComparison]::OrdinalIgnoreCase)){throw ('Drive roots are not valid {0} roots.' -f $Label)}
    if(-not [IO.Directory]::Exists($resolved)){throw ('{0} root does not exist: {1}' -f $Label,$resolved)}
    return $resolved
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
        [Parameter(Mandatory=$true)][string]$ClaudeUserRoot
    )
    $repo=Assert-GlobalRuleProjectionRoot $RepoRoot 'repository';$codex=Assert-GlobalRuleProjectionRoot $CodexUserRoot 'Codex user';$claude=Assert-GlobalRuleProjectionRoot $ClaudeUserRoot 'Claude user'
    return @(
        [pscustomobject][ordered]@{ id='codex'; source_path=(Join-Path $repo 'rules\global\codex\AGENTS.md'); target_path=(Join-Path $codex 'AGENTS.md');root=$codex }
        [pscustomobject][ordered]@{ id='claude'; source_path=(Join-Path $repo 'rules\global\claude\CLAUDE.md'); target_path=(Join-Path $claude 'CLAUDE.md');root=$claude }
    )
}

function Get-GlobalRuleFileFacts([string]$Path) {
    if(-not [IO.File]::Exists($Path)){return [pscustomobject]@{exists=$false;path=$Path}}
    $bytes=[IO.File]::ReadAllBytes($Path);$text=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes)
    $versionMatch=[regex]::Match($text,'(?m)^\*\*版本\*\*:\s*([0-9][0-9A-Za-z_.-]*)\s*$')
    return [pscustomobject][ordered]@{
        exists=$true;path=[IO.Path]::GetFullPath($Path);bytes=$bytes.Length;lines=($text -split "`r?`n").Count
        bom=($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF)
        version=$(if($versionMatch.Success){$versionMatch.Groups[1].Value}else{$null});text=$text
        hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
}

function Get-GlobalRuleCommonSections([string]$Text) {
    $normalized=$Text.Replace("`r`n","`n")
    $aStart=$normalized.IndexOf('## A.');$bStart=$normalized.IndexOf('## B.');$cStart=$normalized.IndexOf('## C.')
    if($aStart -lt 0 -or $bStart -le $aStart -or $cStart -le $bStart){return $null}
    return [pscustomobject]@{ a=$normalized.Substring($aStart,$bStart-$aStart); cd=$normalized.Substring($cStart) }
}

function Test-GlobalRuleSourceFamily {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot)
    $findings=New-Object Collections.Generic.List[object]
    $entries=Get-GlobalRuleProjectionEntries $RepoRoot $CodexUserRoot $ClaudeUserRoot
    $facts=@{}
    foreach($entry in $entries){
        if(Test-GlobalRuleProjectionReparsePath $entry.source_path ([IO.Path]::GetFullPath($RepoRoot))){$findings.Add([pscustomobject]@{code='source_reparse_forbidden';path=$entry.source_path;message='Global rule sources must not cross reparse points.'})|Out-Null}
        if(Test-GlobalRuleProjectionReparsePath $entry.target_path $entry.root){$findings.Add([pscustomobject]@{code='target_reparse_forbidden';path=$entry.target_path;message='Global rule targets must be ordinary files below the user root.'})|Out-Null}
        try{$fact=Get-GlobalRuleFileFacts $entry.source_path}catch{$findings.Add([pscustomobject]@{code='source_encoding_invalid';path=$entry.source_path;message=$_.Exception.Message})|Out-Null;continue}
        $facts[$entry.id]=$fact
        if(-not $fact.exists){$findings.Add([pscustomobject]@{code='source_missing';path=$entry.source_path;message='Global rule source is missing.'})|Out-Null;continue}
        if($fact.bom){$findings.Add([pscustomobject]@{code='source_bom_forbidden';path=$entry.source_path;message='Global rules must be UTF-8 without BOM.'})|Out-Null}
        if($fact.bytes -gt 16384){$findings.Add([pscustomobject]@{code='source_byte_budget_exceeded';path=$entry.source_path;message='Global rule exceeds 16 KiB.'})|Out-Null}
        if($fact.lines -gt 130){$findings.Add([pscustomobject]@{code='source_line_budget_exceeded';path=$entry.source_path;message='Global rule exceeds 130 lines.'})|Out-Null}
        if([string]::IsNullOrWhiteSpace([string]$fact.version)){$findings.Add([pscustomobject]@{code='source_version_missing';path=$entry.source_path;message='Global rule version is missing.'})|Out-Null}
    }
    if($facts.ContainsKey('codex') -and $facts.ContainsKey('claude') -and $facts.codex.exists -and $facts.claude.exists){
        if($facts.codex.version -ne $facts.claude.version){$findings.Add([pscustomobject]@{code='source_version_mismatch';path='$';message='Codex and Claude global rule versions differ.'})|Out-Null}
        $codexCommon=Get-GlobalRuleCommonSections $facts.codex.text;$claudeCommon=Get-GlobalRuleCommonSections $facts.claude.text
        if($null -eq $codexCommon -or $null -eq $claudeCommon){$findings.Add([pscustomobject]@{code='source_structure_invalid';path='$';message='Global rules require A, B, and C sections.'})|Out-Null}
        elseif($codexCommon.a -cne $claudeCommon.a -or $codexCommon.cd -cne $claudeCommon.cd){$findings.Add([pscustomobject]@{code='source_common_sections_drift';path='$';message='Codex and Claude A/C/D common sections must be byte-equivalent after newline normalization.'})|Out-Null}
    }
    return [pscustomobject][ordered]@{pass=($findings.Count -eq 0);findings=@($findings.ToArray());entries=$entries;facts=$facts}
}

function New-GlobalRuleProjectionPlan {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot)
    $validation=Test-GlobalRuleSourceFamily $RepoRoot $CodexUserRoot $ClaudeUserRoot
    if(-not $validation.pass){throw ('Global rule sources are invalid: {0}' -f (@($validation.findings.code)-join ', '))}
    $actions=foreach($entry in $validation.entries){
        $source=$validation.facts[$entry.id];$target=Get-GlobalRuleFileFacts $entry.target_path
        [pscustomobject][ordered]@{
            id=$entry.id;source_path=[IO.Path]::GetFullPath($entry.source_path);target_path=[IO.Path]::GetFullPath($entry.target_path)
            source_hash=$source.hash;before_exists=[bool]$target.exists;before_hash=$(if($target.exists){$target.hash}else{Get-OperationSha256 ''})
            operation=$(if(-not $target.exists){'create'}elseif($source.hash -eq $target.hash){'unchanged'}else{'update'})
        }
    }
    $seed=(@($actions|ForEach-Object{"$($_.id)|$($_.source_hash)|$($_.before_hash)|$($_.target_path)"})-join "`n")
    $operationId='global-rules-{0}' -f (Get-OperationSha256 $seed).Substring(0,16)
    return [pscustomobject][ordered]@{
        schema_version=1;domain='global_rule_projection';operation_id=$operationId;generated_at=[datetimeoffset]::UtcNow.ToString('o')
        repo_root=[IO.Path]::GetFullPath($RepoRoot);codex_user_root=[IO.Path]::GetFullPath($CodexUserRoot);claude_user_root=[IO.Path]::GetFullPath($ClaudeUserRoot)
        actions=@($actions);apply=[pscustomobject]@{required_token=('APPLY_GLOBAL_RULES_{0}' -f (Get-OperationSha256 $operationId).Substring(0,16).ToUpperInvariant());freshness='source_and_target_hash';rollback='receipt_bound'}
        truth_boundary='planned_not_applied';provider_calls=0;native_mutations=0
    }
}

function Test-GlobalRulePlanFreshness($Plan) {
    $findings=New-Object Collections.Generic.List[object]
    if($null -eq $Plan -or $Plan.schema_version -ne 1 -or $Plan.domain -ne 'global_rule_projection'){$findings.Add([pscustomobject]@{code='plan_invalid';path='$'})|Out-Null;return [pscustomobject]@{pass=$false;findings=@($findings)}}
    $fresh=Test-GlobalRuleSourceFamily $Plan.repo_root $Plan.codex_user_root $Plan.claude_user_root
    foreach($finding in @($fresh.findings)){$findings.Add($finding)|Out-Null}
    foreach($action in @($Plan.actions)){
        $source=Get-GlobalRuleFileFacts ([string]$action.source_path);$target=Get-GlobalRuleFileFacts ([string]$action.target_path)
        $targetHash=if($target.exists){$target.hash}else{Get-OperationSha256 ''}
        if(-not $source.exists -or $source.hash -ne [string]$action.source_hash){$findings.Add([pscustomobject]@{code='source_hash_stale';path=$action.source_path})|Out-Null}
        if($targetHash -ne [string]$action.before_hash -or [bool]$target.exists -ne [bool]$action.before_exists){$findings.Add([pscustomobject]@{code='target_hash_stale';path=$action.target_path})|Out-Null}
    }
    return [pscustomobject]@{pass=($findings.Count -eq 0);findings=@($findings.ToArray())}
}

function Invoke-GlobalRuleProjectionApply {
    param($Plan,[Parameter(Mandatory=$true)][string]$Token,[Parameter(Mandatory=$true)][string]$BackupRoot,[Parameter(Mandatory=$true)][string]$ReceiptPath)
    if($Token -cne [string]$Plan.apply.required_token){throw 'Global rule projection token does not match the plan.'}
    $freshness=Test-GlobalRulePlanFreshness $Plan;if(-not $freshness.pass){throw ('Global rule projection plan is stale: {0}' -f (@($freshness.findings.code)-join ', '))}
    $backupBase=Join-Path ([IO.Path]::GetFullPath($BackupRoot)) ([string]$Plan.operation_id);[IO.Directory]::CreateDirectory($backupBase)|Out-Null
    $completed=New-Object Collections.Generic.List[object]
    try{
        foreach($action in @($Plan.actions|Where-Object operation -ne 'unchanged')){
            $backup=$null
            if([bool]$action.before_exists){$backup=Join-Path $backupBase ("{0}-{1}.bak" -f $action.id,([string]$action.before_hash).Substring(0,12));Write-BytesAtomic -Path $backup -Bytes ([IO.File]::ReadAllBytes([string]$action.target_path))}
            Write-BytesAtomic -Path ([string]$action.target_path) -Bytes ([IO.File]::ReadAllBytes([string]$action.source_path))
            $completed.Add([pscustomobject][ordered]@{id=$action.id;target_path=$action.target_path;before_exists=[bool]$action.before_exists;before_hash=$action.before_hash;desired_hash=$action.source_hash;backup_path=$backup})|Out-Null
        }
    }catch{
        $reverse=@($completed.ToArray());[array]::Reverse($reverse)
        foreach($done in $reverse){if($done.before_exists){Write-BytesAtomic -Path $done.target_path -Bytes ([IO.File]::ReadAllBytes($done.backup_path))}elseif([IO.File]::Exists($done.target_path)){Remove-Item -LiteralPath $done.target_path -Force}}
        throw
    }
    $receipt=[pscustomobject][ordered]@{schema_version=1;domain='global_rule_projection';operation_id=$Plan.operation_id;status='applied';applied_at=[datetimeoffset]::UtcNow.ToString('o');writes=$completed.Count;actions=@($completed.ToArray());rollback=[pscustomobject]@{required_token='ROLLBACK_GLOBAL_RULES'};truth_boundary='filesystem_applied_not_host_loaded'}
    Write-Utf8FileAtomic -Path $ReceiptPath -Content ($receipt|ConvertTo-Json -Depth 20 -Compress)
    return $receipt
}

function Test-GlobalRuleProjection {
    param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$CodexUserRoot,[Parameter(Mandatory=$true)][string]$ClaudeUserRoot)
    $source=Test-GlobalRuleSourceFamily $RepoRoot $CodexUserRoot $ClaudeUserRoot;$findings=New-Object Collections.Generic.List[object]
    foreach($finding in @($source.findings)){$findings.Add($finding)|Out-Null}
    if($source.pass){foreach($entry in $source.entries){$target=Get-GlobalRuleFileFacts $entry.target_path;if(-not $target.exists){$findings.Add([pscustomobject]@{code='target_missing';path=$entry.target_path})|Out-Null}elseif($target.hash -ne $source.facts[$entry.id].hash){$findings.Add([pscustomobject]@{code='target_source_drift';path=$entry.target_path})|Out-Null}}}
    return [pscustomobject][ordered]@{pass=($findings.Count -eq 0);findings=@($findings.ToArray());truth_boundary=$(if($findings.Count -eq 0){'filesystem_projected_not_host_loaded'}else{'projection_not_verified'})}
}

function Invoke-GlobalRuleProjectionRollback {
    param([Parameter(Mandatory=$true)][string]$ReceiptPath,[Parameter(Mandatory=$true)][string]$Token)
    if($Token -cne 'ROLLBACK_GLOBAL_RULES'){throw 'Global rule rollback token is invalid.'}
    $receipt=[IO.File]::ReadAllText([IO.Path]::GetFullPath($ReceiptPath))|ConvertFrom-Json
    if($receipt.domain -ne 'global_rule_projection' -or $receipt.status -ne 'applied'){throw 'Global rule receipt is invalid.'}
    foreach($action in @($receipt.actions)){if((Get-GlobalRuleFileFacts $action.target_path).hash -ne [string]$action.desired_hash){throw ('Global rule target drift blocks rollback: {0}' -f $action.target_path)}}
    $reverse=@($receipt.actions);[array]::Reverse($reverse)
    foreach($action in $reverse){if([bool]$action.before_exists){if(-not [IO.File]::Exists([string]$action.backup_path)){throw ('Global rule backup is missing: {0}' -f $action.backup_path)};Write-BytesAtomic -Path $action.target_path -Bytes ([IO.File]::ReadAllBytes([string]$action.backup_path))}elseif([IO.File]::Exists([string]$action.target_path)){Remove-Item -LiteralPath $action.target_path -Force}}
    return [pscustomobject]@{pass=$true;status='rolled_back';writes=@($receipt.actions).Count;truth_boundary='filesystem_rolled_back'}
}
