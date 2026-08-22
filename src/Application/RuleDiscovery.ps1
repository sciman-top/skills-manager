function Get-RuleFileSha256([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Test-RuleDiscoveryPathWithin([string]$Path, [string]$Root) {
    $candidate = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $boundary = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $candidate.Equals($boundary, [System.StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith(($boundary + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-RuleDiscoveryNonEmptyFile([string]$Path) {
    return [System.IO.File]::Exists($Path) -and -not [string]::IsNullOrWhiteSpace([System.IO.File]::ReadAllText($Path))
}

function New-ObservedRuleDocument([string]$Path, [string]$HostName, [string]$Scope, [int]$Precedence, [string]$Responsibility = 'project_action') {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return New-RuleDocument -Host $HostName -Scope $Scope -Responsibility $Responsibility -Path ([System.IO.Path]::GetFullPath($Path)) -Owner $(if ($Scope -eq 'global') { 'user' } else { 'repo' }) -ContentHash (Get-RuleFileSha256 $Path) -ByteSize $bytes.Length -Precedence $Precedence -DiscoveryState observed -SourceOfTruth 'filesystem' -VerificationState static_validated -Evidence @([pscustomobject]@{ type = 'file'; path = [System.IO.Path]::GetFullPath($Path) })
}

function Get-RuleDiscovery {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$CurrentDirectory = $RepoRoot,
        [Parameter(Mandatory = $true)][ValidateSet('codex', 'claude', 'zcode')][string]$HostName,
        [string]$UserRuleRoot,
        [string[]]$FallbackNames = @(),
        [int]$MaxCombinedBytes = 32768
    )
    $repo = [System.IO.Path]::GetFullPath($RepoRoot)
    $cwd = [System.IO.Path]::GetFullPath($CurrentDirectory)
    if (-not (Test-RuleDiscoveryPathWithin $cwd $repo)) { throw 'CurrentDirectory is outside the authorized repository root.' }
    $documents = New-Object System.Collections.Generic.List[object]
    $candidates = New-Object System.Collections.Generic.List[object]
    $precedence = 0
    if (-not [string]::IsNullOrWhiteSpace($UserRuleRoot)) {
        $user = [System.IO.Path]::GetFullPath($UserRuleRoot)
        $globalNames = if ($HostName -eq 'codex') { @('AGENTS.override.md', 'AGENTS.md') } elseif ($HostName -eq 'zcode') { @('AGENTS.md') } else { @('CLAUDE.md') }
        foreach ($name in $globalNames) {
            $path = Join-Path $user $name
            $exists = [System.IO.File]::Exists($path)
            $nonEmpty = $exists -and (Test-RuleDiscoveryNonEmptyFile $path)
            $reason = if (-not $exists) { 'absent' } elseif (-not $nonEmpty) { 'empty_candidate' } else { 'candidate' }
            $candidates.Add([pscustomobject]@{ path = $path; scope = 'global'; exists = $exists; selected = $false; reason = $reason }) | Out-Null
            if ($nonEmpty) { $documents.Add((New-ObservedRuleDocument $path $HostName $(if ($name -match 'override') { 'override' } else { 'global' }) $precedence $(if ($HostName -eq 'claude') { 'platform_delta' } else { 'common' }))) | Out-Null; $candidates[$candidates.Count - 1].selected = $true; $candidates[$candidates.Count - 1].reason = 'first_non_empty_candidate'; $precedence++; break }
        }
    }
    $dirs = New-Object System.Collections.Generic.List[string]
    $cursor = $cwd
    while ($true) {
        $dirs.Insert(0, $cursor)
        if ($cursor.Equals($repo, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [System.IO.Directory]::GetParent($cursor)
        if ($null -eq $parent -or -not (Test-RuleDiscoveryPathWithin $parent.FullName $repo)) { throw 'Unable to construct a bounded repository rule chain.' }
        $cursor = $parent.FullName
    }
    $projectDirs = if ($HostName -eq 'zcode') { @($repo) } else { @($dirs) }
    foreach ($dir in $projectDirs) {
        $names = if ($HostName -eq 'codex') { @('AGENTS.override.md', 'AGENTS.md') + @($FallbackNames) } elseif ($HostName -eq 'zcode') { @('AGENTS.md') } else { @('CLAUDE.md') }
        $selected = $false
        foreach ($name in $names) {
            $path = Join-Path $dir $name
            $exists = [System.IO.File]::Exists($path)
            $nonEmpty = $exists -and (Test-RuleDiscoveryNonEmptyFile $path)
            $reason = if (-not $exists) { 'absent' } elseif (-not $nonEmpty) { 'empty_candidate' } else { 'shadowed_by_higher_priority_candidate' }
            $candidate = [pscustomobject]@{ path = $path; scope = $(if ($dir -eq $repo) { 'repo' } else { 'subtree' }); exists = $exists; selected = $false; reason = $reason }
            if ($nonEmpty -and -not $selected) {
                $scope = if ($name -match 'override') { 'override' } elseif ($dir -eq $repo) { 'repo' } else { 'subtree' }
                $document = New-ObservedRuleDocument $path $HostName $scope $precedence $(if ($HostName -eq 'claude') { 'platform_delta' } else { 'project_action' })
                if ($HostName -eq 'claude') { $document.discovery_state = 'inferred'; $document.precedence = $null }
                $documents.Add($document) | Out-Null; $candidate.selected = $true; $candidate.reason = $(if ($HostName -eq 'claude') { 'candidate_precedence_not_verified' } else { 'first_non_empty_candidate' }); $selected = $true; $precedence++
            }
            $candidates.Add($candidate) | Out-Null
        }
    }
    $consumed = 0
    $truncated = New-Object System.Collections.Generic.List[string]
    foreach ($document in @($documents.ToArray() | Sort-Object precedence)) {
        if ($consumed + [int]$document.byte_size -gt $MaxCombinedBytes) { $truncated.Add([string]$document.path) | Out-Null }
        else { $consumed += [int]$document.byte_size }
    }
    return [pscustomobject][ordered]@{
        schema_version = 1; host = $HostName; repo_root = $repo; current_directory = $cwd; read_only = $true
        documents = @($documents.ToArray()); candidates = @($candidates.ToArray()); combined_bytes = $consumed
        max_combined_bytes = $MaxCombinedBytes; truncated_paths = @($truncated.ToArray())
        load_verification = 'not_run'; writes = 0; provider_calls = 0; native_mutations = 0; profile_changed = $false
    }
}
