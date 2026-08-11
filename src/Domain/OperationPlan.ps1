function New-OperationFinding([string]$Code, [string]$Severity, [string]$Path, [string]$Message) {
    return [pscustomobject]@{ code = $Code; severity = $Severity; path = $Path; message = $Message }
}
function New-OperationValidationResult([object[]]$Findings) {
    $all = @($Findings)
    return [pscustomobject]@{
        pass = (@($all | Where-Object { [string]$_.severity -eq "error" }).Count -eq 0)
        findings = $all
    }
}
function Get-OperationObjectProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in @($Object.Keys)) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) { return ,$Object[$key] }
        }
        return $null
    }
    $property = @($Object.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if ($null -eq $property) { return $null }
    return ,$property.Value
}
function Test-OperationObjectProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in @($Object.Keys)) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    return (@($Object.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)
}
function Test-OperationArray($Value) {
    return ($Value -is [System.Collections.IList]) -and -not ($Value -is [string])
}
function Test-OperationRfc3339($Value) {
    if ($Value -is [datetimeoffset] -or $Value -is [datetime]) { return $true }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') { return $false }
    $parsed = [datetimeoffset]::MinValue
    return [datetimeoffset]::TryParse(
        $text,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
}
function Get-OperationSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally { $sha.Dispose() }
}
function Normalize-OperationPathKey([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $value = $Path.Trim().Replace('/', '\')
    $prefix = ""
    if ($value -match '^[A-Za-z]:') {
        $prefix = $value.Substring(0, 2).ToLowerInvariant()
        $value = $value.Substring(2).TrimStart('\')
    }
    elseif ($value.StartsWith('\\')) {
        $prefix = "\\"
        $value = $value.TrimStart('\')
    }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($value -split '\\+' | Where-Object { $_ -ne "" -and $_ -ne "." })) {
        if ($segment -eq "..") {
            if ($parts.Count -gt 0 -and $parts[$parts.Count - 1] -ne "..") { $parts.RemoveAt($parts.Count - 1) }
            else { $parts.Add("..") | Out-Null }
        }
        else { $parts.Add($segment.ToLowerInvariant()) | Out-Null }
    }
    $body = $parts -join '\'
    if ($prefix -eq "\\") { return "\\$body".TrimEnd('\') }
    if ($prefix -ne "") { return ("{0}\{1}" -f $prefix, $body).TrimEnd('\') }
    return $body.TrimEnd('\')
}
function Test-OperationPathWithinRoot([string]$Path, [string]$Root) {
    $pathKey = Normalize-OperationPathKey $Path
    $rootKey = Normalize-OperationPathKey $Root
    if ([string]::IsNullOrWhiteSpace($pathKey) -or [string]::IsNullOrWhiteSpace($rootKey)) { return $false }
    return ($pathKey -eq $rootKey -or $pathKey.StartsWith(($rootKey + '\'), [System.StringComparison]::OrdinalIgnoreCase))
}
function Protect-OperationSensitiveString([string]$Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -match '(?i)\b(postgres|postgresql)://') { return "<redacted-connection-string>" }
    if ($Value -match '(?i)(^|;)\s*(Host|Server|Data Source)\s*=' -and $Value -match '(?i)(^|;)\s*(Password|Pwd)\s*=') { return "<redacted-connection-string>" }
    $masked = [regex]::Replace($Value, '(?i)(Authorization\s*[:=]\s*(?:Bearer\s+)?)([^\s,;]+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)(\b(?:https?|wss?)://)([^/@\s]+)@', '$1<redacted>@')
    $masked = [regex]::Replace($masked, '(?i)([?&](?:access_token|api_key|apikey|token|secret|password|key)=)[^&#\s]+', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{8,})\b', '<redacted>')
    $masked = [regex]::Replace($masked, '(?i)((?:Password|Pwd|ApiKey|API_KEY|Token|Secret)\s*=\s*)[^;\s]+', '$1<redacted>')
    return $masked
}
function Test-OperationSensitiveKey([string]$Name) {
    return ($Name -match '(?i)(^|_)(token|api_key|apikey|password|passwd|pwd|secret|authorization|connection_string|oauth)(_|$)')
}
function Test-OperationSerializedSensitiveValue([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value -match '(?i)(Bearer\s+(?!<redacted>)[A-Za-z0-9._-]+|postgres(?:ql)?://|(?:Password|Pwd)\s*[=:]\s*(?!<redacted>)[^;\s"}]+|\b(?:token|secret|password|passwd|api[-_]?key)\s+(?!<redacted>)[^\s"},;]+|(?:[A-Z0-9_]*(?:API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD))\s*=\s*(?!<redacted>)[^\s"}]+|gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{8,}|[?&](?:access_token|api_key|apikey|token|secret|password|key)=(?!<redacted>)[^&#\s"}]+|"(?:token|api_key|apikey|password|passwd|pwd|secret|authorization|connection_string|oauth)[^"]*"\s*:\s*"(?!<redacted>))'
}
function Protect-OperationSensitiveValue($Value, [string]$PropertyName = "") {
    if ($null -eq $Value) { return $null }
    if (Test-OperationSensitiveKey $PropertyName) { return "<redacted>" }
    if ($PropertyName -match '(?i)^(args|argv)$') {
        if (Test-OperationArray $Value) { return @($Value | ForEach-Object { "<redacted>" }) }
        return "<redacted>"
    }
    if ($Value -is [string]) { return Protect-OperationSensitiveString $Value }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        $result = [ordered]@{}
        $properties = if ($Value -is [System.Collections.IDictionary]) {
            @($Value.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $Value[$_] } })
        }
        else { @($Value.PSObject.Properties) }
        foreach ($property in $properties) {
            $name = [string]$property.Name
            if ($PropertyName -match '(?i)^(env|headers)$') { $result[$name] = "<redacted>" }
            else { $result[$name] = Protect-OperationSensitiveValue $property.Value $name }
        }
        return [pscustomobject]$result
    }
    if (Test-OperationArray $Value) { return @($Value | ForEach-Object { Protect-OperationSensitiveValue $_ $PropertyName }) }
    return $Value
}
function Get-OperationActionId([string]$Domain, $Action) {
    $type = ([string](Get-OperationObjectProperty $Action "type")).Trim().ToLowerInvariant()
    $targetRef = ([string](Get-OperationObjectProperty $Action "target_ref")).Trim().ToLowerInvariant()
    $summary = ([string](Protect-OperationSensitiveValue (Get-OperationObjectProperty $Action "summary") "summary")).Trim().ToLowerInvariant()
    $canonical = "{0}|{1}|{2}|{3}" -f $Domain.Trim().ToLowerInvariant(), $type, $targetRef, $summary
    return "act-{0}" -f (Get-OperationSha256 $canonical).Substring(0, 16)
}
function New-OperationPlan {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$CreatedAt,
        [object[]]$Targets = @(),
        [object[]]$Actions = @(),
        [string]$SourceRevision,
        [object[]]$Preconditions = @(),
        [object[]]$Verification = @(),
        [object[]]$Rollback = @()
    )
    $protectedTargets = foreach ($target in @($Targets)) {
        [pscustomobject][ordered]@{
            target_ref = [string](Get-OperationObjectProperty $target "target_ref")
            path = ([string](Get-OperationObjectProperty $target "path")).Replace('/', '\')
            before_hash = Get-OperationObjectProperty $target "before_hash"
            desired_hash = [string](Get-OperationObjectProperty $target "desired_hash")
            owner = [string](Get-OperationObjectProperty $target "owner")
        }
    }
    $protectedActions = foreach ($action in @($Actions)) {
        $item = [ordered]@{
            action_id = Get-OperationActionId $Domain $action
            type = [string](Get-OperationObjectProperty $action "type")
            target_ref = [string](Get-OperationObjectProperty $action "target_ref")
            summary = Protect-OperationSensitiveValue (Get-OperationObjectProperty $action "summary") "summary"
            risk = [string](Get-OperationObjectProperty $action "risk")
        }
        if (Test-OperationObjectProperty $action "metadata") { $item.metadata = Protect-OperationSensitiveValue (Get-OperationObjectProperty $action "metadata") "metadata" }
        [pscustomobject]$item
    }
    return [pscustomobject][ordered]@{
        schema_version = 1
        operation_id = $OperationId
        domain = $Domain
        mode = $Mode
        created_at = $CreatedAt
        source_revision = if ([string]::IsNullOrWhiteSpace($SourceRevision)) { $null } else { $SourceRevision }
        targets = @($protectedTargets | Sort-Object @{ Expression = { ([string]$_.target_ref).ToLowerInvariant() } }, @{ Expression = { Normalize-OperationPathKey ([string]$_.path) } })
        actions = @($protectedActions | Sort-Object action_id)
        preconditions = @(Protect-OperationSensitiveValue @($Preconditions) "preconditions")
        verification = @(Protect-OperationSensitiveValue @($Verification) "verification")
        rollback = @(Protect-OperationSensitiveValue @($Rollback) "rollback")
    }
}
function Test-OperationPlanContract($Plan) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan) { return New-OperationValidationResult @((New-OperationFinding "plan_missing" "error" "$" "Plan is required.")) }
    if ((Get-OperationObjectProperty $Plan "schema_version") -ne 1) { $findings.Add((New-OperationFinding "schema_version_invalid" "error" "$.schema_version" "Only schema version 1 is supported.")) | Out-Null }
    foreach ($field in @("operation_id", "domain", "mode", "created_at")) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Plan $field))) { $findings.Add((New-OperationFinding "required_field_missing" "error" ("$.{0}" -f $field) "Required field is missing.")) | Out-Null }
    }
    if (-not (Test-OperationRfc3339 (Get-OperationObjectProperty $Plan "created_at"))) { $findings.Add((New-OperationFinding "created_at_invalid" "error" "$.created_at" "Created time must be RFC3339.")) | Out-Null }
    if ([string](Get-OperationObjectProperty $Plan "domain") -notin @("mcp", "skill_projection", "rules", "plugin", "skill_lifecycle")) { $findings.Add((New-OperationFinding "domain_invalid" "error" "$.domain" "Domain is not supported.")) | Out-Null }
    if ([string](Get-OperationObjectProperty $Plan "mode") -notin @("dry_run", "apply")) { $findings.Add((New-OperationFinding "mode_invalid" "error" "$.mode" "Mode is not supported.")) | Out-Null }
    $targets = Get-OperationObjectProperty $Plan "targets"
    $actions = Get-OperationObjectProperty $Plan "actions"
    if (-not (Test-OperationArray $targets)) { $findings.Add((New-OperationFinding "targets_type_invalid" "error" "$.targets" "Targets must be an array.")) | Out-Null; $targets = @() }
    if (-not (Test-OperationArray $actions)) { $findings.Add((New-OperationFinding "actions_type_invalid" "error" "$.actions" "Actions must be an array.")) | Out-Null; $actions = @() }
    foreach ($field in @("preconditions", "verification", "rollback")) {
        if (-not (Test-OperationArray (Get-OperationObjectProperty $Plan $field))) { $findings.Add((New-OperationFinding "array_type_invalid" "error" ("$.{0}" -f $field) "Plan field must be an array.")) | Out-Null }
    }
    $targetRefs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt @($targets).Count; $i++) {
        $target = @($targets)[$i]
        $targetRef = [string](Get-OperationObjectProperty $target "target_ref")
        if ([string]::IsNullOrWhiteSpace($targetRef) -or -not $targetRefs.Add($targetRef)) { $findings.Add((New-OperationFinding "target_ref_invalid" "error" ("$.targets[{0}].target_ref" -f $i) "Target reference is missing or duplicated.")) | Out-Null }
        foreach ($field in @("path", "desired_hash", "owner")) {
            if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $target $field))) { $findings.Add((New-OperationFinding "target_field_missing" "error" ("$.targets[{0}].{1}" -f $i, $field) "Target field is required.")) | Out-Null }
        }
        foreach ($hashField in @("before_hash", "desired_hash")) {
            $hashValue = Get-OperationObjectProperty $target $hashField
            if ($null -ne $hashValue -and [string]$hashValue -notmatch '^[a-fA-F0-9]{64}$') { $findings.Add((New-OperationFinding "hash_invalid" "error" ("$.targets[{0}].{1}" -f $i, $hashField) "Hash must be SHA-256 or null.")) | Out-Null }
        }
    }
    $actionIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt @($actions).Count; $i++) {
        $action = @($actions)[$i]
        $actionId = [string](Get-OperationObjectProperty $action "action_id")
        if ([string]::IsNullOrWhiteSpace($actionId) -or -not $actionIds.Add($actionId)) { $findings.Add((New-OperationFinding "action_id_invalid" "error" ("$.actions[{0}].action_id" -f $i) "Action ID is missing or duplicated.")) | Out-Null }
        elseif ($actionId -notmatch '^act-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding "action_id_format_invalid" "error" ("$.actions[{0}].action_id" -f $i) "Action ID format is invalid.")) | Out-Null }
        if ([string](Get-OperationObjectProperty $action "type") -notin @("create", "update", "delete", "native_command")) { $findings.Add((New-OperationFinding "action_type_invalid" "error" ("$.actions[{0}].type" -f $i) "Action type is not supported.")) | Out-Null }
        if ([string](Get-OperationObjectProperty $action "risk") -notin @("low", "medium", "high")) { $findings.Add((New-OperationFinding "risk_invalid" "error" ("$.actions[{0}].risk" -f $i) "Risk is not supported.")) | Out-Null }
        if (-not $targetRefs.Contains([string](Get-OperationObjectProperty $action "target_ref"))) { $findings.Add((New-OperationFinding "action_target_unknown" "error" ("$.actions[{0}].target_ref" -f $i) "Action target is not declared.")) | Out-Null }
    }
    if ([string](Get-OperationObjectProperty $Plan "domain") -eq 'skill_lifecycle') {
        $lifecycle = Get-OperationObjectProperty $Plan 'lifecycle'
        if ($null -eq $lifecycle) { $findings.Add((New-OperationFinding 'skill_lifecycle_missing' 'error' '$.lifecycle' 'Skill lifecycle plans require a lifecycle binding.')) | Out-Null }
        else {
            $operationKind = [string](Get-OperationObjectProperty $lifecycle 'operation_kind')
            if ([string]::IsNullOrWhiteSpace($operationKind)) { $operationKind = 'promotion' }
            $requiredFields = if ($operationKind -eq 'promotion') {
                @('skill_name', 'candidate_directory', 'candidate_fingerprint', 'baseline_fingerprint', 'catalog_fingerprint', 'evaluation_path', 'evaluation_hash', 'review_path', 'review_hash', 'review_expires_at', 'projection_disposition')
            }
            elseif ($operationKind -eq 'activation') {
                @('skill_name', 'activation_action', 'package_fingerprint', 'catalog_fingerprint', 'config_path', 'config_before_hash', 'config_after_hash', 'request_path', 'request_hash', 'review_path', 'review_hash', 'review_expires_at', 'projection_disposition', 'projection_token')
            }
            else {
                $findings.Add((New-OperationFinding 'skill_lifecycle_kind_invalid' 'error' '$.lifecycle.operation_kind' 'Skill lifecycle operation_kind must be promotion or activation.')) | Out-Null
                @('skill_name')
            }
            foreach ($field in $requiredFields) {
                if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $lifecycle $field))) { $findings.Add((New-OperationFinding 'skill_lifecycle_field_missing' 'error' ('$.lifecycle.{0}' -f $field) 'Skill lifecycle binding field is required.')) | Out-Null }
            }
            if ([string](Get-OperationObjectProperty $lifecycle 'skill_name') -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { $findings.Add((New-OperationFinding 'skill_lifecycle_name_invalid' 'error' '$.lifecycle.skill_name' 'Skill lifecycle name must be lowercase kebab-case.')) | Out-Null }
            $hashFields = if ($operationKind -eq 'activation') { @('package_fingerprint', 'catalog_fingerprint', 'config_before_hash', 'config_after_hash', 'request_hash', 'review_hash') } else { @('candidate_fingerprint', 'baseline_fingerprint', 'catalog_fingerprint', 'evaluation_hash', 'review_hash') }
            foreach ($hashField in $hashFields) {
                if ([string](Get-OperationObjectProperty $lifecycle $hashField) -notmatch '^[a-fA-F0-9]{64}$') { $findings.Add((New-OperationFinding 'skill_lifecycle_hash_invalid' 'error' ('$.lifecycle.{0}' -f $hashField) 'Skill lifecycle hashes must be SHA-256 values.')) | Out-Null }
            }
            if (-not (Test-OperationRfc3339 (Get-OperationObjectProperty $lifecycle 'review_expires_at'))) { $findings.Add((New-OperationFinding 'skill_lifecycle_expiry_invalid' 'error' '$.lifecycle.review_expires_at' 'Review expiry must be RFC3339.')) | Out-Null }
            if ($operationKind -eq 'promotion' -and ((Get-OperationObjectProperty $lifecycle 'host_mutation') -ne $false -or [string](Get-OperationObjectProperty $lifecycle 'projection_disposition') -ne 'cold_catalog_only')) { $findings.Add((New-OperationFinding 'skill_lifecycle_boundary_invalid' 'error' '$.lifecycle' 'Skill lifecycle promotion cannot mutate host projection.')) | Out-Null }
            if ($operationKind -eq 'activation') {
                if ([string](Get-OperationObjectProperty $lifecycle 'activation_action') -notin @('enable', 'refresh', 'retire') -or (Get-OperationObjectProperty $lifecycle 'host_mutation') -ne $true -or [string](Get-OperationObjectProperty $lifecycle 'projection_disposition') -ne 'staged_then_project_after_clean_gate' -or [string](Get-OperationObjectProperty $lifecycle 'projection_token') -ne 'PROJECT_SKILL_TO_HOST') { $findings.Add((New-OperationFinding 'skill_activation_boundary_invalid' 'error' '$.lifecycle' 'Skill activation must stage an allowed action and bind later controlled projection.')) | Out-Null }
                $desiredIncludes = Get-OperationObjectProperty $lifecycle 'desired_managed_link_includes'
                if (-not (Test-OperationArray $desiredIncludes) -or @($desiredIncludes).Count -lt 1 -or @($desiredIncludes | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique).Count -ne @($desiredIncludes).Count) { $findings.Add((New-OperationFinding 'skill_activation_includes_invalid' 'error' '$.lifecycle.desired_managed_link_includes' 'Activation desired includes must be a non-empty unique array.')) | Out-Null }
            }
            $allowedPaths = Get-OperationObjectProperty $lifecycle 'allowed_paths'
            if (-not (Test-OperationArray $allowedPaths) -or @($allowedPaths).Count -lt 1) { $findings.Add((New-OperationFinding 'skill_lifecycle_paths_invalid' 'error' '$.lifecycle.allowed_paths' 'Skill lifecycle allowed_paths must be a non-empty array.')) | Out-Null }
            else {
                $normalizedPaths = @($allowedPaths | ForEach-Object { ([string]$_).Replace('/', '\') })
                if (@($normalizedPaths | Sort-Object -Unique).Count -ne $normalizedPaths.Count -or @($normalizedPaths | Where-Object { [System.IO.Path]::IsPathRooted($_) -or $_ -match '(^|\\)\.\.(\\|$)' }).Count -gt 0) { $findings.Add((New-OperationFinding 'skill_lifecycle_paths_invalid' 'error' '$.lifecycle.allowed_paths' 'Skill lifecycle paths must be unique contained relative paths.')) | Out-Null }
            }
            if (@($targets).Count -ne 1 -or @($actions).Count -ne 1 -or [string](Get-OperationObjectProperty $Plan 'mode') -ne 'apply') { $findings.Add((New-OperationFinding 'skill_lifecycle_shape_invalid' 'error' '$' 'Skill lifecycle operations require one target, one action, and apply mode.')) | Out-Null }
        }
    }
    $serialized = $Plan | ConvertTo-Json -Depth 30 -Compress
    if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding "sensitive_value_present" "error" "$" "Plan contains a sensitive value.")) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
