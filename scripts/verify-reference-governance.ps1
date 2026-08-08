[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root "references\reference-shelf.manifest.json"
$readmePath = Join-Path $root "references\README.md"
$agentsPath = Join-Path $root "AGENTS.md"
$tierDocPath = Join-Path $root "docs\EXTERNAL_REFERENCE_REPO_TIERS.md"
$productIndexPath = Join-Path $root "docs\product\README.md"
$prdPath = Join-Path $root "docs\product\skills-manager-vnext-prd.md"
$architecturePath = Join-Path $root "docs\product\skills-manager-vnext-architecture.md"
$roadmapPath = Join-Path $root "docs\product\skills-manager-vnext-roadmap.md"
$provenancePath = Join-Path $root "overrides\patches\provenance.json"
$findings = [System.Collections.Generic.List[string]]::new()

function Add-Finding([string]$message) {
    $findings.Add($message) | Out-Null
}

function Test-ContainedReferenceRelativePath([string]$pathValue) {
    if ([string]::IsNullOrWhiteSpace($pathValue)) { return $false }
    $raw = $pathValue.Trim()
    $normalized = $raw.Replace("\", "/")
    if ([System.IO.Path]::IsPathRooted($raw) -or $normalized.StartsWith("/", [System.StringComparison]::Ordinal) -or $normalized -match '^[A-Za-z]:') {
        return $false
    }
    $segments = @($normalized.Split(@('/'), [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($segments.Count -eq 0) { return $false }
    return (@($segments | Where-Object { $_ -eq "." -or $_ -eq ".." }).Count -eq 0)
}

function Test-ReferenceLifecycleState([string]$Tier, [string]$Status) {
    switch ($Tier) {
        "core-mainline" { return $Status -eq "active" }
        "secondary" { return $Status -eq "active" }
        "historical-compatibility" { return $Status -eq "deprecated" }
        "conditional-not-cloned" { return $Status -eq "not-cloned" }
        default { return $false }
    }
}

try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "reference shelf manifest cannot be parsed: $($_.Exception.Message)" }

if ([int]$manifest.schema_version -ne 1) { Add-Finding "reference manifest schema_version must be 1" }
if ([string]::IsNullOrWhiteSpace([string]$manifest.references_root)) { Add-Finding "reference manifest references_root is required" }
$expectedReferencesRoot = "D:\CODE\external\skills-manager-references"
if ([string]$manifest.references_root -ne $expectedReferencesRoot) {
    Add-Finding "reference manifest must use the project-owned external root: $expectedReferencesRoot"
}
$allowedTiers = @("core-mainline", "historical-compatibility", "secondary", "conditional-not-cloned")
$allowedStatuses = @("active", "deprecated", "not-cloned")
$names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$repoByName = @{}

foreach ($repo in @($manifest.repos)) {
    $name = ([string]$repo.name).Trim()
    $relativePathRaw = ([string]$repo.relative_path).Trim()
    $relativePath = $relativePathRaw.Replace("\", "/").TrimEnd("/")
    if ([string]::IsNullOrWhiteSpace($name)) { Add-Finding "reference repo name is required"; continue }
    if (-not $names.Add($name)) { Add-Finding "duplicate reference repo name: $name" }
    if (-not (Test-ContainedReferenceRelativePath $relativePathRaw)) {
        Add-Finding "reference repo relative_path must be contained and relative: $name"
    }
    elseif (-not $paths.Add($relativePath)) { Add-Finding "duplicate reference repo relative_path: $relativePath" }
    if ([string]$repo.tier -notin $allowedTiers) { Add-Finding "unsupported reference tier: $name=$($repo.tier)" }
    if ([string]$repo.status -notin $allowedStatuses) { Add-Finding "unsupported reference status: $name=$($repo.status)" }
    if (-not (Test-ReferenceLifecycleState ([string]$repo.tier) ([string]$repo.status))) {
        Add-Finding "reference tier/status violates lifecycle contract: $name=$($repo.tier)/$($repo.status)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$repo.upstream_url)) { Add-Finding "reference repo upstream_url is required: $name" }
    if ([string]$repo.tier -eq "core-mainline" -and -not $relativePath.StartsWith("core/", [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Finding "core-mainline repo must use core/ path: $name"
    }
    if ([string]$repo.tier -eq "secondary" -and -not $relativePath.StartsWith("secondary/", [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Finding "secondary repo must use secondary/ path: $name"
    }
    if ([string]$repo.tier -eq "conditional-not-cloned" -and -not $relativePath.StartsWith("conditional/", [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Finding "conditional repo must use conditional/ path: $name"
    }
    if ([string]$repo.tier -eq "historical-compatibility") {
        foreach ($field in @("replacement", "source_disposition")) {
            if ($repo.PSObject.Properties.Match($field).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$repo.$field)) {
                Add-Finding "historical reference is missing ${field}: $name"
            }
        }
    }
    if ([string]$repo.tier -eq "conditional-not-cloned" -or $repo.PSObject.Properties.Match("review_revision").Count -gt 0) {
        if ($repo.PSObject.Properties.Match("review_revision").Count -eq 0 -or [string]$repo.review_revision -notmatch '^[0-9a-fA-F]{40}$') { Add-Finding "review_revision must be a full commit: $name" }
        foreach ($field in @("license", "review_decision", "reviewed_at", "review_evidence", "activation_trigger")) {
            if ($repo.PSObject.Properties.Match($field).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$repo.$field)) {
                Add-Finding "reviewed candidate is missing ${field}: $name"
            }
        }
        if ([string]$repo.source_disposition -ne "reviewed-discovery-candidate" -or [string]$repo.tier -ne "conditional-not-cloned" -or [string]$repo.status -ne "not-cloned") {
            Add-Finding "reviewed candidate must remain conditional and not-cloned: $name"
        }
        $reviewedDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$repo.reviewed_at, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$reviewedDate)) {
            Add-Finding "reviewed_at must be a real YYYY-MM-DD date: $name"
        }
        if (-not (Test-ContainedReferenceRelativePath ([string]$repo.review_evidence))) {
            Add-Finding "review_evidence must be a contained repository-relative path: $name"
        }
        else {
            $reviewEvidencePath = Join-Path $root ([string]$repo.review_evidence)
            if (-not (Test-Path -LiteralPath $reviewEvidencePath -PathType Leaf)) { Add-Finding "review_evidence does not exist: $name" }
        }
    }
    $repoByName[$name] = $repo
}

$defaultNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($nameValue in @($manifest.default_refresh_set)) {
    $name = [string]$nameValue
    if (-not $defaultNames.Add($name)) { Add-Finding "duplicate default_refresh_set entry: $name"; continue }
    if (-not $repoByName.ContainsKey($name)) { Add-Finding "unknown default_refresh_set repo: $name"; continue }
    if ([string]$repoByName[$name].status -ne "active") { Add-Finding "default_refresh_set repo must be active: $name" }
    if ([string]$repoByName[$name].tier -ne "core-mainline") { Add-Finding "default_refresh_set repo must be core-mainline: $name" }
}
foreach ($repo in @($manifest.repos | Where-Object { $_.PSObject.Properties.Match("review_revision").Count -gt 0 })) {
    if ($defaultNames.Contains([string]$repo.name)) { Add-Finding "reviewed discovery candidate must not enter default_refresh_set: $($repo.name)" }
}

$readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
foreach ($name in $names) {
    if ($readme.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Add-Finding "references README omits manifest repo: $name"
    }
}

$agents = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
$tierDoc = Get-Content -LiteralPath $tierDocPath -Raw -Encoding UTF8
$productIndex = Get-Content -LiteralPath $productIndexPath -Raw -Encoding UTF8
$prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8
$architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8
$roadmap = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8
foreach ($contract in @(
        @{ Label = "AGENTS"; Text = $agents; Tokens = @("references/reference-shelf.manifest.json", "scripts/refresh-reference-repos.ps1", "克隆不等于采纳/安装/执行", "不在联动边界", "来源/许可证不明") },
        @{ Label = "reference README"; Text = $readme; Tokens = @("<registered-candidate>", "conditional-not-cloned", "只读比对", "Portfolio lifecycle", "runtime/import 删除", "Owned-root boundary") },
        @{ Label = "tier documentation"; Text = $tierDoc; Tokens = @("Autonomous discovery and clone boundary", "conditional-not-cloned", "does not authorize adoption", "Portfolio lifecycle and removal boundary", "Demotion is not runtime removal", "retire before delete", "Owned-root boundary") },
        @{ Label = "product index"; Text = $productIndex; Tokens = @("可逆 reference portfolio", "最薄真实主链", '不接管 `D:\CODE\external` 根') },
        @{ Label = "PRD"; Text = $prd; Tokens = @("PP-013 Bounded research and reversible reference portfolio", "FR-CAT-006", "FR-CAT-007", "FR-CAT-008", "FR-CAT-009") },
        @{ Label = "architecture"; Text = $architecture; Tokens = @('`ReferencePortfolio`', '`ReferenceCandidate`', "ADR-SMV-039 Reference portfolio is reversible evidence") },
        @{ Label = "roadmap"; Text = $roadmap; Tokens = @("reference_portfolio_action", "runtime/import 删除", '不创建 `D:\CODE\external` 中央管理能力') }
    )) {
    foreach ($token in $contract.Tokens) {
        if ($contract.Text.IndexOf($token, [System.StringComparison]::Ordinal) -lt 0) {
            Add-Finding ("{0} omits reference portfolio contract token: {1}" -f $contract.Label, $token)
        }
    }
}

try { $provenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "patch provenance cannot be parsed: $($_.Exception.Message)" }
if ([int]$provenance.schema_version -ne 1) { Add-Finding "patch provenance schema_version must be 1" }
$patchDirectories = @(Get-ChildItem -LiteralPath (Join-Path $root "overrides\patches") -Directory | Sort-Object Name)
$provenanceNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($patch in @($provenance.patches)) {
    $name = [string]$patch.name
    if (-not $provenanceNames.Add($name)) { Add-Finding "duplicate patch provenance entry: $name" }
    foreach ($field in @("upstream_repo", "upstream_path", "license", "local_delta_reason")) {
        if ($patch.PSObject.Properties.Match($field).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$patch.$field)) {
            Add-Finding "patch provenance is missing ${field}: $name"
        }
    }
    foreach ($field in @("base_revision", "reviewed_revision")) {
        if ([string]$patch.$field -notmatch '^[0-9a-fA-F]{40}$') { Add-Finding "patch ${field} must be a full commit: $name" }
    }
}
foreach ($directory in $patchDirectories) {
    if (-not $provenanceNames.Contains($directory.Name)) { Add-Finding "patch directory lacks provenance: $($directory.Name)" }
}
foreach ($name in $provenanceNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $root ("overrides\patches\{0}\SKILL.md" -f $name)) -PathType Leaf)) {
        Add-Finding "patch provenance points to a missing SKILL.md: $name"
    }
}

if ($findings.Count -gt 0) {
    $findings | ForEach-Object { Write-Host ("- {0}" -f $_) -ForegroundColor Red }
    throw ("reference governance verification failed with {0} finding(s)" -f $findings.Count)
}

Write-Host ("Reference governance OK: repos={0}, default={1}, patches={2}" -f $names.Count, $defaultNames.Count, $provenanceNames.Count) -ForegroundColor Green
