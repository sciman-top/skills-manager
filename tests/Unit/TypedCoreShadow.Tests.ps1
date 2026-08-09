$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifier = Join-Path $repoRoot 'scripts\verify-typed-core-shadow.ps1'
$planningVerifier = Join-Path $repoRoot 'scripts\verify-typed-core-pilot-planning.ps1'

function Invoke-TypedCorePlanningVerifier([string]$RootPath) {
    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $planningVerifier -RepoRoot $RootPath -Json 2>&1)
    return [pscustomobject]@{
        exit_code = $LASTEXITCODE
        output = ($output -join "`n")
    }
}

function New-TypedCorePlanningFixture([string]$Name) {
    $fixtureRoot = Join-Path $TestDrive ("typed-core-planning-{0}-{1}" -f $Name, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

    foreach ($relativePath in @(
        'tasks/skills-manager-vnext-typed-core-pilot.tasks.json',
        'tasks/skills-manager-vnext-lean-delivery-pilot.json',
        'docs/superpowers/specs/2026-08-05-typed-core-operation-contract-shadow-poc.md',
        'docs/change-evidence/20260805-typed-core-operation-contract-shadow-poc.md',
        'docs/product/skills-manager-vnext-prd.md',
        'docs/product/skills-manager-vnext-architecture.md',
        'docs/product/skills-manager-vnext-roadmap.md',
        'tasks/plan.md',
        'tasks/todo.md',
        'AGENTS.md',
        'typed-core/SkillsManager.TypedCore/SkillsManager.TypedCore.csproj',
        'typed-core/SkillsManager.TypedCore/Program.cs',
        'typed-core/SkillsManager.TypedCore/OperationContractValidator.cs',
        'scripts/verify-typed-core-shadow.ps1',
        'tests/Unit/TypedCoreShadow.Tests.ps1',
        'global.json'
    )) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $fixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    Copy-Item -LiteralPath (Join-Path $repoRoot 'src') -Destination (Join-Path $fixtureRoot 'src') -Recurse -Force
    return $fixtureRoot
}

Describe 'Typed-core OperationPlan and Receipt shadow PoC' {
    It 'pins a supported .NET 10 SDK without prerelease roll-forward' {
        $globalJson = Get-Content -LiteralPath (Join-Path $repoRoot 'global.json') -Raw | ConvertFrom-Json
        $globalJson.sdk.version | Should Be '10.0.302'
        $globalJson.sdk.rollForward | Should Be 'latestPatch'
        $globalJson.sdk.allowPrerelease | Should Be $false
    }

    It 'keeps the typed core package-free and outside the PowerShell runtime bundle' {
        $project = Get-Content -LiteralPath (Join-Path $repoRoot 'typed-core\SkillsManager.TypedCore\SkillsManager.TypedCore.csproj') -Raw
        $project | Should Match '<TargetFramework>net10.0</TargetFramework>'
        $project | Should Not Match '<PackageReference\b'
        $runtimeSource = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Recurse -File -Filter '*.ps1' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $runtimeSource | Should Not Match '(?i)typed-core|skills-manager-typed-core|verify-typed-core-shadow'
    }

    It 'matches the PowerShell validators on the fixed corpus and fails closed on bad requests' {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $verifier -RootPath $repoRoot 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { Write-Host ($output -join "`n") }
        $result = ($output -join "`n") | ConvertFrom-Json

        $exitCode | Should Be 0
        $result.status | Should Be 'pass'
        $result.seam | Should Be 'operation_contract_validation_v1'
        $result.powershell_runtime_authoritative | Should Be $true
        $result.typed_core_mode | Should Be 'shadow_only'
        $result.fixture_count | Should Be 4
        $result.parity_count | Should Be 4
        $result.negative_case_count | Should Be 4
        $result.negative_pass_count | Should Be 4
        @($result.mismatches).Count | Should Be 0
    }

    It 'accepts the current typed-core planning contract' {
        $result = Invoke-TypedCorePlanningVerifier $repoRoot
        if ($result.exit_code -ne 0) { Write-Host $result.output }
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
        $parsed.tasks | Should Be 3
        $parsed.done | Should Be 3
        $parsed.tc1_status | Should Be 'repo_verified'
        $parsed.tc2_status | Should Be 'not_started'
        @($parsed.findings).Count | Should Be 0
    }

    It 'accepts plan and todo as stable indexes without copied typed-core task ids' {
        $fixtureRoot = New-TypedCorePlanningFixture 'manifest-only-task-truth'
        foreach ($relativePath in @('tasks/plan.md', 'tasks/todo.md')) {
            $path = Join-Path $fixtureRoot $relativePath
            $text = Get-Content -LiteralPath $path -Raw
            foreach ($id in @('SMV-TC-001', 'SMV-TC-002', 'SMV-TC-003')) { $text = $text.Replace($id, '') }
            Set-Content -LiteralPath $path -Value $text -Encoding UTF8
        }

        $result = Invoke-TypedCorePlanningVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
    }

    It 'fails closed when production integration status drifts' {
        $fixtureRoot = New-TypedCorePlanningFixture 'production-status'
        $manifestPath = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-typed-core-pilot.tasks.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.production_integration_status = 'integrated'
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = Invoke-TypedCorePlanningVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'production_integration_status_invalid').Count | Should Be 1
    }

    It 'fails closed when a package dependency enters TC1' {
        $fixtureRoot = New-TypedCorePlanningFixture 'package-reference'
        $projectPath = Join-Path $fixtureRoot 'typed-core\SkillsManager.TypedCore\SkillsManager.TypedCore.csproj'
        $project = (Get-Content -LiteralPath $projectPath -Raw).Replace(
            '</Project>',
            '  <ItemGroup><PackageReference Include="Injected.Dependency" Version="1.0.0" /></ItemGroup></Project>'
        )
        Set-Content -LiteralPath $projectPath -Value $project -Encoding UTF8

        $result = Invoke-TypedCorePlanningVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'package_reference_forbidden').Count | Should Be 1
    }

    It 'fails closed when reviewed evidence is missing' {
        $fixtureRoot = New-TypedCorePlanningFixture 'missing-evidence'
        Remove-Item -LiteralPath (Join-Path $fixtureRoot 'docs\change-evidence\20260805-typed-core-operation-contract-shadow-poc.md') -Force

        $result = Invoke-TypedCorePlanningVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object code -eq 'required_file_missing').Count | Should Be 1
    }
}
