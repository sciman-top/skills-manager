[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "references\reference-shelf.manifest.json"),
    [string]$ReferencesRoot,
    [string[]]$RepoNames,
    [string[]]$Tier,
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) "references\updates"),
    [switch]$CloneMissing,
    [switch]$FetchOnly,
    [switch]$SkipDirtyRepos
)

$ErrorActionPreference = "Stop"

function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $RepositoryPath @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $rendered = $Arguments -join " "
        throw "git -C `"$RepositoryPath`" $rendered failed with exit code $exitCode.`n$($output.TrimEnd())"
    }

    return $output.TrimEnd()
}

function Invoke-GitClone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpstreamUrl,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [string]$Branch
    )

    $parent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $args = @("clone")
    if (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $args += @("--branch", $Branch, "--single-branch")
    }
    $args += @($UpstreamUrl, $DestinationPath)

    $output = & git @args 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $rendered = $args -join " "
        throw "git $rendered failed with exit code $exitCode.`n$($output.TrimEnd())"
    }

    return $output.TrimEnd()
}

function Get-TrimmedErrorMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $normalized = ($Message -replace "\r\n", "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return "unknown git error"
    }

    $lines = @($normalized -split "`n" | Where-Object { $_ -and $_.Trim() })
    if ($lines.Count -eq 0) {
        return "unknown git error"
    }

    return $lines[-1].Trim()
}

function New-UtcTimestamp {
    return (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
}

function Normalize-RepoNames {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    $normalized = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        foreach ($segment in ($name -split ",")) {
            $candidate = $segment.Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            if (-not $normalized.Contains($candidate)) {
                $normalized.Add($candidate)
            }
        }
    }

    return @($normalized)
}

function Normalize-TierNames {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    $normalized = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        foreach ($segment in ($name -split ",")) {
            $candidate = $segment.Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            $resolved = switch ($candidate) {
                "core" { "core-mainline"; break }
                "core-mainline" { "core-mainline"; break }
                "secondary" { "secondary"; break }
                "conditional" { "conditional-not-cloned"; break }
                "conditional-not-cloned" { "conditional-not-cloned"; break }
                "historical" { "historical-compatibility"; break }
                "historical-compatibility" { "historical-compatibility"; break }
                "all" { "all"; break }
                default { $segment.Trim() }
            }

            if (-not $normalized.Contains($resolved)) {
                $normalized.Add($resolved)
            }
        }
    }

    return @($normalized)
}

function Read-ReferenceManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Get-ManifestRepoIndex {
    param($Manifest)

    $index = @{}
    if ($Manifest -and $Manifest.repos) {
        foreach ($entry in $Manifest.repos) {
            if ($entry.name) {
                $index[[string]$entry.name] = $entry
            }
        }
    }
    return $index
}

function Resolve-ManifestRepoPath {
    param(
        [Parameter(Mandatory = $true)]
        $ManifestRepo,
        [Parameter(Mandatory = $true)]
        [string]$ReferencesRoot
    )

    if ($ManifestRepo.PSObject.Properties.Match("absolute_path").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ManifestRepo.absolute_path)) {
        $absolutePath = ([string]$ManifestRepo.absolute_path).Trim()
        if (-not [System.IO.Path]::IsPathRooted($absolutePath)) {
            throw ("reference manifest absolute_path must be rooted: {0}" -f $absolutePath)
        }
        return [System.IO.Path]::GetFullPath($absolutePath)
    }

    $relativePath = if ($ManifestRepo.PSObject.Properties.Match("relative_path").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ManifestRepo.relative_path)) {
        ([string]$ManifestRepo.relative_path).Trim()
    }
    else { ([string]$ManifestRepo.name).Trim() }
    $normalizedRelative = $relativePath.Replace("\", "/")
    $segments = @($normalizedRelative.Split(@('/'), [System.StringSplitOptions]::RemoveEmptyEntries))
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $normalizedRelative.StartsWith("/", [System.StringComparison]::Ordinal) -or $normalizedRelative -match '^[A-Za-z]:' -or @($segments | Where-Object { $_ -eq "." -or $_ -eq ".." }).Count -gt 0) {
        throw ("reference manifest relative path must stay inside references root: {0}" -f $relativePath)
    }

    $rootPath = [System.IO.Path]::GetFullPath($ReferencesRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $relativePath))
    $rootPrefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidatePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("reference manifest path escaped references root: {0}" -f $relativePath)
    }
    return $candidatePath
}

