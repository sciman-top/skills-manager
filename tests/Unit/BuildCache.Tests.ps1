. $PSScriptRoot\..\..\skills.ps1

Describe "Build Cache and Transaction" {
    Context "Get-DirectoryFingerprint" {
        It "Changes when file content changes" {
            $dir = Join-Path $TestDrive "skill"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $file = Join-Path $dir "SKILL.md"
            Set-Content -Path $file -Value "v1"
            $h1 = Get-DirectoryFingerprint $dir
            Start-Sleep -Milliseconds 20
            Set-Content -Path $file -Value "v2"
            $h2 = Get-DirectoryFingerprint $dir
            $h1 | Should Not Be $h2
        }

        It "Reads directories containing wildcard characters literally" {
            $dir = Join-Path $TestDrive "skill[brackets]"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir "SKILL.md") -Value "v1"

            Get-DirectoryFingerprint $dir | Should Not Be "missing"
        }

        It "Keeps a stable fingerprint for an unchanged nested tree" {
            $dir = Join-Path $TestDrive "stable"
            New-Item -ItemType Directory -Path (Join-Path $dir "nested") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir "SKILL.md") -Value "v1"
            Set-Content -LiteralPath (Join-Path $dir "nested\notes.txt") -Value "notes"

            $h1 = Get-DirectoryFingerprint $dir
            $h2 = Get-DirectoryFingerprint $dir

            $h1 | Should Be $h2
        }
    }

    Context "Mirror-SkillWithCache" {
        It "Skips mirror when cache fingerprint matches and target exists" {
            $src = Join-Path $TestDrive "src"
            $dst = Join-Path $TestDrive "dst"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Set-Content -Path (Join-Path $src "SKILL.md") -Value "hello"
            Set-Content -Path (Join-Path $dst "SKILL.md") -Value "hello"

            $key = "mapping|a|b|c"
            $fp = Get-DirectoryFingerprint $src
            $oldCache = @{ $key = $fp }
            $newCache = @{}
            $stats = [pscustomobject]@{ mirrored = 0; skipped = 0 }

            Mock RoboMirror {}
            Mirror-SkillWithCache $src $dst $key $oldCache $newCache $stats

            $stats.skipped | Should Be 1
            $stats.mirrored | Should Be 0
            Assert-MockCalled RoboMirror -Times 0 -Exactly -Scope It
        }

        It "Forces an override mirror when a clean build recreated the target" {
            $src = Join-Path $TestDrive "override-src"
            $dst = Join-Path $TestDrive "override-dst"
            New-Item -ItemType Directory -Path $src, $dst -Force | Out-Null
            Set-Content -Path (Join-Path $src "SKILL.md") -Value "override"
            Set-Content -Path (Join-Path $dst "SKILL.md") -Value "mapped"

            $key = "override|same-name"
            $fp = Get-DirectoryFingerprint $src
            $oldCache = @{ $key = $fp }
            $newCache = @{}
            $stats = [pscustomobject]@{ mirrored = 0; skipped = 0 }

            Mock RoboMirror {}
            Mirror-SkillWithCache $src $dst $key $oldCache $newCache $stats -ForceMirror

            $stats.skipped | Should Be 0
            $stats.mirrored | Should Be 1
            Assert-MockCalled RoboMirror -Times 1 -Exactly -Scope It
        }

        It "Resolves relative-path SKILL placeholders after mirror" {
            $src = Join-Path $TestDrive "src"
            $dst = Join-Path $TestDrive "dst"
            $targetSkillDir = Join-Path $src "plugin\skills\do"
            $placeholderDir = Join-Path $src "openclaw\skills\do"
            New-Item -ItemType Directory -Path $targetSkillDir -Force | Out-Null
            New-Item -ItemType Directory -Path $placeholderDir -Force | Out-Null

            $realSkill = @"
---
name: do
description: Execute a phased implementation plan using subagents.
---
"@
            Set-Content -Path (Join-Path $targetSkillDir "SKILL.md") -Value $realSkill
            Set-Content -Path (Join-Path $placeholderDir "SKILL.md") -Value "../../../plugin/skills/do/SKILL.md"
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            & robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
            Expand-RelativeSkillPlaceholders $dst | Should Be 1

            $mirrored = Get-Content -Raw (Join-Path $dst "openclaw\skills\do\SKILL.md")
            $mirrored | Should Match "^---"
            $mirrored | Should Match "name:\s*do"
            $mirrored | Should Not Match "^\.\./\.\./\.\./plugin/skills/do/SKILL\.md\s*$"
        }

        It "Preserves UTF-8 punctuation when resolving relative-path placeholders" {
            $src = Join-Path $TestDrive "src-utf8"
            $dst = Join-Path $TestDrive "dst-utf8"
            $targetSkillDir = Join-Path $src "plugin\skills\make-plan"
            $placeholderDir = Join-Path $src "openclaw\skills\make-plan"
            New-Item -ItemType Directory -Path $targetSkillDir -Force | Out-Null
            New-Item -ItemType Directory -Path $placeholderDir -Force | Out-Null

            $realSkill = @"
---
name: make-plan
description: Create a phased plan — especially before executing with do.
---
"@
            Set-ContentUtf8 (Join-Path $targetSkillDir "SKILL.md") $realSkill
            Set-Content -Path (Join-Path $placeholderDir "SKILL.md") -Value "../../../plugin/skills/make-plan/SKILL.md"
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            & robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

            Expand-RelativeSkillPlaceholders $dst | Should Be 1

            $mirrored = Get-ContentUtf8 (Join-Path $dst "openclaw\skills\make-plan\SKILL.md")
            $mirrored | Should Be $realSkill
        }

        It "Reads placeholder SKILL files through Get-ContentUtf8 instead of legacy Get-Content -Raw" {
            $root = Join-Path $TestDrive "placeholder-utf8"
            $targetSkillDir = Join-Path $root "plugin\skills\plan"
            $placeholderPath = Join-Path $root "openclaw\skills\plan\SKILL.md"
            New-Item -ItemType Directory -Path $targetSkillDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path $placeholderPath -Parent) -Force | Out-Null
            Set-ContentUtf8 (Join-Path $targetSkillDir "SKILL.md") @"
---
name: plan
description: 中文占位目标
---
"@
            Set-ContentUtf8 $placeholderPath "../../../plugin/skills/plan/SKILL.md"

            Mock Get-Content { throw "legacy raw read should not be used for placeholder skill files" } -ParameterFilter {
                (($LiteralPath -eq $placeholderPath) -or ($Path -eq $placeholderPath))
            }

            $resolved = Resolve-RelativeSkillPlaceholderTarget $placeholderPath $root

            $resolved | Should Be (Join-Path $targetSkillDir "SKILL.md")
        }

        It "Resolves cached relative-path SKILL placeholders even when mirror is skipped" {
            $src = Join-Path $TestDrive "src-cache"
            $dst = Join-Path $TestDrive "dst-cache"
            $targetSkillDir = Join-Path $dst "plugin\skills\do"
            $placeholderDir = Join-Path $dst "openclaw\skills\do"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-Item -ItemType Directory -Path $targetSkillDir -Force | Out-Null
            New-Item -ItemType Directory -Path $placeholderDir -Force | Out-Null

            $realSkill = @"
---
name: do
description: Execute a phased implementation plan using subagents.
---
"@
            Set-Content -Path (Join-Path $src "SKILL.md") -Value "cache-marker"
            Set-Content -Path (Join-Path $targetSkillDir "SKILL.md") -Value $realSkill
            Set-Content -Path (Join-Path $placeholderDir "SKILL.md") -Value "../../../plugin/skills/do/SKILL.md"

            $key = "mapping|manual|openclaw|do"
            $fp = Get-DirectoryFingerprint $src
            $oldCache = @{ $key = $fp }
            $newCache = @{}
            $stats = [pscustomobject]@{ mirrored = 0; skipped = 0 }

            Mock RoboMirror {}

            Mirror-SkillWithCache $src $dst $key $oldCache $newCache $stats

            $stats.skipped | Should Be 1
            $stats.mirrored | Should Be 0
            (Get-ContentUtf8 (Join-Path $dst "openclaw\skills\do\SKILL.md")) | Should Match "^---"
        }

        It "Skips fingerprint calculation when destination is rebuilt from scratch" {
            $src = Join-Path $TestDrive "src-fresh"
            $dst = Join-Path $TestDrive "dst-fresh"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            Set-Content -Path (Join-Path $src "SKILL.md") -Value "fresh"

            $oldCache = @{ "mapping|v|fresh|1" = "fp-old" }
            $newCache = @{}
            $stats = [pscustomobject]@{ mirrored = 0; skipped = 0 }

            Mock Get-DirectoryFingerprint { throw "Fingerprint should not be called when destination is missing." }
            Mock RoboMirror {}
            Mock Expand-RelativeSkillPlaceholders { 0 }

            Mirror-SkillWithCache $src $dst "mapping|v|fresh|1" $oldCache $newCache $stats

            Assert-MockCalled Get-DirectoryFingerprint -Times 0 -Exactly -Scope It
            Assert-MockCalled RoboMirror -Times 1 -Exactly -Scope It
            $stats.mirrored | Should Be 1
            $stats.skipped | Should Be 0
        }

        It "Reuses computed fingerprint for repeated source directory in one build pass" {
            $src = Join-Path $TestDrive "shared-src"
            $dst1 = Join-Path $TestDrive "dst-a"
            $dst2 = Join-Path $TestDrive "dst-b"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-Item -ItemType Directory -Path $dst1 -Force | Out-Null
            New-Item -ItemType Directory -Path $dst2 -Force | Out-Null
            Set-Content -Path (Join-Path $src "SKILL.md") -Value "same"

            $oldCache = @{}
            $newCache = @{}
            $stats = [pscustomobject]@{ mirrored = 0; skipped = 0 }
            $fpCache = @{}

            Mock Get-DirectoryFingerprint { "fp-shared" }
            Mock RoboMirror {}

            Mirror-SkillWithCache $src $dst1 "mapping|v|a|1" $oldCache $newCache $stats $fpCache
            Mirror-SkillWithCache $src $dst2 "mapping|v|a|2" $oldCache $newCache $stats $fpCache

            Assert-MockCalled Get-DirectoryFingerprint -Times 1 -Exactly -Scope It
            $newCache["mapping|v|a|1"] | Should Be "fp-shared"
            $newCache["mapping|v|a|2"] | Should Be "fp-shared"
            $stats.fp_cache_hit | Should Be 1
            $stats.fp_cache_miss | Should Be 1
        }

    }

    Context "Agent build skip cache" {
        It "Uses distinct metric names for cache-hit and full Agent builds" {
            (Get-AgentBuildMetricName $true) | Should Be "build_agent_cache_hit"
            (Get-AgentBuildMetricName $false) | Should Be "build_agent_full"
        }

        It "Builds a real state signature from current mapping sources" {
            $src = Join-Path $TestDrive "vendor-src\skill-a"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $src "SKILL.md") -Value "---`nname: skill-a`ndescription: fixture`n---" -Encoding UTF8

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "vendor-a" })
                mappings = @([pscustomobject]@{ vendor = "vendor-a"; from = "skill-a"; to = "skill-a" })
                imports = @()
            }

            Mock Resolve-SourceBase { Join-Path $TestDrive "vendor-src" }
            Mock Get-OverridesDirs { @() }

            $state = Get-AgentBuildState $cfg

            $state.can_skip | Should Be $true
            [string]::IsNullOrWhiteSpace([string]$state.signature) | Should Be $false
            @($state.outputs) | Should Contain "skill-a"
        }

        It "Reuses source resolution caches in a shared mapping resolver context" {
            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "vendor-a" })
                mappings = @(
                    [pscustomobject]@{ vendor = "manual"; from = "shared-manual"; to = "manual-copy-a" },
                    [pscustomobject]@{ vendor = "manual"; from = "shared-manual"; to = "manual-copy-b" },
                    [pscustomobject]@{ vendor = "vendor-a"; from = "shared-skill"; to = "vendor-copy-a" },
                    [pscustomobject]@{ vendor = "vendor-a"; from = "shared-skill"; to = "vendor-copy-b" }
                )
                imports = @()
            }

            Mock Resolve-ManualImportSkillPath { Join-Path $TestDrive "manual-src" }
            Mock Resolve-SourceBase { Join-Path $TestDrive "vendor-src" }

            $context = New-AgentMappingResolveContext
            foreach ($mapping in @($cfg.mappings)) {
                $resolved = Resolve-AgentMappingForAgent $cfg $mapping $context
                $resolved.sync | Should Be $true
                $resolved.source_valid | Should Be $true
            }

            Assert-MockCalled Resolve-ManualImportSkillPath -Times 1 -Exactly -Scope It
            Assert-MockCalled Resolve-SourceBase -Times 1 -Exactly -Scope It
        }

        It "Accepts a matching build signature when expected outputs exist" {
            $oldAgent = $script:AgentDir
            try {
                $script:AgentDir = Join-Path $TestDrive "agent-hit"
                New-Item -ItemType Directory -Path (Join-Path $script:AgentDir "skill-a") -Force | Out-Null

                Mock Load-BuildCache { @{
                        "__agent_build_algorithm" = (Get-AgentBuildCacheAlgorithmVersion)
                        "__agent_build_signature" = "sig-1"
                        "__agent_build_output_fingerprint" = (Get-DirectoryFingerprint $script:AgentDir)
                    } }
                Mock Get-AgentBuildState { [pscustomobject]@{ can_skip = $true; reason = "ok"; signature = "sig-1"; outputs = @("skill-a") } }

                $hit = Test-AgentBuildCacheHit ([pscustomobject]@{})

                $hit.hit | Should Be $true
                $hit.reason | Should Be "cache-hit"
            }
            finally {
                $script:AgentDir = $oldAgent
            }
        }

        It "Rejects a matching build signature when an expected output is missing" {
            $oldAgent = $script:AgentDir
            try {
                $script:AgentDir = Join-Path $TestDrive "agent-missing-output"
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null

                Mock Load-BuildCache { @{
                        "__agent_build_algorithm" = (Get-AgentBuildCacheAlgorithmVersion)
                        "__agent_build_signature" = "sig-1"
                        "__agent_build_output_fingerprint" = (Get-DirectoryFingerprint $script:AgentDir)
                    } }
                Mock Get-AgentBuildState { [pscustomobject]@{ can_skip = $true; reason = "ok"; signature = "sig-1"; outputs = @("skill-a") } }

                $hit = Test-AgentBuildCacheHit ([pscustomobject]@{})

                $hit.hit | Should Be $false
                $hit.reason | Should Match "output-missing"
            }
            finally {
                $script:AgentDir = $oldAgent
            }
        }

        It "Rejects a matching build signature when a stale top-level output remains" {
            $oldAgent = $script:AgentDir
            try {
                $script:AgentDir = Join-Path $TestDrive "agent-stale-output"
                New-Item -ItemType Directory -Path (Join-Path $script:AgentDir "skill-a") -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $script:AgentDir "stale-skill") -Force | Out-Null

                Mock Load-BuildCache { @{
                        "__agent_build_algorithm" = (Get-AgentBuildCacheAlgorithmVersion)
                        "__agent_build_signature" = "sig-1"
                        "__agent_build_output_fingerprint" = (Get-DirectoryFingerprint $script:AgentDir)
                    } }
                Mock Get-AgentBuildState { [pscustomobject]@{ can_skip = $true; reason = "ok"; signature = "sig-1"; outputs = @("skill-a") } }

                $hit = Test-AgentBuildCacheHit ([pscustomobject]@{})

                $hit.hit | Should Be $false
                $hit.reason | Should Be "unexpected-output:stale-skill"
            }
            finally {
                $script:AgentDir = $oldAgent
            }
        }

        It "Rejects a poisoned cache when the agent output fingerprint differs" {
            $oldAgent = $script:AgentDir
            try {
                $script:AgentDir = Join-Path $TestDrive "agent-poisoned-cache"
                New-Item -ItemType Directory -Path (Join-Path $script:AgentDir "skill-a") -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $script:AgentDir "skill-a\SKILL.md") -Value "stale output"

                Mock Load-BuildCache { @{
                        "__agent_build_algorithm" = (Get-AgentBuildCacheAlgorithmVersion)
                        "__agent_build_signature" = "sig-1"
                        "__agent_build_output_fingerprint" = "fingerprint-from-new-output"
                    } }
                Mock Get-AgentBuildState { [pscustomobject]@{ can_skip = $true; reason = "ok"; signature = "sig-1"; outputs = @("skill-a") } }
                Mock Get-DirectoryFingerprint { "fingerprint-from-stale-output" }

                $hit = Test-AgentBuildCacheHit ([pscustomobject]@{})

                $hit.hit | Should Be $false
                $hit.reason | Should Be "output-fingerprint-mismatch"
            }
            finally {
                $script:AgentDir = $oldAgent
            }
        }

        It "Skips the build transaction when the agent build cache is valid" {
            $cfg = [pscustomobject]@{
                vendors = @()
                mappings = @()
                targets = @()
                sync_mode = "link"
            }

            Mock Preflight {}
            Mock Invoke-PrebuildCheck {}
            Mock LoadCfg { $cfg }
            Mock Optimize-Imports {}
            Mock Get-CfgChangeSummaryLines { @() }
            Mock Write-BuildSummary {}
            Mock Test-AgentBuildCacheHit { [pscustomobject]@{ hit = $true; reason = "cache-hit"; state = [pscustomobject]@{ signature = "sig-1"; outputs = @("skill-a") } } }
            Mock Start-BuildTransaction { throw "Start-BuildTransaction should not be called on cache hit." }
            Mock 构建Agent { throw "构建Agent should not be called on cache hit." }
            Mock 应用到ClaudeCodex { @() }
            Mock Start-DryRunMirrorCollect {}
            Mock Stop-DryRunMirrorCollect {}
            Mock Write-DryRunMirrorSummary {}
            Mock Complete-BuildTransaction {}
            Mock Rollback-BuildTransaction {}
            Mock Log {}

            构建生效

            Assert-MockCalled 应用到ClaudeCodex -Times 1 -Exactly -Scope It
            Assert-MockCalled Start-BuildTransaction -Times 0 -Exactly -Scope It
            Assert-MockCalled 构建Agent -Times 0 -Exactly -Scope It
        }

    }

    Context "Build Transaction" {
        It "Restores previous agent folder on rollback" {
            $oldRoot = $script:Root
            $oldAgent = $script:AgentDir
            try {
                $script:Root = Join-Path $TestDrive "repo"
                $script:AgentDir = Join-Path $script:Root "agent"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null
                Set-Content -Path (Join-Path $script:AgentDir "old.txt") -Value "old"

                $txn = Start-BuildTransaction
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null
                Set-Content -Path (Join-Path $script:AgentDir "new.txt") -Value "new"

                Rollback-BuildTransaction $txn
                (Test-Path (Join-Path $script:AgentDir "old.txt")) | Should Be $true
                (Test-Path (Join-Path $script:AgentDir "new.txt")) | Should Be $false
            }
            finally {
                $script:Root = $oldRoot
                $script:AgentDir = $oldAgent
            }
        }

        It "Restores previous build cache together with the agent folder" {
            $oldRoot = $script:Root
            $oldAgent = $script:AgentDir
            try {
                $script:Root = Join-Path $TestDrive "repo-cache-rollback"
                $script:AgentDir = Join-Path $script:Root "agent"
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $script:AgentDir "old.txt") -Value "old"
                Set-Content -LiteralPath (Join-Path $script:Root ".build-cache.json") -Value '{"__agent_build_signature":"old-signature"}'

                $txn = Start-BuildTransaction
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $script:AgentDir "new.txt") -Value "new"
                Set-Content -LiteralPath (Join-Path $script:Root ".build-cache.json") -Value '{"__agent_build_signature":"new-signature"}'

                Rollback-BuildTransaction $txn

                (Get-Content -LiteralPath (Join-Path $script:Root ".build-cache.json") -Raw | ConvertFrom-Json).__agent_build_signature | Should Be "old-signature"
                (Test-Path -LiteralPath (Join-Path $script:AgentDir "old.txt")) | Should Be $true
                (Test-Path -LiteralPath (Join-Path $script:AgentDir "new.txt")) | Should Be $false
            }
            finally {
                $script:Root = $oldRoot
                $script:AgentDir = $oldAgent
            }
        }
    }

    Context "Agent cleanup" {
        It "Uses retry-capable deletion when clearing the agent directory" {
            $oldAgent = $script:AgentDir
            try {
                $script:AgentDir = Join-Path $TestDrive "agent-clean"
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null

                Mock Invoke-RemoveItemWithRetry { $true }
                Mock EnsureDir {}

                清空Agent目录

                Assert-MockCalled Invoke-RemoveItemWithRetry -Times 1 -Exactly -ParameterFilter { $path -eq $script:AgentDir -and $Recurse }
                Assert-MockCalled EnsureDir -Times 1 -Exactly -ParameterFilter { $p -eq $script:AgentDir }
            }
            finally {
                $script:AgentDir = $oldAgent
            }
        }

    }

    Context "构建Agent mapping caches" {
        It "Caches repeated manual and vendor source resolution within one mapping pass" {
            $oldRoot = $script:Root
            $oldAgent = $script:AgentDir
            try {
                $script:Root = Join-Path $TestDrive "repo"
                $script:AgentDir = Join-Path $script:Root "agent"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "vendor-a" })
                    mappings = @(
                        [pscustomobject]@{ vendor = "manual"; from = "shared-manual"; to = "manual-copy-a" },
                        [pscustomobject]@{ vendor = "manual"; from = "shared-manual"; to = "manual-copy-b" },
                        [pscustomobject]@{ vendor = "vendor-a"; from = "shared-skill"; to = "vendor-copy-a" },
                        [pscustomobject]@{ vendor = "vendor-a"; from = "shared-skill"; to = "vendor-copy-b" }
                    )
                    imports = @()
                }

                Mock Preflight {}
                Mock 清空Agent目录 {}
                Mock Load-BuildCache { @{} }
                Mock Should-SyncMappingToAgent { $true }
                Mock Test-SafeRelativePath { $true }
                Mock Resolve-ManualImportSkillPath { Join-Path $TestDrive "manual-src" }
                Mock Resolve-SourceBase { Join-Path $TestDrive "vendor-src" }
                Mock Is-PathInsideOrEqual { $true }
                Mock Test-IsSkillDir { $true }
                Mock Mirror-SkillWithCache {}
                Mock 收集ManualSkills { @() }
                Mock Get-OverridesDirs { @() }
                Mock Remove-VendorRootMappingOutputsFromAgent { 0 }
                Mock Normalize-SkillMarkdownFiles { [pscustomobject]@{ normalized = 0; failed = 0; failed_paths = @() } }
                Mock Remove-InvalidSkillMarkdownFiles { [pscustomobject]@{ removed = 0; failed = 0; failed_paths = @() } }
                Mock Get-SkillNameConflictBuckets { @{} }
                Mock Get-DuplicateMappingSourceGroups { @() }
                Mock Set-AgentBuildStateCache {}
                Mock Save-BuildCache {}
                Mock Complete-BuildTransaction {}
                Mock Write-Host {}
                Mock Log {}

                构建Agent $cfg -SkipPreflight | Out-Null

                Assert-MockCalled Resolve-ManualImportSkillPath -Times 1 -Exactly -Scope It
                Assert-MockCalled Resolve-SourceBase -Times 1 -Exactly -Scope It
                Assert-MockCalled Test-IsSkillDir -Times 2 -Exactly -Scope It
                Assert-MockCalled Mirror-SkillWithCache -Times 4 -Exactly -Scope It
            }
            finally {
                $script:Root = $oldRoot
                $script:AgentDir = $oldAgent
            }
        }
    }

    Context "Invalid mapping discovery" {
        It "Uses shared agent mapping resolution when checking invalid mappings" {
            $manualSrc = Join-Path $TestDrive "manual-src"
            $vendorBase = Join-Path $TestDrive "vendor-src"
            $vendorSrc = Join-Path $vendorBase "shared-skill"
            New-Item -ItemType Directory -Path $manualSrc -Force | Out-Null
            New-Item -ItemType Directory -Path $vendorSrc -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $manualSrc "SKILL.md") -Value "---`nname: shared-manual`ndescription: fixture`n---"
            Set-Content -LiteralPath (Join-Path $vendorSrc "SKILL.md") -Value "---`nname: shared-skill`ndescription: fixture`n---"

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "vendor-a" })
                mappings = @(
                    [pscustomobject]@{ vendor = "manual"; from = "shared-manual"; to = "manual-copy-a" },
                    [pscustomobject]@{ vendor = "manual"; from = "shared-manual"; to = "manual-copy-b" },
                    [pscustomobject]@{ vendor = "vendor-a"; from = "shared-skill"; to = "vendor-copy-a" },
                    [pscustomobject]@{ vendor = "vendor-a"; from = "shared-skill"; to = "vendor-copy-b" }
                )
                imports = @()
            }

            Mock Resolve-ManualImportSkillPath { $manualSrc }
            Mock Resolve-SourceBase { $vendorBase }

            @(Get-InvalidMappings $cfg).Count | Should Be 0
            Assert-MockCalled Resolve-ManualImportSkillPath -Times 1 -Exactly -Scope It
            Assert-MockCalled Resolve-SourceBase -Times 1 -Exactly -Scope It
        }

        It "Treats missing manual imports as invalid mappings instead of build failures" {
            $oldRoot = $script:Root
            $oldAgent = $script:AgentDir
            try {
                $script:Root = Join-Path $TestDrive "repo-invalid-manual"
                $script:AgentDir = Join-Path $script:Root "agent"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                New-Item -ItemType Directory -Path $script:AgentDir -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @()
                    mappings = @(
                        [pscustomobject]@{ vendor = "manual"; from = "missing-manual"; to = "missing-manual" }
                    )
                    imports = @()
                }

                Mock Preflight {}
                Mock 清空Agent目录 {}
                Mock Load-BuildCache { @{} }
                Mock Save-BuildCache {}
                Mock Set-AgentBuildStateCache {}
                Mock Should-SyncMappingToAgent { $true }
                Mock Test-SafeRelativePath { $true }
                Mock Resolve-ManualImportSkillPath { $null }
                Mock Test-ResolvedAgentMappingSkillDir { throw "missing manual import should not reach skill-dir validation" }
                Mock Mirror-SkillWithCache { throw "missing manual import should not be mirrored" }
                Mock 收集ManualSkills { @() }
                Mock Get-OverridesDirs { @() }
                Mock Remove-VendorRootMappingOutputsFromAgent { 0 }
                Mock Should-SkipBuildPostScan { $true }
                Mock Get-DuplicateMappingSourceGroups { @() }
                Mock Write-Host {}
                Mock Log {}

                $failures = @(构建Agent $cfg -SkipPreflight)

                $failures.Count | Should Be 0
                @(Get-InvalidMappings $cfg).Count | Should Be 1
                @(Get-InvalidMappings $cfg)[0].reason | Should Be "manual 导入不存在或无效"
                Assert-MockCalled Resolve-ManualImportSkillPath -Times 3 -Exactly -Scope It
                Assert-MockCalled Mirror-SkillWithCache -Times 0 -Exactly -Scope It
                Assert-MockCalled Test-ResolvedAgentMappingSkillDir -Times 0 -Exactly -Scope It
            }
            finally {
                $script:Root = $oldRoot
                $script:AgentDir = $oldAgent
            }
        }


    }

    Context "Skill name conflicts" {
        It "Allows multiple duplicate skill names when files are byte-identical aliases" {
            $agent = Join-Path $TestDrive "agent"
            $cases = @(
                [pscustomobject]@{
                    name = "do"
                    content = @"
---
name: do
description: Execute a phased implementation plan using subagents.
---
"@
                }
                [pscustomobject]@{
                    name = "make-plan"
                    content = @"
---
name: make-plan
description: Create a detailed, phased implementation plan with documentation discovery.
---
"@
                }
            )

            foreach ($case in $cases) {
                $plugin = Join-Path $agent ("manual-claude-mem\plugin\skills\{0}" -f $case.name)
                $openclaw = Join-Path $agent ("manual-claude-mem\openclaw\skills\{0}" -f $case.name)
                New-Item -ItemType Directory -Path $plugin -Force | Out-Null
                New-Item -ItemType Directory -Path $openclaw -Force | Out-Null
                Set-Content -Path (Join-Path $plugin "SKILL.md") -Value $case.content
                Set-Content -Path (Join-Path $openclaw "SKILL.md") -Value $case.content
            }

            $buckets = Get-SkillNameConflictBuckets $agent
            foreach ($case in $cases) {
                $paths = @($buckets[$case.name])
                $paths.Count | Should Be 2
                (Test-SkillNameDuplicateContentAllowed $paths) | Should Be $true
            }
        }

        It "Allows system skills to override same-named non-system skills" {
            $repoRoot = Join-Path $TestDrive "skills-manager"
            $paths = @(
                (Join-Path $repoRoot "agent\.system\skill-installer\SKILL.md"),
                (Join-Path $repoRoot "agent\skills-skills-.system-skill-installer\SKILL.md")
            )

            (Test-SkillNameDuplicateContentAllowed $paths) | Should Be $false
            (Test-SkillNameSystemOverrideAllowed $paths) | Should Be $true
        }
    }

    Context "Build post-scan shortcut" {
        It "Skips post-scan when no new mirror happened and agent dir was not reused" {
            $stats = [pscustomobject]@{ mirrored = 0; reused = $false }
            (Should-SkipBuildPostScan $stats) | Should Be $true
        }

        It "Does not skip post-scan when mirrored content exists" {
            $stats = [pscustomobject]@{ mirrored = 2; reused = $false }
            (Should-SkipBuildPostScan $stats) | Should Be $false
        }

        It "Does not skip post-scan when build reused existing agent directory" {
            $stats = [pscustomobject]@{ mirrored = 0; reused = $true }
            (Should-SkipBuildPostScan $stats) | Should Be $false
        }
    }
}
