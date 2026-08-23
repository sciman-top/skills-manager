Describe 'Capability router fallback' {
    BeforeAll {
        function Get-TestSha256([string]$Value) {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') }
            finally { $sha.Dispose() }
        }

        function Set-TestCatalogFingerprint($Document) {
            $payload = [ordered]@{}
            foreach ($property in @($Document.PSObject.Properties)) {
                if ($property.Name -ne 'catalog_fingerprint') { $payload[$property.Name] = $property.Value }
            }
            $fingerprint = Get-TestSha256 ($payload | ConvertTo-Json -Depth 20 -Compress)
            if ($Document.PSObject.Properties.Match('catalog_fingerprint').Count -eq 0) {
                $Document | Add-Member -NotePropertyName catalog_fingerprint -NotePropertyValue $fingerprint
            }
            else { $Document.catalog_fingerprint = $fingerprint }
        }

        function Write-TestCatalog($Document, [string]$Path) {
            Set-TestCatalogFingerprint $Document
            $Document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
        }
    }

    BeforeEach {
        $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:router=Join-Path $repoRoot 'overrides\custom\capability-router\scripts\route-capability.ps1'
        $script:root=Join-Path $TestDrive 'skills';$routerRoot=Join-Path $root 'capability-router';$skillRoot=Join-Path $root 'codebase-design'
        New-Item -ItemType Directory -Path $routerRoot,$skillRoot -Force|Out-Null
        $skillPath=Join-Path $skillRoot 'SKILL.md';"---`nname: codebase-design`ndescription: Design modules.`n---"|Set-Content -LiteralPath $skillPath -Encoding UTF8
        $document = [pscustomobject][ordered]@{
            schema_version=1
            decision_owner='host_ai'
            semantic_routing_performed=$false
            domains=@([ordered]@{name='engineering';purpose='Engineering';skill_names=@('codebase-design')})
            skills=@([ordered]@{name='codebase-design';description='Design modules.';relative_path='..\codebase-design\SKILL.md';entrypoint_sha256=(Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='read_only';dependencies=@();routing_rules=@()})
            capabilities=@()
        }
        Write-TestCatalog $document (Join-Path $routerRoot 'catalog.json')
        $script:catalog=Join-Path $routerRoot 'catalog.json';$script:skillPath=$skillPath
    }

    It 'discovers contained candidates without semantic ranking or writes' {
        $result=& $router -Query 'design' -CatalogPath $catalog -DomainHint engineering|ConvertFrom-Json
        @($result.retrieval.candidates.name)|Should -Be @('codebase-design')
        $result.decision_owner|Should -Be 'host_ai'
        $result.semantic_routing_performed|Should -Be $false
        $result.writes_performed|Should -Be $false
        $result.routing_receipt.status | Should -Be 'candidates_returned'
        $result.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_only'
        $result.routing_receipt.query_sha256 | Should -Match '^[a-f0-9]{64}$'
        $result.routing_receipt.catalog_fingerprint | Should -Match '^[a-f0-9]{64}$'
        $result.routing_receipt.writes_performed | Should -Be $false
        @($result.PSObject.Properties.Name)|Should -Not -Contain 'activation_plan'
        @($result.PSObject.Properties.Name)|Should -Not -Contain 'session_plan'
    }

    It 'validates an exact candidate and reports disclosed side effects' {
        $result=& $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design'|ConvertFrom-Json
        $result.validation.pass|Should -Be $true
        $result.validation.scope|Should -Be 'skill_dependency_closure_load_only'
        $result.load_validation.pass|Should -Be $true
        $result.selected[0].contained|Should -Be $true
        $result.selected[0].load_side_effect|Should -Be 'read_only'
        $result.selected[0].side_effect|Should -Be 'read_only'
        $result.selected[0].entrypoint_hash_validated|Should -Be $true
        @($result.retrieval.candidates.name) | Should -Be @('codebase-design')
        @($result.validated_closure.name) | Should -Be @('codebase-design')
        $result.execution_authorization.status|Should -Be 'not_granted'
        $result.routing_receipt.status | Should -Be 'validated'
        $result.routing_receipt.truth_boundary | Should -Be 'candidate_load_validated'
        @($result.routing_receipt.validated_candidates) | Should -Be @('codebase-design')
        @($result.routing_receipt.validated_closure) | Should -Be @('codebase-design')
        $result.execution_contract.mode | Should -Be 'host_admission_required'
        $result.routing_receipt.execution_contract.stop_condition | Should -Be 'admission_required'
        $result.execution_authorization.reason | Should -Be 'execution_contract_requires_host_admission'
    }

    It 'preserves an interactive closure contract and refuses to reduce it to one-shot runner execution' {
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills[0] | Add-Member -NotePropertyName execution_contract -NotePropertyValue ([pscustomobject]@{
                mode = 'multi_turn_user_decision'
                native_agent = 'design-griller'
                conversation_owner = 'parent'
                stop_condition = 'one_question_then_wait'
            })
        Write-TestCatalog $document $catalog

        $result = & $router -Query 'grill this proposal' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $result.load_validation.pass | Should -Be $true
        $result.load_validation.checks | Should -Contain 'execution_contract'
        $result.execution_contract.mode | Should -Be 'multi_turn_user_decision'
        $result.execution_contract.native_agent | Should -Be 'design-griller'
        $result.execution_contract.conversation_owner | Should -Be 'parent'
        $result.execution_contract.stop_condition | Should -Be 'one_question_then_wait'
        $result.execution_authorization.reason | Should -Be 'execution_contract_requires_interactive_bridge'
        $result.routing_receipt.execution_contract.mode | Should -Be 'multi_turn_user_decision'
    }

    It 'fails closed when a catalog execution contract is malformed' {
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills[0] | Add-Member -NotePropertyName execution_contract -NotePropertyValue ([pscustomobject]@{
                mode = 'multi_turn_user_decision'
                native_agent = 'cold-capability-runner'
                conversation_owner = 'runner'
                stop_condition = 'parent_contract'
            })
        Write-TestCatalog $document $catalog

        $result = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $result.catalog.status | Should -Be 'invalid'
        $result.load_validation.pass | Should -Be $false
        @($result.catalog.findings.code) | Should -Contain 'execution_contract_invalid'
    }

    It 'validates the selected candidate dependency closure, including declared side effects' {
        $grillingRoot = Join-Path $root 'grilling'
        $domainRoot = Join-Path $root 'domain-modeling'
        New-Item -ItemType Directory -Path $grillingRoot,$domainRoot -Force | Out-Null
        $grillingPath = Join-Path $grillingRoot 'SKILL.md'
        $domainPath = Join-Path $domainRoot 'SKILL.md'
        Set-Content -LiteralPath $grillingPath -Encoding UTF8 -Value "---`nname: grilling`ndescription: Read-only grilling.`n---"
        Set-Content -LiteralPath $domainPath -Encoding UTF8 -Value "---`nname: domain-modeling`ndescription: Domain models.`n---"
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills[0].dependencies = @('grilling')
        $document.skills += [pscustomobject][ordered]@{name='grilling';description='Read-only grilling.';relative_path='..\grilling\SKILL.md';entrypoint_sha256=(Get-FileHash $grillingPath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='read_only';dependencies=@('domain-modeling');routing_rules=@()}
        $document.skills += [pscustomobject][ordered]@{name='domain-modeling';description='Domain models.';relative_path='..\domain-modeling\SKILL.md';entrypoint_sha256=(Get-FileHash $domainPath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='controlled_write';dependencies=@();routing_rules=@()}
        $document.domains[0].skill_names += 'grilling','domain-modeling'
        Write-TestCatalog $document $catalog

        $result = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $result.load_validation.pass | Should -Be $true
        $result.load_validation.checks | Should -Contain 'dependency_closure'
        @($result.validated_closure.name) | Should -Be @('codebase-design','grilling','domain-modeling')
        @($result.validated_closure | Where-Object name -eq 'domain-modeling')[0].side_effect | Should -Be 'controlled_write'
        @($result.routing_receipt.validated_closure) | Should -Be @('codebase-design','grilling','domain-modeling')
        $result.execution_authorization.requires_review | Should -Be $true
    }

    It 'fails closed when a dependency is missing from the catalog or stale on disk' {
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills[0].dependencies = @('missing-skill')
        Write-TestCatalog $document $catalog

        $missing = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $missing.catalog.status | Should -Be 'invalid'
        $missing.load_validation.pass | Should -Be $false
        @($missing.catalog.findings.code) | Should -Contain 'skill_dependency_unknown'

        $dependencyRoot = Join-Path $root 'grilling'
        New-Item -ItemType Directory -Path $dependencyRoot -Force | Out-Null
        $dependencyPath = Join-Path $dependencyRoot 'SKILL.md'
        Set-Content -LiteralPath $dependencyPath -Encoding UTF8 -Value "---`nname: grilling`ndescription: Read-only grilling.`n---"
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills[0].dependencies = @('grilling')
        $document.skills += [pscustomobject][ordered]@{name='grilling';description='Read-only grilling.';relative_path='..\grilling\SKILL.md';entrypoint_sha256=(Get-FileHash $dependencyPath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='read_only';dependencies=@();routing_rules=@()}
        $document.domains[0].skill_names += 'grilling'
        Write-TestCatalog $document $catalog
        Add-Content -LiteralPath $dependencyPath -Value '# stale'

        $stale = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

        $stale.catalog.status | Should -Be 'stale'
        $stale.load_validation.pass | Should -Be $false
        @($stale.excluded | Where-Object { $_.name -eq 'grilling' } | ForEach-Object reason) | Should -Contain 'catalog_stale'
        @($stale.validated_closure).Count | Should -Be 0
    }

    It 'fails closed on catalog drift and explicit exclusion' {
        Add-Content $skillPath '# drift'
        $stale=& $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design'|ConvertFrom-Json
        $stale.validation.pass|Should -Be $false
        @($stale.excluded.reason)|Should -Contain 'catalog_stale'

        $fresh=Get-Content $catalog -Raw|ConvertFrom-Json;$fresh.skills[0].entrypoint_sha256=(Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant();Write-TestCatalog $fresh $catalog
        $excluded=& $router -Query 'design' -CatalogPath $catalog -ExcludeCapability 'skill|codebase-design'|ConvertFrom-Json
        @($excluded.retrieval.candidates).Count|Should -Be 0
    }

    It 'fails closed when an entrypoint hash is missing or malformed' {
        foreach ($value in @($null, 'not-a-sha256')) {
            $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $value) { $document.skills[0].PSObject.Properties.Remove('entrypoint_sha256') }
            elseif ($document.skills[0].PSObject.Properties.Match('entrypoint_sha256').Count -eq 0) {
                $document.skills[0] | Add-Member -NotePropertyName entrypoint_sha256 -NotePropertyValue $value
            }
            else { $document.skills[0].entrypoint_sha256 = $value }
            Write-TestCatalog $document $catalog

            $result = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

            $result.catalog.status | Should -Be 'invalid'
            $result.load_validation.pass | Should -Be $false
            @($result.catalog.findings.code) | Should -Contain 'entrypoint_hash_invalid'
        }
    }

    It 'fails closed when the catalog fingerprint is tampered' {
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.catalog_fingerprint = ('0' * 64)
        $document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalog -Encoding UTF8

        $result = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json

        $result.catalog.status | Should -Be 'invalid'
        @($result.catalog.findings.code) | Should -Contain 'catalog_fingerprint_mismatch'
        @($result.retrieval.candidates).Count | Should -Be 0
    }

    It 'separates read-only loading from unknown or controlled workflow execution' {
        foreach ($sideEffect in @('unknown', 'controlled_write')) {
            $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
            $document.skills[0].side_effect = $sideEffect
            Write-TestCatalog $document $catalog

            $result = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|codebase-design' | ConvertFrom-Json

            $result.load_validation.pass | Should -Be $true
            $result.selected[0].side_effect | Should -Be $sideEffect
            $result.execution_authorization.status | Should -Be 'not_granted'
            $result.execution_authorization.requires_review | Should -Be $true
        }
    }

    It 'returns structured failures for malformed JSON and schema mismatch' {
        Set-Content -LiteralPath $catalog -Encoding UTF8 -Value '{not-json'
        $malformed = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json
        $malformed.catalog.status | Should -Be 'invalid'
        @($malformed.catalog.findings.code) | Should -Contain 'catalog_json_invalid'

        $document = [pscustomobject][ordered]@{schema_version=999;decision_owner='host_ai';semantic_routing_performed=$false;domains=@();skills=@();capabilities=@()}
        Write-TestCatalog $document $catalog
        $schema = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json
        $schema.catalog.status | Should -Be 'invalid'
        @($schema.catalog.findings.code) | Should -Contain 'catalog_schema_unsupported'

        $document.schema_version = '1'
        Write-TestCatalog $document $catalog
        $typedSchema = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json
        $typedSchema.catalog.status | Should -Be 'invalid'
        @($typedSchema.catalog.findings.code) | Should -Contain 'catalog_schema_unsupported'
    }

    It 'does not report a load-validation pass until a candidate is selected' {
        $result = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json

        $result.catalog.status | Should -Be 'current'
        @($result.retrieval.candidates.name) | Should -Contain 'codebase-design'
        $result.load_validation.pass | Should -Be $false
        $result.execution_authorization.reason | Should -Be 'no_candidate_selected'
        $result.routing_receipt.selection_required | Should -Be $true
    }

    It 'fails a request with an unknown domain, duplicate candidate, or multiple candidate roots' {
        $domain = & $router -Query 'design' -CatalogPath $catalog -DomainHint missing-domain | ConvertFrom-Json
        $domain.load_validation.pass | Should -Be $false
        @($domain.excluded.reason) | Should -Contain 'unknown_domain'

        $duplicateCandidates = @('skill|codebase-design','skill|codebase-design')
        $duplicate = & $router -Query 'design' -CatalogPath $catalog -Candidate $duplicateCandidates | ConvertFrom-Json
        $duplicate.load_validation.pass | Should -Be $false
        @($duplicate.excluded.reason) | Should -Contain 'duplicate_candidate'

        $secondRoot = Join-Path $root 'domain-modeling'
        New-Item -ItemType Directory -Path $secondRoot -Force | Out-Null
        $secondPath = Join-Path $secondRoot 'SKILL.md'
        Set-Content -LiteralPath $secondPath -Encoding UTF8 -Value "---`nname: domain-modeling`ndescription: Model domains.`n---"
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills += [pscustomobject][ordered]@{name='domain-modeling';description='Model domains.';relative_path='..\domain-modeling\SKILL.md';entrypoint_sha256=(Get-FileHash $secondPath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='read_only';dependencies=@();routing_rules=@()}
        $document.domains[0].skill_names += 'domain-modeling'
        Write-TestCatalog $document $catalog

        $multiple = & $router -Query 'design' -CatalogPath $catalog -Candidate @('skill|codebase-design','skill|domain-modeling') | ConvertFrom-Json

        $multiple.load_validation.pass | Should -Be $false
        @($multiple.selected).Count | Should -Be 0
        @($multiple.validated_closure).Count | Should -Be 0
        @($multiple.excluded.reason) | Should -Contain 'multiple_candidates_not_admissible'
        $multiple.execution_authorization.reason | Should -Be 'multiple_candidates_not_admissible'
        $multiple.routing_receipt.status | Should -Be 'blocked'
        $multiple.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_blocked'
    }

    It 'fails the whole catalog on duplicate identities or a path escape' {
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills = @($document.skills[0], $document.skills[0])
        Write-TestCatalog $document $catalog
        $duplicate = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json
        $duplicate.catalog.status | Should -Be 'invalid'
        @($duplicate.catalog.findings.code) | Should -Contain 'skill_name_duplicate'

        $outsideRoot = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null
        $outsidePath = Join-Path $outsideRoot 'SKILL.md'
        Set-Content -LiteralPath $outsidePath -Encoding UTF8 -Value 'outside'
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills = @($document.skills[0])
        $document.skills[0].relative_path = '..\..\outside\SKILL.md'
        $document.skills[0].entrypoint_sha256 = (Get-FileHash -LiteralPath $outsidePath -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-TestCatalog $document $catalog
        $escape = & $router -Query 'design' -CatalogPath $catalog | ConvertFrom-Json
        $escape.catalog.status | Should -Be 'invalid'
        @($escape.catalog.findings.code) | Should -Contain 'skill_path_outside_root'
    }

    It 'fails the whole catalog when an entrypoint traverses a junction' {
        $outsideRoot = Join-Path $TestDrive 'junction-target'
        New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null
        $outsidePath = Join-Path $outsideRoot 'SKILL.md'
        Set-Content -LiteralPath $outsidePath -Encoding UTF8 -Value 'outside'
        New-Item -ItemType Junction -Path (Join-Path $root 'junction-skill') -Target $outsideRoot | Out-Null
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills += [pscustomobject][ordered]@{name='junction-skill';description='outside';relative_path='..\junction-skill\SKILL.md';entrypoint_sha256=(Get-FileHash -LiteralPath $outsidePath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='read_only';routing_rules=@()}
        $document.domains[0].skill_names += 'junction-skill'
        Write-TestCatalog $document $catalog

        $result = & $router -Query 'design' -CatalogPath $catalog -Candidate 'skill|junction-skill' | ConvertFrom-Json

        $result.catalog.status | Should -Be 'invalid'
        $result.load_validation.pass | Should -Be $false
        @($result.catalog.findings.code) | Should -Contain 'skill_path_reparse_point'
        @($result.selected).Count | Should -Be 0
    }

    It 'requires a narrower domain instead of returning an alphabetical truncated candidate set' {
        $secondRoot = Join-Path $root 'systematic-debugging'
        New-Item -ItemType Directory -Path $secondRoot -Force | Out-Null
        $secondPath = Join-Path $secondRoot 'SKILL.md'
        Set-Content -LiteralPath $secondPath -Encoding UTF8 -Value "---`nname: systematic-debugging`ndescription: Debug.`n---"
        $document = Get-Content -LiteralPath $catalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.skills += [pscustomobject][ordered]@{name='systematic-debugging';description='Debug.';relative_path='..\systematic-debugging\SKILL.md';entrypoint_sha256=(Get-FileHash $secondPath -Algorithm SHA256).Hash.ToLowerInvariant();domains=@('engineering');load_side_effect='read_only';side_effect='unknown';routing_rules=@()}
        $document.domains[0].skill_names += 'systematic-debugging'
        Write-TestCatalog $document $catalog

        $result = & $router -Query 'engineering' -CatalogPath $catalog -MaxCandidates 1 | ConvertFrom-Json

        $result.retrieval.truncated | Should -Be $true
        $result.retrieval.scope_required | Should -Be $true
        $result.retrieval.candidate_count | Should -Be 2
        @($result.retrieval.candidates).Count | Should -Be 0
        $result.routing_receipt.status | Should -Be 'domain_hint_required'
        $result.routing_receipt.truth_boundary | Should -Be 'candidate_discovery_blocked'
        $result.execution_authorization.reason | Should -Be 'domain_hint_required'
        $result.execution_authorization.status | Should -Be 'not_granted'
    }

    It 'is implicit-eligible only as a narrow cold-discovery fallback' {
        $metadata = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\capability-router\agents\openai.yaml')
        $skill = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\capability-router\SKILL.md')

        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $metadata | Should -Match 'high confidence'
        $metadata | Should -Match 'quoted name, skill discussion, or ambiguous ordinary request is not an invocation'
        $metadata | Should -Match 'never use it as per-request middleware'
        $skill | Should -Match 'do not use as a normal preflight'
        $skill | Should -Match 'routing_receipt'
        $skill | Should -Match 'candidate_load_validated'
        $skill | Should -Match 'Native cold-capability handoff'
        $skill | Should -Match 'execution_contract'
        $skill | Should -Match 'multi_turn_user_decision'
        $skill | Should -Match 'design-griller'
        $skill | Should -Match 'not treat validation as execution authorization'
        $skill | Should -Match 'Never use the bridge as automatic middleware'
        $skill | Should -Match 'exact write set,\s+minimum proof, and stop condition'
        $skill | Should -Match 'reliable binary “skill request”'
        $skill | Should -Match 'high-confidence conclusion'
        $skill | Should -Match 'Treat metadata as insufficient when a request combines an interactive workflow verb'
        $metadata | Should -Match 'interview-style verb'
    }

    It 'does not echo the raw query in the routing receipt' {
        $query = 'secret-marker-' + [guid]::NewGuid().ToString('N')
        $result = & $router -Query $query -CatalogPath $catalog -DomainHint engineering | ConvertFrom-Json

        ($result | ConvertTo-Json -Depth 20 -Compress) | Should -Not -Match $query
        $result.routing_receipt.query_sha256 | Should -Be (Get-TestSha256 $query)
    }
}
