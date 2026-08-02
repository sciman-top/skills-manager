Describe 'host capability and truth-state matrix' {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\verify-host-capability-matrix.ps1'
    $currentMatrixPath = Join-Path $repoRoot 'config\host-capability-matrix.json'

    function Invoke-MatrixVerifier([string]$Path) {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -MatrixPath $Path -Json 2>&1)
        return [pscustomobject]@{
            exit_code = $LASTEXITCODE
            result = (($output -join "`n") | ConvertFrom-Json)
        }
    }

    function New-MatrixFixture([string]$Name) {
        $path = Join-Path $TestDrive ($Name + '.json')
        Copy-Item -LiteralPath $currentMatrixPath -Destination $path -Force
        return $path
    }

    function Save-MatrixFixture([string]$Path, $Value) {
        $json = $Value | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    }

    It 'accepts the current matrix without modifying it' {
        $before = (Get-FileHash -LiteralPath $currentMatrixPath -Algorithm SHA256).Hash
        $run = Invoke-MatrixVerifier $currentMatrixPath
        $after = (Get-FileHash -LiteralPath $currentMatrixPath -Algorithm SHA256).Hash

        $run.exit_code | Should Be 0
        $run.result.pass | Should Be $true
        $run.result.host_count | Should Be 5
        $run.result.finding_count | Should Be 0
        $before | Should Be $after
        $run.result.matrix_sha256_before | Should Be $run.result.matrix_sha256_after
    }

    It 'fails closed on an invalid enum' {
        $path = New-MatrixFixture 'invalid-enum'
        $matrix = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $matrix.hosts[0].surfaces[0].support_status = 'available_maybe'
        Save-MatrixFixture $path $matrix

        $run = Invoke-MatrixVerifier $path

        $run.exit_code | Should Be 2
        @($run.result.findings | Where-Object code -eq 'support_status_invalid').Count | Should Be 1
    }

    It 'requires evidence for affirmative support claims' {
        $path = New-MatrixFixture 'missing-evidence'
        $matrix = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $matrix.hosts[0].surfaces[0].evidence_refs = @()
        Save-MatrixFixture $path $matrix

        $run = Invoke-MatrixVerifier $path

        $run.exit_code | Should Be 2
        @($run.result.findings | Where-Object code -eq 'affirmative_evidence_missing').Count | Should Be 1
    }

    It 'forbids automated live acceptance' {
        $path = New-MatrixFixture 'automated-live'
        $matrix = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $matrix.automated_verification_levels += 'live_accepted'
        $matrix.hosts[0].surfaces[0].maximum_automated_verification = 'live_accepted'
        Save-MatrixFixture $path $matrix

        $run = Invoke-MatrixVerifier $path

        $run.exit_code | Should Be 2
        @($run.result.findings | Where-Object code -eq 'automated_live_acceptance_forbidden').Count | Should BeGreaterThan 0
    }

    It 'keeps unknown surfaces read-only and not verified' {
        $path = New-MatrixFixture 'unknown-write'
        $matrix = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $unknown = @($matrix.hosts | Where-Object host_id -eq 'chatgpt_work')[0].surfaces[0]
        $unknown.managed_write_paths = @('hosted://invented-path')
        $unknown.maximum_automated_verification = 'repo_verified'
        Save-MatrixFixture $path $matrix

        $run = Invoke-MatrixVerifier $path

        $run.exit_code | Should Be 2
        @($run.result.findings | Where-Object code -eq 'unknown_surface_write_forbidden').Count | Should Be 1
        @($run.result.findings | Where-Object code -eq 'unknown_surface_verification_invalid').Count | Should Be 1
    }

    It 'contains no host mutation or live inventory operations in the verifier' {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should Not Match '(?im)^\s*(Set-Content|Add-Content|Remove-Item|Move-Item|Copy-Item|Start-Process|Invoke-WebRequest)\b'
        $source | Should Not Match '(?i)\.codex[/\\]config\.toml|\.claude[/\\]settings\.json'
    }
}
