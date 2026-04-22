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
            Assert-MockCalled RoboMirror -Times 0 -Exactly
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
            (Get-Content -Raw (Join-Path $dst "openclaw\skills\do\SKILL.md")) | Should Match "^---"
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
}
