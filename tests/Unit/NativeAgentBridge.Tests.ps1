BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

    # CI checkouts convert text files to CRLF (core.autocrlf=true); anchored
    # (?m)^...$ assertions must not see carriage returns.
    function Get-BridgeTemplateText([string]$RelativePath) {
        return (Get-ContentUtf8 (Join-Path $repoRoot $RelativePath)) -replace "`r", ''
    }

    # CSR-110 static model pin oracle: both managed templates must carry exactly
    # one gpt-5.6-terra/high pair between description and sandbox_mode, and no
    # provider/auth/routing field may smuggle itself into the template.
    function Get-BridgeModelPinViolations([string]$TemplateText) {
        $violations = New-Object System.Collections.Generic.List[string]
        $modelFields = [regex]::Matches($TemplateText, '(?m)^model\s*=\s*"([^"]*)"$')
        $effortFields = [regex]::Matches($TemplateText, '(?m)^model_reasoning_effort\s*=\s*"([^"]*)"$')

        if ($modelFields.Count -ne 1) { $violations.Add('model field count is not exactly one') }
        elseif ($modelFields[0].Groups[1].Value -ne 'gpt-5.6-terra') { $violations.Add('model is not gpt-5.6-terra') }
        if ($effortFields.Count -ne 1) { $violations.Add('model_reasoning_effort field count is not exactly one') }
        elseif ($effortFields[0].Groups[1].Value -ne 'high') { $violations.Add('model_reasoning_effort is not high') }

        if ($modelFields.Count -eq 1 -and $effortFields.Count -eq 1) {
            $description = [regex]::Match($TemplateText, '(?m)^description\s*=')
            $sandbox = [regex]::Match($TemplateText, '(?m)^sandbox_mode\s*=')
            if (-not $description.Success -or -not $sandbox.Success -or
                $modelFields[0].Index -lt $description.Index -or $modelFields[0].Index -gt $sandbox.Index -or
                $effortFields[0].Index -lt $description.Index -or $effortFields[0].Index -gt $sandbox.Index) {
                $violations.Add('model pin is not placed between description and sandbox_mode')
            }
        }

        foreach ($forbidden in @('provider', 'model_provider', 'base_url', 'api_key', 'auth', 'secret', 'fallback', 'profile', 'session')) {
            if ($TemplateText -match ('(?m)^{0}\s*=' -f $forbidden)) { $violations.Add(("forbidden template field present: {0}" -f $forbidden)) }
        }
        return @($violations)
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

    It 'pins both managed bridge templates to exactly one static gpt-5.6-terra/high model pair' {
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            $template = Get-BridgeTemplateText ("overrides\resources\native-agent-bridge\{0}.toml" -f $name)
            @(Get-BridgeModelPinViolations $template) | Should -Be @()
        }
    }

    It 'fails closed when a managed template drops, duplicates, weakens, or smuggles the model pin' {
        $template = Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\design-griller.toml'
        @(Get-BridgeModelPinViolations $template) | Should -Be @()

        $mutations = [ordered]@{
            missing_model = $template -replace '(?m)^model = "gpt-5\.6-terra"$', ''
            missing_effort = $template -replace '(?m)^model_reasoning_effort = "high"$', ''
            duplicate_model = $template -replace '(?m)^(model = "gpt-5\.6-terra")$', ('$1' + "`n" + '$1')
            wrong_model = $template -replace 'gpt-5\.6-terra', 'gpt-5.6-sol'
            wrong_effort = $template -replace '(?m)^(model_reasoning_effort = )"high"$', '$1"medium"'
            forbidden_provider_field = $template -replace '(?m)^(model_reasoning_effort = "high")$', ('$1' + "`n" + 'provider = "smuggled"')
            pin_after_sandbox = ($template -replace '(?m)^model = "gpt-5\.6-terra"$', '') -replace '(?m)^(sandbox_mode = "read-only")$', ('$1' + "`n" + 'model = "gpt-5.6-terra"')
        }

        foreach ($mutation in $mutations.GetEnumerator()) {
            $violations = @(Get-BridgeModelPinViolations ([string]$mutation.Value))
            @($violations).Count | Should -BeGreaterThan 0 -Because ("mutation '{0}' must be rejected by the pin oracle" -f $mutation.Key)
        }
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
            foreach ($definition in @($result.definitions)) {
                $definition.source_sha256 | Should -Be (([string](Get-FileHash -LiteralPath (Join-Path $sourceRoot ($definition.name + '.toml')) -Algorithm SHA256).Hash).ToLowerInvariant())
            }
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

    It 'keeps owned bridge backups outside the recursive host agent discovery root and migrates legacy copies' {
        $targetRoot = Join-Path $TestDrive 'codex\agents'
        $legacyRoot = Join-Path $targetRoot 'skills-manager-backups'
        $newBackupRoot = Get-NativeAgentBridgeBackupRoot $targetRoot
        New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
        $legacyBackup = Join-Path $legacyRoot 'design-griller.fixture.toml'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'overrides\resources\native-agent-bridge\design-griller.toml') -Destination $legacyBackup

        Test-NativeAgentBridgeWithin $newBackupRoot $targetRoot | Should -BeFalse
        $migrations = @(Move-NativeAgentBridgeLegacyBackups $targetRoot $newBackupRoot)

        $migrations.Count | Should -Be 1
        $migrations[0].source_path | Should -Be $legacyBackup
        Test-Path -LiteralPath $legacyBackup | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $newBackupRoot 'design-griller.fixture.toml') | Should -BeTrue
        Test-Path -LiteralPath $legacyRoot | Should -BeFalse
    }

    It 'keeps grill-me prompt-visible as an explicit core entry that delegates to the native griller' {
        $skill = Get-BridgeTemplateText 'overrides\patches\grill-me\SKILL.md'
        $metadata = Get-BridgeTemplateText 'overrides\patches\grill-me\agents\openai.yaml'

        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $skill | Should -Match 'custom `design-griller`'
        $skill | Should -Match '(?s)Do not perform\s+the interview in the parent task'
        $skill | Should -Match 'do not change a shared skill profile'
        $skill | Should -Match 'no repository edits'
        $skill | Should -Match 'non-empty child task or\s+thread identifier'
        $skill | Should -Match 'host-native `spawn_agent` tool'
        $skill | Should -Match '(?s)Do not call `wait` until that\s+identifier exists'
        $skill | Should -Match 'bare `wait`'
        $skill | Should -Match 'native_bridge_unavailable'
        $skill | Should -Match 'simulate a child question'
        $skill | Should -Match 'silently fall back'

        $skill | Should -Match 'still an interview'
        $skill | Should -Match 'one-shot analysis, report, or summary with trailing questions'
        $skill | Should -Match 'that collapse\s+is forbidden'
        $skill | Should -Match 'route through cold discovery to `grill-with-docs`'
        $skill | Should -Match 'gather evidence per question, never instead of asking it'

        $grillingSkill = Get-BridgeTemplateText 'overrides\patches\grilling\SKILL.md'
        $grillingMetadata = Get-BridgeTemplateText 'overrides\patches\grilling\agents\openai.yaml'
        $grillWithDocsSkill = Get-BridgeTemplateText 'overrides\patches\grill-with-docs\SKILL.md'
        $grillingSkill | Should -Match 'disable-model-invocation:\s*true'
        $grillingMetadata | Should -Match 'allow_implicit_invocation:\s*true'
        foreach ($member in @($grillWithDocsSkill, $grillingSkill)) {
            $member | Should -Match 'Native-child dispatch invariant'
            $member | Should -Match 'spawn_agent'
            $member | Should -Match 'design-griller'
            $member | Should -Match 'non-empty child task or\s+thread identifier'
            $member | Should -Match 'native_bridge_unavailable'
            $member | Should -Match 'bare `wait`'
        }
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
