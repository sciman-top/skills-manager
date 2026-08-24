$script:ExecutionAdmissionSchemaVersion = 2
$script:ExecutionAdmissionMode = 'multi_turn_user_decision'
$script:ExecutionAdmissionNativeAgent = 'design-griller'
$script:ExecutionAdmissionConversationOwner = 'parent'
$script:ExecutionAdmissionStopCondition = 'one_question_then_wait'

function New-ExecutionAdmissionFinding([string]$Code, [string]$Path, [string]$Message) {
    return New-OperationFinding $Code 'error' $Path $Message
}

function New-ExecutionAdmissionValidationResult([object[]]$Findings) {
    $all = @($Findings)
    return [pscustomobject][ordered]@{
        pass = (@($all | Where-Object { [string]$_.severity -eq 'error' }).Count -eq 0)
        findings = $all
    }
}

function Get-ExecutionAdmissionProperty($Object, [string]$Name) {
    # Get-OperationObjectProperty deliberately returns arrays as one pipeline
    # object. This module's callers consistently materialize collection fields
    # with @(...), so unwrap exactly that transport layer here.
    $value = Get-OperationObjectProperty $Object $Name
    return $value
}

function Test-ExecutionAdmissionArray($Value) {
    return Test-OperationArray $Value
}

function Get-ExecutionAdmissionCanonicalValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime().ToString('o') }
    if ($Value -is [datetime]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $result[$key] = Get-ExecutionAdmissionCanonicalValue $Value[$key]
        }
        return [pscustomobject]$result
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $result[[string]$property.Name] = Get-ExecutionAdmissionCanonicalValue $property.Value
        }
        return [pscustomobject]$result
    }
    if (Test-ExecutionAdmissionArray $Value) {
        $items = @($Value | ForEach-Object { Get-ExecutionAdmissionCanonicalValue $_ })
        return ,$items
    }
    return $Value
}

function ConvertTo-ExecutionAdmissionCanonicalJson($Value) {
    return ((Get-ExecutionAdmissionCanonicalValue $Value) | ConvertTo-Json -Depth 60 -Compress)
}

function Get-ExecutionAdmissionDigest([string]$Prefix, $Payload) {
    return ('{0}-{1}' -f $Prefix, (Get-OperationSha256 (ConvertTo-ExecutionAdmissionCanonicalJson $Payload)))
}

function Get-ExecutionAdmissionContractSnapshot($Contract) {
    return [pscustomobject][ordered]@{
        mode = [string](Get-ExecutionAdmissionProperty $Contract 'mode')
        native_agent = [string](Get-ExecutionAdmissionProperty $Contract 'native_agent')
        conversation_owner = [string](Get-ExecutionAdmissionProperty $Contract 'conversation_owner')
        stop_condition = [string](Get-ExecutionAdmissionProperty $Contract 'stop_condition')
    }
}

function Test-ExecutionAdmissionMultiTurnContract($Contract) {
    $snapshot = Get-ExecutionAdmissionContractSnapshot $Contract
    return $snapshot.mode -eq $script:ExecutionAdmissionMode -and
        $snapshot.native_agent -eq $script:ExecutionAdmissionNativeAgent -and
        $snapshot.conversation_owner -eq $script:ExecutionAdmissionConversationOwner -and
        $snapshot.stop_condition -eq $script:ExecutionAdmissionStopCondition
}

function Get-ExecutionAdmissionFileSnapshot {
    param(
        [Parameter(Mandatory = $true)][object[]]$Paths,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $root = [IO.Path]::GetFullPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw ('{0}_root_missing' -f $FieldName) }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($rawPath in @($Paths)) {
        $path = [string]$rawPath
        if ([string]::IsNullOrWhiteSpace($path) -or $path -match '[*?\[\]]') { throw ('{0}_path_invalid' -f $FieldName) }
        $fullPath = [IO.Path]::GetFullPath($path)
        if (-not (Test-OperationPathWithinRoot $fullPath $root)) { throw ('{0}_path_outside_repo' -f $FieldName) }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw ('{0}_file_missing' -f $FieldName) }
        $item = Get-Item -LiteralPath $fullPath -Force
        if ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('{0}_reparse_point' -f $FieldName) }
        if (-not $seen.Add($fullPath)) { throw ('{0}_path_duplicate' -f $FieldName) }
        $result.Add([pscustomobject][ordered]@{
            path = $fullPath
            sha256 = ([string](Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash).ToLowerInvariant()
        }) | Out-Null
    }
    if ($result.Count -eq 0) { throw ('{0}_empty' -f $FieldName) }
    return @($result.ToArray() | Sort-Object path)
}

function Get-ExecutionAdmissionValidationSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Validation,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    if (-not [bool](Get-ExecutionAdmissionProperty (Get-ExecutionAdmissionProperty $Validation 'load_validation') 'pass')) { throw 'load_validation_failed' }
    $receipt = Get-ExecutionAdmissionProperty $Validation 'routing_receipt'
    if ($null -eq $receipt -or [string](Get-ExecutionAdmissionProperty $receipt 'truth_boundary') -ne 'candidate_load_validated') { throw 'routing_receipt_not_load_validated' }
    $receiptId = [string](Get-ExecutionAdmissionProperty $receipt 'receipt_id')
    $queryHash = [string](Get-ExecutionAdmissionProperty $receipt 'query_sha256')
    $catalogFingerprint = [string](Get-ExecutionAdmissionProperty $receipt 'catalog_fingerprint')
    if ([string]::IsNullOrWhiteSpace($receiptId) -or $queryHash -notmatch '^[a-f0-9]{64}$' -or $catalogFingerprint -notmatch '^[a-f0-9]{64}$') { throw 'routing_receipt_identity_invalid' }

    $selected = @(Get-ExecutionAdmissionProperty $Validation 'selected')
    $closure = @(Get-ExecutionAdmissionProperty $Validation 'validated_closure')
    if ($selected.Count -ne 1) { throw 'selected_candidate_count_invalid' }
    if ($closure.Count -eq 0) { throw 'validated_closure_empty' }
    $selectedName = [string](Get-ExecutionAdmissionProperty $selected[0] 'name')
    $selectedPath = [string](Get-ExecutionAdmissionProperty $selected[0] 'path')
    if ([string]::IsNullOrWhiteSpace($selectedName) -or [string]::IsNullOrWhiteSpace($selectedPath)) { throw 'selected_candidate_invalid' }

    $contract = Get-ExecutionAdmissionContractSnapshot (Get-ExecutionAdmissionProperty $Validation 'execution_contract')
    $receiptContract = Get-ExecutionAdmissionContractSnapshot (Get-ExecutionAdmissionProperty $receipt 'execution_contract')
    if (-not (Test-ExecutionAdmissionMultiTurnContract $contract) -or (ConvertTo-ExecutionAdmissionCanonicalJson $contract) -ne (ConvertTo-ExecutionAdmissionCanonicalJson $receiptContract)) { throw 'execution_contract_invalid' }

    $closurePaths = New-Object System.Collections.Generic.List[string]
    $closureRows = New-Object System.Collections.Generic.List[object]
    $closureNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($member in @($closure)) {
        $name = [string](Get-ExecutionAdmissionProperty $member 'name')
        $path = [string](Get-ExecutionAdmissionProperty $member 'path')
        $availability = [string](Get-ExecutionAdmissionProperty $member 'availability')
        $sideEffect = [string](Get-ExecutionAdmissionProperty $member 'side_effect')
        $loadSideEffect = [string](Get-ExecutionAdmissionProperty $member 'load_side_effect')
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($path) -or -not $closureNames.Add($name)) { throw 'validated_closure_identity_invalid' }
        if ($availability -ne 'available' -or -not [bool](Get-ExecutionAdmissionProperty $member 'entrypoint_hash_validated') -or -not [bool](Get-ExecutionAdmissionProperty $member 'contained')) { throw 'validated_closure_unavailable' }
        if ($sideEffect -in @('unknown', 'external_read') -or $loadSideEffect -ne 'read_only') { throw 'validated_closure_side_effect_invalid' }
        $closurePaths.Add($path) | Out-Null
        $closureRows.Add([pscustomobject][ordered]@{
            name = $name
            path = $path
            availability = $availability
            load_side_effect = $loadSideEffect
            side_effect = $sideEffect
            dependencies = @((Get-ExecutionAdmissionProperty $member 'dependencies') | ForEach-Object { [string]$_ } | Sort-Object)
        }) | Out-Null
    }
    $entrypointSnapshots = Get-ExecutionAdmissionFileSnapshot -Paths $closurePaths.ToArray() -RepoRoot $RepoRoot -FieldName 'validated_closure'
    $snapshotsByPath = @{}
    foreach ($snapshot in @($entrypointSnapshots)) { $snapshotsByPath[[string]$snapshot.path] = [string]$snapshot.sha256 }
    $closureSnapshot = @($closureRows.ToArray() | ForEach-Object {
        [pscustomobject][ordered]@{
            name = $_.name
            path = $_.path
            entrypoint_sha256 = $snapshotsByPath[[string]$_.path]
            availability = $_.availability
            load_side_effect = $_.load_side_effect
            side_effect = $_.side_effect
            dependencies = @($_.dependencies)
        }
    } | Sort-Object name)
    if (@($closureSnapshot | Where-Object { $_.name -eq $selectedName -and $_.path -eq $selectedPath }).Count -ne 1) { throw 'selected_candidate_not_in_closure' }

    return [pscustomobject][ordered]@{
        routing_receipt_id = $receiptId
        request_sha256 = $queryHash
        catalog_fingerprint = $catalogFingerprint
        selected_candidate = $selectedName
        validated_closure = $closureSnapshot
        effective_execution_contract = $contract
    }
}

