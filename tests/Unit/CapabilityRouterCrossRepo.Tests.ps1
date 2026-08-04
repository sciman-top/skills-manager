Describe 'Portable capability-router cold discovery' {
    BeforeEach {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $sourceRouter = Join-Path $repoRoot 'overrides\capability-router\scripts\route-capability.ps1'
        $portableRoot = Join-Path $TestDrive 'portable-skills'
        $routerRoot = Join-Path $portableRoot 'capability-router'
        $routerScripts = Join-Path $routerRoot 'scripts'
        $targetRoot = Join-Path $portableRoot 'codebase-design'
        $script:routerScript = Join-Path $routerScripts 'route-capability.ps1'

        New-Item -ItemType Directory -Path $routerScripts, $targetRoot -Force | Out-Null
        Copy-Item -LiteralPath $sourceRouter -Destination $script:routerScript -Force
        Set-Content -LiteralPath (Join-Path $targetRoot 'SKILL.md') -Encoding UTF8 -Value @'
---
name: codebase-design
description: >-
  This source description intentionally uses a YAML block scalar that the portable catalog
  has already normalized.
---

# Codebase design
'@
        [ordered]@{
            schema_version = 1
            domains = @(
                [ordered]@{
                    name = 'engineering'
                    purpose = 'Architecture, product specification, and delivery planning.'
                    skill_names = @('codebase-design')
                }
            )
            skills = @(
                [ordered]@{
                    name = 'codebase-design'
                    description = 'Design module boundaries, stable interfaces, and an evidence-based target architecture.'
                    relative_path = '..\codebase-design\SKILL.md'
                    load_side_effect = 'read_only'
                    routing_rules = @()
                }
            )
            capabilities = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Encoding UTF8

        $script:unrelatedCwd = Join-Path $TestDrive 'unrelated-repository'
        New-Item -ItemType Directory -Path $script:unrelatedCwd -Force | Out-Null
    }

    It 'discovers domains and cold skills without a skills-manager repository manifest' {
        Push-Location $script:unrelatedCwd
        try {
            $domains = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界和工程终态' | ConvertFrom-Json
            $candidates = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界和工程终态' -DomainHint engineering | ConvertFrom-Json
        }
        finally {
            Pop-Location
        }

        $domains.catalog_path | Should Match 'capability-router[\\/]catalog\.json$'
        @($domains.discovery_domains.name) | Should Contain 'engineering'
        @($candidates.retrieval.candidates.name) | Should Contain 'codebase-design'
        $candidate = @($candidates.retrieval.candidates | Where-Object name -eq 'codebase-design')[0]
        $candidate.path | Should Be (Join-Path $portableRoot 'codebase-design\SKILL.md')
        $candidate.description | Should Be 'Design module boundaries, stable interfaces, and an evidence-based target architecture.'
        $candidate.load_side_effect | Should Be 'read_only'
        $candidates.manifest_path | Should BeNullOrEmpty
        $candidates.config_path | Should BeNullOrEmpty
        $candidates.policy_path | Should BeNullOrEmpty
        $candidates.writes_performed | Should Be $false
    }
}