$manifest = Read-ReferenceManifest -Path $ManifestPath
if (-not $manifest) {
    throw "Manifest 不存在或无法解析：$ManifestPath"
}

if ($RepoNames -and $RepoNames.Count -gt 0 -and $Tier -and $Tier.Count -gt 0) {
    throw "RepoNames 与 Tier 不能同时指定；请选择具体仓列表或 tier 过滤之一。"
}

if (-not $ReferencesRoot) {
    if ($manifest.references_root) {
        $ReferencesRoot = [string]$manifest.references_root
    }
    else {
        throw "ReferencesRoot not provided and manifest does not define references_root: $ManifestPath"
    }
}

if ($Tier -and $Tier.Count -gt 0) {
    $normalizedTiers = Normalize-TierNames -Names $Tier
    $wantAllTiers = $normalizedTiers -contains "all"
    $manifestRepos = @($manifest.repos | Where-Object {
            if ($wantAllTiers) {
                return $true
            }
            return $normalizedTiers -contains ([string]$_.tier)
        })
    if ($manifestRepos.Count -eq 0) {
        throw ("Tier 过滤未命中任何 repo：{0}" -f ($normalizedTiers -join ", "))
    }
    $RepoNames = @($manifestRepos | ForEach-Object { [string]$_.name })
}
elseif (-not $RepoNames -or $RepoNames.Count -eq 0) {
    if ($manifest.default_refresh_set) {
        $RepoNames = @($manifest.default_refresh_set | ForEach-Object { [string]$_ })
    }
    else {
        throw "RepoNames not provided and manifest does not define default_refresh_set: $ManifestPath"
    }
}

if (-not (Test-Path -LiteralPath $ReferencesRoot)) {
    New-Item -ItemType Directory -Force -Path $ReferencesRoot | Out-Null
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
}

$RepoNames = Normalize-RepoNames -Names $RepoNames
$manifestDefaultRepos = if ($manifest.default_refresh_set) { @($manifest.default_refresh_set | ForEach-Object { [string]$_ }) } else { @() }
$normalizedTierNames = if ($Tier -and $Tier.Count -gt 0) { Normalize-TierNames -Names $Tier } else { @() }
$repoNamesLabel = if ($manifestDefaultRepos.Count -gt 0 -and (@($RepoNames) -join ",") -eq ($manifestDefaultRepos -join ",")) {
    "core-default"
}
elseif ($normalizedTierNames.Count -gt 0) {
    "tier-" + (($normalizedTierNames | ForEach-Object {
                switch ($_) {
                    "core-mainline" { "core"; break }
                    "conditional-not-cloned" { "conditional"; break }
                    default { $_ }
                }
            }) -join "+")
}
else {
    "custom"
}
$shouldUpdateLatest = ($repoNamesLabel -eq "core-default")
$manifestRepoIndex = Get-ManifestRepoIndex -Manifest $manifest

if ($shouldUpdateLatest) {
    foreach ($repoName in $RepoNames) {
        if (-not $manifestRepoIndex.ContainsKey($repoName)) {
            throw "default_refresh_set references unknown repo: $repoName"
        }
        $defaultEntry = $manifestRepoIndex[$repoName]
        if ([string]$defaultEntry.status -ne "active") {
            throw "default_refresh_set can contain only active repos: $repoName status=$($defaultEntry.status)"
        }
    }
}

$timestamp = New-UtcTimestamp
$reportPath = Join-Path $OutputDirectory ("reference-refresh-{0}.md" -f $timestamp)
$latestReportPath = Join-Path $OutputDirectory "reference-refresh-latest.md"
$results = [System.Collections.Generic.List[object]]::new()

