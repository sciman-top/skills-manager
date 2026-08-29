BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

    function New-ProfileFixtureSkill([string]$Root, [string]$Name) {
        $directory = Join-Path $Root $Name
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-ContentUtf8 (Join-Path $directory 'SKILL.md') ("---`nname: {0}`ndescription: {0} fixture.`n---`n# {0}`n" -f $Name)
    }

    function New-ProfileFixtureProjection([string]$Source, [string]$Target, [string]$Receipt) {
        return [pscustomobject]@{
            managed_source_path = $Source
            user_skill_root = $Target
            native_projection = [pscustomobject]@{
                enabled = $true
                owner = 'skills-manager-test'
                target_root = $Target
                receipt_path = $Receipt
            }
            projection_profiles = [pscustomobject]@{
                schema_version = 1
                default_profile = 'core'
                profiles = [pscustomobject]@{
                    core = [pscustomobject]@{ include = @('alpha'); exclude = @() }
                    'full-compatible' = [pscustomobject]@{ include_all = $true; exclude = @() }
                }
                hosts = [pscustomobject]@{
                    codex = [pscustomobject]@{ default_profile = 'core'; exclude = @() }
                    claude = [pscustomobject]@{ default_profile = 'core'; exclude = @() }
                    zcode = [pscustomobject]@{ default_profile = 'core'; exclude = @('zcode-only-incompatible') }
                }
            }
        }
    }
}

