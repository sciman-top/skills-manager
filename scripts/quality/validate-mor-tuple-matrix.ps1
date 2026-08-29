#!/usr/bin/env pwsh
# Validates docs/decision/MOR-090-tuple-matrix.json (canonical MOR-090 tuple contract).
# Static doc validator: zero network, zero host write. Explicit-only entry:
# MOR is design-only (MOR-000), so this is NOT wired into default local/CI
# gates; run it manually or via -Verifier mor when touching MOR contracts.
# Usage: pwsh -NoProfile -File scripts/quality/validate-mor-tuple-matrix.ps1
#        [-Path <alternate matrix json>]  (tests use -Path for negative fixtures)
param([string]$Path = '')
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path $repoRoot 'docs\decision\MOR-090-tuple-matrix.json' }
$m = Get-Content $Path -Raw | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()

# Top-level shape: malformed matrices must fail closed, not silently pass as
# an empty contract ({} / {"tuples":[]} would otherwise validate as passed).
if ($m -isnot [pscustomobject]) { $errors.Add('top level must be a JSON object') }
if (-not $m.PSObject.Properties['_meta']) { $errors.Add('missing _meta') }
if (-not $m.PSObject.Properties['tuples']) { $errors.Add('missing tuples') }
$tuples = @($m.tuples)
if ($tuples.Count -eq 0) { $errors.Add('tuples must be a non-empty array') }
$enum = @($m._meta.status_enum)
$layers = @($m._meta.contract_layers)
if ($enum.Count -eq 0) { $errors.Add('_meta.status_enum must be a non-empty array') }
if ($layers.Count -eq 0) { $errors.Add('_meta.contract_layers must be a non-empty array') }

$seen = [System.Collections.Generic.HashSet[string]]::new()
foreach ($t in $tuples) {
    $key = "$($t.surface)|$($t.model)|$($t.effort)"
    if (-not $seen.Add($key)) { $errors.Add("duplicate tuple: $key") }
    foreach ($field in @('surface', 'model', 'effort', 'field_path', 'status')) {
        $value = $t.$field
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { $errors.Add("missing/empty $field`: $key") }
    }
    if ($enum -notcontains $t.status) { $errors.Add("invalid status '$($t.status)': $key") }
    if ($layers -notcontains $t.layer) { $errors.Add("invalid layer '$($t.layer)': $key") }
    if ($t.surface -match '[<>*]') { $errors.Add("wildcard/placeholder in surface: $key") }
    if ($t.model -match '[<>*]') { $errors.Add("wildcard/placeholder in model: $key") }
    if ($t.effort -match '[<>*]') { $errors.Add("wildcard/placeholder in effort: $key") }
    if (-not $t.field_path) { $errors.Add("missing field_path: $key") }
    # A verified claim must carry at least one evidence id; empty facts make a
    # verified status unverifiable. Non-verified tuples may carry empty facts.
    if ($t.status -eq 'verified') {
        $facts = @($t.facts)
        if ($facts.Count -eq 0) { $errors.Add("verified tuple requires non-empty facts: $key") }
        elseif ($facts | Where-Object { -not ($_ -is [string]) -or [string]::IsNullOrWhiteSpace($_) }) { $errors.Add("facts contain empty/non-string entries: $key") }
    }
}
$verified = @($tuples | Where-Object { $_.status -eq 'verified' })
Write-Host ("tuples={0} verified={1} surfaces={2}" -f $tuples.Count, $verified.Count, (($tuples.surface | Sort-Object -Unique) -join ','))
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host 'MOR tuple matrix validation passed.'
