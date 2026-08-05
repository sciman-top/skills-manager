[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root "references\reference-shelf.manifest.json"
$readmePath = Join-Path $root "references\README.md"
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

try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "reference shelf manifest cannot be parsed: $($_.Exception.Message)" }

if ([int]$manifest.schema_version -ne 1) { Add-Finding "reference manifest schema_version must be 1" }
if ([string]::IsNullOrWhiteSpace([string]$manifest.references_root)) { Add-Finding "reference manifest references_root is required" }
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
    if ([string]::IsNullOrWhiteSpace([string]$repo.upstream_url)) { Add-Finding "reference repo upstream_url is required: $name" }
    if ($repo.PSObject.Properties.Match("review_revision").Count -gt 0) {
        if ([string]$repo.review_revision -notmatch '^[0-9a-fA-F]{40}$') { Add-Finding "review_revision must be a full commit: $name" }
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
