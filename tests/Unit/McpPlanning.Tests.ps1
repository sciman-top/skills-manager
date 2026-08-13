BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

}
Describe 'MCP machine-readable planning' {
    BeforeAll {
$createdAt = '2026-08-01T08:00:00Z'
$sourceRevision = 'f' * 64
function New-TestMcpServer([string]$Name = 'fixture') {
        return [pscustomobject]@{
            name = $Name
            transport = 'stdio'
            command = 'fixture-command'
            args = @('--token', '${FIXTURE_ARG_TOKEN}')
            env = [pscustomobject]@{ API_TOKEN = '${FIXTURE_ENV_TOKEN}' }
        }
    }
function New-TestDesiredState([string]$Root, [bool]$ExistingMatches = $false) {
        $specs = @(Get-McpSyncManagedTargetSpecs -Roots @(
                (Join-Path $Root '.codex'),
                (Join-Path $Root '.gemini'),
                (Join-Path $Root '.trae')
            ) -CandidatePaths @() -RepoRoot $Root)
        $server = New-TestMcpServer
        $initial = New-McpSyncDesiredState -Specs $specs -Servers @($server) -ActiveServers @($server)
        $states = @{}
        foreach ($target in @($initial)) {
            $states[(Normalize-OperationPathKey $target.path)] = [pscustomobject]@{
                exists = $ExistingMatches
                content = if ($ExistingMatches) { [string]$target.desired_content } else { '' }
            }
        }
        return @(New-McpSyncDesiredState -Specs $specs -Servers @($server) -ActiveServers @($server) -ExistingStates $states)
    }
}

    It 'enumerates only known managed targets and adds project Trae only when Trae is present' {
        $root = Join-Path $TestDrive 'targets'
        $repo = Join-Path $TestDrive 'repo'
        $withoutTrae = @(Get-McpSyncManagedTargetSpecs -Roots @((Join-Path $root '.codex')) -RepoRoot $root)
        $withTrae = @(Get-McpSyncManagedTargetSpecs -Roots @(
                (Join-Path $root '.codex'),
                (Join-Path $root '.gemini'),
                (Join-Path $root '.trae')
            ) -RepoRoot $repo)

        @($withoutTrae | Where-Object kind -eq 'trae_project_json').Count | Should -Be 0
        (@($withTrae.kind | Sort-Object) -join ',') | Should -Be 'codex_toml,gemini_settings,generic_json,generic_json,generic_json,trae_json,trae_project_json'
        @($withTrae | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.path) }).Count | Should -Be 0
    }

    It 'produces stable targets actions ids and hashes across repeated plans' {
        $desired = New-TestDesiredState (Join-Path $TestDrive 'stable')
        $first = New-McpSyncOperationPlanResult -DesiredState $desired -CreatedAt $createdAt -SourceRevision $sourceRevision
        $second = New-McpSyncOperationPlanResult -DesiredState @($desired | Sort-Object target_ref -Descending) -CreatedAt $createdAt -SourceRevision $sourceRevision

        ($first | ConvertTo-Json -Depth 50 -Compress) | Should -Be ($second | ConvertTo-Json -Depth 50 -Compress)
        (Test-OperationPlanContract $first.operation_plan).pass | Should -Be $true
        @($first.operation_plan.targets).Count | Should -Be @($desired).Count
        @($first.operation_plan.actions).Count | Should -Be @($desired).Count
    }

    It 'reports changed and unchanged targets without exposing desired content or secrets' {
        $root = Join-Path $TestDrive 'summary'
        $changed = @(New-TestDesiredState $root)
        $unchanged = @(New-TestDesiredState $root $true)
        $mixed = @($changed[0], $unchanged[1])
        $result = New-McpSyncOperationPlanResult -DesiredState $mixed -CreatedAt $createdAt -SourceRevision $sourceRevision
        $json = $result | ConvertTo-Json -Depth 50 -Compress

        $result.summary.changed_target_count | Should -Be 1
        $result.summary.unchanged_target_count | Should -Be 1
        @($result.operation_plan.actions).Count | Should -Be 1
        $result.summary.native_mutation_planned | Should -Be $false
        $result.summary.profile_changed | Should -Be $false
        foreach ($secret in @('FIXTURE_ARG_TOKEN', 'FIXTURE_ENV_TOKEN', 'API_TOKEN', 'desired_content')) {
            $json | Should -Not -Match ([regex]::Escape($secret))
        }
    }

    It 'keeps plan target refs and paths identical to the desired state consumed by apply' {
        $desired = @(New-TestDesiredState (Join-Path $TestDrive 'parity'))
        $result = New-McpSyncOperationPlanResult -DesiredState $desired -CreatedAt $createdAt -SourceRevision $sourceRevision

        (@($result.operation_plan.targets.target_ref | Sort-Object) -join ',') | Should -Be (@($desired.target_ref | Sort-Object) -join ',')
        (@($result.operation_plan.targets.path | Sort-Object) -join ',') | Should -Be (@($desired.path | Sort-Object) -join ',')
    }

    It 'does not write managed targets or invoke native mutation in plan mode' {
        $root = Join-Path $TestDrive 'zero-write'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $targetPath = Join-Path $root '.codex\config.toml'
        $desired = @(New-TestDesiredState $root)
        $beforeCfgHash = (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash
        Mock Get-McpSyncPlanningContext { [pscustomobject]@{ desired_state = $desired; config_revision = $sourceRevision } }
        Mock Invoke-NativeMcpSync {}
        Mock Invoke-NativeMcpCleanup {}

        $json = Invoke-McpSyncPlan -Json | ConvertFrom-Json

        $json.kind | Should -Be 'mcp_sync_plan'
        (Test-Path -LiteralPath $targetPath) | Should -Be $false
        (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash | Should -Be $beforeCfgHash
        Should -Invoke Invoke-NativeMcpSync -Times 0 -Exactly
        Should -Invoke Invoke-NativeMcpCleanup -Times 0 -Exactly
    }

    It 'writes only the explicitly requested plan output file' {
        $root = Join-Path $TestDrive 'out'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $desired = @(New-TestDesiredState $root)
        $outPath = Join-Path $root 'evidence\mcp-plan.json'
        Mock Get-McpSyncPlanningContext { [pscustomobject]@{ desired_state = $desired; config_revision = $sourceRevision } }

        Invoke-McpSyncPlan -Json -OutPath $outPath | Out-Null

        (Test-Path -LiteralPath $outPath -PathType Leaf) | Should -Be $true
        ((Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json).kind) | Should -Be 'mcp_sync_plan'
        foreach ($target in @($desired)) {
            (Test-Path -LiteralPath ([string]$target.path)) | Should -Be $false
        }
    }

    It 'keeps the Application planner free of IO native environment terminal and global-state calls' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Application\McpPlanning.ps1') -Raw
        $source | Should -Not -Match '(?im)^\s*(Get-Content|Set-Content|Set-ContentUtf8|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|SaveCfg|Write-Host|Write-Output|Invoke-Native\w*)\b'
        $source | Should -Not -Match '(?i)\$(env|script):'
    }

    It 'parses MCP plan options without claiming global doctor JSON arguments' {
        $options = Parse-McpSyncPlanOptions @('--plan', '--json', '--out', '.\plan.json')
        $inline = Parse-McpSyncPlanOptions @('--out=.\inline.json')
        $empty = Parse-McpSyncPlanOptions (Merge-FilterAndArgs $null $null)
        $versionSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Version.ps1') -Raw

        $options.plan | Should -Be $true
        $options.json | Should -Be $true
        $options.out_path | Should -Be '.\plan.json'
        $inline.out_path | Should -Be '.\inline.json'
        $empty.plan | Should -Be $false
        $empty.json | Should -Be $false
        $empty.out_path | Should -Be ''
        $versionSource | Should -Not -Match '(?i)\[switch\]\$Json'
        $versionSource | Should -Not -Match '(?i)\[string\]\$Out'
    }
}
