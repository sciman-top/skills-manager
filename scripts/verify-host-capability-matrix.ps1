[CmdletBinding()]
param(
    [string]$MatrixPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($MatrixPath)) {
    $MatrixPath = Join-Path $repoRoot 'config\host-capability-matrix.json'
}

function Add-MatrixFinding([System.Collections.Generic.List[object]]$List, [string]$Code, [string]$Path, [string]$Message) {
    $List.Add([pscustomobject]@{ code = $Code; path = $Path; message = $Message }) | Out-Null
}

function Test-NonEmptyArray($Value) {
    return @($Value).Count -gt 0
}

$findings = New-Object System.Collections.Generic.List[object]
$beforeHash = $null
$afterHash = $null
$matrix = $null

if (-not (Test-Path -LiteralPath $MatrixPath -PathType Leaf)) {
    Add-MatrixFinding $findings 'matrix_missing' '$' 'Host capability matrix is missing.'
}
else {
    $beforeHash = (Get-FileHash -LiteralPath $MatrixPath -Algorithm SHA256).Hash.ToLowerInvariant()
    try {
        $matrix = Get-Content -LiteralPath $MatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-MatrixFinding $findings 'matrix_invalid_json' '$' 'Host capability matrix is not valid JSON.'
    }
}

if ($null -ne $matrix) {
    if ([int]$matrix.schema_version -ne 1) {
        Add-MatrixFinding $findings 'schema_version_invalid' '$.schema_version' 'schema_version must be 1.'
    }

    $requiredRootArrays = @('support_states', 'activation_boundaries', 'truth_states', 'automated_verification_levels', 'evidence_kinds', 'evidence', 'hosts')
    foreach ($field in $requiredRootArrays) {
        if (-not (Test-NonEmptyArray $matrix.$field)) {
            Add-MatrixFinding $findings 'required_array_empty' ('$.{0}' -f $field) ('Required array is empty: {0}' -f $field)
        }
    }

    $supportStates = @($matrix.support_states | ForEach-Object { [string]$_ })
    $activationBoundaries = @($matrix.activation_boundaries | ForEach-Object { [string]$_ })
    $truthStates = @($matrix.truth_states | ForEach-Object { [string]$_ })
    $automatedLevels = @($matrix.automated_verification_levels | ForEach-Object { [string]$_ })
    $evidenceKinds = @($matrix.evidence_kinds | ForEach-Object { [string]$_ })

    foreach ($requiredState in @('repo_verified', 'host_loaded', 'live_accepted')) {
        if ($truthStates -notcontains $requiredState) {
            Add-MatrixFinding $findings 'truth_state_missing' '$.truth_states' ('Required truth state is missing: {0}' -f $requiredState)
        }
    }
    if ($automatedLevels -contains 'live_accepted') {
        Add-MatrixFinding $findings 'automated_live_acceptance_forbidden' '$.automated_verification_levels' 'live_accepted cannot be an automated verification maximum.'
    }

    $evidenceById = @{}
    for ($evidenceIndex = 0; $evidenceIndex -lt @($matrix.evidence).Count; $evidenceIndex++) {
        $evidence = @($matrix.evidence)[$evidenceIndex]
        $path = '$.evidence[{0}]' -f $evidenceIndex
        $id = [string]$evidence.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            Add-MatrixFinding $findings 'evidence_id_missing' ($path + '.id') 'Evidence id is required.'
        }
        elseif ($evidenceById.ContainsKey($id)) {
            Add-MatrixFinding $findings 'evidence_id_duplicate' ($path + '.id') ('Duplicate evidence id: {0}' -f $id)
        }
        else {
            $evidenceById[$id] = $evidence
        }
        if ($evidenceKinds -notcontains [string]$evidence.kind) {
            Add-MatrixFinding $findings 'evidence_kind_invalid' ($path + '.kind') ('Invalid evidence kind: {0}' -f [string]$evidence.kind)
        }
        foreach ($field in @('source', 'observed_at', 'claim')) {
            if ([string]::IsNullOrWhiteSpace([string]$evidence.$field)) {
                Add-MatrixFinding $findings 'evidence_field_missing' ($path + '.' + $field) ('Evidence field is required: {0}' -f $field)
            }
        }
    }

    $hostIds = @{}
    for ($hostIndex = 0; $hostIndex -lt @($matrix.hosts).Count; $hostIndex++) {
        $hostEntry = @($matrix.hosts)[$hostIndex]
        $hostPath = '$.hosts[{0}]' -f $hostIndex
        $hostId = [string]$hostEntry.host_id
        if ([string]::IsNullOrWhiteSpace($hostId)) {
            Add-MatrixFinding $findings 'host_id_missing' ($hostPath + '.host_id') 'host_id is required.'
        }
        elseif ($hostIds.ContainsKey($hostId)) {
            Add-MatrixFinding $findings 'host_id_duplicate' ($hostPath + '.host_id') ('Duplicate host_id: {0}' -f $hostId)
        }
        else {
            $hostIds[$hostId] = $true
        }
        if (-not (Test-NonEmptyArray $hostEntry.surfaces)) {
            Add-MatrixFinding $findings 'host_surfaces_empty' ($hostPath + '.surfaces') 'Each host must declare at least one surface.'
            continue
        }

        $surfaceIds = @{}
        for ($surfaceIndex = 0; $surfaceIndex -lt @($hostEntry.surfaces).Count; $surfaceIndex++) {
            $surface = @($hostEntry.surfaces)[$surfaceIndex]
            $surfacePath = '{0}.surfaces[{1}]' -f $hostPath, $surfaceIndex
            $surfaceId = [string]$surface.surface_id
            $support = [string]$surface.support_status
            $activation = [string]$surface.activation_boundary
            $maximum = [string]$surface.maximum_automated_verification

            if ([string]::IsNullOrWhiteSpace($surfaceId)) {
                Add-MatrixFinding $findings 'surface_id_missing' ($surfacePath + '.surface_id') 'surface_id is required.'
            }
            elseif ($surfaceIds.ContainsKey($surfaceId)) {
                Add-MatrixFinding $findings 'surface_id_duplicate' ($surfacePath + '.surface_id') ('Duplicate surface_id for host: {0}' -f $surfaceId)
            }
            else {
                $surfaceIds[$surfaceId] = $true
            }
            if ($supportStates -notcontains $support) {
                Add-MatrixFinding $findings 'support_status_invalid' ($surfacePath + '.support_status') ('Invalid support status: {0}' -f $support)
            }
            if ($activationBoundaries -notcontains $activation) {
                Add-MatrixFinding $findings 'activation_boundary_invalid' ($surfacePath + '.activation_boundary') ('Invalid activation boundary: {0}' -f $activation)
            }
            if ($automatedLevels -notcontains $maximum) {
                Add-MatrixFinding $findings 'verification_level_invalid' ($surfacePath + '.maximum_automated_verification') ('Invalid automated verification level: {0}' -f $maximum)
            }
            if ($maximum -eq 'live_accepted') {
                Add-MatrixFinding $findings 'automated_live_acceptance_forbidden' ($surfacePath + '.maximum_automated_verification') 'live_accepted requires a real workflow or human acceptance.'
            }

            $evidenceRefs = @($surface.evidence_refs | ForEach-Object { [string]$_ })
            if ($support -in @('supported', 'partial') -and $evidenceRefs.Count -eq 0) {
                Add-MatrixFinding $findings 'affirmative_evidence_missing' ($surfacePath + '.evidence_refs') 'Affirmative support claims require evidence.'
            }
            foreach ($evidenceRef in $evidenceRefs) {
                if (-not $evidenceById.ContainsKey($evidenceRef)) {
                    Add-MatrixFinding $findings 'evidence_ref_unknown' ($surfacePath + '.evidence_refs') ('Unknown evidence reference: {0}' -f $evidenceRef)
                }
            }
            if ($support -in @('unknown', 'platform_na')) {
                if (@($surface.managed_write_paths).Count -gt 0) {
                    Add-MatrixFinding $findings 'unknown_surface_write_forbidden' ($surfacePath + '.managed_write_paths') 'Unknown or unavailable surfaces cannot declare managed writes.'
                }
                if ($maximum -ne 'not_verified') {
                    Add-MatrixFinding $findings 'unknown_surface_verification_invalid' ($surfacePath + '.maximum_automated_verification') 'Unknown or unavailable surfaces must remain not_verified.'
                }
            }
        }
    }
}

if (Test-Path -LiteralPath $MatrixPath -PathType Leaf) {
    $afterHash = (Get-FileHash -LiteralPath $MatrixPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($null -ne $beforeHash -and $beforeHash -ne $afterHash) {
        Add-MatrixFinding $findings 'input_modified' '$' 'Verifier modified the matrix, which is forbidden.'
    }
}

$result = [ordered]@{
    schema_version = 1
    valid = ($findings.Count -eq 0)
    pass = ($findings.Count -eq 0)
    host_count = $(if ($null -eq $matrix) { 0 } else { @($matrix.hosts).Count })
    evidence_count = $(if ($null -eq $matrix) { 0 } else { @($matrix.evidence).Count })
    finding_count = $findings.Count
    matrix_sha256_before = $beforeHash
    matrix_sha256_after = $afterHash
    findings = @($findings.ToArray())
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 10)
}
else {
    foreach ($finding in @($result.findings)) {
        Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.path, $finding.message) -ForegroundColor Red
    }
    if ($result.pass) {
        Write-Host ('Host capability matrix passed: hosts={0}, evidence={1}' -f $result.host_count, $result.evidence_count) -ForegroundColor Green
    }
}

if (-not $result.pass) { exit 2 }
exit 0
