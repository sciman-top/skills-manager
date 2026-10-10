Describe 'Portable capability-router cold discovery' {
    BeforeAll {
. (Join-Path $PSScriptRoot '..\Shared\TestHelpers.ps1')

    }

    BeforeEach {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $sourceRouter = Join-Path $repoRoot 'overrides\custom\capability-router\scripts\route-capability.ps1'
        $portableRoot = Join-Path $TestDrive 'portable-skills'
        # Pester 6 keeps one TestDrive per file; earlier scenarios in this file
        # drop a neutral .skills-manager catalog that would win the auto-discover
        # search, so every scenario must start from a clean portable root. The
        # stable fixture directories are reused and their files rewritten below;
        # only scenario artifacts that do not belong to the fixture are removed.
        # Deleting the whole root instead costs seconds per scenario in a
        # sandboxed host, where deletion is charged per directory node (see
        # docs/runbooks/agent-sandbox-instrumentation.md), while rewriting the
        # fixture files is effectively free.
        if (Test-Path -LiteralPath $portableRoot) {
            foreach ($stale in @([IO.Directory]::GetDirectories($portableRoot, '*', [IO.SearchOption]::TopDirectoryOnly))) {
                if ([IO.Path]::GetFileName($stale) -notin @('capability-router', 'codebase-design')) {
                    Remove-Item -LiteralPath $stale -Recurse -Force
                }
            }
            foreach ($staleFile in @([IO.Directory]::GetFiles($portableRoot, '*', [IO.SearchOption]::TopDirectoryOnly))) {
                Remove-Item -LiteralPath $staleFile -Force
            }
        }
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
                    package_sha256 = Get-TestPackageSha256 $targetRoot
                    domains = @('engineering')
                    load_side_effect = 'read_only'
                    side_effect = 'unknown'
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
            $domains = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界和工程终态' -AutoDiscover | ConvertFrom-Json
            $candidates = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界和工程终态' -AutoDiscover -DomainHint engineering | ConvertFrom-Json
        }
        finally {
            Pop-Location
        }

        $domains.catalog_path | Should -Match 'capability-router[\\/]catalog\.json$'
        $domains.catalog.status | Should -Be 'current'
        @($domains.discovery_domains.name) | Should -Contain 'engineering'
        $domains.decision_owner | Should -Be 'host_ai'
        $domains.semantic_routing_performed | Should -Be $false
        $domains.retrieval.strategy | Should -Be 'catalog_discovery'
        @($domains.retrieval.candidates.name) | Should -Contain 'codebase-design'
        @($candidates.retrieval.candidates.name) | Should -Contain 'codebase-design'
        $candidate = @($candidates.retrieval.candidates | Where-Object name -eq 'codebase-design')[0]
        $candidate.path | Should -Be (Join-Path $portableRoot 'codebase-design\SKILL.md')
        $candidate.description | Should -Be 'Design module boundaries, stable interfaces, and an evidence-based target architecture.'
        $candidate.load_side_effect | Should -Be 'read_only'
        $candidates.writes_performed | Should -Be $false
    }

    It 'prefers the neutral discovery catalog and keeps the legacy router catalog as fallback' {
        $neutralRoot = Join-Path $portableRoot '.skills-manager'
        New-Item -ItemType Directory -Path $neutralRoot -Force | Out-Null
        $neutralCatalog = Get-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Raw | ConvertFrom-Json
        $neutralCatalog.skills[0].relative_path = '..\codebase-design\SKILL.md'
        $neutralCatalog.catalog_fingerprint = Get-TestSha256 ($neutralCatalog | Select-Object -Property * -ExcludeProperty catalog_fingerprint | ConvertTo-Json -Depth 20 -Compress)
        $neutralCatalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $neutralRoot 'catalog.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Encoding UTF8 -Value '{"schema_version":1,"skills":[]}'

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界' -AutoDiscover | ConvertFrom-Json

        $result.catalog_path | Should -Match '\.skills-manager[\\/]catalog\.json$'
        @($result.retrieval.candidates.name) | Should -Contain 'codebase-design'
    }

    It 'resolves cold skills through the router junction when siblings are not resident' {
        $residentRoot = Join-Path $TestDrive 'resident-skills'
        New-Item -ItemType Directory -Path $residentRoot -Force | Out-Null
        $residentRouter = Join-Path $residentRoot 'capability-router'
        New-Item -ItemType Junction -Path $residentRouter -Target $routerRoot | Out-Null

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $residentRouter 'scripts\route-capability.ps1') `
            -Query '设计模块边界和工程终态' -AutoDiscover -DomainHint engineering | ConvertFrom-Json

        (Test-Path -LiteralPath (Join-Path $residentRoot 'codebase-design')) | Should -Be $false
        $result.catalog.status | Should -Be 'current'
        $candidate = @($result.retrieval.candidates | Where-Object name -eq 'codebase-design')[0]
        $candidate.path | Should -Be (Join-Path $portableRoot 'codebase-design\SKILL.md')
    }

    It 'canonicalizes an explicit catalog path through the router junction only' {
        $residentRoot = Join-Path $TestDrive 'resident-skills-explicit'
        New-Item -ItemType Directory -Path $residentRoot -Force | Out-Null
        $residentRouter = Join-Path $residentRoot 'capability-router'
        New-Item -ItemType Junction -Path $residentRouter -Target $routerRoot | Out-Null

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $residentRouter 'scripts\route-capability.ps1') `
            -Query '设计模块边界和工程终态' -CatalogPath (Join-Path $residentRouter 'catalog.json') -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $result.catalog_resolution.mode | Should -Be 'explicit'
        $result.catalog_path | Should -Be (Join-Path $routerRoot 'catalog.json')
        $result.catalog.status | Should -Be 'current'
        $result.load_validation.pass | Should -BeTrue
        $result.selected[0].path | Should -Be (Join-Path $portableRoot 'codebase-design\SKILL.md')
    }

    It 'canonicalizes an environment catalog path whose junction parent belongs to a foreign root' {
        $residentRoot = Join-Path $TestDrive 'resident-skills-environment'
        New-Item -ItemType Directory -Path $residentRoot -Force | Out-Null
        $residentRouter = Join-Path $residentRoot 'capability-router'
        New-Item -ItemType Junction -Path $residentRouter -Target $routerRoot | Out-Null

        $env:SKILLS_MANAGER_CAPABILITY_CATALOG = Join-Path $residentRouter 'catalog.json'
        try {
            $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript `
                -Query '设计模块边界和工程终态' -Candidate 'skill|codebase-design' | ConvertFrom-Json
        }
        finally {
            Remove-Item Env:\SKILLS_MANAGER_CAPABILITY_CATALOG -ErrorAction SilentlyContinue
        }

        $result.catalog_resolution.mode | Should -Be 'environment'
        $result.catalog_path | Should -Be (Join-Path $routerRoot 'catalog.json')
        $result.catalog.status | Should -Be 'current'
        $result.load_validation.pass | Should -BeTrue
        $result.selected[0].path | Should -Be (Join-Path $portableRoot 'codebase-design\SKILL.md')
    }

    It 'fails closed when a junction-form environment catalog has no physical counterpart' {
        $emptyTarget = Join-Path $TestDrive 'router-without-catalog'
        New-Item -ItemType Directory -Path $emptyTarget -Force | Out-Null
        $residentRoot = Join-Path $TestDrive 'resident-skills-missing-catalog'
        New-Item -ItemType Directory -Path $residentRoot -Force | Out-Null
        $residentRouter = Join-Path $residentRoot 'capability-router'
        New-Item -ItemType Junction -Path $residentRouter -Target $emptyTarget | Out-Null

        $env:SKILLS_MANAGER_CAPABILITY_CATALOG = Join-Path $residentRouter 'catalog.json'
        try {
            $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript `
                -Query '设计模块边界和工程终态' -Candidate 'skill|codebase-design' | ConvertFrom-Json
        }
        finally {
            Remove-Item Env:\SKILLS_MANAGER_CAPABILITY_CATALOG -ErrorAction SilentlyContinue
        }

        $result.catalog_resolution.mode | Should -Be 'environment'
        $result.catalog_path | Should -Be ''
        @($result.catalog.findings.code) | Should -Contain 'catalog_not_found'
        @($result.retrieval.candidates).Count | Should -Be 0
        $result.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_blocked'
    }


    It 'excludes a cold skill when its entrypoint no longer matches the catalog hash' {
        Add-Content -LiteralPath (Join-Path $targetRoot 'SKILL.md') -Encoding UTF8 -Value "`n# Drift after catalog projection"

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript `
            -Query '设计模块边界和工程终态' -AutoDiscover -DomainHint engineering -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $result.catalog.status | Should -Be 'stale'
        @($result.retrieval.candidates.name) | Should -Not -Contain 'codebase-design'
        @($result.selected.name) | Should -Not -Contain 'codebase-design'
        @($result.excluded | Where-Object { $_.name -eq 'codebase-design' -and $_.reason -eq 'catalog_stale' }).Count | Should -Be 1
    }

    It 'requires explicit auto-discovery when no catalog path or environment override is supplied' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界' | ConvertFrom-Json

        $result.catalog.status | Should -Be 'invalid'
        @($result.catalog.findings.code) | Should -Contain 'catalog_path_required'
        @($result.retrieval.candidates).Count | Should -Be 0
    }

    It 'names the missing sibling and keeps validating the intact copy in a copied router root' {
        # 2026-10-09 scoped 决议（修订 F4 live-probe 2026-10-03）：一次 F4 观测把
        # "one stale entry fails the whole directory" 钉为全局阻断；实机证明这会把
        # 单条无关漂移放大为整本目录冷发现停摆（"看似已投影、实际冷发现失效"）。
        # 每个候选行已有独立的 entrypoint/package hash 与 containment 校验，字节
        # 不一致的复制品本来就过不了校验；因此漂移条目按名排除、catalog.status
        # 保持 stale，逐行验证过的完整候选照常发现与校验，receipt 不夸大边界。
        $ghostRoot = Join-Path $portableRoot 'ghost-cold-skill'
        $catalogDoc = Get-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Raw | ConvertFrom-Json
        $ghostEntry = [ordered]@{
            name = 'ghost-cold-skill'
            description = 'Cold skill that only exists in the managed tree, never in this copied host root.'
            relative_path = '..\ghost-cold-skill\SKILL.md'
            entrypoint_sha256 = ('a' * 64)
            package_sha256 = ('b' * 64)
            domains = @('engineering')
            load_side_effect = 'read_only'
            side_effect = 'unknown'
            routing_rules = @()
        }
        $catalogDoc.skills = @($catalogDoc.skills) + @($ghostEntry)
        $catalogDoc.domains[0].skill_names = @($catalogDoc.domains[0].skill_names) + @('ghost-cold-skill')
        $catalogDoc.catalog_fingerprint = Get-TestSha256 ($catalogDoc | Select-Object -Property * -ExcludeProperty catalog_fingerprint | ConvertTo-Json -Depth 20 -Compress)
        $catalogDoc | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Encoding UTF8
        New-Item -ItemType Directory -Path $ghostRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $ghostRoot 'SKILL.md') -Encoding UTF8 -Value 'placeholder used only to compute nothing'

        # Simulate the host receiving only the router package: remove the
        # sibling copy after the catalog (whose hashes still point at it) is in
        # place; in a real host root the cold skills were never projected.
        Remove-Item -LiteralPath $ghostRoot -Recurse -Force

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript -Query '设计模块边界和工程终态' -AutoDiscover -DomainHint engineering | ConvertFrom-Json

        $result.catalog.status | Should -Be 'stale'
        $result.routing_receipt.status | Should -Be 'candidates_returned'
        $result.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_only'
        @($result.retrieval.candidates.name) | Should -Contain 'codebase-design'
        @($result.retrieval.candidates.name) | Should -Not -Contain 'ghost-cold-skill'
        @($result.selected.name) | Should -Not -Contain 'ghost-cold-skill'
        @($result.excluded | Where-Object { $_.name -eq 'ghost-cold-skill' -and $_.reason -eq 'entrypoint_unavailable' }).Count | Should -Be 1

        $validated = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript `
            -Query '设计模块边界和工程终态' -AutoDiscover -Candidate 'skill|codebase-design' | ConvertFrom-Json
        $validated.load_validation.pass | Should -Be $true
        $validated.routing_receipt.truth_boundary | Should -Be 'candidate_load_validated'
        $validated.routing_receipt.status | Should -Be 'validated'
    }

    It 'fails closed when the environment catalog is a reachable but stale copy' {
        # A copied catalog that is still loadable (valid JSON, valid schema) but
        # whose content no longer matches its fingerprint must not validate any
        # candidate; otherwise a host root could keep an outdated mirror alive.
        $staleCopyRoot = Join-Path $TestDrive 'stale-catalog-copy'
        New-Item -ItemType Directory -Path $staleCopyRoot -Force | Out-Null
        $catalogDoc = Get-Content -LiteralPath (Join-Path $routerRoot 'catalog.json') -Raw | ConvertFrom-Json
        $catalogDoc.skills[0].description = $catalogDoc.skills[0].description + ' (tampered after fingerprint)'
        $catalogDoc | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $staleCopyRoot 'catalog.json') -Encoding UTF8

        $env:SKILLS_MANAGER_CAPABILITY_CATALOG = Join-Path $staleCopyRoot 'catalog.json'
        try {
            $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:routerScript `
                -Query '设计模块边界和工程终态' -Candidate 'skill|codebase-design' | ConvertFrom-Json
        }
        finally {
            Remove-Item Env:\SKILLS_MANAGER_CAPABILITY_CATALOG -ErrorAction SilentlyContinue
        }

        $result.catalog_resolution.mode | Should -Be 'environment'
        $result.catalog.status | Should -Be 'invalid'
        @($result.catalog.findings.code) | Should -Contain 'catalog_fingerprint_mismatch'
        @($result.retrieval.candidates).Count | Should -Be 0
        $result.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_blocked'
    }

    It 'restores discovery for a copy-form host root by pinning the managed catalog through the environment' {
        # Operational mitigation for the copy-form failure: an explicit catalog
        # pin (env or -CatalogPath) resolves siblings inside the managed tree,
        # where the real files live, so validation succeeds again.
        $copyHostRoot = Join-Path $TestDrive 'copy-host-skills'
        $copyRouter = Join-Path $copyHostRoot 'capability-router'
        New-Item -ItemType Directory -Path (Join-Path $copyRouter 'scripts') -Force | Out-Null
        Copy-Item -LiteralPath $script:routerScript -Destination (Join-Path $copyRouter 'scripts\route-capability.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $routerRoot 'catalog.json') -Destination (Join-Path $copyRouter 'catalog.json') -Force

        # Without the managed catalog pin, the copied router can read its valid
        # catalog but none of the referenced sibling entrypoints exist.  This
        # must be an explicit projection failure, not an empty successful
        # discovery that the host could mistake for a semantic no-match.
        $unbound = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copyRouter 'scripts\route-capability.ps1') `
            -Query '设计模块边界和工程终态' -AutoDiscover -DomainHint engineering | ConvertFrom-Json
        $unbound.catalog.status | Should -Be 'stale'
        @($unbound.catalog.diagnostics | Where-Object code -eq 'catalog_projection_incomplete').Count | Should -Be 1
        $unbound.routing_receipt.status | Should -Be 'blocked'
        $unbound.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_blocked'
        @($unbound.retrieval.candidates).Count | Should -Be 0

        $env:SKILLS_MANAGER_CAPABILITY_CATALOG = Join-Path $routerRoot 'catalog.json'
        try {
            $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copyRouter 'scripts\route-capability.ps1') `
                -Query '设计模块边界和工程终态' -DomainHint engineering | ConvertFrom-Json
        }
        finally {
            Remove-Item Env:\SKILLS_MANAGER_CAPABILITY_CATALOG -ErrorAction SilentlyContinue
        }

        $result.catalog_resolution.mode | Should -Be 'environment'
        $result.catalog.status | Should -Be 'current'
        @($result.retrieval.candidates.name) | Should -Contain 'codebase-design'
    }
}