foreach ($repoName in $RepoNames) {
    $manifestRepo = if ($manifestRepoIndex.ContainsKey($repoName)) { $manifestRepoIndex[$repoName] } else { $null }
    if (-not $manifestRepo) {
        $results.Add([pscustomobject]@{
                repo = $repoName
                tier = $null
                upstream = $null
                path = $null
                status = "unknown-repo"
                branch = $null
                head_before = $null
                head_after = $null
                changed = $false
                cloned = $false
                ahead_behind = $null
                note = "repo not defined in manifest"
                compare_log = @()
            })
        continue
    }

    $repoPath = Resolve-ManifestRepoPath -ManifestRepo $manifestRepo -ReferencesRoot $ReferencesRoot
    $repoTier = [string]$manifestRepo.tier
    $upstreamUrl = [string]$manifestRepo.upstream_url
    $branchHint = if ($manifestRepo.PSObject.Properties.Match("branch").Count -gt 0) { [string]$manifestRepo.branch } else { "" }
    $cloned = $false

    if (-not (Test-Path -LiteralPath $repoPath)) {
        if (-not $CloneMissing) {
            $results.Add([pscustomobject]@{
                    repo = $repoName
                    tier = $repoTier
                    upstream = $upstreamUrl
                    path = $repoPath
                    status = "missing"
                    branch = $null
                    head_before = $null
                    head_after = $null
                    changed = $false
                    cloned = $false
                    ahead_behind = $null
                    note = "repository path not found"
                    compare_log = @()
                })
            continue
        }

        if ([string]::IsNullOrWhiteSpace($upstreamUrl)) {
            $results.Add([pscustomobject]@{
                    repo = $repoName
                    tier = $repoTier
                    upstream = $upstreamUrl
                    path = $repoPath
                    status = "clone-blocked"
                    branch = $null
                    head_before = $null
                    head_after = $null
                    changed = $false
                    cloned = $false
                    ahead_behind = $null
                    note = "missing upstream_url; cannot clone"
                    compare_log = @()
                })
            continue
        }

        try {
            Invoke-GitClone -UpstreamUrl $upstreamUrl -DestinationPath $repoPath -Branch $branchHint | Out-Null
            $cloned = $true
        }
        catch {
            $results.Add([pscustomobject]@{
                    repo = $repoName
                    tier = $repoTier
                    upstream = $upstreamUrl
                    path = $repoPath
                    status = "clone-failed"
                    branch = $null
                    head_before = $null
                    head_after = $null
                    changed = $false
                    cloned = $false
                    ahead_behind = $null
                    note = Get-TrimmedErrorMessage -Message $_.Exception.Message
                    compare_log = @()
                })
            continue
        }
    }

    $branch = Invoke-GitText -RepositoryPath $repoPath -Arguments @("branch", "--show-current")
    $headBefore = Invoke-GitText -RepositoryPath $repoPath -Arguments @("rev-parse", "HEAD")
    $statusText = Invoke-GitText -RepositoryPath $repoPath -Arguments @("status", "--short")
    $isDirty = -not [string]::IsNullOrWhiteSpace($statusText)

    if ($isDirty -and $SkipDirtyRepos) {
        $results.Add([pscustomobject]@{
                repo = $repoName
                tier = $repoTier
                upstream = $upstreamUrl
                path = $repoPath
                status = if ($cloned) { "cloned-dirty" } else { "skipped-dirty" }
                branch = $branch
                head_before = $headBefore
                head_after = $headBefore
                changed = $false
                cloned = $cloned
                ahead_behind = $null
                note = if ($cloned) { "cloned this run; worktree is dirty after clone or local changes" } else { "dirty worktree; skipped by policy" }
                compare_log = @()
            })
        continue
    }

    try {
        Invoke-GitText -RepositoryPath $repoPath -Arguments @("fetch", "--prune", "origin") | Out-Null
    }
    catch {
        $results.Add([pscustomobject]@{
                repo = $repoName
                tier = $repoTier
                upstream = $upstreamUrl
                path = $repoPath
                status = "fetch-failed"
                branch = $branch
                head_before = $headBefore
                head_after = $headBefore
                changed = $false
                cloned = $cloned
                ahead_behind = $null
                note = Get-TrimmedErrorMessage -Message $_.Exception.Message
                compare_log = @()
            })
        continue
    }

    $upstreamRevision = if (-not [string]::IsNullOrWhiteSpace($branch)) {
        try { Invoke-GitText -RepositoryPath $repoPath -Arguments @("rev-parse", ("origin/{0}" -f $branch)) }
        catch { $null }
    }
    else { $null }

    $statusLabel = if ($FetchOnly) { "fetch-only" } else { "pull --ff-only" }
    $note = if ($FetchOnly) { "remote refs fetched" } else { "pull --ff-only completed" }

    if (-not $FetchOnly) {
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $results.Add([pscustomobject]@{
                    repo = $repoName
                    tier = $repoTier
                    upstream = $upstreamUrl
                    path = $repoPath
                    status = "pull-skipped-no-branch"
                    branch = $branch
                    head_before = $headBefore
                    head_after = $headBefore
                    changed = $false
                    cloned = $cloned
                    ahead_behind = $null
                    remote_refs_current = $true
                    working_tree_matches_upstream = $null
                    upstream_revision = $upstreamRevision
                    consumable_revision = $headBefore
                    note = "current branch is empty; skipped pull"
                    compare_log = @()
                })
            continue
        }

        try {
            Invoke-GitText -RepositoryPath $repoPath -Arguments @("pull", "--ff-only", "origin", $branch) | Out-Null
        }
        catch {
            $results.Add([pscustomobject]@{
                    repo = $repoName
                    tier = $repoTier
                    upstream = $upstreamUrl
                    path = $repoPath
                    status = "pull-failed"
                    branch = $branch
                    head_before = $headBefore
                    head_after = $headBefore
                    changed = $false
                    cloned = $cloned
                    ahead_behind = $null
                    remote_refs_current = $true
                    working_tree_matches_upstream = ($headBefore -eq $upstreamRevision)
                    upstream_revision = $upstreamRevision
                    consumable_revision = $headBefore
                    note = Get-TrimmedErrorMessage -Message $_.Exception.Message
                    compare_log = @()
                })
            continue
        }
    }

    $headAfter = Invoke-GitText -RepositoryPath $repoPath -Arguments @("rev-parse", "HEAD")
    $changed = ($headBefore -ne $headAfter)
    $aheadBehind = if (-not [string]::IsNullOrWhiteSpace($branch)) {
        try {
            Invoke-GitText -RepositoryPath $repoPath -Arguments @("rev-list", "--left-right", "--count", ("{0}...origin/{1}" -f $branch, $branch))
        }
        catch {
            $null
        }
    } else { $null }

    $compareLog = @()
    if ($changed) {
        $compareLogRaw = Invoke-GitText -RepositoryPath $repoPath -Arguments @("log", "--oneline", "--decorate", ("{0}..{1}" -f $headBefore, "HEAD"))
        if (-not [string]::IsNullOrWhiteSpace($compareLogRaw)) {
            $compareLog = @($compareLogRaw -split "`r?`n" | Where-Object { $_ -and $_.Trim() })
        }
    }

    $finalStatus = if ($cloned -and $changed) { "cloned-updated" } elseif ($cloned) { "cloned" } elseif ($changed) { "updated" } else { $statusLabel }
    $results.Add([pscustomobject]@{
            repo = $repoName
            tier = $repoTier
            upstream = $upstreamUrl
            path = $repoPath
            status = $finalStatus
            branch = $branch
            head_before = $headBefore
            head_after = $headAfter
            changed = $changed
            cloned = $cloned
            ahead_behind = $aheadBehind
            remote_refs_current = $true
            working_tree_matches_upstream = (-not [string]::IsNullOrWhiteSpace($upstreamRevision) -and $headAfter -eq $upstreamRevision)
            upstream_revision = $upstreamRevision
            consumable_revision = $headAfter
            note = $note
            compare_log = $compareLog
        })
}