function Get-ExecutionAdmissionPayload($Admission) {
    return [pscustomobject][ordered]@{
        schema_version = Get-ExecutionAdmissionProperty $Admission 'schema_version'
        kind = Get-ExecutionAdmissionProperty $Admission 'kind'
        attempt_id = Get-ExecutionAdmissionProperty $Admission 'attempt_id'
        request_sha256 = Get-ExecutionAdmissionProperty $Admission 'request_sha256'
        admitted_goal = Get-ExecutionAdmissionProperty $Admission 'admitted_goal'
        authority_basis = Get-ExecutionAdmissionProperty $Admission 'authority_basis'
        issued_at = Get-ExecutionAdmissionProperty $Admission 'issued_at'
        requested_operation = Get-ExecutionAdmissionProperty $Admission 'requested_operation'
        exact_write_set = @(Get-ExecutionAdmissionProperty $Admission 'exact_write_set')
        allowed_read_set = @(Get-ExecutionAdmissionProperty $Admission 'allowed_read_set')
        minimum_proof = Get-ExecutionAdmissionProperty $Admission 'minimum_proof'
        stop_condition = Get-ExecutionAdmissionProperty $Admission 'stop_condition'
        validation_snapshot = Get-ExecutionAdmissionProperty $Admission 'validation_snapshot'
        prior_admission_id = Get-ExecutionAdmissionProperty $Admission 'prior_admission_id'
        attributable_user_answer_sha256 = Get-ExecutionAdmissionProperty $Admission 'attributable_user_answer_sha256'
    }
}

