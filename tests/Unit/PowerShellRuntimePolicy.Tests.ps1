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
        '.gitlab-ci.yml'
    )) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $fixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    # Mutation cases exercise one targeted contract each. The current-repository
    # acceptance above already parses the real generated bundle, so keep fixture
    # replays deterministic without reparsing the same 1+ MiB bundle eight times.
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot 'skills.ps1'),
        "#requires -Version 7.0`r`n# focused generated-bundle fixture`r`n",
        [Text.UTF8Encoding]::new($true)
    )

    return $fixtureRoot
}

Describe 'PowerShell 7-only runtime policy verifier' {
    It 'accepts the current PS7-only repository contract' {
        $result = Invoke-PowerShellRuntimePolicyVerifier $repoRoot
        if ($result.exit_code -ne 0) { Write-Host $result.output }
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
        $parsed.scope | Should Be 'active_runtime'
        $parsed.runtime_policy | Should Be 'ps7_only'
        $parsed.tasks | Should Be 0
        $parsed.historical_evidence | Should Be 'not_evaluated'
        $parsed.powershell_files_scanned | Should BeGreaterThan 0
        @($parsed.findings).Count | Should Be 0
    }

    It 'keeps mutation fixtures focused instead of copying the multi-megabyte generated bundle' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'fixture-size'
        (Get-Item -LiteralPath (Join-Path $fixtureRoot 'skills.ps1')).Length | Should BeLessThan 4096
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

    It 'excludes transaction backups from the active PowerShell estate' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'transaction-backup-boundary'
        $backupPath = Join-Path $fixtureRoot '.txn\build-fixture\agent.backup\legacy.ps1'
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        Set-Content -LiteralPath $backupPath -Value '& powershell.exe -NoProfile' -Encoding UTF8

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        if ($result.exit_code -ne 0) { Write-Host $result.output }
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
        @($parsed.findings | Where-Object code -eq 'legacy_runtime_invocation_detected').Count | Should Be 0
    }

    It 'checks the generated bundle through its dedicated policy instead of the source estate scan' {
        $fixtureRoot = New-PowerShellRuntimePolicyFixture 'generated-policy-boundary'
        $generatedPath = Join-Path $fixtureRoot 'skills.ps1'
        Add-Content -LiteralPath $generatedPath -Value "`nStart-Process powershell.exe -ArgumentList '-NoProfile'"

        $result = Invoke-PowerShellRuntimePolicyVerifier $fixtureRoot
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 1
        @($parsed.findings | Where-Object { $_.code -eq 'legacy_fallback_detected' -and $_.path -eq 'skills.ps1' }).Count | Should Be 1
        @($parsed.findings | Where-Object { $_.code -eq 'legacy_runtime_invocation_detected' -and $_.path -eq 'skills.ps1' }).Count | Should Be 0
    }

}