$lines = [System.Collections.Generic.List[string]]::new()
$modeLabel = if ($FetchOnly) { "fetch-only" } else { "pull --ff-only" }
$lines.Add("# 参考仓刷新摘要")
$lines.Add("")
$lines.Add(('生成时间（UTC）：`' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") + '`'))
$lines.Add(('模式：`' + $modeLabel + '`'))
$lines.Add(('clone_missing：`' + ([bool]$CloneMissing).ToString().ToLowerInvariant() + '`'))
$lines.Add(('根目录：`' + $ReferencesRoot + '`'))
$lines.Add(('manifest：`' + $ManifestPath + '`'))
$lines.Add(('集合：`' + $repoNamesLabel + '`'))
$lines.Add(('更新 latest：`' + $shouldUpdateLatest.ToString().ToLowerInvariant() + '`'))
if ($normalizedTierNames.Count -gt 0) {
    $lines.Add(('tier 过滤：`' + (($normalizedTierNames -join ", ") -replace "\\", "/") + '`'))
}
$lines.Add(('仓列表：`' + (($RepoNames -join ", ") -replace "\\", "/") + '`'))
$lines.Add("")

foreach ($result in $results) {
    $lines.Add(("## {0}" -f $result.repo))
    $lines.Add("")
    if ($result.tier) {
        $lines.Add(('- 分层：`' + $result.tier + '`'))
    }
    if ($result.upstream) {
        $lines.Add(('- 上游：`' + $result.upstream + '`'))
    }
    if ($result.path) {
        $lines.Add(('- 路径：`' + $result.path + '`'))
    }
    if ($result.branch) {
        $lines.Add(('- 分支：`' + $result.branch + '`'))
    }
    $lines.Add(('- 状态：`' + $result.status + '`'))
    if ($null -ne $result.cloned) {
        $lines.Add(('- 本次是否克隆：`' + ([bool]$result.cloned).ToString().ToLowerInvariant() + '`'))
    }
    if ($result.head_before) {
        $lines.Add(('- 更新前：`' + $result.head_before + '`'))
    }
    if ($result.head_after) {
        $lines.Add(('- 更新后：`' + $result.head_after + '`'))
    }
    if ($result.ahead_behind) {
        $lines.Add(('- ahead/behind：`' + $result.ahead_behind + '`'))
    }
    if ($null -ne $result.remote_refs_current) {
        $lines.Add(('- remote refs current：`' + ([bool]$result.remote_refs_current).ToString().ToLowerInvariant() + '`'))
    }
    if ($null -ne $result.working_tree_matches_upstream) {
        $lines.Add(('- working tree matches upstream：`' + ([bool]$result.working_tree_matches_upstream).ToString().ToLowerInvariant() + '`'))
    }
    if ($result.upstream_revision) {
        $lines.Add(('- upstream revision：`' + $result.upstream_revision + '`'))
    }
    if ($result.consumable_revision) {
        $lines.Add(('- consumable revision：`' + $result.consumable_revision + '`'))
    }
    $lines.Add(("- 说明：{0}" -f $result.note))
    if ($result.compare_log -and $result.compare_log.Count -gt 0) {
        $lines.Add("- 本次更新 commit：")
        foreach ($entry in $result.compare_log) {
            $lines.Add(('  - `' + $entry + '`'))
        }
    }
    $lines.Add("")
}

while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$lines[$lines.Count - 1])) {
    $lines.RemoveAt($lines.Count - 1)
}

[System.IO.File]::WriteAllText(
    $reportPath,
    (($lines -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
if ($shouldUpdateLatest) {
    [System.IO.File]::WriteAllText(
        $latestReportPath,
        (($lines -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

[pscustomobject]@{
    manifest_path = $ManifestPath
    references_root = $ReferencesRoot
    output_path = $reportPath
    latest_output_path = $latestReportPath
    repo_set = $repoNamesLabel
    tier_filter = $normalizedTierNames
    latest_updated = [bool]$shouldUpdateLatest
    repo_names = $RepoNames
    clone_missing = [bool]$CloneMissing
    fetch_only = [bool]$FetchOnly
    skip_dirty_repos = [bool]$SkipDirtyRepos
    results = $results
}
