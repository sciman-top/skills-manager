$qualityGateIntegrityErrorAction = 'Stop'

function Invoke-QualityGateGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& git -C $RepoRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('git command failed: git -C {0} {1}' -f $RepoRoot, ($Arguments -join ' ')) }
    return ($output -join [Environment]::NewLine).Trim()
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
    $trackedDiff = Invoke-QualityGateGit $resolvedRoot @('diff', '--binary', '--no-ext-diff', '--no-color', '--no-renames', 'HEAD', '--')
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
        [string]$ErrorMessage = ''
    )

    $root = [IO.Path]::GetFullPath($ReceiptRoot)
    $receiptPath = Join-Path $root ('{0}.json' -f $RunId)
    $pointerPath = Join-Path $root 'current.json'
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) { throw ('Immutable quality gate receipt already exists: {0}' -f $receiptPath) }
    $comparison = Compare-QualityGateSourceFingerprint -Start $SourceStart -End $SourceEnd
    $receipt = [ordered]@{
        schema_version = 1
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
        gates = [object[]]@($GateResults)
    }
    Write-QualityGateJsonAtomic -Path $receiptPath -Value $receipt
    $receiptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant()
    $pointer = [ordered]@{
        schema_version = 1
        pointer_type = 'latest_quality_gate_receipt'
        run_id = $RunId
        profile = $Profile
        status = $Status
        receipt_path = $receiptPath
        receipt_sha256 = $receiptHash
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
