. $PSScriptRoot\..\..\skills.ps1

function New-ProjectionSkill([string]$root, [string]$dir, [string]$name, [string]$description = "fixture") {
    $skillDir = Join-Path $root $dir
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    Set-ContentUtf8 (Join-Path $skillDir "SKILL.md") ("---`nname: {0}`ndescription: {1}`n---`n" -f $name, $description)
    return $skillDir
}

Describe "Skill projection" {
    Context "Repository GPT-5.6 profile policy" {
        It "Keeps routine profiles free from the mandatory Superpowers bootstrap" {
            $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
            $config = Get-ContentUtf8 (Join-Path $repoRoot "skills.json") | ConvertFrom-Json
            $routineProfiles = @("default", "coding", "engineering", "python", "mcp", "review", "dotnet")

            foreach ($profileName in $routineProfiles) {
                $enabledNames = @($config.skill_projection.profiles.$profileName.enabled_names)
                ($enabledNames -contains "using-superpowers") | Should Be $false
            }

            $defaultNames = @($config.skill_projection.profiles.default.enabled_names)
            $config.skill_projection.profiles.default.budget_limit_chars | Should Be 8000
            $defaultNames.Count | Should Be 2
            @($config.skill_projection.resident_names) | Should Be @("capability-router", "watch-interrupted-task")
            foreach ($workflowName in @("research", "brainstorming", "planning-and-task-breakdown", "git-workflow-and-versioning", "incremental-implementation")) {
                ($defaultNames -contains $workflowName) | Should Be $false
            }

            $codingNames = @($config.skill_projection.profiles.coding.enabled_names)
            $config.skill_projection.profiles.coding.budget_limit_chars | Should Be 7500
            $codingNames | Should Be @(
                "systematic-debugging",
                "verification-before-completion",
                "incremental-implementation",
                "code-review-and-quality",
                "api-and-interface-design",
                "security-and-hardening"
            )
            foreach ($workflowName in @("brainstorming", "writing-plans", "executing-plans", "test-driven-development", "finishing-a-development-branch", "dispatching-parallel-agents", "subagent-driven-development", "requesting-code-review", "using-git-worktrees")) {
                ($codingNames -contains $workflowName) | Should Be $false
            }
        }

        It "Keeps the strict profile evidence-focused and removes the mandatory router" {
            $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
            $config = Get-ContentUtf8 (Join-Path $repoRoot "skills.json") | ConvertFrom-Json
            $strictNames = @($config.skill_projection.profiles."coding-strict".enabled_names)
            foreach ($workflowName in @("systematic-debugging", "test-driven-development", "verification-before-completion", "code-review-and-quality", "domain-modeling", "grill-with-docs", "grilling")) {
                ($strictNames -contains $workflowName) | Should Be $true
            }
            foreach ($workflowName in @("using-superpowers", "brainstorming", "writing-plans", "executing-plans", "dispatching-parallel-agents", "subagent-driven-development", "using-git-worktrees")) {
                ($strictNames -contains $workflowName) | Should Be $false
            }

            $routingPolicy = Get-ContentUtf8 (Join-Path $repoRoot "config\skill-routing-policy.json") | ConvertFrom-Json
            $developmentFlow = @($routingPolicy.groups | Where-Object id -eq "development-flow")[0]
            $developmentFlow.router | Should Be ""
            $developmentFlow.selection_policy | Should Match "native"
            (@($developmentFlow.members | Where-Object name -eq "using-superpowers").Count) | Should Be 0
        }

        It "Separates visible engineering planning from explicit side-effecting skills" {
            $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
            $config = Get-ContentUtf8 (Join-Path $repoRoot "skills.json") | ConvertFrom-Json
            $engineeringNames = @($config.skill_projection.profiles.engineering.enabled_names)
            $engineeringNames | Should Be @(
                "codebase-design",
                "idea-refine",
                "spec-driven-development",
                "planning-and-task-breakdown",
                "research",
                "domain-modeling",
                "draft-spec"
            )
            ($engineeringNames -contains "draft-tickets") | Should Be $false

            $policy = Get-ContentUtf8 (Join-Path $repoRoot "config\skill-routing-policy.json") | ConvertFrom-Json
            $engineeringFlow = @($policy.groups | Where-Object id -eq "engineering-design-and-delivery")[0]
            @($engineeringFlow.members | Where-Object name -eq "draft-spec").Count | Should Be 1
            @($engineeringFlow.members | Where-Object name -eq "draft-tickets").Count | Should Be 1
            $engineeringFlow.selection_policy | Should Match "draft-spec"
            $engineeringFlow.selection_policy | Should Match "explicit"

            $grillSkill = Get-ContentUtf8 (Join-Path $repoRoot "overrides\grill-with-docs\SKILL.md")
            $grillSkill | Should Not Match "disable-model-invocation:\s*true"
            $grillPolicy = Get-ContentUtf8 (Join-Path $repoRoot "overrides\grill-with-docs\agents\openai.yaml")
            $grillPolicy | Should Match "allow_implicit_invocation:\s*true"

            foreach ($explicitName in @("improve-codebase-architecture", "to-spec", "to-tickets")) {
                $source = Get-ChildItem -LiteralPath (Join-Path $repoRoot "imports") -Recurse -Filter "SKILL.md" -File |
                    Where-Object { (Get-ContentUtf8 $_.FullName) -match ("(?m)^name:\s*" + [regex]::Escape($explicitName) + "\s*$") } |
                    Select-Object -First 1
                ($null -ne $source) | Should Be $true
                (Get-ContentUtf8 $source.FullName) | Should Match "disable-model-invocation:\s*true"
                $agentMetadata = Join-Path $source.Directory.FullName "agents\openai.yaml"
                (Test-Path -LiteralPath $agentMetadata -PathType Leaf) | Should Be $true
                (Get-ContentUtf8 $agentMetadata) | Should Match "allow_implicit_invocation:\s*false"
            }

            $setupSkill = Get-ContentUtf8 (Join-Path $repoRoot "overrides\setup-matt-pocock-skills\SKILL.md")
            $setupSkill | Should Match "disable-model-invocation:\s*true"
            $setupPolicy = Get-ContentUtf8 (Join-Path $repoRoot "overrides\setup-matt-pocock-skills\agents\openai.yaml")
            $setupPolicy | Should Match "allow_implicit_invocation:\s*false"
        }
    }

    Context "Sync-CodexManagedSkillLinks" {
        It "Projects managed skills into the standard user root and preserves .system" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managed = Join-Path $TestDrive "managed-links"
                $userRoot = Join-Path $TestDrive "agents-skills"
                New-ProjectionSkill $managed "demo" "demo" | Out-Null
                New-ProjectionSkill (Join-Path $userRoot ".system") "system" "system" | Out-Null
                $cfg = [pscustomobject]@{
                    managed_source_path = $managed
                    user_skill_root = $userRoot
                }

                $result = Sync-CodexManagedSkillLinks $cfg

                $result.managed_link_count | Should Be 1
                (Is-ReparsePoint (Join-Path $userRoot "demo")) | Should Be $true
                (Get-ReparsePointTargetFullPath (Join-Path $userRoot "demo")) | Should Be ([System.IO.Path]::GetFullPath((Join-Path $managed "demo")))
                (Test-Path -LiteralPath (Join-Path $userRoot ".system\system\SKILL.md") -PathType Leaf) | Should Be $true
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Excludes exact managed directories from Codex links without removing the source" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managed = Join-Path $TestDrive "managed-link-excludes"
                $userRoot = Join-Path $TestDrive "agents-skills-excludes"
                $keepDir = New-ProjectionSkill $managed "keep" "keep"
                $excludeDir = New-ProjectionSkill $managed "exclude" "exclude"
                $initialCfg = [pscustomobject]@{
                    managed_source_path = $managed
                    user_skill_root = $userRoot
                }
                Sync-CodexManagedSkillLinks $initialCfg | Out-Null
                $cfg = [pscustomobject]@{
                    managed_source_path = $managed
                    user_skill_root = $userRoot
                    managed_link_excludes = @("exclude")
                }

                $result = Sync-CodexManagedSkillLinks $cfg

                $result.managed_link_count | Should Be 1
                $result.stale_link_count | Should Be 1
                (Is-ReparsePoint (Join-Path $userRoot "keep")) | Should Be $true
                (Test-Path -LiteralPath (Join-Path $userRoot "exclude")) | Should Be $false
                (Test-Path -LiteralPath (Join-Path $excludeDir "SKILL.md") -PathType Leaf) | Should Be $true
                (Test-Path -LiteralPath (Join-Path $keepDir "SKILL.md") -PathType Leaf) | Should Be $true
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }
    }

    Context "Capability-router catalog projection" {
        It "builds a portable cold-discovery catalog without changing profile budgets" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managed = Join-Path $TestDrive "catalog-managed"
                New-ProjectionSkill $managed "capability-router" "capability-router" "Portable cold discovery." | Out-Null
                New-ProjectionSkill $managed "codebase-design" "codebase-design" "Design module boundaries." | Out-Null
                New-ProjectionSkill $managed "unrouted-tool" "unrouted-tool" "Perform an uncommon cold workflow." | Out-Null
                $policyPath = Join-Path $TestDrive "catalog-policy.json"
                [ordered]@{
                    groups = @(
                        [ordered]@{ id = "engineering"; purpose = "Engineering"; selection_policy = "host decides"; members = @([ordered]@{ name = "codebase-design"; role = "reference"; activation = "architecture design"; negative_activation = "" }) },
                        [ordered]@{ id = "review"; purpose = "Review"; selection_policy = "host decides"; members = @([ordered]@{ name = "codebase-design"; role = "workflow"; activation = "architecture review"; negative_activation = "" }) }
                    )
                    capabilities = @()
                } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $policyPath -Encoding UTF8
                $cfg = [pscustomobject]@{
                    managed_source_path = $managed
                    routing_policy_path = $policyPath
                    profiles = [pscustomobject]@{
                        engineering = [pscustomobject]@{ purpose = "Architecture and planning."; enabled_names = @("codebase-design") }
                    }
                    discovery_catalog = [pscustomobject]@{
                        fallback_domain = "other"
                        fallback_purpose = "Other installed cold skills."
                        domain_memberships = [pscustomobject]@{ engineering = @("unrouted-tool") }
                    }
                }

                $first = Sync-CapabilityRouterCatalog $cfg
                $second = Sync-CapabilityRouterCatalog $cfg
                $catalog = Get-ContentUtf8 $first.path | ConvertFrom-Json
                $initialFingerprint = [string]$catalog.catalog_fingerprint

                $first.changed | Should Be $true
                $second.changed | Should Be $false
                $catalog.schema_version | Should Be 1
                $catalog.catalog_fingerprint | Should Match '^[0-9a-f]{64}$'
                @($catalog.domains | Where-Object name -eq "engineering")[0].skill_names | Should Contain "unrouted-tool"
                $design = @($catalog.skills | Where-Object name -eq "codebase-design")[0]
                @($design.routing_rules).Count | Should Be 2
                $design.relative_path | Should Be "..\codebase-design\SKILL.md"
                $design.load_side_effect | Should Be "read_only"
                $design.entrypoint_sha256 | Should Be (Get-FileContentHash (Join-Path $managed 'codebase-design\SKILL.md'))
                ([IO.Path]::IsPathRooted([string]$design.relative_path)) | Should Be $false

                Add-Content -LiteralPath (Join-Path $managed 'codebase-design\SKILL.md') -Encoding UTF8 -Value "`n# Changed body"
                $third = Sync-CapabilityRouterCatalog $cfg
                $updatedCatalog = Get-ContentUtf8 $third.path | ConvertFrom-Json
                $updatedDesign = @($updatedCatalog.skills | Where-Object name -eq "codebase-design")[0]

                $third.changed | Should Be $true
                $updatedDesign.entrypoint_sha256 | Should Not Be $design.entrypoint_sha256
                $updatedCatalog.catalog_fingerprint | Should Not Be $initialFingerprint
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }
    }

    Context "New-SkillProjectionPlan" {
        It "Unions resident skills into every profile without repeating them in profile config" {
            $root = Join-Path $TestDrive "resident-profile"
            New-ProjectionSkill $root "router" "router" | Out-Null
            New-ProjectionSkill $root "worker" "worker" | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                resident_names = @("router")
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("worker") }
                    narrow = [pscustomobject]@{ enabled_names = @() }
                }
                sources = @([pscustomobject]@{ id = "fixture"; path = $root; priority = 1; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.active_names | Sort-Object) -join "," | Should Be "router,worker"
            @($plan.resident_names) | Should Be @("router")
            ($plan.profile_budgets | Where-Object profile -eq "narrow").active_skill_count | Should Be 1
        }

        It "Rejects unknown resident skills" {
            $root = Join-Path $TestDrive "unknown-resident"
            New-ProjectionSkill $root "worker" "worker" | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                resident_names = @("missing")
                sources = @([pscustomobject]@{ id = "fixture"; path = $root; priority = 1; platforms = @("codex") })
            }

            { New-SkillProjectionPlan $cfg } | Should Throw
        }

        It "Keeps the higher-priority path for same-content duplicates" {
            $managed = Join-Path $TestDrive "managed-same"
            $legacy = Join-Path $TestDrive "legacy-same"
            New-ProjectionSkill $managed "shared" "shared-skill" | Out-Null
            New-ProjectionSkill $legacy "shared-copy" "shared-skill" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.skills).Count | Should Be 2
            @($plan.disabled).Count | Should Be 1
            $plan.disabled[0].source_id | Should Be "legacy"
            $plan.disabled[0].decision | Should Be "duplicate_same_content"
            @($plan.unique_names).Count | Should Be 1
        }

        It "Keeps the higher-priority path and records different-content conflicts" {
            $managed = Join-Path $TestDrive "managed-conflict"
            $legacy = Join-Path $TestDrive "legacy-conflict"
            New-ProjectionSkill $managed "shared" "shared-skill" "managed version" | Out-Null
            New-ProjectionSkill $legacy "shared-copy" "shared-skill" "legacy version" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.conflicts).Count | Should Be 1
            $plan.conflicts[0].name | Should Be "shared-skill"
            $plan.disabled[0].source_id | Should Be "legacy"
            $plan.disabled[0].decision | Should Be "conflict_priority_winner"
        }

        It "Leaves skills that only exist in a lower-priority source enabled" {
            $managed = Join-Path $TestDrive "managed-unique"
            $legacy = Join-Path $TestDrive "legacy-unique"
            New-ProjectionSkill $managed "managed-only" "managed-only" | Out-Null
            New-ProjectionSkill $legacy "legacy-only" "legacy-only" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.disabled).Count | Should Be 0
            @($plan.unique_names | Sort-Object) -join "," | Should Be "legacy-only,managed-only"
        }

        It "Prefers the .system copy inside the same root" {
            $root = Join-Path $TestDrive "managed-system"
            New-ProjectionSkill $root "ordinary" "openai-docs" "ordinary" | Out-Null
            New-ProjectionSkill (Join-Path $root ".system") "openai-docs" "openai-docs" "system" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.disabled).Count | Should Be 1
            $plan.disabled[0].path | Should Match "ordinary\\SKILL\.md$"
            $plan.canonical[0].path | Should Match "\.system\\openai-docs\\SKILL\.md$"
        }

        It "Disables migrated aliases and points them at the replacement" {
            $managed = Join-Path $TestDrive "managed-alias"
            $legacy = Join-Path $TestDrive "legacy-alias"
            New-ProjectionSkill $managed "social" "social" "current" | Out-Null
            New-ProjectionSkill $legacy "social-content" "social-content" "legacy" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                aliases = @([pscustomobject]@{ name = "social-content"; replacement = "social" })
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.active).Count | Should Be 1
            $plan.active[0].name | Should Be "social"
            $alias = @($plan.disabled | Where-Object decision -eq "alias_replaced")[0]
            $alias.name | Should Be "social-content"
            $alias.replacement | Should Be "social"
            $alias.canonical_path | Should Match "social\\SKILL\.md$"
        }

        It "Keeps system skills and only profile-enabled canonical skills active" {
            $root = Join-Path $TestDrive "profile"
            New-ProjectionSkill $root "always" "always" | Out-Null
            New-ProjectionSkill $root "optional" "optional" | Out-Null
            New-ProjectionSkill (Join-Path $root ".system") "system" "system" | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("always") }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.active | ForEach-Object name | Sort-Object) -join "," | Should Be "always,system"
            @($plan.disabled | Where-Object decision -eq "profile_excluded" | ForEach-Object name) | Should Be @("optional")
            $plan.active_profile | Should Be "default"
        }

        It "Distinguishes skills routed through another profile from unrouted skills" {
            $root = Join-Path $TestDrive "profile-reachability"
            New-ProjectionSkill $root "active" "active" | Out-Null
            New-ProjectionSkill $root "elsewhere" "elsewhere" | Out-Null
            New-ProjectionSkill $root "orphan" "orphan" | Out-Null
            New-ProjectionSkill (Join-Path $root ".system") "system" "system" | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("active") }
                    coding = [pscustomobject]@{ enabled_names = @("active", "elsewhere") }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            $elsewhere = @($plan.disabled | Where-Object name -eq "elsewhere")[0]
            $elsewhere.decision | Should Be "profile_excluded"
            $elsewhere.profile_reachability | Should Be "routed_elsewhere"
            @($elsewhere.available_profiles) | Should Be @("coding")
            $orphan = @($plan.disabled | Where-Object name -eq "orphan")[0]
            $orphan.decision | Should Be "profile_excluded"
            $orphan.profile_reachability | Should Be "unrouted"
            @($orphan.available_profiles).Count | Should Be 0
            @($plan.profile_routed_names) | Should Be @("active", "elsewhere")
            @($plan.unrouted_names) | Should Be @("orphan")
            $plan.profile_routed_name_count | Should Be 2
            $plan.unrouted_name_count | Should Be 1
        }

        It "Includes the external reserve in the metadata budget verdict" {
            $root = Join-Path $TestDrive "budget"
            New-ProjectionSkill $root "large" "large" ("x" * 90) | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                budget_limit_chars = 100
                external_metadata_reserve_chars = 10
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            $plan.skill_metadata_chars | Should Be 95
            $plan.estimated_metadata_chars | Should Be 105
            $plan.budget_pass | Should Be $false
        }

        It "Reports every profile budget even when the active profile passes" {
            $root = Join-Path $TestDrive "all-profile-budgets"
            New-ProjectionSkill $root "small" "small" "small" | Out-Null
            New-ProjectionSkill $root "large" "large" ("x" * 90) | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                budget_limit_chars = 100
                external_metadata_reserve_chars = 0
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("small") }
                    oversized = [pscustomobject]@{ enabled_names = @("small", "large") }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.profile_budgets).Count | Should Be 2
            ($plan.profile_budgets | Where-Object profile -eq "default").budget_pass | Should Be $true
            ($plan.profile_budgets | Where-Object profile -eq "oversized").budget_pass | Should Be $false
            $plan.all_profiles_budget_pass | Should Be $false
            $plan.budget_pass | Should Be $true
        }

        It "Enforces a lower per-profile budget without weakening the global ceiling" {
            $root = Join-Path $TestDrive "profile-specific-budget"
            New-ProjectionSkill $root "large" "large" ("x" * 96) | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                budget_limit_chars = 200
                external_metadata_reserve_chars = 0
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("large"); budget_limit_chars = 100 }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg
            $profileBudget = @($plan.profile_budgets)[0]

            $plan.budget_limit_chars | Should Be 200
            $plan.effective_budget_limit_chars | Should Be 100
            $plan.budget_pass | Should Be $false
            $profileBudget.budget_limit_chars | Should Be 100
            $profileBudget.budget_pass | Should Be $false
        }

        It "Rejects a per-profile budget above the global ceiling" {
            $root = Join-Path $TestDrive "profile-budget-above-global"
            New-ProjectionSkill $root "small" "small" "small" | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                budget_limit_chars = 100
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("small"); budget_limit_chars = 101 }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            { New-SkillProjectionPlan $cfg } | Should Throw
        }
    }

    Context "Package hash cache" {
        It "Classifies managed cache hits as hot even when system skills still require full hashes" {
            $hot = [pscustomobject]@{ cache_valid = $true; cache_hits = 110; cache_misses = 0; full_hash_count = 5 }
            $miss = [pscustomobject]@{ cache_valid = $true; cache_hits = 109; cache_misses = 1; full_hash_count = 6 }
            $invalid = [pscustomobject]@{ cache_valid = $false; cache_hits = 0; cache_misses = 0; full_hash_count = 115 }

            (Test-SkillProjectionManagedCacheHotPath $hot) | Should Be $true
            (Test-SkillProjectionManagedCacheHotPath $miss) | Should Be $false
            (Test-SkillProjectionManagedCacheHotPath $invalid) | Should Be $false
        }

        It "Rejects malformed hashes when loading cache entries" {
            $managedRoot = Join-Path $TestDrive "package-cache-malformed-managed"
            $manifestPath = Join-Path $TestDrive "package-cache-malformed.json"
            EnsureDir $managedRoot
            Set-ContentUtf8 $manifestPath ([ordered]@{
                    schema_version = 2
                    package_hash_cache_schema = 1
                    agent_build_signature = "sig-1"
                    skills = @([ordered]@{
                            skill_dir = (Join-Path $TestDrive "package-cache-malformed-user\demo")
                            content_hash = ("a" * 64)
                            package_hash = "not-a-sha256"
                            package_fingerprint = ("b" * 64)
                        })
                } | ConvertTo-Json -Depth 10)
            $cfg = [pscustomobject]@{ managed_source_path = $managedRoot }

            $context = New-SkillProjectionPackageHashContext $cfg "sig-1" $manifestPath

            $context.cache_valid | Should Be $true
            $context.cache_entries.Count | Should Be 0
        }

        It "Reuses a package hash only for an unchanged managed Junction" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managedRoot = Join-Path $TestDrive "package-cache-managed"
                $userRoot = Join-Path $TestDrive "package-cache-user"
                $skillDir = New-ProjectionSkill $managedRoot "demo" "demo"
                Set-ContentUtf8 (Join-Path $skillDir "asset.txt") "asset"
                EnsureDir $userRoot
                $linkDir = Join-Path $userRoot "demo"
                New-Junction $linkDir $skillDir

                $contentHash = Get-FileContentHash (Join-Path $linkDir "SKILL.md")
                $packageHash = Get-SkillPackageContentHash $linkDir
                $fingerprint = Get-DirectoryFingerprint $skillDir
                $manifestPath = Join-Path $TestDrive "package-cache-hit.json"
                Set-ContentUtf8 $manifestPath ([ordered]@{
                        schema_version = 2
                        package_hash_cache_schema = 1
                        agent_build_signature = "sig-1"
                        skills = @([ordered]@{
                                skill_dir = $linkDir
                                content_hash = $contentHash
                                package_hash = $packageHash
                                package_fingerprint = $fingerprint
                            })
                    } | ConvertTo-Json -Depth 10)
                $cfg = [pscustomobject]@{
                    managed_source_path = $managedRoot
                    user_skill_root = $userRoot
                }
                $source = [pscustomobject]@{ id = "managed"; path = $userRoot; priority = 200; platforms = @("codex") }

                $context = New-SkillProjectionPackageHashContext $cfg "sig-1" $manifestPath
                Mock Get-SkillPackageContentHash { throw "full package hash should not run on a valid cache hit" }
                $entries = @(Get-SkillProjectionSourceEntries $source 0 $context)

                $entries.Count | Should Be 1
                $entries[0].package_hash | Should Be $packageHash
                $entries[0].package_fingerprint | Should Be $fingerprint
                $context.cache_hits | Should Be 1
                $context.cache_misses | Should Be 0
                $context.full_hash_count | Should Be 0
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Falls back to a full package hash when nested package metadata changes" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managedRoot = Join-Path $TestDrive "package-cache-stale-managed"
                $userRoot = Join-Path $TestDrive "package-cache-stale-user"
                $skillDir = New-ProjectionSkill $managedRoot "demo" "demo"
                $assetPath = Join-Path $skillDir "asset.txt"
                Set-ContentUtf8 $assetPath "before"
                EnsureDir $userRoot
                $linkDir = Join-Path $userRoot "demo"
                New-Junction $linkDir $skillDir

                $contentHash = Get-FileContentHash (Join-Path $linkDir "SKILL.md")
                $fingerprint = Get-DirectoryFingerprint $skillDir
                $manifestPath = Join-Path $TestDrive "package-cache-stale.json"
                Set-ContentUtf8 $manifestPath ([ordered]@{
                        schema_version = 2
                        package_hash_cache_schema = 1
                        agent_build_signature = "sig-1"
                        skills = @([ordered]@{
                                skill_dir = $linkDir
                                content_hash = $contentHash
                                package_hash = "stale-hash"
                                package_fingerprint = $fingerprint
                            })
                    } | ConvertTo-Json -Depth 10)
                Set-ContentUtf8 $assetPath "after-with-different-size"
                $cfg = [pscustomobject]@{
                    managed_source_path = $managedRoot
                    user_skill_root = $userRoot
                }
                $source = [pscustomobject]@{ id = "managed"; path = $userRoot; priority = 200; platforms = @("codex") }

                $context = New-SkillProjectionPackageHashContext $cfg "sig-1" $manifestPath
                Mock Get-SkillPackageContentHash { "fresh-hash" }
                $entries = @(Get-SkillProjectionSourceEntries $source 0 $context)

                $entries[0].package_hash | Should Be "fresh-hash"
                $context.cache_hits | Should Be 0
                $context.cache_misses | Should Be 1
                $context.full_hash_count | Should Be 1
                Assert-MockCalled Get-SkillPackageContentHash -Times 1 -Exactly -Scope It
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Falls back when the cached SKILL content hash does not match" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managedRoot = Join-Path $TestDrive "package-cache-content-managed"
                $userRoot = Join-Path $TestDrive "package-cache-content-user"
                $skillDir = New-ProjectionSkill $managedRoot "demo" "demo"
                EnsureDir $userRoot
                $linkDir = Join-Path $userRoot "demo"
                New-Junction $linkDir $skillDir
                $manifestPath = Join-Path $TestDrive "package-cache-content.json"
                Set-ContentUtf8 $manifestPath ([ordered]@{
                        schema_version = 2
                        package_hash_cache_schema = 1
                        agent_build_signature = "sig-1"
                        skills = @([ordered]@{
                                skill_dir = $linkDir
                                content_hash = "wrong-content-hash"
                                package_hash = "stale-hash"
                                package_fingerprint = (Get-DirectoryFingerprint $skillDir)
                            })
                    } | ConvertTo-Json -Depth 10)
                $cfg = [pscustomobject]@{
                    managed_source_path = $managedRoot
                    user_skill_root = $userRoot
                }
                $source = [pscustomobject]@{ id = "managed"; path = $userRoot; priority = 200; platforms = @("codex") }

                $context = New-SkillProjectionPackageHashContext $cfg "sig-1" $manifestPath
                Mock Get-SkillPackageContentHash { "fresh-content-hash" }
                $entries = @(Get-SkillProjectionSourceEntries $source 0 $context)

                $entries[0].package_hash | Should Be "fresh-content-hash"
                $context.cache_misses | Should Be 1
                Assert-MockCalled Get-SkillPackageContentHash -Times 1 -Exactly -Scope It
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }
    }

    Context "Build-CodexSkillsProjectionToml" {
        It "Replaces only the managed block and preserves user config" {
            $existing = @'
model = "gpt-5.6-sol"

# BEGIN skills-manager:skills-projection
[[skills.config]]
path = "C:\\old\\SKILL.md"
enabled = false
# END skills-manager:skills-projection

[windows]
sandbox = "elevated"
'@
            $disabled = @([pscustomobject]@{ path = "C:\new\SKILL.md" })

            $toml = Build-CodexSkillsProjectionToml $existing $disabled

            $toml | Should Match 'model = "gpt-5\.6-sol"'
            $toml | Should Match '\[windows\]'
            $toml | Should Not Match 'C:\\\\old'
            $toml | Should Match 'C:\\\\new\\\\SKILL\.md'
            ([regex]::Matches($toml, 'BEGIN skills-manager:skills-projection')).Count | Should Be 1
        }

        It "Preserves foreign TOML tables moved inside the managed markers" {
            $existing = @'
model_provider = "codex_local_access"

# BEGIN skills-manager:skills-projection
[[skills.config]]
path = "C:\\old\\SKILL.md"
enabled = false

[model_providers]

[model_providers.codex_local_access]
name = "Codex Local Access"
base_url = "http://127.0.0.1:8045/v1"

[features]
unified_exec = true
# END skills-manager:skills-projection
'@
            $disabled = @([pscustomobject]@{ path = "C:\new\SKILL.md" })

            $toml = Build-CodexSkillsProjectionToml $existing $disabled

            $toml | Should Not Match 'C:\\\\old'
            $toml | Should Match '\[model_providers\.codex_local_access\]'
            $toml | Should Match 'base_url = "http://127\.0\.0\.1:8045/v1"'
            $toml | Should Match '\[features\]'
            $toml | Should Match 'unified_exec = true'
            ([regex]::Matches($toml, 'BEGIN skills-manager:skills-projection')).Count | Should Be 1
            $toml.IndexOf('[features]') | Should BeLessThan $toml.IndexOf('# BEGIN skills-manager:skills-projection')
        }
    }

    Context "Sync-CodexSkillProjection" {
        It "Signals canonical inventory changes but ignores profile-only and no-op syncs" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $source = Join-Path $TestDrive "reconciliation-source"
                New-ProjectionSkill $source "alpha" "alpha" "first" | Out-Null
                $configPath = Join-Path $TestDrive "reconciliation-codex\config.toml"
                $manifestPath = Join-Path $TestDrive "reconciliation-reports\projection.json"
                $signalPath = Join-Path $TestDrive "reconciliation-reports\pending.json"
                $projection = [pscustomobject]@{
                    enabled = $true
                    active_profile = "default"
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{ enabled_names = @("alpha") }
                        coding = [pscustomobject]@{ enabled_names = @("alpha") }
                    }
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    reconciliation_signal_path = $signalPath
                    sources = @([pscustomobject]@{ id = "managed"; path = $source; priority = 200; platforms = @("codex") })
                }

                $initial = Sync-CodexSkillProjection $projection
                $initial.reconciliation.status | Should Be "reconciliation_needed"
                $initial.reconciliation.added_names | Should Be @("alpha")
                (Test-Path -LiteralPath $signalPath -PathType Leaf) | Should Be $true

                Remove-Item -LiteralPath $signalPath -Force
                $noOp = Sync-CodexSkillProjection $projection
                $noOp.reconciliation.status | Should Be "not_needed"
                (Test-Path -LiteralPath $signalPath) | Should Be $false

                $projection.active_profile = "coding"
                $profileOnly = Sync-CodexSkillProjection $projection
                $profileOnly.reconciliation.status | Should Be "not_needed"
                (Test-Path -LiteralPath $signalPath) | Should Be $false

                New-ProjectionSkill $source "alpha" "alpha" "updated" | Out-Null
                New-ProjectionSkill $source "beta" "beta" "second" | Out-Null
                $metadataAndAdd = Sync-CodexSkillProjection $projection
                $metadataAndAdd.reconciliation.status | Should Be "reconciliation_needed"
                $metadataAndAdd.reconciliation.added_names | Should Be @("beta")
                $metadataAndAdd.reconciliation.metadata_changed_names | Should Be @("alpha")

                Remove-Item -LiteralPath (Join-Path $source "beta") -Recurse -Force
                $removed = Sync-CodexSkillProjection $projection
                $removed.reconciliation.removed_names | Should Be @("beta")
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Persists profile reachability summary in the manifest" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $root = Join-Path $TestDrive "sync-profile-reachability"
                New-ProjectionSkill $root "active" "active" | Out-Null
                New-ProjectionSkill $root "elsewhere" "elsewhere" | Out-Null
                New-ProjectionSkill $root "orphan" "orphan" | Out-Null
                $configPath = Join-Path $TestDrive "sync-profile-reachability-codex\config.toml"
                $manifestPath = Join-Path $TestDrive "sync-profile-reachability-reports\projection.json"
                $projection = [pscustomobject]@{
                    enabled = $true
                    active_profile = "default"
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{ enabled_names = @("active") }
                        coding = [pscustomobject]@{ enabled_names = @("active", "elsewhere") }
                    }
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
                }

                Sync-CodexSkillProjection $projection | Out-Null
                $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json

                $manifest.profile_routed_name_count | Should Be 2
                $manifest.unrouted_name_count | Should Be 1
                @($manifest.profile_routed_names) | Should Be @("active", "elsewhere")
                @($manifest.unrouted_names) | Should Be @("orphan")
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Persists package cache metadata and reuses it on the next verified sync" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $managedRoot = Join-Path $TestDrive "sync-cache-managed"
                $userRoot = Join-Path $TestDrive "sync-cache-user"
                New-ProjectionSkill $managedRoot "demo" "demo" | Out-Null
                $configPath = Join-Path $TestDrive "sync-cache-codex\config.toml"
                $manifestPath = Join-Path $TestDrive "sync-cache-reports\projection.json"
                $projection = [pscustomobject]@{
                    enabled = $true
                    managed_source_path = $managedRoot
                    user_skill_root = $userRoot
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    sources = @([pscustomobject]@{ id = "managed"; path = $userRoot; priority = 200; platforms = @("codex") })
                }

                $cold = Sync-CodexSkillProjection $projection "sig-1"
                $coldManifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
                $coldHash = [string]$cold.plan.skills[0].package_hash

                $coldManifest.package_hash_cache_schema | Should Be 1
                $coldManifest.agent_build_signature | Should Be "sig-1"
                [string]::IsNullOrWhiteSpace([string]$coldManifest.skills[0].package_fingerprint) | Should Be $false

                $hot = Sync-CodexSkillProjection $projection "sig-1"

                $hot.plan.skills[0].package_hash | Should Be $coldHash
                $hot.package_hash_cache.cache_hits | Should Be 1
                $hot.package_hash_cache.cache_misses | Should Be 0
                $hot.package_hash_cache.full_hash_count | Should Be 0
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Fails closed when an inactive profile exceeds the metadata budget" {
            $oldDryRun = $script:DryRun
            try {
                $profileRoot = Join-Path $TestDrive "inactive-profile-budget"
                New-ProjectionSkill $profileRoot "small" "small" "small" | Out-Null
                New-ProjectionSkill $profileRoot "large" "large" ("x" * 90) | Out-Null
                $script:DryRun = $true
                $projection = [pscustomobject]@{
                    enabled = $true
                    active_profile = "default"
                    budget_limit_chars = 100
                    external_metadata_reserve_chars = 0
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{ enabled_names = @("small") }
                        oversized = [pscustomobject]@{ enabled_names = @("small", "large") }
                    }
                    sources = @([pscustomobject]@{ id = "managed"; path = $profileRoot; priority = 200; platforms = @("codex") })
                }

                (Test-Path -LiteralPath (Join-Path $profileRoot "small\SKILL.md") -PathType Leaf) | Should Be $true
                @((Get-SkillProjectionSourceEntries $projection.sources[0] 0) | ForEach-Object name | Sort-Object) -join "," | Should Be "large,small"
                $preflightPlan = New-SkillProjectionPlan $projection
                @($preflightPlan.canonical).Count | Should Be 2
                { Sync-CodexSkillProjection $projection } | Should Throw
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Does not write config or manifest during dry-run" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $true
                $source = Join-Path $TestDrive "dry-source"
                New-ProjectionSkill $source "a" "same" "a" | Out-Null
                New-ProjectionSkill $source "b" "same" "b" | Out-Null
                $configPath = Join-Path $TestDrive "codex\config.toml"
                $manifestPath = Join-Path $TestDrive "reports\projection.json"
                $projection = [pscustomobject]@{
                    enabled = $true
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    sources = @([pscustomobject]@{ id = "managed"; path = $source; priority = 200; platforms = @("codex") })
                }

                $result = Sync-CodexSkillProjection $projection

                $result.success | Should Be $true
                $result.persisted | Should Be $false
                (Test-Path -LiteralPath $configPath) | Should Be $false
                (Test-Path -LiteralPath $manifestPath) | Should Be $false
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Removes the managed block and refreshes the manifest when projection is disabled" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $configPath = Join-Path $TestDrive "disabled\config.toml"
                $manifestPath = Join-Path $TestDrive "disabled\projection.json"
                EnsureDir (Split-Path $configPath -Parent)
                Set-ContentUtf8 $configPath @'
model = "gpt-5.6-sol"

# BEGIN skills-manager:skills-projection
[[skills.config]]
path = "C:\\old\\SKILL.md"
enabled = false
# END skills-manager:skills-projection
'@
                $projection = [pscustomobject]@{
                    enabled = $false
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                }

                $result = Sync-CodexSkillProjection $projection
                $config = Get-ContentUtf8 $configPath
                $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json

                $result.success | Should Be $true
                $result.persisted | Should Be $true
                $result.changed | Should Be $true
                $config | Should Match 'model = "gpt-5\.6-sol"'
                $config | Should Not Match 'skills-manager:skills-projection'
                $manifest.enabled | Should Be $false
                $manifest.disabled_path_count | Should Be 0
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }
    }
}
