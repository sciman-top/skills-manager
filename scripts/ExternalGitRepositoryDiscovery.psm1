function Test-ExternalPathWithin {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ExternalGitRepositories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExternalRoot,
        [string[]]$ExcludedTreeRoots = @(),
        [string[]]$ExcludedRepositoryRoots = @()
    )

    $rootPath = [IO.Path]::GetFullPath($ExternalRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $excludedTrees = @($ExcludedTreeRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            [IO.Path]::GetFullPath($_).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        })
    $excludedRepositories = @($ExcludedRepositoryRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            [IO.Path]::GetFullPath($_).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        })
    $pending = [Collections.Generic.Stack[string]]::new()
    $repositories = [Collections.Generic.List[object]]::new()
    $pending.Push($rootPath)

    while ($pending.Count -gt 0) {
        $currentPath = $pending.Pop()
        foreach ($directory in @(Get-ChildItem -LiteralPath $currentPath -Directory -Force -ErrorAction Stop)) {
            if ($directory.Name -eq '.git' -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }

            $candidate = [IO.Path]::GetFullPath($directory.FullName)
            if (@($excludedTrees | Where-Object { Test-ExternalPathWithin -Path $candidate -Root $_ }).Count -gt 0) { continue }
            if (@($excludedRepositories | Where-Object { $candidate.Equals($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                $pending.Push($candidate)
                continue
            }

            $gitMarker = Join-Path $candidate '.git'
            if (Test-Path -LiteralPath $gitMarker) {
                $gitRootText = (& git -C $candidate rev-parse --show-toplevel 2>&1 | Out-String).Trim()
                $gitRootValid = $false
                if ($LASTEXITCODE -eq 0 -and $gitRootText) {
                    $gitRoot = [IO.Path]::GetFullPath($gitRootText)
                    $gitRootValid = $gitRoot.Equals($candidate, [StringComparison]::OrdinalIgnoreCase)
                }
                $relativePath = [IO.Path]::GetRelativePath($rootPath, $candidate).Replace([string][char]92, '/')
                $repositories.Add([pscustomobject]@{
                        relative_path = $relativePath
                        path = $candidate
                        git_root_valid = $gitRootValid
                    })
                continue
            }

            $pending.Push($candidate)
        }
    }

    return @($repositories | Sort-Object relative_path)
}

function New-ExternalGitBaselinePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExternalRoot,
        [Parameter(Mandatory)][psobject]$BaselineDocument,
        [string[]]$ExcludedTreeRoots = @(),
        [string[]]$ExcludedRepositoryRoots = @()
    )

    $rootPath = [IO.Path]::GetFullPath($ExternalRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([int]$BaselineDocument.schema_version -ne 1) { throw 'external baseline schema_version must be 1' }
    $baselineRoot = [IO.Path]::GetFullPath([string]$BaselineDocument.external_root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not $rootPath.Equals($baselineRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "external baseline root mismatch: expected $rootPath, got $baselineRoot"
    }

    $oldByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($BaselineDocument.repos)) {
        $relativePath = ([string]$entry.relative_path).Replace('\', '/').TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath) -or
            @($relativePath.Split('/') | Where-Object { $_ -in @('.', '..') }).Count -gt 0) {
            throw "invalid external baseline path: $relativePath"
        }
        if ($oldByPath.ContainsKey($relativePath)) { throw "duplicate external baseline path: $relativePath" }
        $oldByPath.Add($relativePath, $entry)
    }

    $repositories = @(Get-ExternalGitRepositories -ExternalRoot $rootPath -ExcludedTreeRoots $ExcludedTreeRoots -ExcludedRepositoryRoots $ExcludedRepositoryRoots)
    $currentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $newEntries = [Collections.Generic.List[object]]::new()
    $added = [Collections.Generic.List[string]]::new()
    $updated = [Collections.Generic.List[string]]::new()
    $blocked = [Collections.Generic.List[string]]::new()
    foreach ($repository in $repositories) {
        $relativePath = [string]$repository.relative_path
        [void]$currentPaths.Add($relativePath)

        $blockedReason = ''
        $head = ''
        $origin = ''
        if (-not $repository.git_root_valid) {
            $blockedReason = 'Git metadata does not resolve to the repository root'
        }
        else {
            $statusText = (& git -C $repository.path status --porcelain 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { $blockedReason = 'Git status failed' }
            elseif ($statusText) { $blockedReason = 'dirty working tree' }
        }
        if (-not $blockedReason) {
            $head = (& git -C $repository.path rev-parse HEAD 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') { $blockedReason = 'HEAD could not be resolved' }
        }
        if (-not $blockedReason) {
            $origin = (& git -C $repository.path remote get-url origin 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) { $blockedReason = 'origin could not be resolved' }
        }

        if (-not $blockedReason -and $oldByPath.ContainsKey($relativePath)) {
            $old = $oldByPath[$relativePath]
            if (-not [string]::IsNullOrWhiteSpace([string]$old.origin) -and [string]$old.origin -cne $origin) {
                $blockedReason = 'origin changed from the recorded baseline'
            }
            $oldHead = [string]$old.head
            if (-not $blockedReason -and $oldHead -ne $head) {
                if ($oldHead -notmatch '^[0-9a-f]{40}$') { $blockedReason = 'recorded HEAD is invalid' }
                else {
                    $null = & git -C $repository.path merge-base --is-ancestor $oldHead $head 2>&1
                    if ($LASTEXITCODE -ne 0) { $blockedReason = 'HEAD is not a fast-forward from the recorded baseline' }
                    else { $updated.Add($relativePath) }
                }
            }
        }

        if ($blockedReason) {
            $blocked.Add("$relativePath ($blockedReason)")
            if ($oldByPath.ContainsKey($relativePath)) { $newEntries.Add($oldByPath[$relativePath]) }
            continue
        }

        if (-not $oldByPath.ContainsKey($relativePath)) { $added.Add($relativePath) }

        $newEntries.Add([ordered]@{ relative_path = $relativePath; head = $head; origin = $origin })
    }

    $retired = [Collections.Generic.List[string]]::new()
    foreach ($oldPath in $oldByPath.Keys) {
        if (-not $currentPaths.Contains($oldPath)) { $retired.Add($oldPath) }
    }

    $document = [ordered]@{
        schema_version = 1
        external_root = $rootPath
        repos = @($newEntries | Sort-Object { [string]$_.relative_path })
        note = 'Canonical physical Git repositories outside the skills-manager reference shelf and _shared control repository; junction aliases are excluded.'
    }
    [pscustomobject]@{
        document = $document
        repositories = $repositories.Count
        added = @($added.ToArray())
        fast_forward_updated = @($updated.ToArray())
        retired = @($retired.ToArray())
        blocked = @($blocked.ToArray())
        changed = ($added.Count + $updated.Count + $retired.Count) -gt 0
    }
}

Export-ModuleMember -Function Get-ExternalGitRepositories, New-ExternalGitBaselinePlan
