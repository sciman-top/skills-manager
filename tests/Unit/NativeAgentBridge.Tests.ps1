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

    It 'lets both managed bridge templates use the active preset route' {
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            $template = Get-BridgeTemplateText ("overrides\resources\native-agent-bridge\{0}.toml" -f $name)
            # Model/effort belongs to the active preset; check the shipped
            # templates directly rather than testing a separate routing oracle.
            $template | Should -Not -Match '(?m)^model\s*=\s*"([^"]*)"$'
            $template | Should -Not -Match '(?m)^model_reasoning_effort\s*=\s*"([^"]*)"$'
            foreach ($forbidden in @('provider', 'model_provider', 'base_url', 'api_key', 'auth', 'secret', 'fallback', 'profile', 'session')) {
                $template | Should -Not -Match ('(?m)^{0}\s*=' -f $forbidden)
            }
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

    It 'ships Claude subagent templates that keep the ownership marker and pin no route or credential' {
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            $template = Get-BridgeTemplateText ("overrides\resources\native-agent-bridge\claude\{0}.md" -f $name)

            $template | Should -Match '(?m)^---$'
            $template | Should -Match '(?m)^# skills-manager-native-agent-bridge: v1$'
            $template | Should -Match ("(?m)^name: {0}$" -f [regex]::Escape($name))
            $template | Should -Match '(?m)^description: '
            $template | Should -Match '(?m)^tools: '
            $template | Should -Not -Match '(?m)^(model|effort|provider|model_provider|base_url|api_key|auth|secret|profile|session|fallback)\s*:'
        }
        (Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\claude\cold-capability-runner.md') | Should -Match '(?m)^tools: Read, Glob, Grep$'
        (Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\claude\design-griller.md') | Should -Match '(?m)^tools: Read, Glob, Grep, WebFetch, WebSearch$'
        # Web reads must not become an exfiltration channel for repository content.
        (Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\claude\design-griller.md') | Should -Match 'Never place repository text'
    }

    It 'recognizes ownership only inside opening frontmatter' {
        Test-ClaudeNativeAgentOwnership "---`nname: user-agent`n---`n# skills-manager-native-agent-bridge: v1`n" | Should -BeFalse
        Test-ClaudeNativeAgentOwnership "# skills-manager-native-agent-bridge: v1`n" | Should -BeFalse
        Test-ClaudeNativeAgentOwnership "---`n# skills-manager-native-agent-bridge: v1`nname: managed`n---`nbody" | Should -BeTrue
    }

    It 'rejects quoted route keys in Claude frontmatter (<Field>)' -ForEach @(@{ Field = '"model": opus' }, @{ Field = "'effort': high" }) {
        $template = Get-BridgeTemplateText 'overrides/resources/native-agent-bridge/claude/design-griller.md'
        $template = $template.Replace('name: design-griller', "name: design-griller`n$Field")
        { Assert-ClaudeNativeAgentTemplateContent $template 'fixture.md' 'design-griller' } | Should -Throw '*unsupported frontmatter*'
    }

    It 'validates the Claude bridge block against ~/.claude/agents only' {
        $config = Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
        $block = $config.skill_projection.claude_native_agent_bridge

        @(Get-NativeAgentBridgeConfigErrors $block '~/.claude/agents' 'claude_native_agent_bridge') | Should -BeNullOrEmpty
        $wrongTarget = [pscustomobject]@{
            enabled = $true; owner = 'skills-manager'; source_root = 'agent/native-agent-bridge/claude'
            target_root = '~/.codex/agents'; receipt_path = 'reports/native-agent-bridge/claude-x.json'; definitions = @('design-griller')
        }
        (@(Get-NativeAgentBridgeConfigErrors $wrongTarget '~/.claude/agents' 'claude_native_agent_bridge') -join ' ') | Should -Match 'claude_native_agent_bridge\.target_root 必须等于 ~/\.claude/agents'
    }

    It 'plans Claude bridge projection without writing the host agents directory during dry run' {
        $config = Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
        $previousRoot = $Root
        $previousAgentDir = $AgentDir
        $previousDryRun = $DryRun
        try {
            $Root = $TestDrive
            $AgentDir = Join-Path $Root 'agent'
            $sourceRoot = Join-Path $AgentDir 'native-agent-bridge\claude'
            New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
            foreach ($name in @('design-griller', 'cold-capability-runner')) {
                Copy-Item -LiteralPath (Join-Path $repoRoot ("overrides\resources\native-agent-bridge\claude\{0}.md" -f $name)) -Destination (Join-Path $sourceRoot ("{0}.md" -f $name))
            }
            $config.skill_projection.claude_native_agent_bridge.receipt_path = 'reports/native-agent-bridge/claude-fixture.json'
            $DryRun = $true
            $result = Sync-ClaudeNativeAgentBridge $config

            $result.enabled | Should -BeTrue
            $result.persisted | Should -BeFalse
            $result.truth_boundary | Should -Be 'planned'
            @($result.changed_names) | Should -Be @('cold-capability-runner', 'design-griller')
            foreach ($definition in @($result.definitions)) {
                $definition.target_path | Should -Match ([regex]::Escape((Join-Path $HOME '.claude\agents')))
                $definition.target_path | Should -Match ('\.md$')
                $definition.source_sha256 | Should -Be (([string](Get-FileHash -LiteralPath $definition.source_path -Algorithm SHA256).Hash).ToLowerInvariant())
            }
        }
        finally {
            $Root = $previousRoot
            $AgentDir = $previousAgentDir
            $DryRun = $previousDryRun
        }
    }

    It 'projects owned Claude templates idempotently and restores them when the receipt fails (<FailReceipt>)' -ForEach @(@{ FailReceipt = $false }, @{ FailReceipt = $true }) {
        $previousRoot = $Root
        $previousAgentDir = $AgentDir
        $previousDryRun = $DryRun
        try {
            $Root = $TestDrive
            $AgentDir = Join-Path $Root 'agent'
            $DryRun = $false
            $config = Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
            $script:claudeBridgeStates = @{}
            $script:claudeBridgeFailReceipt = $FailReceipt
            $targetRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude/agents'
            $originalHashes = @{}
            foreach ($name in @('cold-capability-runner', 'design-griller')) {
                $source = Join-Path $AgentDir ('native-agent-bridge/claude/{0}.md' -f $name)
                $target = Join-Path $targetRoot ($name + '.md')
                $sourceBytes = [IO.File]::ReadAllBytes((Join-Path $repoRoot ('overrides/resources/native-agent-bridge/claude/{0}.md' -f $name)))
                $oldBytes = [Text.Encoding]::UTF8.GetBytes("---`n# skills-manager-native-agent-bridge: v1`nname: $name`n---`nold $name")
                foreach ($entry in @(@{ path = $source; bytes = $sourceBytes }, @{ path = $target; bytes = $oldBytes })) {
                    $script:claudeBridgeStates[[IO.Path]::GetFullPath($entry.path)] = [pscustomobject]@{
                        path = $entry.path; exists = $true; kind = 'file'; bytes = $entry.bytes
                        hash = Get-NativeAgentBridgeBytesSha256 $entry.bytes
                    }
                }
                $originalHashes[$target] = Get-NativeAgentBridgeBytesSha256 $oldBytes
            }
            # All write primitives are mocked: the production target-path checks
            # remain active without touching the user's real ~/.claude directory.
            Mock Assert-NativeSkillProjectionPathHasNoReparseAncestor {}
            Mock Get-NativeAgentBridgeItem {
                param($Path)
                if ($Path.EndsWith('.json')) { return $null }
                return [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::Directory }
            }
            Mock Get-NativeAgentBridgeFileState {
                param($Path)
                $key = [IO.Path]::GetFullPath($Path)
                if ($script:claudeBridgeStates.ContainsKey($key)) { return $script:claudeBridgeStates[$key] }
                return [pscustomobject]@{ path = $key; exists = $false; kind = 'missing'; hash = ''; bytes = [byte[]]@() }
            }
            Mock Write-BytesAtomic {
                param($Path, $Bytes)
                $key = [IO.Path]::GetFullPath($Path)
                $script:claudeBridgeStates[$key] = [pscustomobject]@{
                    path = $key; exists = $true; kind = 'file'; bytes = [byte[]]$Bytes
                    hash = Get-NativeAgentBridgeBytesSha256 $Bytes
                }
            }
            Mock Write-Utf8FileAtomic {
                param($Path, $Content)
                if ($script:claudeBridgeFailReceipt) { throw 'fixture receipt persistence failed' }
                Write-BytesAtomic $Path ([Text.Encoding]::UTF8.GetBytes($Content))
            }
            $promotion = [pscustomobject]@{ required = $true; source_revision = ('a' * 40); promotion_mode = 'verified_clean_commit' }
            if ($FailReceipt) {
                { Sync-ClaudeNativeAgentBridge $config -PromotionContext $promotion -SkipLock } | Should -Throw '*fixture receipt persistence failed*'
                foreach ($target in $originalHashes.Keys) {
                    (Get-NativeAgentBridgeFileState $target).hash | Should -Be $originalHashes[$target]
                }
            }
            else {
                $result = Sync-ClaudeNativeAgentBridge $config -PromotionContext $promotion -SkipLock
                $result.persisted | Should -BeTrue
                $result.truth_boundary | Should -Be 'filesystem_projected'
                @($result.changed_names).Count | Should -Be 2
                $receipt = (Get-NativeAgentBridgeTextFromBytes (Get-NativeAgentBridgeFileState $result.receipt_path).bytes $result.receipt_path) | ConvertFrom-Json
                $receipt.provider_calls | Should -Be 0
                foreach ($definition in $receipt.definitions) { $definition.target_sha256 | Should -Be $definition.source_sha256 }
                @( (Sync-ClaudeNativeAgentBridge $config -PromotionContext $promotion -SkipLock).changed_names ).Count | Should -Be 0
            }
        }
        finally {
            $Root = $previousRoot
            $AgentDir = $previousAgentDir
            $DryRun = $previousDryRun
        }
    }

    It 'treats a <BridgeName>-only host projection as requiring promotion' -ForEach @(@{ BridgeName = 'native_agent_bridge' }, @{ BridgeName = 'claude_native_agent_bridge' }) {
        $previousRoot = $Root
        try {
            $Root = $TestDrive
            $config = [pscustomobject]@{
                targets = @()
                skill_projection = [pscustomobject]@{
                    $BridgeName = [pscustomobject]@{
                        target_root = if ($BridgeName -eq 'native_agent_bridge') { '~/.codex/agents' } else { '~/.claude/agents' }
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

    It 'restores a legacy migration without deleting a pre-existing identical destination' {
        $targetRoot = Join-Path $TestDrive 'codex\agents-preexisting'
        $legacyRoot = Join-Path $targetRoot 'skills-manager-backups'
        $backupRoot = Join-Path $TestDrive 'codex\skills-manager-agent-backups-preexisting'
        New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $legacyBackup = Join-Path $legacyRoot 'design-griller.fixture.toml'
        $destination = Join-Path $backupRoot 'design-griller.fixture.toml'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'overrides\resources\native-agent-bridge\design-griller.toml') -Destination $legacyBackup
        Copy-Item -LiteralPath $legacyBackup -Destination $destination

        $migrations = @(Move-NativeAgentBridgeLegacyBackups $targetRoot $backupRoot)
        $migrations.Count | Should -Be 1
        $migrations[0].destination_preexisted | Should -BeTrue
        Test-Path -LiteralPath $legacyBackup | Should -BeFalse

        Restore-NativeAgentBridgeLegacyMigration $migrations[0]

        Test-Path -LiteralPath $legacyBackup -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $destination -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath $legacyBackup -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    }

    It 'keeps a partial migration ledger across the failure and restores migrated entries' {
        $targetRoot = Join-Path $TestDrive 'codex\agents-partial'
        $legacyRoot = Join-Path $targetRoot 'skills-manager-backups'
        $backupRoot = Join-Path $TestDrive 'codex\skills-manager-agent-backups-partial'
        New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
        $goodLegacy = Join-Path $legacyRoot 'a-good.fixture.toml'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'overrides\resources\native-agent-bridge\design-griller.toml') -Destination $goodLegacy
        # 有 ownership marker 但缺 name 行：迁移循环处理到它时 throw。
        $badLegacy = Join-Path $legacyRoot 'z-bad.fixture.toml'
        Set-ContentUtf8 $badLegacy "# skills-manager-native-agent-bridge: v1`r`ndescription = malformed fixture without a name line"

        $log = New-Object System.Collections.Generic.List[object]
        { Move-NativeAgentBridgeLegacyBackups $targetRoot $backupRoot $log } | Should -Throw '*lacks a role name*'

        # 好文件已迁移且必须仍在账上：否则回滚循环无从把它搬回 legacy 根。
        $log.Count | Should -Be 1
        [string]$log[0].source_path | Should -Be $goodLegacy
        Test-Path -LiteralPath (Join-Path $backupRoot 'a-good.fixture.toml') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $goodLegacy | Should -BeFalse

        Restore-NativeAgentBridgeLegacyMigration $log[0]
        Test-Path -LiteralPath $goodLegacy -PathType Leaf | Should -BeTrue
    }

    It 'keeps grill-me prompt-visible as an explicit core entry that delegates to the native griller' {
        $skill = Get-BridgeTemplateText 'overrides\patches\grill-me\SKILL.md'
        $metadata = Get-BridgeTemplateText 'overrides\patches\grill-me\agents\openai.yaml'

        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $skill | Should -Match 'custom `design-griller`'
        $skill | Should -Match '(?s)Do not perform\s+the interview in the parent task'
        $skill | Should -Match 'do not change a shared skill profile'
        $skill | Should -Match 'no repository edits'
        $skill | Should -Match 'non-empty child\s+identifier'
        $skill | Should -Match 'On Codex that is `spawn_agent`'
        $skill | Should -Match '(?i)on Claude it is the\s+`Agent` tool'
        $skill | Should -Match 'continue the same child with `SendMessage`'
        $skill | Should -Match '(?s)Do not call `wait` until that\s+identifier\s+exists'
        $skill | Should -Match 'bare `wait`'
        $skill | Should -Match 'native_bridge_unavailable'
        $skill | Should -Match 'simulate a child question'
        $skill | Should -Match 'silently fall back'
        $skill | Should -Match 'New-ExecutionAdmissionSuccessor'
        $skill | Should -Match 'parent-side soft guard'

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
        $runner | Should -Match 'full dependency closure'
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
        $runner | Should -Match 'YOU must execute Test-ExecutionAdmissionRevalidation'
        $runner | Should -Match 'parent.s pass=true is not your write-time check'
        $runner | Should -Match 'reason=write_revalidation_required'
        $runner | Should -Match 'Do not rebuild the admission or refresh its snapshots'
        $runner | Should -Match 'single canonical bridge payload generated by New-ExecutionAdmissionBridgePayload'
        $runner | Should -Match 'Export-ExecutionAdmissionHandoff'
        $runner | Should -Match 'complete compact JSON under one bridge_payload field'
        $runner | Should -Match 'validated_skill_name'
        $runner | Should -Match 'If validated_skill_name is absent or does not match'
        $runner | Should -Match 'external_read, unknown side effects'
        $runner | Should -Match 'Never spawn subagents'

        $routerSkill = Get-BridgeTemplateText 'overrides\custom\capability-router\SKILL.md'
        $routerSkill | Should -Match 'New-ExecutionAdmissionBridgePayload'
        $routerSkill | Should -Match 'Do not hand-build parallel child fields or rename `validated_skill_name`'
        $routerSkill | Should -Match '\$validatedSkillName = \$bridgePayload\.validated_skill_name'

        $griller = Get-BridgeTemplateText 'overrides\resources\native-agent-bridge\design-griller.toml'
        $griller | Should -Match 'status=awaiting_user_answer'
        $griller | Should -Match 'never overrides this wait state'
        $griller | Should -Match 'ExecutionAdmission'
        $griller | Should -Match 'ExecutionPlan'
        $griller | Should -Match 'admission_id'
        $griller | Should -Match 'plan_id'
        $griller | Should -Match 'admission_revalidation_required'
        $griller | Should -Match 'human_decision_required'
        $griller | Should -Match 'authorized_ai_delegate_answer'
        $griller | Should -Match 'authorization evidence'
        $griller | Should -Match 'host_specific_live_accepted'
        $griller | Should -Match 'answer SHA-256'
        $griller | Should -Match 'opaque/unreadable payload'
        $griller | Should -Match 'parent is the only semantic scope owner'
        $griller | Should -Match 'successor admission'
    }
}

Describe 'Claude bridge apply path against an in-memory host' {
    # Complements the merged mock-based projection test above. Every host-side read and
    # write goes through the mocks below, so nothing here can touch the real ~/.claude/agents.
    BeforeAll {
        $script:repoRootForApply = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

        function New-BridgeFixtureConfig {
            $config = Get-ContentUtf8 (Join-Path $script:repoRootForApply 'skills.json') | ConvertFrom-Json
            $config.skill_projection.claude_native_agent_bridge.receipt_path = 'reports/native-agent-bridge/claude-apply-test.json'
            return $config
        }

        function New-BridgePromotionContext {
            return [pscustomobject]@{ required = $true; source_revision = 'test'; promotion_mode = 'test' }
        }

        function New-BridgeOwnedBytes([string]$Name, [string]$Body) {
            return [Text.Encoding]::UTF8.GetBytes(("---`n# skills-manager-native-agent-bridge: v1`nname: {0}`ndescription: test`ntools: Read`n---`n{1}`n" -f $Name, $Body))
        }

        function Get-BridgeHostKey([string]$Name) {
            return [IO.Path]::GetFullPath((Join-Path $global:BridgeHomeTargetRoot ("{0}.md" -f $Name)))
        }

        function Set-BridgeHostFile([string]$Name, [byte[]]$Bytes) {
            $global:BridgeHostStore[(Get-BridgeHostKey $Name)] = $Bytes
        }

        function Get-BridgeHostHash([string]$Name) {
            return Get-NativeAgentBridgeBytesSha256 ([byte[]]$global:BridgeHostStore[(Get-BridgeHostKey $Name)])
        }

        function Invoke-BridgeApply($PromotionContext = (New-BridgePromotionContext)) {
            try {
                return [pscustomobject]@{ result = (Sync-ClaudeNativeAgentBridge (New-BridgeFixtureConfig) $PromotionContext -SkipLock); error = '' }
            }
            catch {
                return [pscustomobject]@{ result = $null; error = [string]$_.Exception.Message }
            }
        }
    }

    BeforeEach {
        $script:previousRoot = $Root
        $script:previousAgentDir = $AgentDir
        $script:previousDryRun = $DryRun
        $Root = $TestDrive
        $AgentDir = Join-Path $TestDrive 'agent'
        $DryRun = $false

        $sourceRoot = Join-Path $AgentDir 'native-agent-bridge\claude'
        New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'reports\native-agent-bridge') -Force | Out-Null
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            Copy-Item -LiteralPath (Join-Path $script:repoRootForApply ("overrides\resources\native-agent-bridge\claude\{0}.md" -f $name)) -Destination (Join-Path $sourceRoot ("{0}.md" -f $name)) -Force
        }

        $global:BridgeHostStore = @{}
        $global:BridgeHostWrites = 0
        $global:BridgeCorruptPath = $null
        $global:BridgeTamperReceipt = $false
        $global:BridgeTestRoot = [IO.Path]::GetFullPath($TestDrive).TrimEnd('\')
        $global:BridgeHomeTargetRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\agents')).TrimEnd('\')

        Mock Get-NativeAgentBridgeFileState {
            $full = [IO.Path]::GetFullPath([string]$Path)
            if ($global:BridgeHostStore.ContainsKey($full)) {
                $bytes = [byte[]]$global:BridgeHostStore[$full]
            }
            elseif ($full.StartsWith($global:BridgeTestRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full -PathType Leaf)) {
                $bytes = [IO.File]::ReadAllBytes($full)
            }
            else {
                return [pscustomobject][ordered]@{ path = $full; exists = $false; kind = 'missing'; hash = ''; bytes = [byte[]]@() }
            }
            return [pscustomobject][ordered]@{ path = $full; exists = $true; kind = 'file'; hash = (Get-NativeAgentBridgeBytesSha256 $bytes); bytes = $bytes }
        }

        Mock Write-BytesAtomic {
            $full = [IO.Path]::GetFullPath([string]$Path)
            $global:BridgeHostWrites++
            $content = [byte[]]$Bytes
            if ($global:BridgeCorruptPath -and $full -eq $global:BridgeCorruptPath) {
                $global:BridgeCorruptPath = $null
                $content = [Text.Encoding]::UTF8.GetBytes('corrupted write landed')
            }
            if ($global:BridgeTamperReceipt -and $full.EndsWith('claude-apply-test.json', [StringComparison]::OrdinalIgnoreCase)) {
                $global:BridgeTamperReceipt = $false
                $content = [Text.Encoding]::UTF8.GetBytes(([Text.Encoding]::UTF8.GetString($content) -replace '"applied"', '"tampered"'))
            }
            $global:BridgeHostStore[$full] = $content
        }

        Mock Get-NativeAgentBridgeItem {
            $full = [IO.Path]::GetFullPath([string]$Path).TrimEnd('\')
            if ($full.Equals($global:BridgeHomeTargetRoot, [StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ FullName = $full; PSIsContainer = $true; Attributes = [IO.FileAttributes]::Directory }
            }
            if ($full.StartsWith($global:BridgeTestRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                return (Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue)
            }
            return $null
        }

        Mock New-Item {
            $full = [IO.Path]::GetFullPath([string]$Path)
            if ($full.StartsWith($global:BridgeTestRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                [IO.Directory]::CreateDirectory($full) | Out-Null
            }
        }

        Mock Assert-NativeSkillProjectionPathHasNoReparseAncestor {}
    }

    AfterEach {
        $Root = $script:previousRoot
        $AgentDir = $script:previousAgentDir
        $DryRun = $script:previousDryRun
    }

    It 'writes both files, verifies them, and records an applied receipt' {
        Set-BridgeHostFile 'design-griller' (New-BridgeOwnedBytes 'design-griller' 'old')
        Set-BridgeHostFile 'cold-capability-runner' (New-BridgeOwnedBytes 'cold-capability-runner' 'old')

        $outcome = Invoke-BridgeApply
        $outcome.error | Should -BeNullOrEmpty
        $outcome.result.persisted | Should -BeTrue
        @($outcome.result.changed_names) | Should -Be @('cold-capability-runner', 'design-griller')
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            $expected = ([string](Get-FileHash -LiteralPath (Join-Path $Root ("agent\native-agent-bridge\claude\{0}.md" -f $name)) -Algorithm SHA256).Hash).ToLowerInvariant()
            Get-BridgeHostHash $name | Should -Be $expected
        }
        $receipt = [Text.Encoding]::UTF8.GetString($global:BridgeHostStore[[IO.Path]::GetFullPath((Join-Path $Root 'reports\native-agent-bridge\claude-apply-test.json'))]) | ConvertFrom-Json
        $receipt.status | Should -Be 'applied'
    }

    It 'treats byte-identical owned files as unchanged and writes only the receipt' {
        $sourceRoot = Join-Path $AgentDir 'native-agent-bridge\claude'
        foreach ($name in @('design-griller', 'cold-capability-runner')) {
            Set-BridgeHostFile $name ([IO.File]::ReadAllBytes((Join-Path $sourceRoot ("{0}.md" -f $name))))
        }

        $outcome = Invoke-BridgeApply
        $outcome.error | Should -BeNullOrEmpty
        @($outcome.result.changed_names).Count | Should -Be 0
        $global:BridgeHostWrites | Should -Be 1
    }

    It 'refuses to overwrite a file skills-manager does not own and restores earlier writes' {
        Set-BridgeHostFile 'cold-capability-runner' (New-BridgeOwnedBytes 'cold-capability-runner' 'old')
        $handWritten = [Text.Encoding]::UTF8.GetBytes("---`nname: design-griller`ndescription: hand written`ntools: Read`n---`nmine`n")
        Set-BridgeHostFile 'design-griller' $handWritten

        $outcome = Invoke-BridgeApply
        $outcome.error | Should -Match 'not owned by skills-manager'
        # cold-capability-runner was written first and must be restored to its owned content.
        Get-BridgeHostHash 'cold-capability-runner' | Should -Be (Get-NativeAgentBridgeBytesSha256 (New-BridgeOwnedBytes 'cold-capability-runner' 'old'))
        Get-BridgeHostHash 'design-griller' | Should -Be (Get-NativeAgentBridgeBytesSha256 $handWritten)
    }

    It 'rolls back a landed write that fails verification instead of reporting rollback incomplete' {
        Set-BridgeHostFile 'design-griller' (New-BridgeOwnedBytes 'design-griller' 'old')
        Set-BridgeHostFile 'cold-capability-runner' (New-BridgeOwnedBytes 'cold-capability-runner' 'old')
        $global:BridgeCorruptPath = Get-BridgeHostKey 'design-griller'

        $outcome = Invoke-BridgeApply
        $outcome.error | Should -Match 'claude agent target verification failed'
        $outcome.error | Should -Not -Match 'rollback incomplete'
        Get-BridgeHostHash 'design-griller' | Should -Be (Get-NativeAgentBridgeBytesSha256 (New-BridgeOwnedBytes 'design-griller' 'old'))
        Get-BridgeHostHash 'cold-capability-runner' | Should -Be (Get-NativeAgentBridgeBytesSha256 (New-BridgeOwnedBytes 'cold-capability-runner' 'old'))
    }

    It 'replaces an applied receipt with rolled_back when receipt verification fails' {
        Set-BridgeHostFile 'design-griller' (New-BridgeOwnedBytes 'design-griller' 'old')
        Set-BridgeHostFile 'cold-capability-runner' (New-BridgeOwnedBytes 'cold-capability-runner' 'old')
        $global:BridgeTamperReceipt = $true

        $outcome = Invoke-BridgeApply
        $outcome.error | Should -Match 'receipt verification failed'
        $receiptKey = [IO.Path]::GetFullPath((Join-Path $Root 'reports\native-agent-bridge\claude-apply-test.json'))
        $recorded = [Text.Encoding]::UTF8.GetString($global:BridgeHostStore[$receiptKey]) | ConvertFrom-Json
        $recorded.status | Should -Be 'rolled_back'
        Get-BridgeHostHash 'design-griller' | Should -Be (Get-NativeAgentBridgeBytesSha256 (New-BridgeOwnedBytes 'design-griller' 'old'))
    }

    It 'refuses a host write without a verified promotion context and writes nothing' {
        Set-BridgeHostFile 'design-griller' (New-BridgeOwnedBytes 'design-griller' 'old')
        Set-BridgeHostFile 'cold-capability-runner' (New-BridgeOwnedBytes 'cold-capability-runner' 'old')

        $outcome = Invoke-BridgeApply -PromotionContext $null
        $outcome.error | Should -Match 'verified host projection promotion context'
        $global:BridgeHostWrites | Should -Be 0
    }
}
