Describe 'Cross-host model orchestration static contract' {
    BeforeAll {
        $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:prd = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot 'docs\product\cross-host-model-orchestration-prd.md')
        $script:architecture = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot 'docs\product\cross-host-model-orchestration-architecture.md')
        $script:mor000 = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot 'docs\decision\MOR-000-brief.md')
        $script:mor001 = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot 'docs\decision\MOR-001-automatic-failover-simulation.md')
    }

    It 'keeps the five semantic slots stable and gives deep investigation both operations' {
        $slotNames = @(
            'quick_triage',
            'routine_maintenance',
            'standard_review',
            'bounded_implementation',
            'deep_investigation_or_implementation'
        )

        foreach ($slot in $slotNames) {
            $script:prd | Should -Match ([regex]::Escape("| ``$slot`` |"))
            $script:architecture | Should -Match ([regex]::Escape("| ``$slot`` |"))
        }

        $deepSlot = 'deep_investigation_or_implementation: \{ route_key: deep, operations: \[read_only, workspace_write\] \}'
        $script:prd | Should -Match $deepSlot
        $script:architecture | Should -Match $deepSlot
        $script:prd | Should -Not -Match 'deep_investigation_or_implementation: \{ route_key: deep, operation: workspace_write \}'
        $script:architecture | Should -Not -Match 'deep_investigation_or_implementation: \{ route_key: deep, operation: workspace_write \}'
    }

    It 'makes high risk route promotion deterministic after the gate' {
        $script:prd | Should -Match 'risk_level=high.*route_key=deep'
        $script:architecture | Should -Match 'risk_level=high.*route_key=deep'
        $script:prd | Should -Match 'gate 通过后强制.*route_key=deep'
        $script:architecture | Should -Match 'gate 通过后.*route_key=deep'
    }

    It 'defines only-preset scope without silently rewriting child roles' {
        foreach ($document in @($script:prd, $script:architecture, $script:mor000)) {
            $document | Should -Match 'parent_route_only'
            $document | Should -Match '不自动.*(?:覆盖|重写|约束).*(?:native bridge|custom subagent)'
        }
    }

    It 'keeps automatic failover stricter than ordinary high-risk resolve' {
        $script:mor001 | Should -Match 'risk_level=high'
        $script:mor001 | Should -Match 'blocked_high_risk'
        $script:mor001 | Should -Match '自动切换.*(?:不得|不能|不继承)'
    }

    It 'keeps the canonical tuple matrix validator executable' {
        $validator = Join-Path $script:repoRoot 'scripts\quality\validate-mor-tuple-matrix.ps1'
        & pwsh -NoProfile -File $validator | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
