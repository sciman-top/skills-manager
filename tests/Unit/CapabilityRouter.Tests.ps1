Describe 'Capability router fallback' {
    BeforeEach {
        $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:router=Join-Path $repoRoot 'overrides\custom\capability-router\scripts\route-capability.ps1'
        $script:root=Join-Path $TestDrive 'skills';$routerRoot=Join-Path $root 'capability-router';$skillRoot=Join-Path $root 'codebase-design'
        New-Item -ItemType Directory -Path $routerRoot,$skillRoot -Force|Out-Null
        $skillPath=Join-Path $skillRoot 'SKILL.md';"---`nname: codebase-design`ndescription: Design modules.`n---"|Set-Content $skillPath
        [ordered]@{schema_version=1;domains=@([ordered]@{name='engineering';purpose='Engineering';skill_names=@('codebase-design')});skills=@([ordered]@{name='codebase-design';description='Design modules.';relative_path='..\codebase-design\SKILL.md';entrypoint_sha256=(Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant();load_side_effect='read_only'})}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $routerRoot 'catalog.json')
        $script:catalog=Join-Path $routerRoot 'catalog.json';$script:skillPath=$skillPath
    }

    It 'discovers contained candidates without semantic ranking or writes' {
        $result=& pwsh -NoProfile -File $router -Query 'design' -CatalogPath $catalog -DomainHint engineering|ConvertFrom-Json
        @($result.retrieval.candidates.name)|Should -Be @('codebase-design')
        $result.decision_owner|Should -Be 'host_ai'
        $result.semantic_routing_performed|Should -Be $false
        $result.writes_performed|Should -Be $false
        @($result.PSObject.Properties.Name)|Should -Not -Contain 'activation_plan'
        @($result.PSObject.Properties.Name)|Should -Not -Contain 'session_plan'
    }

    It 'validates an exact candidate and reports disclosed side effects' {
        $result=& pwsh -NoProfile -File $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design'|ConvertFrom-Json
        $result.validation.pass|Should -Be $true
        $result.selected[0].contained|Should -Be $true
        $result.selected[0].load_side_effect|Should -Be 'read_only'
    }

    It 'fails closed on catalog drift and explicit exclusion' {
        Add-Content $skillPath '# drift'
        $stale=& pwsh -NoProfile -File $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design'|ConvertFrom-Json
        $stale.validation.pass|Should -Be $false
        @($stale.excluded.reason)|Should -Contain 'catalog_stale'

        $fresh=Get-Content $catalog -Raw|ConvertFrom-Json;$fresh.skills[0].entrypoint_sha256=(Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant();$fresh|ConvertTo-Json -Depth 10|Set-Content $catalog
        $excluded=& pwsh -NoProfile -File $router -Query 'design' -CatalogPath $catalog -ExcludeCapability 'skill|codebase-design'|ConvertFrom-Json
        @($excluded.retrieval.candidates).Count|Should -Be 0
    }

    It 'is implicit-eligible only as a narrow cold-discovery fallback' {
        $metadata = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\capability-router\agents\openai.yaml')
        $skill = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\capability-router\SKILL.md')

        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $metadata | Should -Match 'visible metadata is insufficient'
        $metadata | Should -Match 'never use it as middleware'
        $skill | Should -Match 'do not use as a normal preflight'
    }
}
