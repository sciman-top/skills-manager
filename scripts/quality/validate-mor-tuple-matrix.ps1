#!/usr/bin/env pwsh
# Validates docs/decision/MOR-090-tuple-matrix.json (canonical MOR-090 tuple contract).
# Static doc validator: zero network, zero host write. Wired into local/CI quality gates.
# Usage: pwsh -NoProfile -File scripts/quality/validate-mor-tuple-matrix.ps1
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path = Join-Path $repoRoot 'docs\decision\MOR-090-tuple-matrix.json'
$m = Get-Content $path -Raw | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()

$enum = $m._meta.status_enum
$layers = $m._meta.contract_layers
$seen = [System.Collections.Generic.HashSet[string]]::new()
foreach ($t in $m.tuples) {
    $key = "$($t.surface)|$($t.model)|$($t.effort)"
    if (-not $seen.Add($key)) { $errors.Add("duplicate tuple: $key") }
    if ($enum -notcontains $t.status) { $errors.Add("invalid status '$($t.status)': $key") }
    if ($layers -notcontains $t.layer) { $errors.Add("invalid layer '$($t.layer)': $key") }
    if ($t.surface -match '[<>*]') { $errors.Add("wildcard/placeholder in surface: $key") }
    if ($t.model -match '[<>*]') { $errors.Add("wildcard/placeholder in model: $key") }
    if ($t.effort -match '[<>*]') { $errors.Add("wildcard/placeholder in effort: $key") }
    if (-not $t.field_path) { $errors.Add("missing field_path: $key") }
}
$verified = @($m.tuples | Where-Object { $_.status -eq 'verified' })
Write-Host ("tuples={0} verified={1} surfaces={2}" -f $m.tuples.Count, $verified.Count, (($m.tuples.surface | Sort-Object -Unique) -join ','))
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host 'MOR tuple matrix validation passed.'
