$qualityGateIntegrityErrorAction = 'Stop'

function Invoke-QualityGateGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $isWriteTree = $Arguments.Count -eq 1 -and [string]::Equals($Arguments[0], 'write-tree', [StringComparison]::Ordinal)
    $maxAttempts = if ($isWriteTree) { 10 } else { 1 }
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $output = @(& git -C $RepoRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
        $outputText = ($output -join [Environment]::NewLine).Trim()
        if ($exitCode -eq 0) { return $outputText }

        $transientIndexLock = $isWriteTree -and $outputText -match '(?i)index\.lock' -and
            $outputText -match '(?i)(unable to create|file exists|another git process)'
        if ($transientIndexLock -and $attempt -lt $maxAttempts) {
            Start-Sleep -Milliseconds 100
            continue
        }

        $detail = if ([string]::IsNullOrWhiteSpace($outputText)) { 'no diagnostic output' } else { $outputText }
        throw ('git command failed: git -C {0} {1}: {2}' -f $RepoRoot, ($Arguments -join ' '), $detail)
    }
}

function Get-QualityGateUntrackedFingerprint {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $paths = @(& git -C $RepoRoot -c core.quotepath=false ls-files --others --exclude-standard -- 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('git command failed while listing untracked source: {0}' -f $RepoRoot) }
    $entries = [Collections.Generic.List[string]]::new()
    $rootPrefix = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($relativePath in @($paths | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepoRoot $relativePath))
        if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw ('Untracked source path is invalid or escapes the repository: {0}' -f $relativePath)
        }
        $contentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath).Hash.ToLowerInvariant()
        $entries.Add(('{0}`0{1}' -f $relativePath.Replace('\', '/'), $contentHash)) | Out-Null
    }
    $canonical = $entries -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    $hash = ([Security.Cryptography.SHA256]::HashData($bytes) | ForEach-Object ToString x2) -join ''
    return [pscustomobject][ordered]@{
        fingerprint = $hash.ToLowerInvariant()
        file_count = $entries.Count
    }
}

function Get-QualityGateSourceFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $resolvedRoot = [IO.Path]::GetFullPath($RepoRoot)
    $head = Invoke-QualityGateGit $resolvedRoot @('rev-parse', 'HEAD')
    $indexTree = Invoke-QualityGateGit $resolvedRoot @('write-tree')
    $trackedOutput = @(& git -C $resolvedRoot diff --binary --no-ext-diff --no-color --no-renames HEAD -- 2>$null)
    if ($LASTEXITCODE -ne 0) { throw ('git command failed: git -C {0} diff --binary --no-ext-diff --no-color --no-renames HEAD --' -f $resolvedRoot) }
    $trackedDiff = ($trackedOutput -join [Environment]::NewLine).Trim()
    $trackedBytes = [Text.Encoding]::UTF8.GetBytes($trackedDiff)
    $trackedHash = ([Security.Cryptography.SHA256]::HashData($trackedBytes) | ForEach-Object ToString x2) -join ''
    $untracked = Get-QualityGateUntrackedFingerprint -RepoRoot $resolvedRoot
    return [pscustomobject][ordered]@{
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        repo_root = $resolvedRoot
        head = $head
        index_fingerprint = $indexTree
        tracked_worktree_fingerprint = $trackedHash.ToLowerInvariant()
        untracked_worktree_fingerprint = $untracked.fingerprint
        untracked_file_count = $untracked.file_count
    }
}

function Compare-QualityGateSourceFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Start,
        [Parameter(Mandatory = $true)]$End
    )

    $changed = [Collections.Generic.List[string]]::new()
    foreach ($field in @('head', 'index_fingerprint', 'tracked_worktree_fingerprint', 'untracked_worktree_fingerprint')) {
        if (-not [string]::Equals([string]$Start.$field, [string]$End.$field, [StringComparison]::Ordinal)) { $changed.Add($field) | Out-Null }
    }
    return [pscustomobject][ordered]@{
        pass = ($changed.Count -eq 0)
        code = if ($changed.Count -eq 0) { 'quality_gate_source_stable' } else { 'quality_gate_source_drift' }
        changed_fields = [object[]]@($changed.ToArray())
        start = $Start
        end = $End
    }
}

