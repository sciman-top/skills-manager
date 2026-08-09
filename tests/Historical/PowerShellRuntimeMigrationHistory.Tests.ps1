$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifier = Join-Path $repoRoot 'scripts\verify-powershell-runtime-policy.ps1'

function Invoke-PowerShellMigrationHistoryVerifier([string]$RootPath) {
    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $verifier -RepoRoot $RootPath -HistoricalMigration -Json 2>&1)
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = ($output -join "`n") }
}

function New-PowerShellMigrationHistoryFixture([string]$Name) {
    $fixtureRoot = Join-Path $TestDrive ("powershell-migration-history-{0}-{1}" -f $Name, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    foreach ($relativePath in @(
        'tasks/skills-manager-vnext-powershell7-migration.tasks.json',
        'tasks/skills-manager-vnext-typed-core-pilot.tasks.json',
        'tasks/skills-manager-vnext-phase0.tasks.json',
        'docs/superpowers/specs/2026-08-05-powershell-7-only-runtime-migration.md',
        'docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md',
        'docs/change-evidence/20260805-powershell-7-only-runtime-migration.md',
        'docs/runbooks/powershell-runtime-compatibility.md',
        'docs/product/skills-manager-vnext-prd.md',
        'docs/product/skills-manager-vnext-architecture.md',
        'docs/product/skills-manager-vnext-roadmap.md',
        'AGENTS.md',
        'RELEASE_TEMPLATE.md'
    )) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $fixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    return $fixtureRoot
}

Describe 'PowerShell runtime migration history diagnostic' {
    It 'accepts the completed migration history' {
        $result = Invoke-PowerShellMigrationHistoryVerifier $repoRoot
        if ($result.exit_code -ne 0) { Write-Host $result.output }
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
        $parsed.scope | Should Be 'migration_history'
        $parsed.tasks | Should Be 5
        $parsed.done | Should Be 5
        $parsed.historical_evidence | Should Be 'preserved'
        $parsed.typed_core_production_status | Should Be 'not_started'
        $parsed.current_p6_admission_status | Should Be 'admitted'
    }

    It 'fails closed when historical Phase 0 compatibility evidence is erased' {
        $fixtureRoot = New-PowerShellMigrationHistoryFixture 'historical-truth'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tasks\skills-manager-vnext-phase0.tasks.json') -Value '{"schema_version":1,"tasks":[]}' -Encoding UTF8

        $parsed = (Invoke-PowerShellMigrationHistoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'historical_truth_missing').Count | Should Be 1
    }

    It 'fails closed when a historical truth surface restores the bounded-smoke policy' {
        $fixtureRoot = New-PowerShellMigrationHistoryFixture 'current-policy'
        $path = Join-Path $fixtureRoot 'docs\superpowers\specs\2026-08-03-lean-ai-delivery-maintenance-design.md'
        $text = (Get-Content -LiteralPath $path -Raw).Replace('POWERSHELL_COMPATIBILITY_STATUS: ps7_only', 'POWERSHELL_COMPATIBILITY_STATUS: ps7_primary_ps51_bounded_smoke')
        Set-Content -LiteralPath $path -Value $text -Encoding UTF8

        $parsed = (Invoke-PowerShellMigrationHistoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object { $_.code -in @('current_policy_missing', 'stale_current_policy_detected') }).Count | Should Be 2
    }

    It 'fails closed when migration history is misreported as TC2 integration' {
        $fixtureRoot = New-PowerShellMigrationHistoryFixture 'typed-core-boundary'
        $path = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-typed-core-pilot.tasks.json'
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $manifest.tc2_status = 'repo_verified'
        $manifest.production_integration_status = 'integrated'
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $parsed = (Invoke-PowerShellMigrationHistoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'typed_core_boundary_invalid').Count | Should Be 1
    }
}