function New-ExecutionAdmission {
    param(
        [Parameter(Mandatory = $true)][string]$OriginalRequest,
        [Parameter(Mandatory = $true)][string]$AdmittedGoal,
        [Parameter(Mandatory = $true)]$Validation,
        [Parameter(Mandatory = $true)][object[]]$AllowedReadSet,
        [Parameter(Mandatory = $true)][string]$AuthorityBasis,
        [Parameter(Mandatory = $true)][string]$IssuedAt,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$PriorAdmissionId = '',
        [string]$AttributableUserAnswer = ''
    )

    if ([string]::IsNullOrWhiteSpace($OriginalRequest) -or [string]::IsNullOrWhiteSpace($AdmittedGoal) -or [string]::IsNullOrWhiteSpace($AuthorityBasis)) { throw 'admission_required_field_missing' }
    if (-not (Test-OperationRfc3339 $IssuedAt)) { throw 'admission_issued_at_invalid' }
    if (-not [string]::IsNullOrWhiteSpace($PriorAdmissionId) -and $PriorAdmissionId -notmatch '^adm-[a-f0-9]{64}$') { throw 'prior_admission_id_invalid' }

    $validationSnapshot = Get-ExecutionAdmissionValidationSnapshot -Validation $Validation -RepoRoot $RepoRoot
    $allowedReadSet = Get-ExecutionAdmissionFileSnapshot -Paths $AllowedReadSet -RepoRoot $RepoRoot -FieldName 'allowed_read_set'
    $admission = [pscustomobject][ordered]@{
        schema_version = $script:ExecutionAdmissionSchemaVersion
        kind = 'execution_admission'
        attempt_id = ([guid]::NewGuid().ToString('N')).ToLowerInvariant()
        request_sha256 = Get-OperationSha256 $OriginalRequest
        admitted_goal = $AdmittedGoal.Trim()
        authority_basis = $AuthorityBasis.Trim()
        issued_at = ([datetimeoffset]::Parse($IssuedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime().ToString('o')
        requested_operation = 'read_only'
        exact_write_set = @()
        allowed_read_set = $allowedReadSet
        minimum_proof = 'one native design-griller question, then await one user answer'
        stop_condition = $script:ExecutionAdmissionStopCondition
        validation_snapshot = $validationSnapshot
        prior_admission_id = $PriorAdmissionId
        attributable_user_answer_sha256 = if ([string]::IsNullOrWhiteSpace($AttributableUserAnswer)) { '' } else { Get-OperationSha256 $AttributableUserAnswer }
    }
    $admission | Add-Member -NotePropertyName admission_id -NotePropertyValue (Get-ExecutionAdmissionDigest 'adm' (Get-ExecutionAdmissionPayload $admission))
    $contract = Test-ExecutionAdmissionContract -Admission $admission -RepoRoot $RepoRoot
    if (-not $contract.pass) { throw ('execution_admission_invalid: {0}' -f ((@($contract.findings | ForEach-Object code) -join ','))) }
    return $admission
}

function Test-ExecutionAdmissionContract {
    param(
        [Parameter(Mandatory = $true)]$Admission,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Admission) { return New-ExecutionAdmissionValidationResult @((New-ExecutionAdmissionFinding 'admission_missing' '$' 'Admission is required.')) }
    if ((Get-ExecutionAdmissionProperty $Admission 'schema_version') -ne $script:ExecutionAdmissionSchemaVersion) { $findings.Add((New-ExecutionAdmissionFinding 'schema_version_invalid' '$.schema_version' ('Only execution admission schema version {0} is supported.' -f $script:ExecutionAdmissionSchemaVersion))) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Admission 'kind') -ne 'execution_admission') { $findings.Add((New-ExecutionAdmissionFinding 'kind_invalid' '$.kind' 'Admission kind is invalid.')) | Out-Null }
    foreach ($field in @('attempt_id', 'request_sha256', 'admitted_goal', 'authority_basis', 'issued_at', 'requested_operation', 'minimum_proof', 'stop_condition', 'admission_id')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ExecutionAdmissionProperty $Admission $field))) { $findings.Add((New-ExecutionAdmissionFinding 'required_field_missing' ('.{0}' -f $field) 'Required admission field is missing.')) | Out-Null }
    }
    if ([string](Get-ExecutionAdmissionProperty $Admission 'attempt_id') -notmatch '^[a-f0-9]{32}$') { $findings.Add((New-ExecutionAdmissionFinding 'attempt_id_invalid' '$.attempt_id' 'Attempt identity must be a 32-character lowercase hex nonce.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Admission 'request_sha256') -notmatch '^[a-f0-9]{64}$') { $findings.Add((New-ExecutionAdmissionFinding 'request_hash_invalid' '$.request_sha256' 'Request hash must be SHA-256.')) | Out-Null }
    if (-not (Test-OperationRfc3339 (Get-ExecutionAdmissionProperty $Admission 'issued_at'))) { $findings.Add((New-ExecutionAdmissionFinding 'issued_at_invalid' '$.issued_at' 'Issued timestamp must be RFC3339.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Admission 'requested_operation') -ne 'read_only') { $findings.Add((New-ExecutionAdmissionFinding 'requested_operation_invalid' '$.requested_operation' 'P0 only admits read_only.')) | Out-Null }
    $writeSet = Get-ExecutionAdmissionProperty $Admission 'exact_write_set'
    if ($null -ne $writeSet -and -not (Test-ExecutionAdmissionArray $writeSet)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$writeSet)) { $findings.Add((New-ExecutionAdmissionFinding 'read_only_write_set_not_empty' '$.exact_write_set' 'Read-only admission must carry an empty write set.')) | Out-Null }
        else { $findings.Add((New-ExecutionAdmissionFinding 'write_set_type_invalid' '$.exact_write_set' 'Write set must be an array.')) | Out-Null }
    }
    elseif (@($writeSet).Count -ne 0) { $findings.Add((New-ExecutionAdmissionFinding 'read_only_write_set_not_empty' '$.exact_write_set' 'Read-only admission must carry an empty write set.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Admission 'stop_condition') -ne $script:ExecutionAdmissionStopCondition) { $findings.Add((New-ExecutionAdmissionFinding 'stop_condition_invalid' '$.stop_condition' 'P0 must stop after one question.')) | Out-Null }
    $priorAdmissionId = [string](Get-ExecutionAdmissionProperty $Admission 'prior_admission_id')
    if (-not [string]::IsNullOrWhiteSpace($priorAdmissionId) -and $priorAdmissionId -notmatch '^adm-[a-f0-9]{64}$') { $findings.Add((New-ExecutionAdmissionFinding 'prior_admission_id_invalid' '$.prior_admission_id' 'Prior admission id must be content-addressed.')) | Out-Null }
    $answerHash = [string](Get-ExecutionAdmissionProperty $Admission 'attributable_user_answer_sha256')
    if ([string]::IsNullOrWhiteSpace($priorAdmissionId) -and -not [string]::IsNullOrWhiteSpace($answerHash)) { $findings.Add((New-ExecutionAdmissionFinding 'initial_admission_has_user_answer' '$.attributable_user_answer_sha256' 'Only a successor admission may bind a user answer.')) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($priorAdmissionId) -and $answerHash -notmatch '^[a-f0-9]{64}$') { $findings.Add((New-ExecutionAdmissionFinding 'successor_user_answer_missing' '$.attributable_user_answer_sha256' 'A successor admission must bind one attributable user answer hash.')) | Out-Null }

    $readSet = Get-ExecutionAdmissionProperty $Admission 'allowed_read_set'
    if (-not (Test-ExecutionAdmissionArray $readSet) -or @($readSet).Count -eq 0) { $findings.Add((New-ExecutionAdmissionFinding 'allowed_read_set_invalid' '$.allowed_read_set' 'Read set must be a non-empty array.')) | Out-Null }
    else {
        foreach ($entry in @($readSet)) {
            if ([string](Get-ExecutionAdmissionProperty $entry 'path') -match '[*?\[\]]' -or [string](Get-ExecutionAdmissionProperty $entry 'sha256') -notmatch '^[a-f0-9]{64}$') { $findings.Add((New-ExecutionAdmissionFinding 'allowed_read_set_entry_invalid' '$.allowed_read_set' 'Read set entries need exact paths and SHA-256 hashes.')) | Out-Null; break }
        }
    }
    $snapshot = Get-ExecutionAdmissionProperty $Admission 'validation_snapshot'
    if ($null -eq $snapshot -or [string](Get-ExecutionAdmissionProperty $snapshot 'selected_candidate') -eq '' -or [string](Get-ExecutionAdmissionProperty $snapshot 'catalog_fingerprint') -notmatch '^[a-f0-9]{64}$' -or -not (Test-ExecutionAdmissionMultiTurnContract (Get-ExecutionAdmissionProperty $snapshot 'effective_execution_contract'))) { $findings.Add((New-ExecutionAdmissionFinding 'validation_snapshot_invalid' '$.validation_snapshot' 'Validated selection snapshot is incomplete or has the wrong contract.')) | Out-Null }
    $closure = if ($null -eq $snapshot) { @() } else { @(Get-ExecutionAdmissionProperty $snapshot 'validated_closure') }
    if ($closure.Count -eq 0) { $findings.Add((New-ExecutionAdmissionFinding 'validated_closure_invalid' '$.validation_snapshot.validated_closure' 'Validated closure is required.')) | Out-Null }
    foreach ($entry in @($closure)) {
        if ([string](Get-ExecutionAdmissionProperty $entry 'entrypoint_sha256') -notmatch '^[a-f0-9]{64}$') { $findings.Add((New-ExecutionAdmissionFinding 'closure_entry_hash_invalid' '$.validation_snapshot.validated_closure' 'Closure entries require SHA-256 snapshots.')) | Out-Null; break }
    }
    $expectedId = Get-ExecutionAdmissionDigest 'adm' (Get-ExecutionAdmissionPayload $Admission)
    if ([string](Get-ExecutionAdmissionProperty $Admission 'admission_id') -ne $expectedId) { $findings.Add((New-ExecutionAdmissionFinding 'admission_id_mismatch' '$.admission_id' 'Admission id does not match its canonical immutable payload.')) | Out-Null }
    return New-ExecutionAdmissionValidationResult $findings.ToArray()
}

function Get-ExecutionPlanPayload($Plan) {
    $schemaVersion = Get-ExecutionAdmissionProperty $Plan 'schema_version'
    $kind = Get-ExecutionAdmissionProperty $Plan 'kind'
    $admissionId = Get-ExecutionAdmissionProperty $Plan 'admission_id'
    $adapter = Get-ExecutionAdmissionProperty $Plan 'adapter'
    $action = Get-ExecutionAdmissionProperty $Plan 'action'
    $effectiveContract = Get-ExecutionAdmissionProperty $Plan 'effective_execution_contract'
    $allowedReadSet = @(Get-ExecutionAdmissionProperty $Plan 'allowed_read_set')
    $minimumProof = Get-ExecutionAdmissionProperty $Plan 'minimum_proof'
    $stopCondition = Get-ExecutionAdmissionProperty $Plan 'stop_condition'
    $revalidationSnapshot = Get-ExecutionAdmissionProperty $Plan 'revalidation_snapshot'
    return [pscustomobject][ordered]@{
        schema_version = $schemaVersion
        kind = $kind
        admission_id = $admissionId
        adapter = $adapter
        action = $action
        effective_execution_contract = $effectiveContract
        allowed_read_set = $allowedReadSet
        minimum_proof = $minimumProof
        stop_condition = $stopCondition
        revalidation_snapshot = $revalidationSnapshot
    }
}

function New-ExecutionPlan {
    param([Parameter(Mandatory = $true)]$Admission)

    $readSet = @(Get-ExecutionAdmissionProperty $Admission 'allowed_read_set')
    if ($readSet.Count -eq 0) { throw 'execution_plan_read_set_missing' }

    # The read set has already been containment-checked when the immutable
    # admission was created. Locate the actual repository root instead of
    # assuming a fixed number of parent directories from its first file.
    $currentDirectory = Split-Path -Path ([string](Get-ExecutionAdmissionProperty $readSet[0] 'path')) -Parent
    $repoRoot = ''
    while (-not [string]::IsNullOrWhiteSpace($currentDirectory)) {
        if (Test-Path -LiteralPath (Join-Path $currentDirectory 'skills.json') -PathType Leaf) {
            $repoRoot = $currentDirectory
            break
        }
        $parentDirectory = Split-Path -Path $currentDirectory -Parent
        if ([string]::Equals($parentDirectory, $currentDirectory, [StringComparison]::OrdinalIgnoreCase)) { break }
        $currentDirectory = $parentDirectory
    }
    if ([string]::IsNullOrWhiteSpace($repoRoot)) { throw 'execution_plan_repo_root_unresolved' }

    $admissionContract = Test-ExecutionAdmissionContract -Admission $Admission -RepoRoot $repoRoot
    if (-not $admissionContract.pass) { throw ('execution_admission_invalid: {0}' -f ((@($admissionContract.findings | ForEach-Object code) -join ','))) }
    $snapshot = Get-ExecutionAdmissionProperty $Admission 'validation_snapshot'
    $planAdmissionId = [string](Get-ExecutionAdmissionProperty $Admission 'admission_id')
    $planContract = Get-ExecutionAdmissionProperty $snapshot 'effective_execution_contract'
    $planReadSet = @(Get-ExecutionAdmissionProperty $Admission 'allowed_read_set')
    $planMinimumProof = [string](Get-ExecutionAdmissionProperty $Admission 'minimum_proof')
    $planStopCondition = [string](Get-ExecutionAdmissionProperty $Admission 'stop_condition')
    $planRoutingReceiptId = [string](Get-ExecutionAdmissionProperty $snapshot 'routing_receipt_id')
    $planCatalogFingerprint = [string](Get-ExecutionAdmissionProperty $snapshot 'catalog_fingerprint')
    $planSelectedCandidate = [string](Get-ExecutionAdmissionProperty $snapshot 'selected_candidate')
    $planValidatedClosure = @(Get-ExecutionAdmissionProperty $snapshot 'validated_closure')
    $planRevalidationSnapshot = [pscustomobject][ordered]@{
        routing_receipt_id = $planRoutingReceiptId
        catalog_fingerprint = $planCatalogFingerprint
        selected_candidate = $planSelectedCandidate
        validated_closure = $planValidatedClosure
        effective_execution_contract = $planContract
    }
    $executionPlan = [pscustomobject][ordered]@{
        schema_version = $script:ExecutionAdmissionSchemaVersion
        kind = 'execution_plan'
        admission_id = $planAdmissionId
        adapter = $script:ExecutionAdmissionNativeAgent
        action = 'ask_one_question'
        effective_execution_contract = $planContract
        allowed_read_set = $planReadSet
        minimum_proof = $planMinimumProof
        stop_condition = $planStopCondition
        revalidation_snapshot = $planRevalidationSnapshot
    }
    $executionPlan | Add-Member -NotePropertyName plan_id -NotePropertyValue (Get-ExecutionAdmissionDigest 'plan' (Get-ExecutionPlanPayload $executionPlan))
    return $executionPlan
}

function Test-ExecutionPlanContract {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Admission
    )

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan) { return New-ExecutionAdmissionValidationResult @((New-ExecutionAdmissionFinding 'plan_missing' '$' 'Execution plan is required.')) }
    if ((Get-ExecutionAdmissionProperty $Plan 'schema_version') -ne $script:ExecutionAdmissionSchemaVersion -or [string](Get-ExecutionAdmissionProperty $Plan 'kind') -ne 'execution_plan') { $findings.Add((New-ExecutionAdmissionFinding 'plan_schema_invalid' '$' 'Execution plan schema is invalid.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Plan 'admission_id') -ne [string](Get-ExecutionAdmissionProperty $Admission 'admission_id')) { $findings.Add((New-ExecutionAdmissionFinding 'plan_admission_mismatch' '$.admission_id' 'Plan is not bound to its admission.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Plan 'adapter') -ne $script:ExecutionAdmissionNativeAgent -or [string](Get-ExecutionAdmissionProperty $Plan 'action') -ne 'ask_one_question') { $findings.Add((New-ExecutionAdmissionFinding 'plan_dispatch_invalid' '$' 'P0 may dispatch only one design-griller question.')) | Out-Null }
    if (-not (Test-ExecutionAdmissionMultiTurnContract (Get-ExecutionAdmissionProperty $Plan 'effective_execution_contract'))) { $findings.Add((New-ExecutionAdmissionFinding 'plan_contract_invalid' '$.effective_execution_contract' 'Plan contract is invalid.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $Plan 'stop_condition') -ne $script:ExecutionAdmissionStopCondition) { $findings.Add((New-ExecutionAdmissionFinding 'plan_stop_invalid' '$.stop_condition' 'Plan stop condition is invalid.')) | Out-Null }
    $expectedId = Get-ExecutionAdmissionDigest 'plan' (Get-ExecutionPlanPayload $Plan)
    if ([string](Get-ExecutionAdmissionProperty $Plan 'plan_id') -ne $expectedId) { $findings.Add((New-ExecutionAdmissionFinding 'plan_id_mismatch' '$.plan_id' 'Plan id does not match its canonical payload.')) | Out-Null }
    return New-ExecutionAdmissionValidationResult $findings.ToArray()
}

function Test-ExecutionAdmissionRevalidation {
    param(
        [Parameter(Mandatory = $true)]$Admission,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Validation,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @((Test-ExecutionAdmissionContract -Admission $Admission -RepoRoot $RepoRoot).findings)) { $findings.Add($finding) | Out-Null }
    foreach ($finding in @((Test-ExecutionPlanContract -Plan $Plan -Admission $Admission).findings)) { $findings.Add($finding) | Out-Null }
    if ($findings.Count -gt 0) { return [pscustomobject][ordered]@{ pass = $false; disposition = 'reject'; findings = @($findings.ToArray()) } }

    $storedSnapshot = Get-ExecutionAdmissionProperty $Admission 'validation_snapshot'
    try {
        $currentSnapshot = Get-ExecutionAdmissionValidationSnapshot -Validation $Validation -RepoRoot $RepoRoot
        if ((ConvertTo-ExecutionAdmissionCanonicalJson $currentSnapshot) -ne (ConvertTo-ExecutionAdmissionCanonicalJson $storedSnapshot)) { $findings.Add((New-ExecutionAdmissionFinding 'validation_snapshot_drift' '$.validation_snapshot' 'Current router validation differs from the admitted snapshot.')) | Out-Null }
    }
    catch { $findings.Add((New-ExecutionAdmissionFinding 'current_validation_invalid' '$.validation' $_.Exception.Message)) | Out-Null }

    $storedFiles = @((Get-ExecutionAdmissionProperty $storedSnapshot 'validated_closure') | ForEach-Object { [pscustomobject]@{ path = [string]$_.path; sha256 = [string]$_.entrypoint_sha256; code = 'closure_hash_drift' } }) + @((Get-ExecutionAdmissionProperty $Admission 'allowed_read_set') | ForEach-Object { [pscustomobject]@{ path = [string]$_.path; sha256 = [string]$_.sha256; code = 'read_set_hash_drift' } })
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($storedFiles)) {
        if (-not $seen.Add([string]$entry.path)) { continue }
        if (-not (Test-Path -LiteralPath ([string]$entry.path) -PathType Leaf)) { $findings.Add((New-ExecutionAdmissionFinding ([string]$entry.code) '$.snapshot' ('Snapshot file is missing: {0}' -f $entry.path))) | Out-Null; continue }
        $actualHash = ([string](Get-FileHash -LiteralPath ([string]$entry.path) -Algorithm SHA256).Hash).ToLowerInvariant()
        if ($actualHash -ne [string]$entry.sha256) { $findings.Add((New-ExecutionAdmissionFinding ([string]$entry.code) '$.snapshot' ('Snapshot file hash changed: {0}' -f $entry.path))) | Out-Null }
    }
    return [pscustomobject][ordered]@{ pass = ($findings.Count -eq 0); disposition = $(if ($findings.Count -eq 0) { 'admit' } else { 'reject' }); findings = @($findings.ToArray()) }
}

function Test-ExecutionAdmissionContinuation {
    param(
        [Parameter(Mandatory = $true)]$PriorAdmission,
        [Parameter(Mandatory = $true)]$PriorPlan,
        [Parameter(Mandatory = $true)]$SuccessorAdmission,
        [Parameter(Mandatory = $true)]$SuccessorPlan,
        [Parameter(Mandatory = $true)]$Validation,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @((Test-ExecutionAdmissionRevalidation -Admission $PriorAdmission -Plan $PriorPlan -Validation $Validation -RepoRoot $RepoRoot).findings)) { $findings.Add($finding) | Out-Null }
    foreach ($finding in @((Test-ExecutionAdmissionRevalidation -Admission $SuccessorAdmission -Plan $SuccessorPlan -Validation $Validation -RepoRoot $RepoRoot).findings)) { $findings.Add($finding) | Out-Null }
    if ($findings.Count -gt 0) { return [pscustomobject][ordered]@{ pass = $false; disposition = 'reject'; findings = @($findings.ToArray()) } }

    $priorId = [string](Get-ExecutionAdmissionProperty $PriorAdmission 'admission_id')
    $successorId = [string](Get-ExecutionAdmissionProperty $SuccessorAdmission 'admission_id')
    if ($priorId -eq $successorId) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_admission_reused' '$.admission_id' 'A continuation must receive a new admission identity.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $PriorAdmission 'attempt_id') -eq [string](Get-ExecutionAdmissionProperty $SuccessorAdmission 'attempt_id')) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_attempt_reused' '$.attempt_id' 'A continuation must receive a new attempt identity.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $SuccessorAdmission 'prior_admission_id') -ne $priorId) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_prior_admission_mismatch' '$.prior_admission_id' 'Successor must bind the exact predecessor admission.')) | Out-Null }
    if ([string](Get-ExecutionAdmissionProperty $SuccessorAdmission 'attributable_user_answer_sha256') -notmatch '^[a-f0-9]{64}$') { $findings.Add((New-ExecutionAdmissionFinding 'continuation_user_answer_missing' '$.attributable_user_answer_sha256' 'Successor must bind an attributable user answer hash.')) | Out-Null }
    foreach ($field in @('request_sha256', 'admitted_goal', 'authority_basis', 'requested_operation', 'minimum_proof', 'stop_condition')) {
        if ([string](Get-ExecutionAdmissionProperty $PriorAdmission $field) -ne [string](Get-ExecutionAdmissionProperty $SuccessorAdmission $field)) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_scope_changed' ('.{0}' -f $field) 'Continuation cannot change the admitted scope.')) | Out-Null }
    }
    if ((ConvertTo-ExecutionAdmissionCanonicalJson @(Get-ExecutionAdmissionProperty $PriorAdmission 'allowed_read_set')) -ne (ConvertTo-ExecutionAdmissionCanonicalJson @(Get-ExecutionAdmissionProperty $SuccessorAdmission 'allowed_read_set'))) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_read_set_changed' '$.allowed_read_set' 'Continuation cannot widen or alter the exact read set.')) | Out-Null }
    if ((ConvertTo-ExecutionAdmissionCanonicalJson (Get-ExecutionAdmissionProperty $PriorAdmission 'validation_snapshot')) -ne (ConvertTo-ExecutionAdmissionCanonicalJson (Get-ExecutionAdmissionProperty $SuccessorAdmission 'validation_snapshot'))) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_validation_snapshot_changed' '$.validation_snapshot' 'Continuation requires the same current validated selection.')) | Out-Null }
    try {
        $priorIssuedAt = [datetimeoffset]::Parse([string](Get-ExecutionAdmissionProperty $PriorAdmission 'issued_at'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $successorIssuedAt = [datetimeoffset]::Parse([string](Get-ExecutionAdmissionProperty $SuccessorAdmission 'issued_at'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($successorIssuedAt -le $priorIssuedAt) { $findings.Add((New-ExecutionAdmissionFinding 'continuation_issued_at_not_later' '$.issued_at' 'Successor must be issued after its predecessor.')) | Out-Null }
    }
    catch { $findings.Add((New-ExecutionAdmissionFinding 'continuation_issued_at_invalid' '$.issued_at' 'Continuation timestamps must be comparable RFC3339 values.')) | Out-Null }
    return [pscustomobject][ordered]@{ pass = ($findings.Count -eq 0); disposition = $(if ($findings.Count -eq 0) { 'admit' } else { 'reject' }); findings = @($findings.ToArray()) }
}

function New-ExecutionAdmissionSuccessor {
    param(
        [Parameter(Mandatory = $true)]$PriorAdmission,
        [Parameter(Mandatory = $true)]$PriorPlan,
        [Parameter(Mandatory = $true)][string]$OriginalRequest,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$AttributableUserAnswer,
        [Parameter(Mandatory = $true)]$Validation,
        [Parameter(Mandatory = $true)][string]$IssuedAt,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($AttributableUserAnswer)) { throw 'attributable_user_answer_missing' }
    $priorRevalidation = Test-ExecutionAdmissionRevalidation -Admission $PriorAdmission -Plan $PriorPlan -Validation $Validation -RepoRoot $RepoRoot
    if (-not $priorRevalidation.pass) { throw ('continuation_predecessor_not_revalidated: {0}' -f ((@($priorRevalidation.findings | ForEach-Object code) -join ','))) }
    if ((Get-OperationSha256 $OriginalRequest) -ne [string](Get-ExecutionAdmissionProperty $PriorAdmission 'request_sha256')) { throw 'continuation_request_mismatch' }

    $successor = New-ExecutionAdmission -OriginalRequest $OriginalRequest -AdmittedGoal ([string](Get-ExecutionAdmissionProperty $PriorAdmission 'admitted_goal')) -Validation $Validation -AllowedReadSet @((Get-ExecutionAdmissionProperty $PriorAdmission 'allowed_read_set') | ForEach-Object { [string](Get-ExecutionAdmissionProperty $_ 'path') }) -AuthorityBasis ([string](Get-ExecutionAdmissionProperty $PriorAdmission 'authority_basis')) -IssuedAt $IssuedAt -RepoRoot $RepoRoot -PriorAdmissionId ([string](Get-ExecutionAdmissionProperty $PriorAdmission 'admission_id')) -AttributableUserAnswer $AttributableUserAnswer
    $successorPlan = New-ExecutionPlan -Admission $successor
    $continuation = Test-ExecutionAdmissionContinuation -PriorAdmission $PriorAdmission -PriorPlan $PriorPlan -SuccessorAdmission $successor -SuccessorPlan $successorPlan -Validation $Validation -RepoRoot $RepoRoot
    if (-not $continuation.pass) { throw ('execution_admission_continuation_invalid: {0}' -f ((@($continuation.findings | ForEach-Object code) -join ','))) }
    return [pscustomobject][ordered]@{
        admission = $successor
        plan = $successorPlan
        enforcement = 'parent_side_soft_guard_only'
    }
}
