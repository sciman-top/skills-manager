Describe 'Portable capability-router cold discovery' {
    function Get-TestSha256([string]$Value) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally { $sha.Dispose() }
    }

    BeforeEach {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $sourceRouter = Join-Path $repoRoot 'overrides\custom\capability-router\scripts\route-capability.ps1'
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
        $catalog = [ordered]@{
            schema_version = 1
            decision_owner = 'host_ai'
            semantic_routing_performed = $false
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
                    entrypoint_sha256 = (Get-FileHash -LiteralPath (Join-Path $targetRoot 'SKILL.md') -Algorithm SHA256).Hash.ToLowerInvariant()
                    load_side_effect = 'read_only'
                    routing_rules = @()
                }
            )
            capabilities = @()
        }
        $catalog.catalog_fingerprint = Get-TestSha256 ($catalog | ConvertTo-Json -Depth 20 -Compress)
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Encoding UTF8

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
        $domains.catalog.status | Should Be 'current'
        @($domains.discovery_domains.name) | Should Contain 'engineering'
        $domains.automatic_dispatch.scope | Should Be 'all_catalog_skills'
        $domains.automatic_dispatch.profile_switch_required | Should Be $false
        $domains.retrieval.strategy | Should Be 'global_catalog_discovery'
        @($domains.retrieval.candidates.name) | Should Contain 'codebase-design'
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

    It 'resolves cold skills through the router junction when siblings are not resident' {
        $residentRoot = Join-Path $TestDrive 'resident-skills'
        New-Item -ItemType Directory -Path $residentRoot -Force | Out-Null
        $residentRouter = Join-Path $residentRoot 'capability-router'
        New-Item -ItemType Junction -Path $residentRouter -Target $routerRoot | Out-Null

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $residentRouter 'scripts\route-capability.ps1') `
            -Query '设计模块边界和工程终态' -DomainHint engineering | ConvertFrom-Json

        (Test-Path -LiteralPath (Join-Path $residentRoot 'codebase-design')) | Should Be $false
        $result.catalog.status | Should Be 'current'
        $candidate = @($result.retrieval.candidates | Where-Object name -eq 'codebase-design')[0]
        $candidate.path | Should Be (Join-Path $portableRoot 'codebase-design\SKILL.md')
    }

    It 'excludes a cold skill when its entrypoint no longer matches the catalog hash' {
        Add-Content -LiteralPath (Join-Path $targetRoot 'SKILL.md') -Encoding UTF8 -Value "`n# Drift after catalog projection"

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript `
            -Query '设计模块边界和工程终态' -DomainHint engineering -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $result.catalog.status | Should Be 'stale'
        @($result.retrieval.candidates.name) | Should Not Contain 'codebase-design'
        @($result.selected.name) | Should Not Contain 'codebase-design'
        @($result.excluded | Where-Object { $_.name -eq 'codebase-design' -and $_.reason -eq 'catalog_stale' }).Count | Should Be 1
    }
}