function Test-OperationPlanFreshness {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [object[]]$CurrentTargets = @(),
        [string[]]$AuthorizedRoots = @(),
        [string]$CurrentSourceRevision
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $currentIndex = @{}
    foreach ($state in @($CurrentTargets)) { $currentIndex[([string](Get-OperationObjectProperty $state "target_ref")).ToLowerInvariant()] = $state }
    foreach ($target in @((Get-OperationObjectProperty $Plan "targets"))) {
        $targetRef = [string](Get-OperationObjectProperty $target "target_ref")
        $path = [string](Get-OperationObjectProperty $target "path")
        if (-not @($AuthorizedRoots | Where-Object { Test-OperationPathWithinRoot $path $_ }).Count) { $findings.Add((New-OperationFinding "target_out_of_root" "error" ("$.targets[{0}]" -f $targetRef) "Target is outside authorized roots.")) | Out-Null }
        $key = $targetRef.ToLowerInvariant()
        if (-not $currentIndex.ContainsKey($key)) { $findings.Add((New-OperationFinding "target_state_missing" "error" ("$.targets[{0}]" -f $targetRef) "Current target state is missing.")) | Out-Null; continue }
        $state = $currentIndex[$key]
        if ([string](Get-OperationObjectProperty $state "owner") -ne [string](Get-OperationObjectProperty $target "owner")) { $findings.Add((New-OperationFinding "target_owner_changed" "error" ("$.targets[{0}].owner" -f $targetRef) "Target owner changed.")) | Out-Null }
        $beforeHash = Get-OperationObjectProperty $target "before_hash"
        $exists = [bool](Get-OperationObjectProperty $state "exists")
        if ($null -eq $beforeHash -and $exists) { $findings.Add((New-OperationFinding "target_created_since_plan" "error" ("$.targets[{0}].before_hash" -f $targetRef) "Target now exists.")) | Out-Null }
        elseif ($null -ne $beforeHash -and (-not $exists -or [string](Get-OperationObjectProperty $state "current_hash") -ne [string]$beforeHash)) { $findings.Add((New-OperationFinding "target_hash_stale" "error" ("$.targets[{0}].before_hash" -f $targetRef) "Target hash changed.")) | Out-Null }
    }
    $sourceRevision = [string](Get-OperationObjectProperty $Plan "source_revision")
    if (-not [string]::IsNullOrWhiteSpace($sourceRevision) -and $sourceRevision -ne $CurrentSourceRevision) { $findings.Add((New-OperationFinding "source_revision_stale" "error" "$.source_revision" "Source revision changed.")) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
