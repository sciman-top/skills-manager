BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

    # CI checkouts convert text files to CRLF (core.autocrlf=true); anchored
    # (?m)^...$ assertions must not see carriage returns.
    function Get-BridgeTemplateText([string]$RelativePath) {
        return (Get-ContentUtf8 (Join-Path $repoRoot $RelativePath)) -replace "`r", ''
    }
}

Describe 'Native agent bridge' {
    It 'keeps each projected custom agent narrow, owned, and scoped to its job' {
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            $template = Get-BridgeTemplateText ("overrides\resources\native-agent-bridge\{0}.toml" -f $name)

            $template | Should -Match '(?m)^# skills-manager-native-agent-bridge: v1$'
            $template | Should -Match ("(?m)^name = `"{0}`"$" -f [regex]::Escape($name))
            $template | Should -Match '(?m)^description = '
            $template | Should -Match '(?m)^developer_instructions = '
            $template | Should -Match '(?m)^enabled = false$'
        }

        (Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\design-griller.toml') | Should -Match '(?m)^sandbox_mode = "read-only"$'
        (Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\cold-capability-runner.toml') | Should -Match '(?m)^sandbox_mode = "workspace-write"$'
    }

    It 'plans bridge projection without writing the host agent directory during dry run' {
        $config = Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
        $previousRoot = $Root
        $previousAgentDir = $AgentDir
        $previousDryRun = $DryRun
        try {
            $Root = $TestDrive
            $AgentDir = Join-Path $Root 'agent'
            $sourceRoot = Join-Path $AgentDir 'native-agent-bridge'
            New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
            foreach ($name in @('design-griller', 'cold-capability-runner')) {
                Copy-Item -LiteralPath (Join-Path $repoRoot ("overrides\resources\native-agent-bridge\{0}.toml" -f $name)) -Destination (Join-Path $sourceRoot ("{0}.toml" -f $name))
            }
            $config.skill_projection.native_agent_bridge.source_root = 'agent/native-agent-bridge'
            $config.skill_projection.native_agent_bridge.receipt_path = 'reports/native-agent-bridge/fixture.json'
            $DryRun = $true
            $result = Sync-NativeAgentBridge $config

            $result.enabled | Should -BeTrue
            $result.persisted | Should -BeFalse
            $result.truth_boundary | Should -Be 'planned'
            @($result.changed_names) | Should -Be @('cold-capability-runner', 'design-griller')
            @($result.definitions | ForEach-Object { $_.target_path }) | ForEach-Object { $_ | Should -Match ([regex]::Escape((Join-Path $HOME '.codex\agents'))) }
        }
        finally {
            $Root = $previousRoot
            $AgentDir = $previousAgentDir
            $DryRun = $previousDryRun
        }
    }

    It 'treats a bridge-only host projection as requiring promotion' {
        $previousRoot = $Root
        try {
            $Root = $TestDrive
            $config = [pscustomobject]@{
                targets = @()
                skill_projection = [pscustomobject]@{
                    native_agent_bridge = [pscustomobject]@{
                        target_root = '~/.codex/agents'
                    }
                }
            }
            (Test-ConfiguredHostProjection $config) | Should -BeTrue
        }
        finally { $Root = $previousRoot }
    }

    It 'keeps grill-me as an explicit core entry that delegates to the native griller' {
        $skill = Get-BridgeTemplateText 'overrides\patches\grill-me\SKILL.md'
        $metadata = Get-BridgeTemplateText 'overrides\patches\grill-me\agents\openai.yaml'

        $metadata | Should -Match 'allow_implicit_invocation:\s*false'
        $skill | Should -Match 'native `design-griller`'
        $skill | Should -Match '(?s)Do not perform\s+the interview in the parent task'
        $skill | Should -Match 'do not change a shared skill profile'
        $skill | Should -Match 'no repository edits'
        $skill | Should -Match 'non-empty child task or\s+thread identifier'
        $skill | Should -Match 'not a delegation receipt'
        $skill | Should -Match 'simulate a child question'
        $skill | Should -Match '(?s)Do not silently\s+fall back'
    }

    It 'requires an explicit bounded admission before a cold controlled-write skill can execute' {
        $runner = Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\cold-capability-runner.toml'

        $runner | Should -Match 'Validation authorizes reading, never execution'
        $runner | Should -Match 'full validated dependency closure'
        $runner | Should -Match 'effective execution contract'
        $runner | Should -Match 'execution_contract.mode=one_shot'
        $runner | Should -Match 'multi_turn_user_decision'
        $runner | Should -Match 'interactive_bridge_required'
        $runner | Should -Match 'never overrides an interactive contract'
        $runner | Should -Match 'validated closure contains the selected entry plus every declared dependency'
        $runner | Should -Match 'requested_operation=read_only'
        $runner | Should -Match 'even if a closure member declares controlled_write'
        $runner | Should -Match 'user requested implementation'
        $runner | Should -Match 'exact non-empty write set'
        $runner | Should -Match 'minimum proof'
        $runner | Should -Match 'requested_operation=controlled_write'
        $runner | Should -Match 'external_read, unknown side effects'
        $runner | Should -Match 'Never spawn subagents'

        $griller = Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\design-griller.toml'
        $griller | Should -Match 'status=awaiting_user_answer'
        $griller | Should -Match 'never overrides this wait state'
    }
}