function Get-QualityGateObjectProperty {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)

    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-QualityGatePathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return [string]::Equals($fullPath, $fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith(($fullRoot + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Get-QualityGateSourceBinding {
    param([Parameter(Mandatory = $true)]$Source)

    return [ordered]@{
        repo_root = [IO.Path]::GetFullPath([string](Get-QualityGateObjectProperty $Source 'repo_root'))
        head = ([string](Get-QualityGateObjectProperty $Source 'head')).ToLowerInvariant()
        index_fingerprint = ([string](Get-QualityGateObjectProperty $Source 'index_fingerprint')).ToLowerInvariant()
        tracked_worktree_fingerprint = ([string](Get-QualityGateObjectProperty $Source 'tracked_worktree_fingerprint')).ToLowerInvariant()
        untracked_worktree_fingerprint = ([string](Get-QualityGateObjectProperty $Source 'untracked_worktree_fingerprint')).ToLowerInvariant()
    }
}

function Get-QualityGateSourceBindingSha256 {
    param([Parameter(Mandatory = $true)]$Source)

    $canonical = Get-QualityGateSourceBinding $Source | ConvertTo-Json -Compress
    return (([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)) | ForEach-Object ToString x2) -join '').ToLowerInvariant()
}

function Assert-QualityGateSourceFingerprint {
    param([Parameter(Mandatory = $true)]$Source, [Parameter(Mandatory = $true)][string]$Label)

    $repoRoot = [string](Get-QualityGateObjectProperty $Source 'repo_root')
    if ([string]::IsNullOrWhiteSpace($repoRoot)) { throw ("{0}.repo_root is required." -f $Label) }
    $binding = Get-QualityGateSourceBinding $Source
    foreach ($field in @('head', 'index_fingerprint')) {
        if ([string]$binding[$field] -notmatch '^[0-9a-f]{40,64}$') { throw ("{0}.{1} is not a Git object id." -f $Label, $field) }
    }
    foreach ($field in @('tracked_worktree_fingerprint', 'untracked_worktree_fingerprint')) {
        if ([string]$binding[$field] -notmatch '^[0-9a-f]{64}$') { throw ("{0}.{1} is not a SHA-256 value." -f $Label, $field) }
    }
    return $binding
}

function Assert-QualityGateResults {
    param([object[]]$GateResults, [string]$Status)

    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $failed = [Collections.Generic.List[string]]::new()
    foreach ($gate in @($GateResults)) {
        $name = ([string](Get-QualityGateObjectProperty $gate 'name')).Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or -not $names.Add($name)) { throw 'Quality gate results require unique non-empty names.' }
        $elapsed = Get-QualityGateObjectProperty $gate 'elapsed_ms'
        if ($null -eq $elapsed -or [long]$elapsed -lt 0) { throw ("Quality gate elapsed_ms is invalid: {0}" -f $name) }
        if ((Get-QualityGateObjectProperty $gate 'passed') -ne $true) { $failed.Add($name) | Out-Null }
    }
    if ($Status -eq 'passed' -and (@($GateResults).Count -eq 0 -or $failed.Count -gt 0)) {
        throw ("A passed quality receipt requires non-empty all-passing gates. failed={0}" -f ($failed -join ','))
    }
}

function Get-QualityGateTimingBinding {
    param(
        [Parameter(Mandatory = $true)][string]$TimingReportPath,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)]$SourceStart
    )

    $path = [IO.Path]::GetFullPath($TimingReportPath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ("Quality gate timing report does not exist: {0}" -f $path) }
    $sourceBinding = Assert-QualityGateSourceFingerprint $SourceStart 'source_start'
    if (-not (Test-QualityGatePathWithinRoot $path ([string]$sourceBinding.repo_root))) { throw 'Quality gate timing report must stay inside the source repository.' }
    try { $timing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ("Quality gate timing report is invalid JSON: {0}" -f $_.Exception.Message) }
    if ([int](Get-QualityGateObjectProperty $timing 'schema_version') -lt 3) { throw 'Quality gate timing report schema version 3 or newer is required.' }
    if (-not [string]::Equals([string](Get-QualityGateObjectProperty $timing 'quality_gate_run_id'), $RunId, [StringComparison]::Ordinal)) { throw 'Quality gate timing report run id does not match.' }
    $timingSource = Get-QualityGateObjectProperty $timing 'quality_gate_source_start'
    if ($null -eq $timingSource -or -not [string]::Equals((Get-QualityGateSourceBindingSha256 $timingSource), (Get-QualityGateSourceBindingSha256 $SourceStart), [StringComparison]::Ordinal)) {
        throw 'Quality gate timing report source binding does not match.'
    }
    return [ordered]@{
        status = 'bound'
        run_id = $RunId
        path = $path
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        source_binding_sha256 = Get-QualityGateSourceBindingSha256 $SourceStart
    }
}