Describe 'Skill projection profiles' {
    It 'keeps the checked-in default core profile small for every host' {
        $config = (Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json).skill_projection

        foreach ($hostName in @('codex', 'claude', 'zcode')) {
            $selection = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName $hostName
            $selection.profile | Should -Be 'core'
            $selection.include_all | Should -BeFalse
            @($selection.included_names).Count | Should -Be 9
            @($selection.included_names) | Should -Contain 'grill-me'
        }
        @(Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName zcode).excluded_names | Should -Be @('agent-browser', 'skill-creator', 'web-artifacts-builder')
    }

    It 'represents the full-compatible ZCode projection as all managed skills minus host exclusions' {
        $config = (Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json).skill_projection
        $selection = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName zcode -RequestedProfile 'full-compatible'

        $selection.profile | Should -Be 'full-compatible'
        $selection.include_all | Should -BeTrue
        @($selection.included_names).Count | Should -Be 0
        @($selection.excluded_names) | Should -Be @('agent-browser', 'skill-creator', 'web-artifacts-builder')

        $codexSelection = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName codex -RequestedProfile 'full-compatible'
        @($codexSelection.excluded_names) | Should -Be @('skill-creator', 'web-artifacts-builder')
    }

    It 'projects every fixture skill except the selected host exclusion in full-compatible mode' {
        $source = Join-Path $TestDrive 'profile-source'
        $target = Join-Path $TestDrive 'profile-target'
        $receipt = Join-Path $repoRoot ('reports\skill-projection\profile-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        foreach ($name in @('alpha', 'beta', 'zcode-only-incompatible')) { New-ProfileFixtureSkill $source $name }
        $projection = New-ProfileFixtureProjection $source $target $receipt

        $selection = Resolve-SkillProjectionSelection -ProjectionConfig $projection -HostName zcode -RequestedProfile 'full-compatible'
        $effective = New-SkillProjectionHostConfig -ProjectionConfig $projection -Selection $selection
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $source -Config ([pscustomobject]@{ skill_projection = $effective }) -IncludedNames @($selection.included_names) -ExcludedNames @($selection.excluded_names)

        $plan.status | Should -Be 'ready'
        @($plan.skills | ForEach-Object name) | Should -Be @('alpha', 'beta')
        @($plan.removals).Count | Should -Be 0
    }

    It 'preserves the resolved host selection for downstream native projection' {
        $source = Join-Path $TestDrive 'effective-source'
        $target = Join-Path $TestDrive 'effective-target'
        $receipt = Join-Path $repoRoot ('reports\skill-projection\effective-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        $projection = New-ProfileFixtureProjection $source $target $receipt
        $selection = Resolve-SkillProjectionSelection -ProjectionConfig $projection -HostName zcode -RequestedProfile 'full-compatible'
        $effective = New-SkillProjectionHostConfig -ProjectionConfig $projection -Selection $selection

        $resolved = Get-SkillProjectionEffectiveSelection $effective zcode

        $resolved.host | Should -Be 'zcode'
        $resolved.profile | Should -Be 'full-compatible'
    }

    It 'fails closed for an unknown profile and an include/exclude conflict' {
        $config = (Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json).skill_projection
        { Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName codex -RequestedProfile 'does-not-exist' } | Should -Throw '*不存在的 profile*'

        $invalid = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $invalid.projection_profiles.profiles.core.exclude = @('research')
        { Resolve-SkillProjectionSelection -ProjectionConfig $invalid -HostName codex } | Should -Throw '*include/exclude 冲突*'
    }

    It 'derives legacy target hosts and rejects unknown managed-link-only targets' {
        (Get-SkillProjectionTargetHost ([pscustomobject]@{ path = '~/.claude/skills'; managed_link_only = $true })) | Should -Be 'claude'
        (Get-SkillProjectionTargetHost ([pscustomobject]@{ path = '~/.zcode/skills'; managed_link_only = $true })) | Should -Be 'zcode'
        { Get-SkillProjectionTargetHost ([pscustomobject]@{ path = '~/.other/skills'; managed_link_only = $true }) } | Should -Throw '*无法由 path 推导宿主*'
    }

    It 'derives host root declarations from managed-link targets and retains compatibility roots' {
        $config = [pscustomobject]@{
            targets = @(
                [pscustomobject]@{ path = '~/.claude/skills'; host = 'claude'; managed_link_only = $true }
            )
            skill_projection = [pscustomobject]@{
                host_skill_roots = @(
                    [pscustomobject]@{ path = '~/.zcode/skills'; host = 'zcode' }
                )
            }
        }

        $declarations = @(Get-SkillProjectionHostRootDeclarations $config)

        @($declarations | Where-Object { $_.host -eq 'claude' -and $_.source -eq 'managed_link_target' } | ForEach-Object path) | Should -Be @('~/.claude/skills')
        @($declarations | Where-Object { $_.host -eq 'zcode' -and $_.source -eq 'compatibility_host_skill_roots' } | ForEach-Object path) | Should -Be @('~/.zcode/skills')
    }

    It 'includes the resolved profile in the projection fingerprint' {
        $config = (Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json).skill_projection
        $plan = [pscustomobject]@{ enabled = $true; canonical = @(); disabled = @() }
        $core = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName codex -RequestedProfile core
        $full = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName codex -RequestedProfile 'full-compatible'

        (Get-SkillProjectionPlanFingerprint $plan $null $core) | Should -Not -Be (Get-SkillProjectionPlanFingerprint $plan $null $full)
    }

    It 'keeps the full-compatible TDD skill prompt-visible while retaining its explicit-use constraint' {
        $metadata = Get-ContentUtf8 (Join-Path $repoRoot 'overrides\patches\test-driven-development\agents\openai.yaml')
        $skill = Get-ContentUtf8 (Join-Path $repoRoot 'overrides\patches\test-driven-development\SKILL.md')

        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $skill | Should -Match 'user explicitly requests strict TDD'
        $skill | Should -Match 'Do not require TDD for routine implementation'
    }

    It 'validates a full-compatible manifest against its recorded profile instead of the default core profile' {
        $source = Join-Path $TestDrive 'manifest-source'
        $target = Join-Path $TestDrive 'manifest-target'
        $receipt = Join-Path $repoRoot ('reports\skill-projection\manifest-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        foreach ($name in @('alpha', 'beta')) { New-ProfileFixtureSkill $source $name }
        $projection = New-ProfileFixtureProjection $source $target $receipt
        $projection | Add-Member -NotePropertyName sources -NotePropertyValue @([pscustomobject]@{ id = 'fixture'; path = $source; priority = 1; platforms = @('codex') })
        $selection = Resolve-SkillProjectionSelection -ProjectionConfig $projection -HostName codex -RequestedProfile 'full-compatible'
        $effective = New-SkillProjectionHostConfig -ProjectionConfig $projection -Selection $selection
        $plan = New-SkillProjectionPlan $effective $repoRoot -OmitExternalInventory
        $native = New-NativeSkillProjectionRuntimePlan -ManagedRoot $source -Config ([pscustomobject]@{ skill_projection = $effective }) -IncludedNames @($selection.included_names) -ExcludedNames @($selection.excluded_names)
        $manifest = [pscustomobject]@{
            schema_version = 2
            projection_fingerprint = Get-SkillProjectionPlanFingerprint $plan $native $selection
            enabled = [bool]$plan.enabled
            source_count = 1
            skill_entry_count = @($plan.skills).Count
            unique_name_count = @($plan.unique_names).Count
            active_name_count = @($plan.active_names).Count
            duplicate_name_groups = [int]$plan.duplicate_name_groups
            disabled_path_count = @($plan.disabled).Count
            conflict_count = @($plan.conflicts).Count
            skills = @($plan.skills)
            canonical = @($plan.canonical)
            active = @($plan.active)
            disabled = @($plan.disabled)
            conflicts = @($plan.conflicts)
            projection_selection = [pscustomobject]@{
                host = $selection.host
                profile = $selection.profile
                include_all = $selection.include_all
                included_names = @($selection.included_names)
                excluded_names = @($selection.excluded_names)
            }
        }

        $validation = Test-SkillProjectionManifestCurrent $manifest $projection $repoRoot

        $validation.pass | Should -BeTrue
        $validation.freshness | Should -Be 'fresh'
    }

    It 'keeps the manifest fresh after shrinking a native profile and removing owned links' {
        $source = Join-Path $TestDrive 'transition-source'
        $target = Join-Path $TestDrive 'transition-target'
        $receipt = Join-Path $repoRoot ('reports\skill-projection\transition-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        $configPath = Join-Path $TestDrive 'transition-config.toml'
        $manifestPath = Join-Path $TestDrive 'transition-manifest.json'
        foreach ($name in @('alpha', 'beta')) { New-ProfileFixtureSkill $source $name }
        $projection = New-ProfileFixtureProjection $source $target $receipt
        $projection | Add-Member -NotePropertyName sources -NotePropertyValue @([pscustomobject]@{ id = 'fixture'; path = $source; priority = 1; platforms = @('codex') })
        $projection | Add-Member -NotePropertyName codex_config_path -NotePropertyValue $configPath
        $projection | Add-Member -NotePropertyName manifest_path -NotePropertyValue $manifestPath
        $promotionContext = [pscustomobject]@{ source_revision = 'fixture'; source_worktree_dirty = $false; source_git_state = 'clean'; promotion_mode = 'test' }

        try {
            $fullSelection = Resolve-SkillProjectionSelection -ProjectionConfig $projection -HostName codex -RequestedProfile 'full-compatible'
            (Sync-CodexSkillProjection (New-SkillProjectionHostConfig -ProjectionConfig $projection -Selection $fullSelection) $promotionContext).success | Should -BeTrue

            $coreSelection = Resolve-SkillProjectionSelection -ProjectionConfig $projection -HostName codex -RequestedProfile core
            (Sync-CodexSkillProjection (New-SkillProjectionHostConfig -ProjectionConfig $projection -Selection $coreSelection) $promotionContext).success | Should -BeTrue

            Test-Path -LiteralPath (Join-Path $target 'beta') | Should -BeFalse
            $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
            $validation = Test-SkillProjectionManifestCurrent $manifest $projection $repoRoot

            $validation.pass | Should -BeTrue
            $validation.freshness | Should -Be 'fresh'
        }
        finally {
            if (Test-Path -LiteralPath $receipt -PathType Leaf) { Remove-Item -LiteralPath $receipt -Force }
        }
    }
}
