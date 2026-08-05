$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifier = Join-Path $repoRoot 'scripts\verify-powershell-runtime-policy.ps1'

function Invoke-PowerShellRuntimePolicyVerifier([string]$RootPath) {
    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $verifier -RepoRoot $RootPath -Json 2>&1)
    return [pscustomobject]@{
        exit_code = $LASTEXITCODE
        output = ($output -join "`n")
    }
}

function New-PowerShellRuntimePolicyFixture([string]$Name) {
    $fixtureRoot = Join-Path $TestDrive ("powershell-runtime-policy-{0}-{1}" -f $Name, [guid]::NewGuid().ToString('N'))
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
        'tasks/plan.md',
        'tasks/todo.md',
        'AGENTS.md',
        'RELEASE_TEMPLATE.md',
        'src/Version.ps1',
        'src/Core.ps1',
        'src/Commands/Mcp.ps1',
        'build.ps1',
        'install.ps1',
        'skills.cmd',
        'skills.ps1',
        '.github/workflows/ci.yml',
        'azure-pipelines.yml',
        '.gitlab-ci.yml',
        'scripts/quality/run-local-quality-gates.ps1'
    )) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $fixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    return $fixtureRoot
}

Describe 'PowerShell 7-only runtime policy verifier' {
    It 'accepts the current PS7-only repository contract' {
        $result = Invoke-PowerShellRuntimePolicyVerifier $repoRoot
        if ($result.exit_code -ne 0) { Write-Host $result.output }
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
        $parsed.runtime_policy | Should Be 'ps7_only'
        $parsed.tasks | Should Be 5
        $parsed.done | Should Be 5
        $parsed.historical_evidence | Should Be 'preserved'
        $parsed.typed_core_production_status | Should Be 'not_started'
        @($parsed.findings).Count | Should Be 0
    }

    It 'fails closed when the source runtime floor drifts to 5.1' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'version-floor'
        $path = Join-Path $fixtureRoot 'src\Version.ps1'
        $text = (Get-Content -LiteralPath $path -Raw).Replace('#requires -Version 7.0', '#requires -Version 5.1')
        Set-Content -LiteralPath $path -Value $text -Encoding UTF8

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'powershell_version_floor_invalid').Count | Should Be 1
    }

    It 'fails closed when a Windows PowerShell fallback returns' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'legacy-fallback'
        $path = Join-Path $fixtureRoot 'src\Core.ps1'
        Add-Content -LiteralPath $path -Value "`nGet-Command powershell.exe"

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'legacy_fallback_detected').Count | Should BeGreaterThan 0
    }

    It 'fails closed when a newly added active script invokes Windows PowerShell' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'dynamic-script-estate'
        $path = Join-Path $fixtureRoot 'scripts\new-entry.ps1'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $path -Value "& powershell.exe -NoProfile -Command 'exit 0'" -Encoding UTF8

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object {
            $_.code -eq 'legacy_runtime_invocation_detected' -and
            $_.path -eq 'scripts/new-entry.ps1'
        }).Count | Should Be 1
    }

    It 'scans active test runners but excludes inert fixture history' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'test-estate-boundary'
        $fixturePath = Join-Path $fixtureRoot 'tests\fixtures\historical-legacy.ps1'
        New-Item -ItemType Directory -Path (Split-Path $fixturePath -Parent) -Force | Out-Null
        Set-Content -LiteralPath $fixturePath -Value '& powershell.exe -NoProfile' -Encoding UTF8

        $allowed = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $allowed.exit_code | Should Be 0

        $activeTestPath = Join-Path $fixtureRoot 'tests\Unit\new-legacy-runner.Tests.ps1'
        New-Item -ItemType Directory -Path (Split-Path $activeTestPath -Parent) -Force | Out-Null
        Set-Content -LiteralPath $activeTestPath -Value 'Start-Process powershell.exe -ArgumentList ''-NoProfile''' -Encoding UTF8

        $rejected = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $rejected.output | ConvertFrom-Json
        $rejected.exit_code | Should Be 1
        @($parsed.findings | Where-Object {
            $_.code -eq 'legacy_runtime_invocation_detected' -and
            $_.path -eq 'tests/Unit/new-legacy-runner.Tests.ps1'
        }).Count | Should Be 1
    }

    It 'fails closed when a current truth surface restores the bounded-smoke policy' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'current-policy'
        $path = Join-Path $fixtureRoot 'docs\superpowers\specs\2026-08-03-lean-ai-delivery-maintenance-design.md'
        $text = (Get-Content -LiteralPath $path -Raw).Replace('POWERSHELL_COMPATIBILITY_STATUS: ps7_only', 'POWERSHELL_COMPATIBILITY_STATUS: ps7_primary_ps51_bounded_smoke')
        Set-Content -LiteralPath $path -Value $text -Encoding UTF8

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object { $_.code -in @('current_policy_missing', 'stale_current_policy_detected') }).Count | Should Be 2
    }

    It 'fails closed when historical Phase 0 compatibility evidence is erased' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'historical-truth'
        $path = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-phase0.tasks.json'
        Set-Content -LiteralPath $path -Value '{"schema_version":1,"tasks":[]}' -Encoding UTF8

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'historical_truth_missing').Count | Should Be 1
    }

    It 'fails closed when PS7 support contraction is misreported as TC2 integration' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'typed-core-boundary'
        $path = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-typed-core-pilot.tasks.json'
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $manifest.tc2_status = 'repo_verified'
        $manifest.production_integration_status = 'integrated'
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'typed_core_boundary_invalid').Count | Should Be 1
    }
}