function New-QualityGateIntegrityFinding([string]$Code, [string]$Message) {
    return [pscustomobject][ordered]@{ code = $Code; message = $Message }
}

function Assert-QualityGateCurrentReceiptSemantics {
    param(
        [Parameter(Mandatory = $true)]$Pointer,
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $repo = [IO.Path]::GetFullPath($RepoRoot)
    $profile = [string](Get-QualityGateObjectProperty $Receipt 'profile')
    $status = [string](Get-QualityGateObjectProperty $Receipt 'status')
    if ($profile -notin @('quick', 'full')) { throw 'Receipt profile is invalid.' }
    if ($status -notin @('passed', 'failed', 'source_drift', 'terminal_evidence_unavailable')) { throw 'Receipt status is invalid.' }

    $sourceStart = Get-QualityGateObjectProperty $Receipt 'source_start'
    $sourceEnd = Get-QualityGateObjectProperty $Receipt 'source_end'
    $startBinding = Assert-QualityGateSourceFingerprint $sourceStart 'receipt.source_start'
    $endBinding = Assert-QualityGateSourceFingerprint $sourceEnd 'receipt.source_end'
    if (-not [string]::Equals([string]$startBinding.repo_root, $repo, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$endBinding.repo_root, $repo, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Receipt source root does not match the repository being verified.'
    }
    $sourceBindingSha256 = Get-QualityGateSourceBindingSha256 $sourceStart
    if (-not [string]::Equals($sourceBindingSha256, [string](Get-QualityGateObjectProperty $Receipt 'source_binding_sha256'), [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($sourceBindingSha256, [string](Get-QualityGateObjectProperty $Pointer 'source_binding_sha256'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Receipt source binding hash is invalid.'
    }

    $actualComparison = Compare-QualityGateSourceFingerprint -Start $sourceStart -End $sourceEnd
    $storedComparison = Get-QualityGateObjectProperty $Receipt 'source_comparison'
    $actualChanged = @($actualComparison.changed_fields | ForEach-Object { [string]$_ } | Sort-Object)
    $storedChanged = @((Get-QualityGateObjectProperty $storedComparison 'changed_fields') | ForEach-Object { [string]$_ } | Sort-Object)
    if ($null -eq $storedComparison -or (Get-QualityGateObjectProperty $storedComparison 'pass') -ne [bool]$actualComparison.pass -or
        [string](Get-QualityGateObjectProperty $storedComparison 'code') -ne [string]$actualComparison.code -or
        ($actualChanged -join "`n") -ne ($storedChanged -join "`n")) {
        throw 'Receipt source comparison does not match its source fingerprints.'
    }
    if ($status -eq 'passed' -and -not [bool]$actualComparison.pass) { throw 'Passed receipt contains source drift.' }
    if ($status -eq 'source_drift' -and [bool]$actualComparison.pass) { throw 'source_drift receipt contains no source drift.' }

    Assert-QualityGateResults -GateResults @((Get-QualityGateObjectProperty $Receipt 'gates')) -Status $status
    if ($status -eq 'passed' -and -not [string]::IsNullOrWhiteSpace([string](Get-QualityGateObjectProperty $Receipt 'error_message'))) {
        throw 'Passed receipt contains an error message.'
    }
    $started = [DateTimeOffset]::MinValue
    $completed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string](Get-QualityGateObjectProperty $Receipt 'started_at'), [ref]$started) -or
        -not [DateTimeOffset]::TryParse([string](Get-QualityGateObjectProperty $Receipt 'completed_at'), [ref]$completed) -or $completed -lt $started) {
        throw 'Receipt timestamps are invalid.'
    }

    $timing = Get-QualityGateObjectProperty $Receipt 'test_timing'
    if ($profile -eq 'full' -and $status -eq 'passed' -and $null -eq $timing) { throw 'Passed full receipt has no timing binding.' }
    if ($null -ne $timing) {
        $actualTiming = Get-QualityGateTimingBinding -TimingReportPath ([string](Get-QualityGateObjectProperty $timing 'path')) `
            -RunId ([string](Get-QualityGateObjectProperty $Receipt 'run_id')) -SourceStart $sourceStart
        $pointerTiming = Get-QualityGateObjectProperty $Pointer 'test_timing'
        foreach ($field in @('status', 'run_id', 'path', 'sha256', 'source_binding_sha256')) {
            $actualValue = [string]$actualTiming[$field]
            if (-not [string]::Equals($actualValue, [string](Get-QualityGateObjectProperty $timing $field), [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals($actualValue, [string](Get-QualityGateObjectProperty $pointerTiming $field), [StringComparison]::OrdinalIgnoreCase)) {
                throw ("Receipt timing binding is invalid: {0}." -f $field)
            }
        }
    }
}

function Write-QualityGateJsonAtomic {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporary = '{0}.tmp.{1}' -f $Path, ([guid]::NewGuid().ToString('N'))
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $utf8)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Write-QualityGateImmutableReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReceiptRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('quick', 'full')][string]$Profile,
        [Parameter(Mandatory = $true)][ValidateSet('passed', 'failed', 'source_drift', 'terminal_evidence_unavailable')][string]$Status,
        [Parameter(Mandatory = $true)]$SourceStart,
        [Parameter(Mandatory = $true)]$SourceEnd,
        [object[]]$GateResults = @(),
        [string]$StartedAt = ([DateTimeOffset]::UtcNow.ToString('o')),
        [string]$CompletedAt = ([DateTimeOffset]::UtcNow.ToString('o')),
        [bool]$AllowDirtyWorktree = $false,
        [string]$ErrorMessage = '',
        [string]$TimingReportPath = ''
    )

    $root = [IO.Path]::GetFullPath($ReceiptRoot)
    if ($RunId -notmatch '^qgr-[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') { throw 'Quality gate run id is unsafe or invalid.' }
    $receiptPath = Join-Path $root ('{0}.json' -f $RunId)
    $pointerPath = Join-Path $root 'current.json'
    if (-not (Test-QualityGatePathWithinRoot $receiptPath $root)) { throw 'Quality gate receipt path escaped the receipt root.' }
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) { throw ('Immutable quality gate receipt already exists: {0}' -f $receiptPath) }
    $sourceStartBinding = Assert-QualityGateSourceFingerprint $SourceStart 'source_start'
    $sourceEndBinding = Assert-QualityGateSourceFingerprint $SourceEnd 'source_end'
    if (-not [string]::Equals([string]$sourceStartBinding.repo_root, [string]$sourceEndBinding.repo_root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Quality gate source roots do not match.' }
    $comparison = Compare-QualityGateSourceFingerprint -Start $SourceStart -End $SourceEnd
    Assert-QualityGateResults -GateResults @($GateResults) -Status $Status
    $started = [DateTimeOffset]::MinValue
    $completed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($StartedAt, [ref]$started) -or -not [DateTimeOffset]::TryParse($CompletedAt, [ref]$completed) -or $completed -lt $started) { throw 'Quality gate receipt timestamps are invalid.' }
    if ($Status -eq 'passed' -and -not [bool]$comparison.pass) { throw 'A passed quality receipt cannot contain source drift.' }
    if ($Status -eq 'passed' -and -not [string]::IsNullOrWhiteSpace($ErrorMessage)) { throw 'A passed quality receipt cannot contain an error message.' }
    if ($Status -eq 'source_drift' -and [bool]$comparison.pass) { throw 'source_drift status requires an observed source change.' }
    if ($Profile -eq 'full' -and $Status -eq 'passed' -and [string]::IsNullOrWhiteSpace($TimingReportPath)) { throw 'A passed full quality receipt requires a bound timing report.' }
    $timingBinding = if ([string]::IsNullOrWhiteSpace($TimingReportPath)) { $null } else { Get-QualityGateTimingBinding -TimingReportPath $TimingReportPath -RunId $RunId -SourceStart $SourceStart }
    $receipt = [ordered]@{
        schema_version = 2
        receipt_type = 'quality_gate_run'
        immutable = $true
        run_id = $RunId
        profile = $Profile
        status = $Status
        allow_dirty_worktree = $AllowDirtyWorktree
        error_message = $ErrorMessage
        started_at = $StartedAt
        completed_at = $CompletedAt
        source_start = $SourceStart
        source_end = $SourceEnd
        source_comparison = $comparison
        source_binding_sha256 = Get-QualityGateSourceBindingSha256 $SourceStart
        test_timing = $timingBinding
        gates = [object[]]@($GateResults)
    }
    Write-QualityGateJsonAtomic -Path $receiptPath -Value $receipt
    $receiptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant()
    $pointer = [ordered]@{
        schema_version = 2
        pointer_type = 'latest_quality_gate_receipt'
        run_id = $RunId
        profile = $Profile
        status = $Status
        receipt_path = $receiptPath
        receipt_sha256 = $receiptHash
        source_binding_sha256 = [string]$receipt.source_binding_sha256
        test_timing = $timingBinding
        updated_at = $CompletedAt
    }
    Write-QualityGateJsonAtomic -Path $pointerPath -Value $pointer
    return [pscustomobject][ordered]@{
        receipt_path = $receiptPath
        pointer_path = $pointerPath
        receipt_sha256 = $receiptHash
        receipt = [pscustomobject]$receipt
        pointer = [pscustomobject]$pointer
    }
}

function Test-QualityGateCurrentReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReceiptRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [ValidateSet('', 'quick', 'full')][string]$RequiredProfile = '',
        [ValidateSet('', 'passed', 'failed', 'source_drift', 'terminal_evidence_unavailable')][string]$RequiredStatus = ''
    )

    $findings = [Collections.Generic.List[object]]::new()
    $root = [IO.Path]::GetFullPath($ReceiptRoot)
    $repo = [IO.Path]::GetFullPath($RepoRoot)
    $pointerPath = Join-Path $root 'current.json'
    $pointer = $null
    $receipt = $null
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
        $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_current_missing' 'current.json does not exist.')) | Out-Null
    }
    else {
        try { $pointer = Get-Content -LiteralPath $pointerPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
        catch { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_current_invalid_json' $_.Exception.Message)) | Out-Null }
    }

    if ($null -ne $pointer) {
        $runId = [string](Get-QualityGateObjectProperty $pointer 'run_id')
        $receiptPath = [string](Get-QualityGateObjectProperty $pointer 'receipt_path')
        if ([int](Get-QualityGateObjectProperty $pointer 'schema_version') -ne 2 -or [string](Get-QualityGateObjectProperty $pointer 'pointer_type') -ne 'latest_quality_gate_receipt') {
            $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_pointer_contract_invalid' 'current.json is not a schema v2 quality gate pointer.')) | Out-Null
        }
        if ($runId -notmatch '^qgr-[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_pointer_run_id_invalid' 'Pointer run id is invalid.')) | Out-Null }
        if ([string]::IsNullOrWhiteSpace($receiptPath)) {
            $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_pointer_receipt_missing' 'Pointer receipt path is empty.')) | Out-Null
        }
        else {
            $receiptPath = [IO.Path]::GetFullPath($receiptPath)
            $expectedPath = [IO.Path]::GetFullPath((Join-Path $root ('{0}.json' -f $runId)))
            if (-not (Test-QualityGatePathWithinRoot $receiptPath $root) -or -not [string]::Equals($receiptPath, $expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
                $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_pointer_receipt_path_invalid' 'Pointer receipt path is outside the immutable receipt location.')) | Out-Null
            }
            elseif (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
                $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_receipt_missing' 'Pointer receipt does not exist.')) | Out-Null
            }
            else {
                $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant()
                if (-not [string]::Equals($actualHash, [string](Get-QualityGateObjectProperty $pointer 'receipt_sha256'), [StringComparison]::OrdinalIgnoreCase)) {
                    $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_receipt_hash_mismatch' 'Immutable receipt hash does not match current.json.')) | Out-Null
                }
                try { $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
                catch { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_receipt_invalid_json' $_.Exception.Message)) | Out-Null }
            }
        }
    }

    if ($null -ne $pointer -and $null -ne $receipt) {
        if ([int](Get-QualityGateObjectProperty $receipt 'schema_version') -ne 2 -or [string](Get-QualityGateObjectProperty $receipt 'receipt_type') -ne 'quality_gate_run' -or (Get-QualityGateObjectProperty $receipt 'immutable') -ne $true) {
            $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_receipt_contract_invalid' 'Receipt is not an immutable schema v2 quality gate receipt.')) | Out-Null
        }
        foreach ($field in @('run_id', 'profile', 'status', 'source_binding_sha256')) {
            if (-not [string]::Equals([string](Get-QualityGateObjectProperty $pointer $field), [string](Get-QualityGateObjectProperty $receipt $field), [StringComparison]::Ordinal)) {
                $findings.Add((New-QualityGateIntegrityFinding ('quality_gate_pointer_{0}_mismatch' -f $field) ("Pointer and receipt {0} differ." -f $field))) | Out-Null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($RequiredProfile) -and [string](Get-QualityGateObjectProperty $receipt 'profile') -ne $RequiredProfile) { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_profile_mismatch' 'Current receipt profile does not satisfy the requirement.')) | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace($RequiredStatus) -and [string](Get-QualityGateObjectProperty $receipt 'status') -ne $RequiredStatus) { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_status_mismatch' 'Current receipt status does not satisfy the requirement.')) | Out-Null }

        try { Assert-QualityGateCurrentReceiptSemantics -Pointer $pointer -Receipt $receipt -RepoRoot $repo }
        catch { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_receipt_semantics_invalid' $_.Exception.Message)) | Out-Null }

        $timing = Get-QualityGateObjectProperty $receipt 'test_timing'
        if ([string](Get-QualityGateObjectProperty $receipt 'profile') -eq 'full' -and [string](Get-QualityGateObjectProperty $receipt 'status') -eq 'passed' -and $null -eq $timing) {
            $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_timing_binding_missing' 'Passed full receipt has no timing binding.')) | Out-Null
        }
        elseif ($null -ne $timing) {
            $timingPath = [string](Get-QualityGateObjectProperty $timing 'path')
            if ([string]::IsNullOrWhiteSpace($timingPath) -or -not (Test-QualityGatePathWithinRoot $timingPath $repo) -or -not (Test-Path -LiteralPath $timingPath -PathType Leaf)) {
                $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_timing_path_invalid' 'Bound timing report is missing or outside the repository.')) | Out-Null
            }
            else {
                $timingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $timingPath).Hash.ToLowerInvariant()
                if (-not [string]::Equals($timingHash, [string](Get-QualityGateObjectProperty $timing 'sha256'), [StringComparison]::OrdinalIgnoreCase)) {
                    $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_timing_hash_mismatch' 'Bound timing report hash changed after receipt publication.')) | Out-Null
                }
            }
        }

        try {
            $currentSource = Get-QualityGateSourceFingerprint -RepoRoot $repo
            $sourceEnd = Get-QualityGateObjectProperty $receipt 'source_end'
            if ($null -eq $sourceEnd -or -not (Compare-QualityGateSourceFingerprint -Start $sourceEnd -End $currentSource).pass) {
                $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_current_source_stale' 'Repository source no longer matches the receipt end fingerprint.')) | Out-Null
            }
        }
        catch { $findings.Add((New-QualityGateIntegrityFinding 'quality_gate_current_source_unavailable' $_.Exception.Message)) | Out-Null }
    }

    return [pscustomobject][ordered]@{
        pass = ($findings.Count -eq 0)
        code = if ($findings.Count -eq 0) { 'quality_gate_current_valid' } else { 'quality_gate_current_invalid' }
        findings = [object[]]@($findings.ToArray())
        pointer_path = $pointerPath
        pointer = $pointer
        receipt = $receipt
    }
}
