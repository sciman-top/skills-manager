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
            @($selection.included_names).Count | Should -Be 8
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

    It 'includes the resolved profile in the projection fingerprint' {
        $config = (Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json).skill_projection
        $plan = [pscustomobject]@{ enabled = $true; canonical = @(); disabled = @() }
        $core = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName codex -RequestedProfile core
        $full = Resolve-SkillProjectionSelection -ProjectionConfig $config -HostName codex -RequestedProfile 'full-compatible'

        (Get-SkillProjectionPlanFingerprint $plan $null $core) | Should -Not -Be (Get-SkillProjectionPlanFingerprint $plan $null $full)
    }
}
