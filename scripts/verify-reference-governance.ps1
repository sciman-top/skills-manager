[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'references\reference-shelf.manifest.json'
$provenancePath = Join-Path $root 'overrides\patches\provenance.json'
$findings = [Collections.Generic.List[string]]::new()

function Add-Finding([string]$Message) { $findings.Add($Message) | Out-Null }

function Test-ContainedReferenceRelativePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or [IO.Path]::IsPathRooted($Value)) { return $false }
    $segments = @($Value.Replace('\', '/').Split('/', [StringSplitOptions]::RemoveEmptyEntries))
    return $segments.Count -gt 0 -and @($segments | Where-Object { $_ -in @('.', '..') }).Count -eq 0
}

function Test-ReferenceLifecycleState([string]$Tier, [string]$Status) {
    return $Tier -in @('core-mainline', 'secondary', 'conditional') -and $Status -eq 'active'
}

function Test-ConditionalReferenceContract($Repo) {
    if ([string]$Repo.tier -ne 'conditional') { return $true }
    return -not [string]::IsNullOrWhiteSpace([string]$Repo.consumer) -and
        -not [string]::IsNullOrWhiteSpace([string]$Repo.retirement_trigger)
}

# Dot-sourcing (unit tests import only the Test-* helpers above) must not run
# the fail-closed environment checks; external reference state belongs to
# explicit verify runs, not to ordinary test loading.
if ($MyInvocation.InvocationName -eq '.') { return }

try { $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json }
catch { throw "reference shelf manifest cannot be parsed: $($_.Exception.Message)" }

if ([int]$manifest.schema_version -ne 1) { Add-Finding 'reference manifest schema_version must be 1' }
$expectedRoot = 'D:\CODE\external\skills-manager-references'
if ([string]$manifest.references_root -ne $expectedRoot) { Add-Finding "reference manifest must use $expectedRoot" }

$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$byName = @{}
foreach ($repo in @($manifest.repos)) {
    $name = ([string]$repo.name).Trim()
    $relativePath = ([string]$repo.relative_path).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { Add-Finding 'reference repo name is required'; continue }
    if (-not $names.Add($name)) { Add-Finding "duplicate reference repo name: $name" }
    if (-not (Test-ContainedReferenceRelativePath $relativePath)) { Add-Finding "invalid reference path: $name" }
    elseif (-not $paths.Add($relativePath.Replace('\', '/').TrimEnd('/'))) { Add-Finding "duplicate reference path: $relativePath" }
    if (-not (Test-ReferenceLifecycleState ([string]$repo.tier) ([string]$repo.status))) { Add-Finding "invalid reference lifecycle: $name" }
    if ([string]$repo.tier -eq 'core-mainline' -and -not $relativePath.Replace('\', '/').StartsWith('core/', [StringComparison]::OrdinalIgnoreCase)) { Add-Finding "core repo must use core/: $name" }
    if ([string]$repo.tier -eq 'secondary' -and -not $relativePath.Replace('\', '/').StartsWith('secondary/', [StringComparison]::OrdinalIgnoreCase)) { Add-Finding "secondary repo must use secondary/: $name" }
    if ([string]$repo.tier -eq 'conditional' -and -not $relativePath.Replace('\', '/').StartsWith('conditional/', [StringComparison]::OrdinalIgnoreCase)) { Add-Finding "conditional repo must use conditional/: $name" }
    if ([string]::IsNullOrWhiteSpace([string]$repo.upstream_url)) { Add-Finding "reference upstream_url is required: $name" }
    if (-not (Test-ConditionalReferenceContract $repo)) { Add-Finding "conditional reference requires consumer and retirement_trigger: $name" }
    $byName[$name] = $repo
}

$defaults = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @($manifest.default_refresh_set)) {
    if (-not $defaults.Add([string]$name)) { Add-Finding "duplicate default reference: $name"; continue }
    if (-not $byName.ContainsKey([string]$name)) { Add-Finding "unknown default reference: $name"; continue }
    if ([string]$byName[[string]$name].tier -ne 'core-mainline') { Add-Finding "default reference must be core-mainline: $name" }
}

try { $provenance = Get-Content -Raw -LiteralPath $provenancePath -Encoding UTF8 | ConvertFrom-Json }
catch { throw "patch provenance cannot be parsed: $($_.Exception.Message)" }
if ([int]$provenance.schema_version -ne 1) { Add-Finding 'patch provenance schema_version must be 1' }
$patchNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($patch in @($provenance.patches)) {
    $name = [string]$patch.name
    if (-not $patchNames.Add($name)) { Add-Finding "duplicate patch provenance: $name" }
    foreach ($field in @('upstream_repo', 'upstream_path', 'license', 'local_delta_reason')) {
        if ([string]::IsNullOrWhiteSpace([string]$patch.$field)) { Add-Finding "patch provenance missing ${field}: $name" }
    }
    foreach ($field in @('base_revision', 'reviewed_revision')) {
        if ([string]$patch.$field -notmatch '^[0-9a-fA-F]{40}$') { Add-Finding "patch ${field} must be a full commit: $name" }
    }
}
foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'overrides\patches') -Directory)) {
    if (@(Get-ChildItem -LiteralPath $directory.FullName -Recurse -File -Force).Count -eq 0) { continue }
    if (-not $patchNames.Contains($directory.Name)) { Add-Finding "patch directory lacks provenance: $($directory.Name)" }
}
foreach ($name in $patchNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $root "overrides\patches\$name\SKILL.md") -PathType Leaf)) { Add-Finding "patch provenance points to a missing skill: $name" }
}

# --- 外置参考仓只读边界:L1 deny-write 锁 + L3 漂移核对 ---
$externalRoot = 'D:\CODE\external'
$baselinesPath = Join-Path $root 'references\external-readonly-baselines.json'
$externalGitCount = 0
$lockAces = @()
if (-not (Test-Path -LiteralPath $externalRoot -PathType Container)) {
    # 工作站专属硬墙:外置根只在装机环境存在;CI/他机无此目录,降级为 observation,不阻断。
    Write-Host "external reference root not present ($externalRoot); L1/L3 hardwall checks skipped" -ForegroundColor Yellow
}
else {
    $denyAces = @(Get-Acl -LiteralPath $externalRoot | Select-Object -ExpandProperty Access |
        Where-Object { $_.AccessControlType -eq 'Deny' -and -not $_.IsInherited })
    $currentUser = $env:USERNAME
    $lockAces = @($denyAces | Where-Object {
            $id = [string]$_.IdentityReference.Value
            ($id -eq $currentUser) -or ($id -like "*\$currentUser")
        })
    if ($lockAces.Count -eq 0) { Add-Finding "external reference root is not deny-write locked: $externalRoot" }

    $knownRootRepos = @{}
    if (-not (Test-Path -LiteralPath $baselinesPath)) {
        Add-Finding "external readonly baselines file is missing: $baselinesPath"
    }
    else {
        try { $baselines = Get-Content -Raw -LiteralPath $baselinesPath -Encoding UTF8 | ConvertFrom-Json }
        catch { throw "external readonly baselines cannot be parsed: $($_.Exception.Message)" }
        if ([int]$baselines.schema_version -ne 1) { Add-Finding 'external readonly baselines schema_version must be 1' }
        if ([string]$baselines.external_root -ne $externalRoot) { Add-Finding "external readonly baselines must use $externalRoot" }
        foreach ($entry in @($baselines.repos)) {
            $knownRootRepos[[string]$entry.relative_path] = [string]$entry.head
        }
    }

    $externalGitCount = 0
    foreach ($dir in @(Get-ChildItem -LiteralPath $externalRoot -Directory)) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName '.git'))) { continue }
        $externalGitCount++
        $statusText = (& git -C $dir.FullName status --porcelain 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { Add-Finding "external repo status check failed: $($dir.Name)"; continue }
        if ($statusText) { Add-Finding "external repo has dirty worktree: $($dir.Name)" }
        if ($knownRootRepos.ContainsKey($dir.Name)) {
            $head = (& git -C $dir.FullName rev-parse HEAD 2>&1 | Out-String).Trim()
            if ($head -ne $knownRootRepos[$dir.Name]) {
                Add-Finding "external repo HEAD drifted from baseline: $($dir.Name) (expected $($knownRootRepos[$dir.Name]), got $head)"
            }
        }
        else {
            Add-Finding "external git repo lacks a readonly baseline: $($dir.Name)"
        }
    }

    # manifest 仓的 HEAD 基线由 refresh 工作流闭环管理,这里只补脏工作树扫描。
    foreach ($repo in @($manifest.repos)) {
        if (-not (Test-ContainedReferenceRelativePath ([string]$repo.relative_path))) { continue }
        $repoPath = [IO.Path]::GetFullPath((Join-Path ([string]$manifest.references_root) ([string]$repo.relative_path)))
        if (-not (Test-Path -LiteralPath (Join-Path $repoPath '.git'))) { continue }
        $statusText = (& git -C $repoPath status --porcelain 2>&1 | Out-String).Trim()
        if ($statusText) { Add-Finding "reference repo has dirty worktree: $($repo.relative_path)" }
    }
}

if ($findings.Count -gt 0) {
    $findings | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    throw "reference governance verification failed with $($findings.Count) finding(s)"
}

Write-Host "Reference governance OK: repos=$($names.Count), default=$($defaults.Count), patches=$($patchNames.Count), external-git=$externalGitCount locked=$($lockAces.Count -gt 0)" -ForegroundColor Green
