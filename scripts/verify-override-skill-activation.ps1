[CmdletBinding()]
param(
    [string]$CorpusPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "config\override-skill-activation-corpus.json")
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$corpus = Get-Content -LiteralPath $CorpusPath -Raw -Encoding UTF8 | ConvertFrom-Json
$findings = [System.Collections.Generic.List[string]]::new()
function Add-Finding([string]$message) { $findings.Add($message) | Out-Null }

if ([int]$corpus.schema_version -ne 1) { Add-Finding "activation corpus schema_version must be 1" }
if ([int]$corpus.case_count -ne @($corpus.cases).Count) { Add-Finding "case_count does not match cases" }
$expectedCategories = @("direct", "indirect", "negative", "edge")
$declaredCategories = @($corpus.categories | ForEach-Object { [string]$_ })
if (($declaredCategories -join "|") -ne ($expectedCategories -join "|")) {
    Add-Finding "activation corpus categories must be direct, indirect, negative, edge in canonical order"
}
$targetNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($nameValue in @($corpus.target_skills)) {
    $name = [string]$nameValue
    if ($name -eq "watch-interrupted-task") { Add-Finding "watch-interrupted-task is frozen and must not enter this corpus" }
    if (-not $targetNames.Add($name)) { Add-Finding "duplicate target skill: $name" }
}

$overrideNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($skillFile in @(Get-ChildItem -LiteralPath (Join-Path $root "overrides") -Recurse -Filter SKILL.md -File)) {
    $header = Get-Content -LiteralPath $skillFile.FullName -Encoding UTF8 -TotalCount 12
    $nameLine = @($header | Where-Object { $_ -match '^name:\s*(.+?)\s*$' } | Select-Object -First 1)
    if ($nameLine.Count -eq 1) { $overrideNames.Add(([regex]::Match($nameLine[0], '^name:\s*(.+?)\s*$')).Groups[1].Value.Trim()) | Out-Null }
}
foreach ($name in $targetNames) {
    if (-not $overrideNames.Contains($name)) { Add-Finding "activation target is not an override skill: $name" }
}

$ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$categoriesByTarget = @{}
foreach ($case in @($corpus.cases)) {
    $id = [string]$case.id
    $target = [string]$case.target_skill
    $category = [string]$case.category
    if ([string]::IsNullOrWhiteSpace($id) -or -not $ids.Add($id)) { Add-Finding "case id is empty or duplicated: $id" }
    if (-not $targetNames.Contains($target)) { Add-Finding "case references unknown target: $id=$target" }
    if ($category -notin $expectedCategories) { Add-Finding "case has unsupported category: $id=$category" }
    if ([string]::IsNullOrWhiteSpace([string]$case.request)) { Add-Finding "case request is empty: $id" }
    if (-not $categoriesByTarget.ContainsKey($target)) { $categoriesByTarget[$target] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
    $categoriesByTarget[$target].Add($category) | Out-Null
    $required = @($case.expected.required | ForEach-Object { [string]$_ })
    $forbidden = @($case.expected.forbidden | ForEach-Object { [string]$_ })
    foreach ($name in $required) {
        if ($forbidden -contains $name) { Add-Finding "case both requires and forbids ${name}: $id" }
    }
    if ($category -eq "direct" -and $required -notcontains $target) { Add-Finding "direct case must require its target: $id" }
    if ($category -eq "negative" -and $forbidden -notcontains $target) { Add-Finding "negative case must forbid its target: $id" }
}

foreach ($target in $targetNames) {
    foreach ($category in $expectedCategories) {
        if (-not $categoriesByTarget.ContainsKey($target) -or -not $categoriesByTarget[$target].Contains($category)) {
            Add-Finding "target lacks ${category} coverage: $target"
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | ForEach-Object { Write-Host ("- {0}" -f $_) -ForegroundColor Red }
    throw ("override activation corpus verification failed with {0} finding(s)" -f $findings.Count)
}

Write-Host ("Override activation corpus OK: targets={0}, cases={1}, watch=excluded" -f $targetNames.Count, $ids.Count) -ForegroundColor Green
