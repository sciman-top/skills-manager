function Get-RulePatchTextHash([string]$Text) {
    return Get-OperationSha256 ([string]$Text)
}

function New-RulePatchUnifiedDiff {
    param([string]$CurrentText, [string]$DesiredText, [string]$DisplayPath, [int]$MaxDiffChars = 131072)
    if ($CurrentText -ceq $DesiredText) { return [pscustomobject][ordered]@{ format = 'unified'; content = ''; has_changes = $false } }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('--- a/{0}' -f $DisplayPath.Replace('\', '/').TrimStart('/'))) | Out-Null
    $lines.Add(('+++ b/{0}' -f $DisplayPath.Replace('\', '/').TrimStart('/'))) | Out-Null
    $lines.Add('@@ -1 +1 @@') | Out-Null
    foreach ($line in @($CurrentText -split "`r?`n")) { $lines.Add(('-{0}' -f $line)) | Out-Null }
    foreach ($line in @($DesiredText -split "`r?`n")) { $lines.Add(('+{0}' -f $line)) | Out-Null }
    $content = $lines -join "`n"
    if ($content.Length -gt $MaxDiffChars) { throw ('Rule patch diff exceeds the bounded limit: {0} > {1}.' -f $content.Length, $MaxDiffChars) }
    return [pscustomobject][ordered]@{ format = 'unified'; content = $content; has_changes = $true }
}

function New-RulePatchPlan {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$CurrentText,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DesiredText,
        [Parameter(Mandatory = $true)][ValidateSet('explicit_user_input', 'reviewed_file', 'semantic_recommendation')][string]$DesiredSource,
        [string[]]$FindingIds = @(), [string[]]$EvidenceRefs = @(), [ValidateSet('low', 'medium', 'high')][string]$Risk = 'medium',
        [string]$Owner = 'rule_patch_executor', [string]$RequiredToken = 'APPLY_RULE_PATCH', [int]$MaxDiffChars = 131072
    )
    $path = [System.IO.Path]::GetFullPath($TargetPath); $root = [System.IO.Path]::GetFullPath($AuthorizedRoot)
    $beforeHash = Get-RulePatchTextHash $CurrentText; $desiredHash = Get-RulePatchTextHash $DesiredText
    $diff = New-RulePatchUnifiedDiff $CurrentText $DesiredText ([System.IO.Path]::GetFileName($path)) $MaxDiffChars
    $identity = '{0}|{1}|{2}|{3}' -f $path.ToLowerInvariant(), $beforeHash, $desiredHash, $DesiredSource
    $patchId = 'patch-{0}' -f (Get-OperationSha256 $identity).Substring(0, 16)
    return [pscustomobject][ordered]@{
        schema_version = 1; patch_id = $patchId; operation_id = ('rule-{0}' -f $patchId.Substring(6)); mode = 'plan'
        target = [pscustomobject][ordered]@{ target_ref = 'rule-target'; path = $path; authorized_root = $root; before_hash = $beforeHash; desired_hash = $desiredHash; owner = $Owner }
        source = [pscustomobject][ordered]@{ finding_ids = @($FindingIds | Sort-Object -Unique); evidence_refs = @($EvidenceRefs | Sort-Object -Unique); desired_source = $DesiredSource }
        diff = $diff; desired_text = $DesiredText; risk = $Risk
        preconditions = @('valid_plan', 'fresh_before_hash', 'authorized_fixture_root', 'explicit_apply_token')
        verification = @('desired_hash_matches', 'receipt_contract_valid'); rollback = @('restore_before_bytes')
        apply = [pscustomobject][ordered]@{ required_token = $RequiredToken; fixture_only = $true }
    }
}

function Test-RulePatchPlanContract($Plan) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan) { return New-OperationValidationResult @((New-OperationFinding 'rule_patch_plan_missing' 'error' '$' 'Rule patch plan is required.')) }
    if ((Get-OperationObjectProperty $Plan 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('patch_id', 'operation_id', 'mode', 'risk')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Plan $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required field is missing.')) | Out-Null } }
    if ([string](Get-OperationObjectProperty $Plan 'patch_id') -notmatch '^patch-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'patch_id_invalid' 'error' '$.patch_id' 'Patch ID is invalid.')) | Out-Null }
    $target = Get-OperationObjectProperty $Plan 'target'
    foreach ($field in @('path', 'authorized_root', 'before_hash', 'desired_hash', 'owner')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $target $field))) { $findings.Add((New-OperationFinding 'target_field_missing' 'error' ('$.target.{0}' -f $field) 'Target field is required.')) | Out-Null } }
    foreach ($field in @('before_hash', 'desired_hash')) { if ([string](Get-OperationObjectProperty $target $field) -notmatch '^[a-f0-9]{64}$') { $findings.Add((New-OperationFinding 'hash_invalid' 'error' ('$.target.{0}' -f $field) 'Hash must be SHA-256.')) | Out-Null } }
    $source = Get-OperationObjectProperty $Plan 'source'; $desiredSource = [string](Get-OperationObjectProperty $source 'desired_source')
    if ($desiredSource -notin @('explicit_user_input', 'reviewed_file')) { $findings.Add((New-OperationFinding 'desired_source_not_authorized' 'error' '$.source.desired_source' 'Desired content must be explicit or reviewed, never a semantic recommendation.')) | Out-Null }
    if (-not [bool](Get-OperationObjectProperty (Get-OperationObjectProperty $Plan 'apply') 'fixture_only')) { $findings.Add((New-OperationFinding 'fixture_only_required' 'error' '$.apply.fixture_only' 'P2 apply must remain fixture-only.')) | Out-Null }
    $serialized = $Plan | ConvertTo-Json -Depth 30 -Compress
    if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding 'sensitive_content_present' 'error' '$' 'Patch plan contains sensitive content.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
