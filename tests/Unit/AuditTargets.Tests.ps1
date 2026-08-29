BeforeAll {
    # Dot-source the main script to load functions
    . $PSScriptRoot\..\..\skills.ps1
    $script:Root = $Root
    $script:CfgPath = $CfgPath
    $script:LogPath = $LogPath
    $script:VendorDir = $VendorDir
    $script:AgentDir = $AgentDir
    $script:OverridesDir = $OverridesDir
    $script:ManualDir = $ManualDir
    $script:ImportDir = $ImportDir
    $script:DryRun = $DryRun

    function Get-FunctionBody {
        param(
            [string]$Text,
            [string]$FunctionName
        )

        $start = $Text.IndexOf("function $FunctionName {")
        if ($start -lt 0) {
            throw "Failed to locate function $FunctionName"
        }

        $cursor = $Text.IndexOf("{", $start)
        if ($cursor -lt 0) {
            throw "Failed to locate opening brace for $FunctionName"
        }

        $depth = 0
        for ($i = $cursor; $i -lt $Text.Length; $i++) {
            $ch = $Text[$i]
            if ($ch -eq "{") {
                $depth++
            }
            elseif ($ch -eq "}") {
                $depth--
                if ($depth -eq 0) {
                    return $Text.Substring($start, $i - $start + 1)
                }
            }
        }

        throw "Failed to extract function body for $FunctionName"
    }

    function New-AuditValidatedWorkflowReceiptFixture([string]$RecommendationsPath) {
        $resolved = [IO.Path]::GetFullPath($RecommendationsPath)
        $state = Get-AuditWorkflowInputState $resolved
        $receipt = [pscustomobject][ordered]@{
            schema_version = 1
            workflow = 'recommendations_validate_dry_run'
            generated_at = [datetimeoffset]::UtcNow.ToString('o')
            success = $true
            persisted = $false
            recommendations_path = $resolved
            recommendations_sha256 = Get-FileContentHash $resolved
            stages = [pscustomobject]@{
                recommendations_validation = [pscustomobject]@{ status = 'passed' }
                preflight = [pscustomobject]@{ status = 'passed' }
                dry_run = [pscustomobject]@{ status = 'passed' }
                input_stability = [pscustomobject]@{ status = 'passed' }
            }
            input_stability = [pscustomobject]@{ matched = $true; after_dry_run = $state }
        }
        Write-AuditReceiptSection $resolved "workflow" $receipt | Out-Null
    }

    function New-TestAuditSnapshot {
        param(
            [string]$Path,
            [string]$RunId = "r-test",
            $InstalledState = $null,
            [object[]]$Scans = @(),
            $SourceStrategy = $null,
            $DecisionInsights = $null,
            [string]$PromptVersion = (Get-AuditPromptContractVersion)
        )
        if ($null -eq $InstalledState) {
            $live = Get-AuditLiveInstalledState
            $InstalledState = [pscustomobject]@{
                snapshot_kind = "audit_input"; captured_at = (Get-Date).ToString("o")
                live_fingerprint = [string]$live.fingerprint; live_external_skill_fingerprint = [string]$live.external_skill_fingerprint; live_mcp_fingerprint = [string]$live.mcp_fingerprint
                skills = @(); external_skills = @(); mcp_servers = @(); host_projection = $null
            }
        }
        if ($null -eq $SourceStrategy) { $SourceStrategy = [pscustomobject]@{ mode="target-repo"; sources=@(); evidence_policy=$null; decision_quality_policy=$null } }
        if ($null -eq $DecisionInsights) { $DecisionInsights = [pscustomobject]@{ derivation="target_scans_only"; keywords=[pscustomobject]@{ target_profile=@("audit"); target_repo=@("repo"); installed_state=@("skills") } } }
        $profile = [pscustomobject]@{
            raw_text="audit workflow"; summary="audit workflow"; last_structured_at=(Get-Date).ToString("o"); structured_by="test"
            structured=[pscustomobject]@{ primary_work_types=@("audit"); preferred_agents=@(); tech_stack=@("powershell"); common_tasks=@("review"); constraints=@("safe"); avoidances=@(); decision_preferences=@("evidence-first") }
        }
        if (@($Scans).Count -eq 0) { $Scans = @([pscustomobject]@{ target=[pscustomobject]@{ name="demo" }; detected=[pscustomobject]@{ languages=@("powershell"); package_managers=@(); frameworks=@(); build_commands=@(); test_commands=@(); capabilities=@(); agent_rule_files=@(); notable_files=@() }; risks=@() }) }
        $targetProfile = [pscustomobject]@{ schema_version=1; derivation="target_scans_only"; summary="test scan profile"; target_names=@("demo"); languages=@("powershell"); package_managers=@(); frameworks=@(); build_commands=@(); test_commands=@(); capabilities=@(); agent_rule_files=@(); notable_files=@() }
        Write-AuditJsonFile $Path ([pscustomobject]@{ schema_version=2; run_id=$RunId; mode="target-repo"; prompt_contract_version=$PromptVersion; target_profile=$targetProfile; installed_state=$InstalledState; target_scans=@($Scans); source_strategy=$SourceStrategy; decision_insights=$DecisionInsights })
    }

}
Describe "Audit Targets" {
    BeforeEach {
        Mock Get-AuditLiveInstalledState {
            [pscustomobject]([ordered]@{
                source_of_truth = 'test_fixture'
                captured_at = '2026-08-03T00:00:00Z'
                skill_count = 0
                fingerprint = 'unit-empty-skills'
                configured_supply_skill_count = 0
                configured_supply_fingerprint = 'unit-empty-configured-supply'
                configured_supply_skills = @()
                profile_selected_skills = @()
                profile_selection = $null
                profile_selection_status = 'not_observed'
                profile_selection_unresolved_names = @()
                external_skill_count = 0
                external_skill_fingerprint = 'unit-empty-external-skills'
                mcp_server_count = 0
                mcp_fingerprint = 'unit-empty-mcp'
                invocation_evidence = [pscustomobject]@{ state = 'not_observed'; scope = 'test'; evidence = 'fixture' }
            })
        }
    }

    Context "Target config" {
        It "Creates default audit target config without overwriting existing file" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-init"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                $path = Get-AuditTargetsConfigPath

                $created = Initialize-AuditTargetsConfig
                $created | Should -Be $true
                (Test-Path $path) | Should -Be $true

                $raw = Get-Content $path -Raw
                $raw | Should -Match '"version"'
                $raw | Should -Match '"targets"'

                $createdAgain = Initialize-AuditTargetsConfig
                $createdAgain | Should -Be $false
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Creates audit-targets config without user profile requirements" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-v2-init"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null

                Initialize-AuditTargetsConfig | Out-Null
                $cfg = Load-AuditTargetsConfig

                $cfg.version | Should -Be 3
                $cfg.PSObject.Properties.Match("user_profile").Count | Should -Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Migrates version 1 audit config to version 3 without user_profile" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-v1-migrate"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Set-ContentUtf8 (Join-Path $script:Root "audit-targets.json") '{"version":1,"path_base":"skills_manager_root","targets":[]}'

                $cfg = Load-AuditTargetsConfig

                $cfg.version | Should -Be 3
                $cfg.PSObject.Properties.Match("user_profile").Count | Should -Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Adds target with normalized name and preserved input path" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-add"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null

                $cfg = Add-AuditTargetConfigEntry " My Repo " "..\my-repo" @("typescript", "frontend") "demo notes"

                @($cfg.targets).Count | Should -Be 1
                $cfg.targets[0].name | Should -Be "my-repo"
                $cfg.targets[0].path | Should -Be "..\my-repo"
                $cfg.targets[0].enabled | Should -Be $true
                $cfg.targets[0].tags[0] | Should -Be "typescript"
                $cfg.targets[0].notes | Should -Be "demo notes"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Updates an existing target without changing its normalized name" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-update"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Add-AuditTargetConfigEntry "demo" "..\demo" @("old") "old notes" | Out-Null

                $cfg = Update-AuditTargetConfigEntry "demo" "..\demo-v2" @("new") "new notes"

                @($cfg.targets).Count | Should -Be 1
                $cfg.targets[0].name | Should -Be "demo"
                $cfg.targets[0].path | Should -Be "..\demo-v2"
                $cfg.targets[0].tags[0] | Should -Be "new"
                $cfg.targets[0].notes | Should -Be "new notes"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Removes an existing target by name" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-remove"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Add-AuditTargetConfigEntry "demo" "..\demo" | Out-Null
                Add-AuditTargetConfigEntry "demo-2" "..\demo-2" | Out-Null

                $cfg = Remove-AuditTargetConfigEntry "demo"

                @($cfg.targets).Count | Should -Be 1
                $cfg.targets[0].name | Should -Be "demo-2"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Resolves relative, absolute, home, and environment paths" {
            $oldRoot = $script:Root
            $oldEnv = $env:SKILLS_AUDIT_TEST_ROOT
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-paths"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                $env:SKILLS_AUDIT_TEST_ROOT = Join-Path $TestDrive "env-root"

                (Resolve-AuditTargetPath "..\target").StartsWith((Resolve-Path (Join-Path $script:Root "..")).Path) | Should -Be $true
                Resolve-AuditTargetPath $script:Root | Should -Be ([System.IO.Path]::GetFullPath($script:Root))
                (Resolve-AuditTargetPath "~").Length -gt 0 | Should -Be $true
                Resolve-AuditTargetPath "%SKILLS_AUDIT_TEST_ROOT%\repo" | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $env:SKILLS_AUDIT_TEST_ROOT "repo")))
            }
            finally {
                $script:Root = $oldRoot
                $env:SKILLS_AUDIT_TEST_ROOT = $oldEnv
            }
        }
    }

    Context "Command parsing" {
        It "Parses init/add/update/remove/list/scan/apply subcommands" {
            (Parse-AuditTargetsArgs @("init")).action | Should -Be "init"

            $add = Parse-AuditTargetsArgs @("add", "demo", "..\demo")
            $add.action | Should -Be "add"
            $add.name | Should -Be "demo"
            $add.path | Should -Be "..\demo"

            $update = Parse-AuditTargetsArgs @("update", "demo", "..\demo-v2")
            $update.action | Should -Be "update"
            $update.name | Should -Be "demo"
            $update.path | Should -Be "..\demo-v2"

            $remove = Parse-AuditTargetsArgs @("remove", "demo")
            $remove.action | Should -Be "remove"
            $remove.name | Should -Be "demo"

            (Parse-AuditTargetsArgs @("list")).action | Should -Be "list"
            (Parse-AuditTargetsArgs @("scan", "--target", "demo")).target | Should -Be "demo"
            $scanWithQuery = Parse-AuditTargetsArgs @("scan", "--target", "demo", "--query", "import scanned exams")
            $scanWithQuery.query | Should -Be "import scanned exams"

            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes")
            $apply.action | Should -Be "apply"
            $apply.recommendations | Should -Be "r.json"
            $apply.apply | Should -Be $true
            $apply.yes | Should -Be $true
            { Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--allow-stale-snapshot") } | Should -Throw "未知参数*"
            { Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--stale-ack", "legacy") } | Should -Throw "未知参数*"

            $status = Parse-AuditTargetsArgs @("status")
            $status.action | Should -Be "status"

            $preflight = Parse-AuditTargetsArgs @("preflight", "--run-id", "20260422-010101-001")
            $preflight.action | Should -Be "preflight"
            $preflight.run_id | Should -Be "20260422-010101-001"

            $validateDryRun = Parse-AuditTargetsArgs @("validate-dry-run", "--recommendations", "r.json", "--dry-run-ack", "我知道未落盘")
            $validateDryRun.action | Should -Be "validate_dry_run"
            $validateDryRun.recommendations | Should -Be "r.json"
            $validateDryRun.dry_run_ack | Should -Be "我知道未落盘"
        }

        It "Parses apply selection indexes for add and remove lists" {
            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes", "--add-indexes", "1,3", "--remove-indexes", "2", "--mcp-add-indexes", "1", "--mcp-remove-indexes", "2", "--dry-run-ack", "我知道未落盘")
            $apply.add_selection | Should -Be "1,3"
            $apply.remove_selection | Should -Be "2"
            $apply.mcp_add_selection | Should -Be "1"
            $apply.mcp_remove_selection | Should -Be "2"
            $apply.dry_run_ack | Should -Be "我知道未落盘"
        }

        It "Parses apply-flow subcommand aliases" {
            $flow = Parse-AuditTargetsArgs @("apply-flow", "--recommendations", "r.json")
            $flow.action | Should -Be "apply_flow"
            $flow.recommendations | Should -Be "r.json"

            $flowCn = Parse-AuditTargetsArgs @("应用确认", "--recommendations", "r.json")
            $flowCn.action | Should -Be "apply_flow"
            $flowCn.recommendations | Should -Be "r.json"
        }

        It "Accepts Chinese subcommands" {
            (Parse-AuditTargetsArgs @("初始化")).action | Should -Be "init"
            (Parse-AuditTargetsArgs @("添加", "demo", "..\demo")).action | Should -Be "add"
            (Parse-AuditTargetsArgs @("修改", "demo", "..\demo-v2")).action | Should -Be "update"
            (Parse-AuditTargetsArgs @("删除", "demo")).action | Should -Be "remove"
            (Parse-AuditTargetsArgs @("列表")).action | Should -Be "list"
            (Parse-AuditTargetsArgs @("列出")).action | Should -Be "list"
            (Parse-AuditTargetsArgs @("目标列表")).action | Should -Be "list"
            (Parse-AuditTargetsArgs @("扫描")).action | Should -Be "scan"
            (Parse-AuditTargetsArgs @("状态")).action | Should -Be "status"
            (Parse-AuditTargetsArgs @("预检", "--run-id", "demo-run")).action | Should -Be "preflight"
            (Parse-AuditTargetsArgs @("校验预演", "--recommendations", "r.json")).action | Should -Be "validate_dry_run"
            (Parse-AuditTargetsArgs @("预演", "--recommendations", "r.json")).action | Should -Be "validate_dry_run"
            (Parse-AuditTargetsArgs @("应用确认", "--recommendations", "r.json")).action | Should -Be "apply_flow"
            (Parse-AuditTargetsArgs @("应用", "--recommendations", "r.json")).action | Should -Be "apply"
        }

        It "Auto-resolves the run-id placeholder for --run-id and --recommendations" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-placeholder-parse"
                $auditRoot = Join-Path $script:Root "reports\skill-audit"
                $runOld = Join-Path $auditRoot "r-old"
                $runNew = Join-Path $auditRoot "r-new"
                New-Item -ItemType Directory -Path $runOld -Force | Out-Null
                New-Item -ItemType Directory -Path $runNew -Force | Out-Null
                $live = Get-AuditLiveInstalledState
                $promptVersion = Get-AuditPromptContractVersion
                Set-ContentUtf8 (Join-Path $runOld "recommendations.json") '{}'
                Set-ContentUtf8 (Join-Path $runNew "recommendations.json") '{}'
                New-TestAuditSnapshot (Join-Path $runOld "snapshot.json") "r-old"
                New-TestAuditSnapshot (Join-Path $runNew "snapshot.json") "r-new"
                foreach($dir in @($runOld,$runNew)){Set-ContentUtf8 (Join-Path $dir "receipt.json") '{"schema_version":1,"persisted":false,"truth_boundary":"test"}'}
                (Get-Item $runOld).LastWriteTimeUtc = [datetime]"2026-01-01T00:00:00Z"
                (Get-Item $runNew).LastWriteTimeUtc = [datetime]"2026-01-02T00:00:00Z"

                $preflight = Parse-AuditTargetsArgs @("preflight", "--run-id", "<run-id>")
                $preflight.run_id | Should -Be "r-new"

                $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "reports/skill-audit/<run-id>/recommendations.json")
                $apply.recommendations | Should -Be "reports/skill-audit/r-new/recommendations.json"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Prefers latest fresh run over newer stale run when resolving the run-id placeholder" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-placeholder-fresh-first"
                $auditRoot = Join-Path $script:Root "reports\skill-audit"
                $runFresh = Join-Path $auditRoot "r-fresh"
                $runStale = Join-Path $auditRoot "r-stale"
                New-Item -ItemType Directory -Path $runFresh -Force | Out-Null
                New-Item -ItemType Directory -Path $runStale -Force | Out-Null

                $live = Get-AuditLiveInstalledState
                $promptVersion = Get-AuditPromptContractVersion

                Set-ContentUtf8 (Join-Path $runFresh "recommendations.json") '{}'
                New-TestAuditSnapshot (Join-Path $runFresh "snapshot.json") "r-fresh"

                Set-ContentUtf8 (Join-Path $runStale "recommendations.json") '{}'
                $staleState=[pscustomobject]@{snapshot_kind="audit_input";captured_at=(Get-Date).ToString("o");live_fingerprint="deadbeef";live_external_skill_fingerprint="unit-empty-external-skills";live_mcp_fingerprint="deadbeef";skills=@();external_skills=@();mcp_servers=@();host_projection=$null}
                New-TestAuditSnapshot (Join-Path $runStale "snapshot.json") "r-stale" $staleState

                (Get-Item $runFresh).LastWriteTimeUtc = [datetime]"2026-01-01T00:00:00Z"
                (Get-Item $runStale).LastWriteTimeUtc = [datetime]"2026-01-02T00:00:00Z"

                $resolved = Resolve-AuditPathRunIdPlaceholder "reports/skill-audit/<run-id>/recommendations.json" "--recommendations" @("recommendations.json")
                $resolved | Should -Be "reports/skill-audit/r-fresh/recommendations.json"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Fails placeholder resolution when only stale runs are found" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-placeholder-only-stale"
                $auditRoot = Join-Path $script:Root "reports\skill-audit"
                $runStale = Join-Path $auditRoot "r-stale"
                New-Item -ItemType Directory -Path $runStale -Force | Out-Null

                $promptVersion = Get-AuditPromptContractVersion
                Set-ContentUtf8 (Join-Path $runStale "recommendations.json") '{}'
                $staleState=[pscustomobject]@{snapshot_kind="audit_input";captured_at=(Get-Date).ToString("o");live_fingerprint="deadbeef";live_external_skill_fingerprint="unit-empty-external-skills";live_mcp_fingerprint="deadbeef";skills=@();external_skills=@();mcp_servers=@();host_projection=$null}
                New-TestAuditSnapshot (Join-Path $runStale "snapshot.json") "r-stale" $staleState

                $thrown = $false
                try {
                    Resolve-AuditPathRunIdPlaceholder "reports/skill-audit/<run-id>/recommendations.json" "--recommendations" @("recommendations.json") | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should -Match "未找到可用 run"
                    $_.Exception.Message | Should -Match "stale run-id"
                    $_.Exception.Message | Should -Match "先执行 .*审查目标 扫描"
                }
                $thrown | Should -Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Shows scan hint when placeholder cannot find required run files" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-placeholder-missing-required"
                $auditRoot = Join-Path $script:Root "reports\skill-audit"
                $run = Join-Path $auditRoot "r-missing-meta"
                New-Item -ItemType Directory -Path $run -Force | Out-Null
                Set-ContentUtf8 (Join-Path $run "recommendations.json") '{}'
                New-TestAuditSnapshot (Join-Path $run "snapshot.json") "r-missing-receipt"

                $thrown = $false
                try {
                    Resolve-AuditPathRunIdPlaceholder "reports/skill-audit/<run-id>/recommendations.json" "--recommendations" @("snapshot.json", "recommendations.json", "receipt.json") | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should -Match "先执行 .*审查目标 扫描"
                    $_.Exception.Message | Should -Match "r-missing-meta"
                }
                $thrown | Should -Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }
    }

    Context "Repository scan" {
        It "Saves raw user profile text and clears stale structured fields" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-set"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                $cfg = Load-AuditTargetsConfig
                $cfg.user_profile.summary = "stale"
                $cfg.user_profile.structured.primary_work_types = @("old")
                Save-AuditTargetsConfig $cfg

                Set-AuditUserProfileRawText "I maintain multi-agent automation and repo governance workflows."
                $saved = Load-AuditTargetsConfig

                $saved.user_profile.raw_text | Should -Match "multi-agent automation"
                $saved.user_profile.summary | Should -Be ""
                $saved.user_profile.structured.primary_work_types.Count | Should -Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Imports structured profile JSON from file" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-structure"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                $profilePath = Join-Path $TestDrive "profile.json"
                Set-ContentUtf8 $profilePath '{"summary":"repo-governance focus","structured":{"primary_work_types":["repo-governance"],"preferred_agents":["codex"],"tech_stack":["powershell"],"common_tasks":["skill review"],"constraints":["windows-first"],"avoidances":["opaque automation"],"decision_preferences":["evidence-first"]},"structured_by":"outer-ai"}'

                Import-AuditUserProfileStructured $profilePath
                $saved = Load-AuditTargetsConfig

                $saved.user_profile.summary | Should -Be "repo-governance focus"
                $saved.user_profile.structured.primary_work_types[0] | Should -Be "repo-governance"
                $saved.user_profile.structured_by | Should -Be "outer-ai"

                $snapshotPath = Join-Path $script:Root "reports\skill-audit\user-profile.json"
                (Test-Path -LiteralPath $snapshotPath) | Should -Be $true
                $snapshot = Get-ContentUtf8 $snapshotPath | ConvertFrom-Json
                $snapshot.summary | Should -Be "repo-governance focus"
                $snapshot.structured.primary_work_types[0] | Should -Be "repo-governance"

                $summaryPath = Join-Path $script:Root "reports\skill-audit\user-profile.json.summary"
                (Test-Path -LiteralPath $summaryPath) | Should -Be $true
                (Get-ContentUtf8 $summaryPath) | Should -Be "repo-governance focus"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Normalizes scalar structured fields into arrays during import" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-normalize"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                $profilePath = Join-Path $TestDrive "profile-normalize.json"
                Set-ContentUtf8 $profilePath '{"summary":"normalized","structured":{"primary_work_types":"repo-governance","preferred_agents":"codex","tech_stack":"powershell","common_tasks":"skill review","constraints":"windows-first","avoidances":"opaque automation","decision_preferences":"evidence-first"},"structured_by":"outer-ai"}'

                Import-AuditUserProfileStructured $profilePath
                $saved = Load-AuditTargetsConfig

                @($saved.user_profile.structured.primary_work_types).Count | Should -Be 1
                $saved.user_profile.structured.primary_work_types[0] | Should -Be "repo-governance"
                @($saved.user_profile.structured.preferred_agents).Count | Should -Be 1
                $saved.user_profile.structured.preferred_agents[0] | Should -Be "codex"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Rejects structured profile when structured is not an object" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-invalid-structured"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                $profilePath = Join-Path $TestDrive "profile-invalid-structured.json"
                Set-ContentUtf8 $profilePath '{"summary":"invalid","structured":"not-object","structured_by":"outer-ai"}'

                $thrown = $false
                try {
                    Import-AuditUserProfileStructured $profilePath | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should -Match "profile.structured"
                }
                $thrown | Should -Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Imports structured profile from default path when profile is omitted" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-default-import"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                $defaultPath = Get-AuditStructuredProfileDefaultPath
                Write-AuditJsonFile $defaultPath ([pscustomobject]@{
                    summary = "default-path profile"
                    structured = [pscustomobject]@{
                        primary_work_types = @("repo-governance")
                        preferred_agents = @("codex")
                        tech_stack = @("powershell")
                        common_tasks = @("skill review")
                        constraints = @("windows-first")
                        avoidances = @("opaque automation")
                        decision_preferences = @("evidence-first")
                    }
                    structured_by = "outer-ai"
                })

                Import-AuditUserProfileStructured ""
                $saved = Load-AuditTargetsConfig

                $saved.user_profile.summary | Should -Be "default-path profile"
                $saved.user_profile.structured.primary_work_types[0] | Should -Be "repo-governance"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Creates structured profile draft at default path when no file exists" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-default-draft"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                Invoke-AuditStructuredProfileFlow ""
                $draftPath = Get-AuditStructuredProfileDefaultPath
                $draft = Get-Content -LiteralPath $draftPath -Raw | ConvertFrom-Json

                $draft.raw_text | Should -Be "I maintain repo governance workflows."
                $draft.structured_by | Should -Be "outer-ai"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks scan when user_profile.raw_text is missing" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-required"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Add-AuditTargetConfigEntry "demo" "..\\demo" | Out-Null

                $thrown = $false
                try {
                    Invoke-AuditTargetsScan -Target "demo" | Out-Null
                }
                catch {
                    $thrown = $true
                }
                $thrown | Should -Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Auto-fills empty summary during profile precheck before scan" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-precheck-autofill-summary"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows and need deterministic audit bundles."

                $repo = Join-Path $script:Root "demo-repo"
                New-Item -ItemType Directory -Path $repo -Force | Out-Null
                Add-AuditTargetConfigEntry "demo" ".\demo-repo" | Out-Null

                Mock Get-InstalledSkillFacts { @() }

                Invoke-AuditTargetsScan -Target "demo" | Out-Null
                $saved = Load-AuditTargetsConfig
                $saved.user_profile.summary | Should -Not -Be ""
                $saved.user_profile.structured_by | Should -Be "outer-ai"
                ([string]$saved.user_profile.last_structured_at).Length -gt 0 | Should -Be $true

                $draftPath = Get-AuditStructuredProfileDefaultPath
                (Test-Path -LiteralPath $draftPath) | Should -Be $true
                $draft = Get-ContentUtf8 $draftPath | ConvertFrom-Json
                $draft.summary | Should -Not -Be ""
                $draft.structured_by | Should -Be "outer-ai"
                ([string]$draft.last_structured_at).Length -gt 0 | Should -Be $true

                $summaryPath = Join-Path $script:Root "reports\skill-audit\user-profile.json.summary"
                (Test-Path -LiteralPath $summaryPath) | Should -Be $true
                (Get-ContentUtf8 $summaryPath) | Should -Not -Be ""
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Fails scan when installed skill facts cannot be collected" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-scan-installed-facts-fail"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                $repo = Join-Path $script:Root "demo-repo"
                New-Item -ItemType Directory -Path $repo -Force | Out-Null
                Add-AuditTargetConfigEntry "demo" ".\demo-repo" | Out-Null

                Mock Get-InstalledSkillFacts { throw "simulated installed facts failure" }

                $thrown = $false
                try {
                    Invoke-AuditTargetsScan -Target "demo" | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should -Match "安装状态快照"
                }
                $thrown | Should -Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Generates a profile-only discovery bundle with exactly three files" -Skip {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-discover-skills"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                $cfg = Load-AuditTargetsConfig
                $cfg.user_profile.raw_text = "I maintain repo governance and agent automation workflows."
                $cfg.user_profile.summary = "Repo governance and agent automation."
                $cfg.user_profile.structured.primary_work_types = @("repo-governance")
                $cfg.user_profile.structured.preferred_agents = @("codex")
                $cfg.user_profile.structured.tech_stack = @("powershell")
                $cfg.user_profile.structured.common_tasks = @("skill discovery")
                $cfg.user_profile.structured.constraints = @("dry-run first")
                $cfg.user_profile.structured.avoidances = @("duplicate skills")
                $cfg.user_profile.structured.decision_preferences = @("source-backed recommendations")
                Save-AuditTargetsConfig $cfg

                Mock Get-InstalledSkillFacts {
                    @([pscustomobject]@{
                            name = "find-skills"
                            source_kind = "manual"
                            vendor = "manual"
                            from = "find-skills"
                            to = "find-skills"
                            repo = "https://example.com/skills.git"
                            ref = "main"
                            skill_path = "."
                            declared_name = "find-skills"
                            description = "Find skills."
                            trigger_summary = "Use when discovering skills."
                            local_path = "imports\find-skills"
                        })
                }

                $out = Join-Path $TestDrive "discover-run"
                $result = Invoke-AuditSkillDiscovery -Query "powershell testing" -OutDir $out

                $result.mode | Should -Be "profile-only"
                @((Get-ChildItem -LiteralPath $out -File).Name | Sort-Object) -join ',' | Should -Be 'receipt.json,recommendations.json,snapshot.json'
                $template = Get-ContentUtf8 (Join-Path $out "recommendations.json") | ConvertFrom-Json
                $template.recommendation_mode | Should -Be "profile-only"
                $template.decision_basis.target_scan_used | Should -Be $false
                $snapshot = Get-ContentUtf8 (Join-Path $out "snapshot.json") | ConvertFrom-Json
                $snapshot.mode | Should -Be "profile-only"
                $snapshot.prompt_contract_version | Should -Be (Get-AuditPromptContractVersion)
                @($snapshot.target_scans).Count | Should -Be 0
                $receipt = Get-ContentUtf8 (Join-Path $out "receipt.json") | ConvertFrom-Json
                $receipt.persisted | Should -BeFalse
                $receipt.truth_boundary | Should -Be "repo_snapshot_created_not_reviewed_not_applied"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Includes target repo facts in decision insight keywords" {
            $cfg = [pscustomobject]@{
                user_profile = [pscustomobject]@{
                    raw_text = "PPT and classroom tools"
                    summary = "classroom tools"
                    structured = [pscustomobject]@{
                        primary_work_types = @("teaching")
                        preferred_agents = @("powerpoint-automation")
                        tech_stack = @("dotnet")
                        common_tasks = @("slides")
                        constraints = @("windows")
                        avoidances = @()
                        decision_preferences = @()
                    }
                }
            }
            $scan = [pscustomobject]@{
                target = [pscustomobject]@{ name = "classroomtoolkit" }
                detected = [pscustomobject]@{
                    languages = @("dotnet")
                    package_managers = @("nuget")
                    frameworks = @()
                    build_commands = @("dotnet build")
                    test_commands = @("dotnet test")
                    agent_rule_files = @("AGENTS.md")
                    notable_files = @("ClassroomToolkit.sln", ".github\workflows\ci.yml")
                }
                risks = @("git_dirty")
            }

            $insights = New-AuditDecisionInsights (New-AuditTargetProfile @($scan)) @($scan) @() @()

            $insights.keywords.target_repo | Should -Contain "classroomtoolkit"
            $insights.keywords.target_repo | Should -Contain "dotnet"
            $insights.keywords.target_repo | Should -Contain "nuget"
            $insights.keywords.target_repo | Should -Contain "dotnet build"
            $insights.keywords.target_repo | Should -Contain "ClassroomToolkit.sln"
            $insights.keywords.target_repo | Should -Contain "git_dirty"
            $insights.PSObject.Properties.Name | Should -Not -Contain 'fit'
            $insights.PSObject.Properties.Name | Should -Contain 'decision_checklist'
        }

        It "Includes target repo facts in decision insight keywords when detected uses ordered dictionaries" {
            $cfg = [pscustomobject]@{
                user_profile = [pscustomobject]@{
                    raw_text = "question graph"
                    summary = "question graph"
                    structured = [pscustomobject]@{
                        primary_work_types = @("teaching")
                        preferred_agents = @()
                        tech_stack = @("dotnet", "python")
                        common_tasks = @("document import")
                        constraints = @("windows")
                        avoidances = @()
                        decision_preferences = @()
                    }
                }
            }
            $scan = [pscustomobject]@{
                target = [ordered]@{ name = "k12-question-graph" }
                detected = [ordered]@{
                    languages = @("dotnet", "python")
                    package_managers = @("nuget", "pip")
                    frameworks = @("aspnetcore", "efcore")
                    build_commands = @("dotnet build")
                    test_commands = @("ui smoke")
                    capabilities = @("document_import", "ocr_pipeline", "backup_recovery")
                    agent_rule_files = @("AGENTS.md")
                    notable_files = @("docs\07_Document_AI_ImportPipeline.md")
                }
                risks = @("design_package_only")
            }

            $insights = New-AuditDecisionInsights (New-AuditTargetProfile @($scan)) @($scan) @() @()

            $insights.keywords.target_repo | Should -Contain "k12-question-graph"
            $insights.keywords.target_repo | Should -Contain "dotnet"
            $insights.keywords.target_repo | Should -Contain "document_import"
            $insights.keywords.target_repo | Should -Contain "backup_recovery"
            $insights.keywords.target_repo | Should -Contain "docs\07_Document_AI_ImportPipeline.md"
            $insights.keywords.target_repo | Should -Contain "design_package_only"
        }

        It "Updates receipt sections without overwriting earlier phase results" {
            $runDir = Join-Path $TestDrive "receipt-sections"
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null
            $recommendationsPath = Join-Path $runDir "recommendations.json"
            Write-AuditJsonFile $recommendationsPath (New-AuditRecommendationsTemplate "r-receipt-sections" "demo")
            Write-AuditJsonFile (Join-Path $runDir "receipt.json") ([pscustomobject]@{
                schema_version = 1
                run_id = "r-receipt-sections"
                success = $true
                persisted = $false
                scan = [pscustomobject]@{ success = $true; snapshot_sha256 = "abc" }
                preflight = $null
                dry_run = $null
                workflow = $null
                apply = $null
            })

            Write-AuditReceiptSection $recommendationsPath "preflight" ([ordered]@{ run_id="r-receipt-sections"; mode="preflight"; success=$true; persisted=$false }) | Out-Null
            Write-AuditReceiptSection $recommendationsPath "dry_run" ([pscustomobject]@{ run_id="r-receipt-sections"; mode="dry_run"; success=$false; persisted=$false; error_code="blocked" }) | Out-Null

            $receipt = Get-ContentUtf8 (Join-Path $runDir "receipt.json") | ConvertFrom-Json
            $receipt.scan.snapshot_sha256 | Should -Be "abc"
            $receipt.preflight.success | Should -Be $true
            $receipt.dry_run.error_code | Should -Be "blocked"
            $receipt.workflow | Should -BeNullOrEmpty
            $receipt.apply | Should -BeNullOrEmpty
            $receipt.persisted | Should -Be $false
            $receipt.truth_boundary | Should -Be "repo_verified_not_applied"
        }

        It "Fails when a required audit bundle file is missing" {
            $presentPath = Join-Path $TestDrive "recommendations.json"
            Write-AuditJsonFile $presentPath (New-AuditRecommendationsTemplate "r" "demo")
            $missingPath = Join-Path $TestDrive "snapshot.json"

            $thrown = $false
            try {
                Assert-AuditBundleRequiredFiles @(
                    [pscustomobject]@{ label = "recommendations.json"; path = $presentPath }
                    [pscustomobject]@{ label = "snapshot.json"; path = $missingPath }
                )
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "snapshot.json"
            }
            $thrown | Should -Be $true
        }

        It "Fails when required audit JSON exists but misses required fields" {
            $invalidProfile = Join-Path $TestDrive "snapshot.json"
            Set-ContentUtf8 $invalidProfile '{"schema_version":2,"run_id":"r"}'

            $thrown = $false
            try {
                Assert-AuditBundleRequiredFiles @(
                    [pscustomobject]@{ label = "snapshot.json"; path = $invalidProfile }
                )
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "snapshot 缺少"
            }
            $thrown | Should -Be $true
        }

        It "Generates run id with millisecond precision" {
            $runId = Get-AuditRunId
            $runId | Should -Match "^\d{8}-\d{6}-\d{3}$"
        }

        It "Detects target repo facts from deterministic files" {
            $repo = Join-Path $TestDrive "target-repo"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            Push-Location $repo
            try {
                git init | Out-Null
                git config user.email "test@example.com" | Out-Null
                git config user.name "Test User" | Out-Null
                Set-Content -Path "package.json" -Value '{"scripts":{"build":"vite build","test":"vitest"},"dependencies":{"vite":"latest","react":"latest"}}'
                Set-Content -Path "vite.config.ts" -Value "export default {}"
                Set-Content -Path "AGENTS.md" -Value "rules"
                git add . | Out-Null
                git commit -m init | Out-Null
            }
            finally {
                Pop-Location
            }

            $scan = New-AuditRepoScan "demo" $repo "..\target-repo"

            $scan.target.name | Should -Be "demo"
            $scan.target.exists | Should -Be $true
            $scan.git.is_repo | Should -Be $true
            (@($scan.detected.package_managers) -contains "npm") | Should -Be $true
            (@($scan.detected.frameworks) -contains "vite") | Should -Be $true
            (@($scan.detected.frameworks) -contains "react") | Should -Be $true
            (@($scan.detected.build_commands) -contains "npm run build") | Should -Be $true
            (@($scan.detected.test_commands) -contains "npm test") | Should -Be $true
            (@($scan.detected.agent_rule_files) -contains "AGENTS.md") | Should -Be $true
        }

        It "Extracts dotnet/python/ci command hints from repo scan inputs" {
            $repo = Join-Path $TestDrive "target-repo-granular"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "pyproject.toml") @"
[tool.poetry]
name = "demo"
version = "0.1.0"

[tool.pytest.ini_options]
addopts = "-q"
"@
            Set-ContentUtf8 (Join-Path $repo "Demo.sln") "Microsoft Visual Studio Solution File, Format Version 12.00"
            Set-ContentUtf8 (Join-Path $repo "Demo.csproj") @"
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="8.0.0" />
    <PackageReference Include="xunit" Version="2.6.0" />
  </ItemGroup>
</Project>
"@
            $workflowDir = Join-Path $repo ".github\workflows"
            New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $workflowDir "ci.yml") @"
name: ci
jobs:
  build:
    steps:
      - run: dotnet build
      - run: dotnet test
"@

            $scan = New-AuditRepoScan "demo" $repo "..\target-repo-granular"

            (@($scan.detected.languages) -contains "dotnet") | Should -Be $true
            (@($scan.detected.languages) -contains "python") | Should -Be $true
            (@($scan.detected.package_managers) -contains "nuget") | Should -Be $true
            (@($scan.detected.package_managers) -contains "poetry") | Should -Be $true
            (@($scan.detected.frameworks) -contains "aspnetcore") | Should -Be $true
            (@($scan.detected.frameworks) -contains "efcore") | Should -Be $true
            (@($scan.detected.build_commands) -contains "dotnet build") | Should -Be $true
            (@($scan.detected.test_commands) -contains "dotnet test") | Should -Be $true
            (@($scan.detected.test_commands) -contains "pytest") | Should -Be $true
            (@($scan.detected.notable_files) | Where-Object { [string]$_ -match "ci\.yml$" }).Count -gt 0 | Should -Be $true
        }

        It "Excludes generated runtime and worktree projects from dotnet repo facts" {
            $repo = Join-Path $TestDrive "target-repo-dotnet-exclusions"
            New-Item -ItemType Directory -Path (Join-Path $repo "src\App") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo ".runtime\tmp\Sample.Tests") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo ".worktrees\feature\tests\Sample.Tests") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "src\App\App.csproj") '<Project Sdk="Microsoft.NET.Sdk" />'
            Set-ContentUtf8 (Join-Path $repo ".runtime\tmp\Sample.Tests\Sample.Tests.csproj") '<Project Sdk="Microsoft.NET.Sdk" />'
            Set-ContentUtf8 (Join-Path $repo ".worktrees\feature\tests\Sample.Tests\Sample.Tests.csproj") '<Project Sdk="Microsoft.NET.Sdk" />'

            $scan = New-AuditRepoScan "demo" $repo "..\target-repo-dotnet-exclusions"

            (@($scan.detected.notable_files) -contains "src\App\App.csproj") | Should -Be $true
            (@($scan.detected.notable_files) | Where-Object { [string]$_ -match '(^|\\)\.(runtime|worktrees)(\\|$)' }).Count | Should -Be 0
        }

        It "Excludes generated backups, build outputs, temporary runs, and configured managed skill output from requirement evidence" {
            $repo = Join-Path $TestDrive "target-repo-generated-evidence-exclusions"
            foreach ($relativePath in @(
                    "src",
                    ".txn\\backup",
                    ".agent-build\\obj",
                    ".tmp\\case",
                    "artifacts\\verify",
                    "vendor\\dependency",
                    "agent\\managed"
                )) {
                New-Item -ItemType Directory -Path (Join-Path $repo $relativePath) -Force | Out-Null
            }
            Set-ContentUtf8 (Join-Path $repo "skills.json") '{"skill_projection":{"managed_source_path":"agent"}}'
            Set-ContentUtf8 (Join-Path $repo "src\\real.py") 'def parse_pdf(path): return read_image(path)'
            foreach ($relativePath in @(
                    ".txn\\backup\\stale.py",
                    ".agent-build\\obj\\generated.py",
                    ".tmp\\case\\fixture.py",
                    "artifacts\\verify\\output.py",
                    "vendor\\dependency\\library.py",
                    "agent\\managed\\skill.py"
                )) {
                Set-ContentUtf8 (Join-Path $repo $relativePath) 'def generate_presentation(): return "stale.pptx"'
            }

            $scan = New-AuditRepoScan "demo" $repo "..\\target-repo-generated-evidence-exclusions"

            $pdf = @($scan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pdf" })
            $pptx = @($scan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pptx" })
            $pdf.Count | Should -Be 1
            $pdf[0].evidence.path | Should -Contain "src\real.py"
            $pptx.Count | Should -Be 0
            $allEvidencePaths = @($scan.detected.artifact_capabilities | ForEach-Object { @($_.evidence | ForEach-Object { [string]$_.path }) })
            (@($allEvidencePaths | Where-Object { $_ -match '(?i)(^|\\)(\.txn|\.agent-build|\.tmp|artifacts|vendor|agent)(\\|$)' })).Count | Should -Be 0
        }

        It "Extracts documented stack facts from design-package repos before code exists" {
            $repo = Join-Path $TestDrive "target-repo-design-docs"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo "docs") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "README.md") @"
# Demo

本仓当前是编码前设计包，尚未创建实际 ASP.NET Core、React、PostgreSQL migration 或 Python Worker 代码。
"@
            Set-ContentUtf8 (Join-Path $repo "docs\04_TechnologyStack.md") @"
Frontend: React + TypeScript + Vite + Ant Design + TanStack Query + React Router
Backend: ASP.NET Core / .NET 10 LTS
ORM: EF Core 10 + Npgsql.EntityFrameworkCore.PostgreSQL 10.x
Worker: Python Adapter process for Docling/PaddleOCR/OCR/AI tasks
Frontend checks: npm run build, UI smoke
Backend checks: dotnet test
"@
            Set-ContentUtf8 (Join-Path $repo "docs\03_Architecture.md") @"
ASP.NET Core API
BackgroundService
PostgreSQL
Document Worker: Docling / PaddleOCR
"@
            Set-ContentUtf8 (Join-Path $repo "docs\07_Document_AI_ImportPipeline.md") @"
Import pipeline: Word/PDF/Image -> OpenXML / Docling / PaddleOCR / OCR -> question extraction -> review queue
"@
            Set-ContentUtf8 (Join-Path $repo "docs\12_PaperGeneration_ExportLayout.md") @"
Paper generation uses a layout engine with Word export and PDF export.
"@
            Set-ContentUtf8 (Join-Path $repo "docs\13_AssessmentAnalytics.md") @"
Assessment analytics supports Excel import, CTT and question stats analytics.
"@
            Set-ContentUtf8 (Join-Path $repo "docs\14_BackupRecoveryMigration.md") @"
Backup / restore / migration / disaster recovery relies on manifest hash validation and WinPE recovery drills.
"@

            $scan = New-AuditRepoScan "demo" $repo "..\target-repo-design-docs"

            (@($scan.detected.languages) -contains "javascript") | Should -Be $true
            (@($scan.detected.languages) -contains "dotnet") | Should -Be $true
            (@($scan.detected.languages) -contains "python") | Should -Be $true
            (@($scan.detected.frameworks) -contains "react") | Should -Be $true
            (@($scan.detected.frameworks) -contains "vite") | Should -Be $true
            (@($scan.detected.frameworks) -contains "aspnetcore") | Should -Be $true
            (@($scan.detected.frameworks) -contains "efcore") | Should -Be $true
            (@($scan.detected.package_managers) -contains "npm") | Should -Be $true
            (@($scan.detected.package_managers) -contains "nuget") | Should -Be $true
            (@($scan.detected.package_managers) -contains "pip") | Should -Be $true
            (@($scan.detected.build_commands) -contains "npm run build") | Should -Be $true
            (@($scan.detected.build_commands) -contains "dotnet build") | Should -Be $true
            (@($scan.detected.test_commands) -contains "dotnet test") | Should -Be $true
            (@($scan.detected.test_commands) -contains "ui smoke") | Should -Be $true
            (@($scan.detected.capabilities) -contains "document_import") | Should -Be $true
            (@($scan.detected.capabilities) -contains "ocr_pipeline") | Should -Be $true
            (@($scan.detected.capabilities) -contains "question_extraction") | Should -Be $true
            (@($scan.detected.capabilities) -contains "review_queue") | Should -Be $true
            (@($scan.detected.capabilities) -contains "paper_generation") | Should -Be $true
            (@($scan.detected.capabilities) -contains "document_export") | Should -Be $true
            (@($scan.detected.capabilities) -contains "assessment_analytics") | Should -Be $true
            (@($scan.detected.capabilities) -contains "spreadsheet_import") | Should -Be $true
            (@($scan.detected.capabilities) -contains "backup_recovery") | Should -Be $true
            (@($scan.detected.capabilities) -contains "migration_recovery") | Should -Be $true
            (@($scan.detected.notable_files) -contains "README.md") | Should -Be $true
            (@($scan.detected.notable_files) -contains "docs\04_TechnologyStack.md") | Should -Be $true
            (@($scan.risks) -contains "design_package_only") | Should -Be $true
        }

        It "Builds evidence-backed multi-domain requirement signals instead of a format-only profile" {
            $repo = Join-Path $TestDrive "target-repo-requirement-signals"
            New-Item -ItemType Directory -Path (Join-Path $repo "src") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo "tests") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "package.json") '{"dependencies":{"react":"1.0.0","pdf-lib":"1.0.0","pptxgenjs":"1.0.0","playwright":"1.0.0"}}'
            Set-ContentUtf8 (Join-Path $repo "requirements.txt") 'rapidocr_onnxruntime==1.2.3'
            Set-ContentUtf8 (Join-Path $repo "src\pipeline.py") @"
def render_pdf(target):
    return parse_pdf(target)

def parse_pdf(target):
    return read_image("page.png")

def read_image(path):
    return RapidOCR()(path)
"@
            Set-ContentUtf8 (Join-Path $repo "src\server.cs") @"
app.MapGet("/health", () => "ok");
public sealed class AppStore : DbContext { }
public string CreatePresentation() => "courseware.pptx";
"@
            Set-ContentUtf8 (Join-Path $repo "tests\pipeline_test.py") 'def test_render_pdf(): assert render_pdf("sample.pdf")'

            $scan = New-AuditRepoScan "demo" $repo "..\target-repo-requirement-signals"
            $profile = New-AuditTargetProfile @($scan)

            $pdf = @($scan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pdf" })
            $pptx = @($scan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pptx" })
            $image = @($scan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "image" })
            $pdf.Count | Should -Be 1
            $pdf[0].actions | Should -Contain "read"
            $pdf[0].actions | Should -Contain "render"
            $pdf[0].confidence | Should -Be "high"
            $pptx.Count | Should -Be 1
            $pptx[0].actions | Should -Contain "generate"
            $image[0].actions | Should -Contain "ocr"
            $image[0].evidence_status | Should -Be "implemented"
            (@($scan.detected.requirement_signals | Where-Object { $_.domain -eq "interface" -and $_.subject -eq "web_ui" })).Count | Should -Be 1
            (@($scan.detected.requirement_signals | Where-Object { $_.domain -eq "integration" -and $_.subject -eq "http_api" })).Count | Should -Be 1
            (@($scan.detected.requirement_signals | Where-Object { $_.domain -eq "data" -and $_.subject -eq "persistence" })).Count | Should -Be 1
            (@($scan.detected.requirement_signals | Where-Object { $_.domain -eq "automation" -and $_.subject -eq "browser_automation" })).Count | Should -Be 1
            (@($profile.requirement_signals | Where-Object { $_.subject -eq "document_processing" })).Count | Should -Be 1
            $profile.requirement_signals[0].targets | Should -Contain "demo"
            (Get-AuditRepoScanKeywords $scan) | Should -Contain "pdf_render"
            (Get-AuditRepoScanKeywords $scan) | Should -Contain "interface_web_ui"
        }

        It "Highlights source-backed product workflows without letting raw file volume promote technical context" {
            $webEvidence = @(
                1..40 | ForEach-Object { [pscustomobject]@{ kind = "source_code"; path = "src\\web-$_.ts"; signal = "interface:web_ui@L$_" } }
            )
            $workflowEvidence = @([pscustomobject]@{ kind = "source_code"; path = "src\\document-flow.cs"; signal = "workflow:document_processing@L12" })
            $documentedOcr = @([pscustomobject]@{ kind = "documentation"; path = "README.md"; signal = "workflow:ocr@L4" })
            $scanOne = [pscustomobject]@{
                target = [pscustomobject]@{ name = "one" }
                detected = [pscustomobject]@{
                    languages = @(); package_managers = @(); frameworks = @(); build_commands = @(); test_commands = @(); capabilities = @(); agent_rule_files = @(); notable_files = @()
                    artifact_capabilities = @()
                    requirement_signals = @(
                        [pscustomobject]@{ domain = "interface"; subject = "web_ui"; actions = @("deliver"); confidence = "high"; evidence_status = "implemented"; targets = @(); evidence = $webEvidence },
                        [pscustomobject]@{ domain = "workflow"; subject = "document_processing"; actions = @("process"); confidence = "high"; evidence_status = "implemented"; targets = @(); evidence = $workflowEvidence },
                        [pscustomobject]@{ domain = "workflow"; subject = "ocr"; actions = @("recognize"); confidence = "low"; evidence_status = "documented"; targets = @(); evidence = $documentedOcr }
                    )
                }
                risks = @()
            }
            $scanTwo = [pscustomobject]@{
                target = [pscustomobject]@{ name = "two" }
                detected = [pscustomobject]@{
                    languages = @(); package_managers = @(); frameworks = @(); build_commands = @(); test_commands = @(); capabilities = @(); agent_rule_files = @(); notable_files = @()
                    artifact_capabilities = @()
                    requirement_signals = @(
                        [pscustomobject]@{ domain = "workflow"; subject = "document_processing"; actions = @("process"); confidence = "high"; evidence_status = "implemented"; targets = @(); evidence = $workflowEvidence },
                        [pscustomobject]@{ domain = "workflow"; subject = "ocr"; actions = @("recognize"); confidence = "low"; evidence_status = "documented"; targets = @(); evidence = $documentedOcr }
                    )
                }
                risks = @()
            }

            $profile = New-AuditTargetProfile @($scanOne, $scanTwo)
            $priority = $profile.prioritized_needs
            $primary = @($priority.primary_needs | Where-Object key -eq "workflow/document_processing")
            $primary.Count | Should -Be 1
            $primary[0].evidence_coverage.source_code_target_count | Should -Be 2
            $priority.ranking_method | Should -Be "role_then_source_coverage_v2"
            @($priority.primary_needs | Where-Object key -eq "interface/web_ui").Count | Should -Be 0
            @($priority.secondary_needs | Where-Object key -eq "interface/web_ui").Count | Should -Be 1
            @($priority.observations | Where-Object key -eq "workflow/ocr").Count | Should -Be 1
            $profile.user_need_summary.scope | Should -Be "portfolio"
            $profile.user_need_summary.primary_needs[0].target_scope | Should -Contain "one"
            $profile.user_need_summary.primary_needs[0].target_scope | Should -Contain "two"
            $oneProfile = @($profile.target_evidence_partitions | Where-Object target -eq "one")
            $twoProfile = @($profile.target_evidence_partitions | Where-Object target -eq "two")
            $oneProfile.Count | Should -Be 1
            $twoProfile.Count | Should -Be 1
            @($oneProfile[0].prioritized_needs.primary_needs | Where-Object key -eq "workflow/document_processing").Count | Should -Be 1
            @($twoProfile[0].prioritized_needs.primary_needs | Where-Object key -eq "workflow/document_processing").Count | Should -Be 1

            $insights = New-AuditDecisionInsights $profile @($scanOne, $scanTwo) @() @()
            $insights.keywords.primary_target_profile | Should -Contain "document_processing"
            $insights.keywords.primary_target_profile | Should -Not -Contain "web_ui"
            ($insights.decision_checklist -join " ") | Should -Match "target_scans"
            $insights.target_repo_by_target[0].target | Should -Be "one"
            $insights.target_repo_by_target[0].keywords | Should -Contain "document_processing"

            $singleSourceScanTwo = $scanTwo | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $singleSourceScanTwo.detected.requirement_signals = @(
                [pscustomobject]@{ domain = "workflow"; subject = "ocr"; actions = @("recognize"); confidence = "low"; evidence_status = "documented"; targets = @(); evidence = $documentedOcr }
            )
            $singleSourceProfile = New-AuditTargetProfile @($scanOne, $singleSourceScanTwo)
            @($singleSourceProfile.prioritized_needs.primary_needs | Where-Object key -eq "workflow/document_processing").Count | Should -Be 0
            $singleSourceWorkflow = @($singleSourceProfile.prioritized_needs.secondary_needs | Where-Object key -eq "workflow/document_processing")
            $singleSourceWorkflow.Count | Should -Be 1
            $singleSourceWorkflow[0].evidence_coverage.source_code_target_count | Should -Be 1
        }

        It "Emits repository scope and source scan coverage for a single target" {
            $repo = Join-Path $TestDrive "target-repo-coverage"
            New-Item -ItemType Directory -Path (Join-Path $repo "src") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo "examples") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "src\main.py") 'def process_document(path): return path'
            Set-ContentUtf8 (Join-Path $repo "examples\sample.py") 'def process_document(path): return path'

            $scan = New-AuditRepoScan "coverage-demo" $repo "..\target-repo-coverage"
            $profile = New-AuditTargetProfile @($scan)

            $profile.scope | Should -Be "portfolio"
            $profile.profile_kind | Should -Be "portfolio_capability_profile"
            $profile.user_need_summary.scope | Should -Be "portfolio"
            $profile.user_need_summary.profile_kind | Should -Be "portfolio_capability_profile"
            $scan.scan_coverage.population_count | Should -Be 2
            $scan.scan_coverage.sampled_count | Should -Be 2
            $scan.scan_coverage.sampled_by_kind.non_product_code | Should -Be 1
            $scan.scan_coverage.confidence_ceiling | Should -Be "complete_source_population"
        }

        It "Keeps nested support code out of product-source attribution" {
            $repo = Join-Path $TestDrive "target-repo-nested-support"
            New-Item -ItemType Directory -Path (Join-Path $repo "packages\tools") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "packages\tools\diagnostic.py") 'provider = "diagnostic"'

            $scan = New-AuditRepoScan "nested-support" $repo "..\target-repo-nested-support"

            $scan.scan_coverage.sampled_by_kind.supporting_code | Should -Be 1
            $scan.scan_coverage.sampled_by_kind.source_code | Should -Be 0
        }

        It "Caps confidence when a source file is too large or text is truncated" {
            $repo = Join-Path $TestDrive "target-repo-coverage-ceiling"
            New-Item -ItemType Directory -Path (Join-Path $repo "src") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "src\large.py") ("x" * 1048577)

            $scan = New-AuditRepoScan "coverage-ceiling-large" $repo "..\target-repo-coverage-ceiling"

            $scan.scan_coverage.large_file_count | Should -Be 1
            $scan.scan_coverage.confidence_ceiling | Should -Be "representative_sample"

            Remove-Item -LiteralPath (Join-Path $repo "src\large.py") -Force
            Set-ContentUtf8 (Join-Path $repo "src\truncated.py") (("# signal`n" * 40000) + "def process_document(path): return path")
            $scan = New-AuditRepoScan "coverage-ceiling-text" $repo "..\target-repo-coverage-ceiling"

            $scan.scan_coverage.text_truncated_count | Should -Be 1
            $scan.scan_coverage.confidence_ceiling | Should -Be "representative_sample"
        }

        It "Separates direct AI content generation from model integration and supporting diagnostic code" {
            $repo = Join-Path $TestDrive "target-repo-ai-intent-roles"
            New-Item -ItemType Directory -Path (Join-Path $repo "src") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo "tools") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo ".artifacts\release") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "src\poster.py") 'def generate_image_poster(topic): return create_image(topic)'
            Set-ContentUtf8 (Join-Path $repo "tools\provider_diagnostic.py") 'provider = "OpenAI" # model provider diagnostic'
            Set-ContentUtf8 (Join-Path $repo ".artifacts\release\generated.py") 'def generate_image_poster(topic): return create_image(topic)'

            $scan = New-AuditRepoScan "ai-intent" $repo "..\target-repo-ai-intent-roles"
            $profile = New-AuditTargetProfile @($scan)
            $generation = @($profile.prioritized_needs.primary_needs | Where-Object key -eq "ai/content_generation")
            $modelIntegration = @($profile.prioritized_needs.observations + $profile.prioritized_needs.secondary_needs | Where-Object key -eq "ai/model_integration")

            $generation.Count | Should -Be 1
            $generation[0].evidence_coverage.source_code_target_count | Should -Be 1
            $modelIntegration.Count | Should -Be 1
            $modelIntegration[0].evidence_coverage.source_code_target_count | Should -Be 0
            $modelIntegration[0].evidence_coverage.supporting_code_target_count | Should -Be 1
            $modelIntegration[0].limitations | Should -Contain "supporting_code_not_direct_product_journey"
            @($scan.detected.requirement_signals | ForEach-Object { @($_.evidence | Where-Object { $_.path -match '\.artifacts\\' }) }).Count | Should -Be 0
        }

        It "Anchors artifact evidence locally, excludes scanner metadata, and does not promote test-only coverage" {
            $separatedRepo = Join-Path $TestDrive "target-repo-separated-artifact-signals"
            New-Item -ItemType Directory -Path (Join-Path $separatedRepo "src") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $separatedRepo "tests") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $separatedRepo "src\separated.py") @"
PDF_FORMAT = "pdf"
status = "ready"
def render_report():
    return status
"@
            Set-ContentUtf8 (Join-Path $separatedRepo "src\scanner-rules.ps1") '$rule = [pscustomobject]@{ artifact = "pdf"; domain = "workflow"; subject = "document_processing"; pattern = "pdf"; actions = @("render") }'
            Set-ContentUtf8 (Join-Path $separatedRepo "src\scanner-implementation.ps1") @'
function Add-AuditArtifactFactsFromText { }
function Add-AuditRequirementFactsFromText { }
if ($text -match "ocr") { }
'@
            Set-ContentUtf8 (Join-Path $separatedRepo "tests\scanner-fixture.ps1") @'
New-AuditRepoScan "fixture" $repo "fixture"
Set-ContentUtf8 $path "render_pdf(sample.pdf)"
$scan.detected.artifact_capabilities | Out-Null
'@

            $separatedScan = New-AuditRepoScan "separated" $separatedRepo "..\target-repo-separated-artifact-signals"
            (@($separatedScan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pdf" })).Count | Should -Be 0
            $separatedEvidencePaths = @($separatedScan.detected.requirement_signals | ForEach-Object { @($_.evidence | ForEach-Object { [string]$_.path }) })
            $separatedEvidencePaths | Should -Not -Contain "src\scanner-rules.ps1"
            $separatedEvidencePaths | Should -Not -Contain "src\scanner-implementation.ps1"
            $separatedEvidencePaths | Should -Not -Contain "tests\scanner-fixture.ps1"

            $implementedRepo = Join-Path $TestDrive "target-repo-local-artifact-evidence"
            New-Item -ItemType Directory -Path (Join-Path $implementedRepo "src") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $implementedRepo "src\pdf_pipeline.py") 'def render_pdf(path): return save_pdf(path)'

            $implementedScan = New-AuditRepoScan "implemented" $implementedRepo "..\target-repo-local-artifact-evidence"
            $implementedPdf = @($implementedScan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pdf" })
            $implementedPdf.Count | Should -Be 1
            $implementedPdf[0].confidence | Should -Be "high"
            $implementedPdf[0].evidence_status | Should -Be "implemented"
            ($implementedPdf[0].evidence | ForEach-Object { [string]$_.signal }) | Should -Match "@L1$"

            $testOnlyRepo = Join-Path $TestDrive "target-repo-test-only-artifact-evidence"
            New-Item -ItemType Directory -Path (Join-Path $testOnlyRepo "tests") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $testOnlyRepo "tests\pdf_pipeline_test.py") 'def test_render_pdf(): return render_pdf("sample.pdf")'

            $testOnlyScan = New-AuditRepoScan "test-only" $testOnlyRepo "..\target-repo-test-only-artifact-evidence"
            $testOnlyPdf = @($testOnlyScan.detected.artifact_capabilities | Where-Object { $_.artifact -eq "pdf" })
            $testOnlyPdf.Count | Should -Be 1
            $testOnlyPdf[0].confidence | Should -Be "medium"
            $testOnlyPdf[0].evidence_status | Should -Be "test_covered"
            ($testOnlyPdf[0].evidence | ForEach-Object { [string]$_.kind } | Select-Object -Unique) | Should -Be @("test")
        }

        It "Samples oversized source scans across source areas instead of a lexical prefix" {
            $repo = Join-Path $TestDrive "target-repo-balanced-source-scan"
            New-Item -ItemType Directory -Path (Join-Path $repo "apps\alpha") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo "apps\omega") -Force | Out-Null
            $files = New-Object System.Collections.Generic.List[object]
            foreach ($i in 1..4) {
                $alpha = Join-Path $repo ("apps\alpha\{0:D2}.cs" -f $i)
                $omega = Join-Path $repo ("apps\omega\{0:D2}.cs" -f $i)
                Set-ContentUtf8 $alpha "class Alpha$i {}"
                Set-ContentUtf8 $omega "class Omega$i {}"
                $files.Add((Get-Item -LiteralPath $alpha)) | Out-Null
                $files.Add((Get-Item -LiteralPath $omega)) | Out-Null
            }

            $sample = @(Select-AuditBalancedSourceFiles $repo @($files.ToArray()) 4)

            $sample.Count | Should -Be 4
            @($sample | Where-Object { $_.FullName -match 'apps\\alpha\\' }).Count | Should -Be 2
            @($sample | Where-Object { $_.FullName -match 'apps\\omega\\' }).Count | Should -Be 2
        }

        It "Extracts java/ruby/php/container/monorepo signals from repo scan inputs" {
            $repo = Join-Path $TestDrive "target-repo-polyglot"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo "pom.xml") "<project><artifactId>demo</artifactId><dependencies><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency></dependencies></project>"
            Set-ContentUtf8 (Join-Path $repo "Gemfile") "source 'https://rubygems.org'`ngem 'rails'"
            Set-ContentUtf8 (Join-Path $repo "composer.json") '{"require":{"laravel/framework":"^11.0"}}'
            Set-ContentUtf8 (Join-Path $repo "Dockerfile") "FROM alpine:3.20"
            Set-ContentUtf8 (Join-Path $repo "pnpm-workspace.yaml") "packages:`n  - apps/*"
            Set-ContentUtf8 (Join-Path $repo "Makefile") "build:`n`t@echo build`n`ntest:`n`t@echo test"

            $scan = New-AuditRepoScan "demo" $repo "..\target-repo-polyglot"

            (@($scan.detected.languages) -contains "java") | Should -Be $true
            (@($scan.detected.languages) -contains "ruby") | Should -Be $true
            (@($scan.detected.languages) -contains "php") | Should -Be $true
            (@($scan.detected.package_managers) -contains "maven") | Should -Be $true
            (@($scan.detected.package_managers) -contains "bundler") | Should -Be $true
            (@($scan.detected.package_managers) -contains "composer") | Should -Be $true
            (@($scan.detected.frameworks) -contains "spring-boot") | Should -Be $true
            (@($scan.detected.frameworks) -contains "rails") | Should -Be $true
            (@($scan.detected.frameworks) -contains "laravel") | Should -Be $true
            (@($scan.detected.frameworks) -contains "docker") | Should -Be $true
            (@($scan.detected.frameworks) -contains "monorepo") | Should -Be $true
            (@($scan.detected.build_commands) -contains "mvn -B -DskipTests package") | Should -Be $true
            (@($scan.detected.test_commands) -contains "bundle exec rspec") | Should -Be $true
            (@($scan.detected.test_commands) -contains "composer test") | Should -Be $true
            (@($scan.detected.build_commands) -contains "make build") | Should -Be $true
            (@($scan.detected.test_commands) -contains "make test") | Should -Be $true
        }
    }

    Context "Installed skill facts" {
        It "Expands YAML block scalar descriptions without regressing inline metadata" {
            $literalPath = Join-Path $TestDrive "literal-skill.md"
            $foldedPath = Join-Path $TestDrive "folded-skill.md"
            $inlinePath = Join-Path $TestDrive "inline-skill.md"
            Set-ContentUtf8 $literalPath "---`nname: literal-skill`ndescription: |`n  Trigger when a literal block is needed.`n`n  Preserve the paragraph boundary.`n---`nBody."
            Set-ContentUtf8 $foldedPath "---`nname: folded-skill`ndescription: >-`n  Use when a folded`n  description spans lines.`n---`nBody."
            Set-ContentUtf8 $inlinePath "---`nname: inline-skill`ndescription: Inline description.`n---`nBody."

            $literal = Read-SkillMetadata $literalPath -Observation
            $folded = Read-SkillMetadata $foldedPath -Observation
            $inline = Read-SkillMetadata $inlinePath -Observation

            $literal.description | Should -Be "Trigger when a literal block is needed.`n`nPreserve the paragraph boundary."
            $folded.description | Should -Be "Use when a folded description spans lines."
            $inline.description | Should -Be "Inline description."
        }

        It "Extracts declared name and description from installed manual skills" {
            $oldImportDir = $script:ImportDir
            $oldOverridesDir = $script:OverridesDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports"
                $script:OverridesDir = Join-Path $TestDrive "empty-overrides"
                $ImportDir = $script:ImportDir
                $OverridesDir = $script:OverridesDir
                New-Item -ItemType Directory -Path (Join-Path $script:ImportDir "demo-skill") -Force | Out-Null
                New-Item -ItemType Directory -Path $script:OverridesDir -Force | Out-Null
                Set-Content -Path (Join-Path $script:ImportDir "demo-skill\SKILL.md") -Value "---`nname: demo-skill`ndescription: Demo description.`n---`nBody trigger text."
                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @([pscustomobject]@{ name = "demo-skill"; repo = "https://example.com/demo.git"; ref = "main"; skill = "."; mode = "manual" })
                    mappings = @([pscustomobject]@{ vendor = "manual"; from = "demo-skill"; to = "demo-skill" })
                }

                $facts = Get-InstalledSkillFacts $cfg

                @($facts).Count | Should -Be 1
                $facts[0].declared_name | Should -Be "demo-skill"
                $facts[0].description | Should -Be "Demo description."
                $facts[0].source_kind | Should -Be "manual"
                $facts[0].content_hash | Should -Be (Get-FileContentHash (Join-Path $script:ImportDir "demo-skill\SKILL.md"))
            }
            finally {
                $script:ImportDir = $oldImportDir
                $script:OverridesDir = $oldOverridesDir
            }
        }

        It "Includes unmapped overrides because they are built into agent output" {
            $oldOverridesDir = $script:OverridesDir
            try {
                $script:OverridesDir = Join-Path $TestDrive "overrides"
                $OverridesDir = $script:OverridesDir
                New-Item -ItemType Directory -Path (Join-Path $script:OverridesDir "custom-windows-wpf-teacher-app") -Force | Out-Null
                Set-Content -Path (Join-Path $script:OverridesDir "custom-windows-wpf-teacher-app\SKILL.md") -Value "---`nname: custom-windows-wpf-teacher-app`ndescription: Windows desktop UI skill.`n---`nUse when testing desktop UI."
                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @()
                    mappings = @()
                }

                $facts = Get-InstalledSkillFacts $cfg

                @($facts).Count | Should -Be 1
                $facts[0].vendor | Should -Be "overrides"
                $facts[0].from | Should -Be "custom-windows-wpf-teacher-app"
                $facts[0].declared_name | Should -Be "custom-windows-wpf-teacher-app"
                $facts[0].description | Should -Be "Windows desktop UI skill."
                $facts[0].content_hash | Should -Be (Get-FileContentHash (Join-Path $script:OverridesDir "custom-windows-wpf-teacher-app\SKILL.md"))
            }
            finally {
                $script:OverridesDir = $oldOverridesDir
            }
        }

        It "Resolves categorized override mappings by stable output name" {
            $oldOverridesDir = $script:OverridesDir
            try {
                $script:OverridesDir = Join-Path $TestDrive "categorized-override-mapping"
                $OverridesDir = $script:OverridesDir
                $overrideDir = Join-Path $script:OverridesDir "custom\custom-demo"
                New-Item -ItemType Directory -Path $overrideDir -Force | Out-Null
                Set-Content -Path (Join-Path $overrideDir "SKILL.md") -Value "---`nname: custom-demo`ndescription: Categorized override.`n---`nUse for categorized tests."
                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @()
                    mappings = @([pscustomobject]@{ vendor = "overrides"; from = "custom-demo"; to = "custom-demo" })
                }

                $facts = Get-InstalledSkillFacts $cfg

                @($facts).Count | Should -Be 1
                $facts[0].declared_name | Should -Be "custom-demo"
                $facts[0].description | Should -Be "Categorized override."
                $facts[0].local_path | Should -Be $overrideDir
                $facts[0].content_hash | Should -Be (Get-FileContentHash (Join-Path $overrideDir "SKILL.md"))
            }
            finally {
                $script:OverridesDir = $oldOverridesDir
            }
        }

        It "Excludes resource-only override directories from installed skill facts" {
            $oldOverridesDir = $script:OverridesDir
            try {
                $script:OverridesDir = Join-Path $TestDrive "overrides-resource-only"
                $OverridesDir = $script:OverridesDir
                $resourceDir = Join-Path $script:OverridesDir "requesting-code-review"
                New-Item -ItemType Directory -Path $resourceDir -Force | Out-Null
                Set-Content -Path (Join-Path $resourceDir "code-reviewer.md") -Value "resource bridge"
                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @()
                    mappings = @()
                }

                $facts = Get-InstalledSkillFacts $cfg

                @($facts).Count | Should -Be 0
            }
            finally {
                $script:OverridesDir = $oldOverridesDir
            }
        }

        It "Changes the installed fingerprint when projected skill semantics change" {
            $base = [pscustomobject]@{
                vendor          = "manual"
                from            = "legacy-cache"
                to              = "to-spec"
                repo            = "https://example.com/skills.git"
                ref             = "main"
                skill_path      = "skills/engineering/to-spec"
                declared_name   = "to-spec"
                description     = "Create a spec."
                trigger_summary = "Use when creating a spec."
                content_hash    = "aaa"
            }
            $renamed = $base.PSObject.Copy()
            $renamed.to = "to-tickets"
            $contentChanged = $base.PSObject.Copy()
            $contentChanged.content_hash = "bbb"

            $baseFingerprint = Get-AuditFingerprintFromSkillFacts @($base)

            (Get-AuditFingerprintFromSkillFacts @($renamed)) | Should -Not -Be $baseFingerprint
            (Get-AuditFingerprintFromSkillFacts @($contentChanged)) | Should -Not -Be $baseFingerprint
        }

        It "Separates configured supply from the current Codex profile selection" {
            $oldOverridesDir = $script:OverridesDir
            try {
                $script:OverridesDir = Join-Path $TestDrive 'profile-selected-inventory'
                $OverridesDir = $script:OverridesDir
                foreach ($name in @('alpha', 'beta')) {
                    $skillDir = Join-Path $script:OverridesDir $name
                    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                    Set-Content -Path (Join-Path $skillDir 'SKILL.md') -Value ("---`nname: {0}`ndescription: {0} fixture.`n---`nUse when testing {0}." -f $name)
                }
                $managedRoot = Join-Path $TestDrive 'agent'
                foreach ($name in @('alpha', 'beta')) {
                    $skillDir = Join-Path $managedRoot $name
                    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                    Set-Content -Path (Join-Path $skillDir 'SKILL.md') -Value ("---`nname: {0}`ndescription: {0} fixture.`n---`nUse when testing {0}." -f $name)
                }
                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @()
                    mappings = @(
                        [pscustomobject]@{ vendor = 'overrides'; from = 'alpha'; to = 'alpha' },
                        [pscustomobject]@{ vendor = 'overrides'; from = 'beta'; to = 'beta' }
                    )
                    mcp_servers = @()
                    skill_projection = [pscustomobject]@{
                        managed_source_path = $managedRoot
                        user_skill_root = (Join-Path $TestDrive 'user-skills')
                        projection_profiles = [pscustomobject]@{
                            schema_version = 1
                            default_profile = 'core'
                            profiles = [pscustomobject]@{
                                core = [pscustomobject]@{ include = @('alpha'); exclude = @() }
                            }
                            hosts = [pscustomobject]@{
                                codex = [pscustomobject]@{ default_profile = 'core'; exclude = @() }
                            }
                        }
                    }
                }

                $configuredSupply = @(Get-InstalledSkillFacts $cfg)
                $upstreamDuplicate = $configuredSupply[0].PSObject.Copy()
                $upstreamDuplicate.vendor = 'manual'
                $upstreamDuplicate.from = 'upstream-alpha'
                $upstreamDuplicate.content_hash = 'unmatched-upstream-content'
                $coreState = Get-AuditCurrentProfileSkillState $cfg @($configuredSupply + $upstreamDuplicate)

                $configuredSupply.Count | Should -Be 2
                $coreState.selected_skill_count | Should -Be 1
                @($coreState.selected_skills | ForEach-Object to) | Should -Be @('alpha')
                $coreState.selected_skills[0].vendor | Should -Be 'overrides'
                $coreState.selection.profile | Should -Be 'core'

                $alternateCfg = $cfg | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $alternateCfg.skill_projection.projection_profiles.profiles.core.include = @('beta')
                $alternateSupply = @(Get-InstalledSkillFacts $alternateCfg)
                $alternate = Get-AuditCurrentProfileSkillState $alternateCfg $alternateSupply
                $snapshotState = [pscustomobject]@{
                    fingerprint = [string]$coreState.fingerprint
                    configured_supply_fingerprint = (Get-AuditFingerprintFromSkillFacts $configuredSupply)
                    mcp_fingerprint = ''
                    external_skill_fingerprint = ''
                    host_projection = $null
                }
                $alternateLiveState = [pscustomobject]@{
                    fingerprint = [string]$alternate.fingerprint
                    configured_supply_fingerprint = (Get-AuditFingerprintFromSkillFacts $alternateSupply)
                    mcp_fingerprint = ''
                    external_skill_fingerprint = ''
                    host_projection = $null
                }
                $staleness = Get-AuditInstalledSnapshotStaleness $snapshotState $alternateLiveState

                @($alternate.selected_skills | ForEach-Object to) | Should -Be @('beta')
                $staleness.skill_stale | Should -BeTrue
                $staleness.profile_selection_stale | Should -BeTrue
            }
            finally {
                $script:OverridesDir = $oldOverridesDir
            }
        }

        It "Captures MCP activation fields in the installed audit snapshot" {
            $cfg = [pscustomobject]@{
                mcp_servers = @([pscustomobject]@{
                        name          = "context7"
                        transport     = "stdio"
                        command       = "npx"
                        args          = @("-y", "@upstash/context7-mcp")
                        enabled       = $false
                        enabled_tools = @("query-docs", "resolve-library-id")
                    })
            }

            $facts = @(Get-AuditMcpServerFacts $cfg)

            $facts.Count | Should -Be 1
            $facts[0].enabled | Should -Be $false
            @($facts[0].enabled_tools) | Should -Be @("query-docs", "resolve-library-id")
        }

        It "Distinguishes an absent MCP tool allowlist from an explicit empty allowlist" {
            $withoutAllowlist = @(Get-AuditMcpServerFacts ([pscustomobject]@{
                        mcp_servers = @([pscustomobject]@{
                                name      = "context7"
                                transport = "stdio"
                                command   = "npx"
                                args      = @("-y", "@upstash/context7-mcp")
                            })
                    }))
            $withEmptyAllowlist = @(Get-AuditMcpServerFacts ([pscustomobject]@{
                        mcp_servers = @([pscustomobject]@{
                                name          = "context7"
                                transport     = "stdio"
                                command       = "npx"
                                args          = @("-y", "@upstash/context7-mcp")
                                enabled_tools = @()
                            })
                    }))

            $withoutAllowlist[0].PSObject.Properties.Match("enabled_tools").Count | Should -Be 0
            $withEmptyAllowlist[0].PSObject.Properties.Match("enabled_tools").Count | Should -Be 1
            @($withEmptyAllowlist[0].enabled_tools).Count | Should -Be 0
        }

        It "Captures system and enabled plugin skills as read-only external facts" {
            $userRoot = Join-Path $TestDrive "external-user-skills"
            $systemDir = Join-Path $userRoot ".system\system-demo"
            $pluginRoot = Join-Path $TestDrive "external-plugin"
            $pluginDir = Join-Path $pluginRoot "skills\plugin-demo"
            New-Item -ItemType Directory -Path $systemDir, $pluginDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $systemDir "SKILL.md") "---`nname: system-demo`ndescription: System demo.`n---`n"
            Set-ContentUtf8 (Join-Path $pluginDir "SKILL.md") "---`nname: plugin-demo`ndescription: Plugin demo.`n---`n"
            Mock Invoke-CodexCliJson { [pscustomobject]@{ installed = @([pscustomobject]@{ pluginId='demo@market'; name='demo'; marketplaceName='market'; version='1.0.0'; installed=$true; enabled=$true; source=[pscustomobject]@{ path=$pluginRoot } }) } }
            $cfg = [pscustomobject]@{
                vendors = @()
                imports = @()
                mappings = @()
                mcp_servers = @()
                skill_projection = [pscustomobject]@{
                    user_skill_root = $userRoot
                    external_skill_inventory = [pscustomobject]@{ enabled = $true }
                }
            }

            $facts = @(Get-AuditExternalSkillFacts $cfg)

            $facts.Count | Should -Be 2
            @($facts | ForEach-Object source_kind | Sort-Object) -join "," | Should -Be "plugin,system"
            ($facts | Where-Object source_kind -eq "plugin").qualified_name | Should -Be "demo@market::plugin-demo"
        }

        It "Checks external capability drift only when the snapshot carries its fingerprint" {
            $live = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external-current" }
            $current = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external-current" }
            $stale = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external-old" }
            $legacy = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp" }

            (Get-AuditInstalledSnapshotStaleness $current $live).is_stale | Should -Be $false
            (Get-AuditInstalledSnapshotStaleness $stale $live).external_skill_stale | Should -Be $true
            (Get-AuditInstalledSnapshotStaleness $legacy $live).is_stale | Should -Be $false
        }

        It "Treats pre-existing host projection health as state, not snapshot drift" {
            $hostAtSnapshot = [pscustomobject]@{ status = "available"; managed_count = 9; stale_count = 1; broken_count = 0; fingerprint = "host-current" }
            $live = [pscustomobject]@{
                fingerprint = "skills"
                mcp_fingerprint = "mcp"
                external_skill_fingerprint = "external"
                host_projection = $hostAtSnapshot
            }
            $current = [pscustomobject]@{
                fingerprint = "skills"
                mcp_fingerprint = "mcp"
                external_skill_fingerprint = "external"
                host_projection = $hostAtSnapshot
            }
            $hostChanged = [pscustomobject]@{
                fingerprint = "skills"
                mcp_fingerprint = "mcp"
                external_skill_fingerprint = "external"
                host_projection = [pscustomobject]@{ status = "available"; managed_count = 9; stale_count = 1; broken_count = 0; fingerprint = "host-changed" }
            }

            (Get-AuditInstalledSnapshotStaleness $current $live).host_projection_stale | Should -Be $false
            (Get-AuditInstalledSnapshotStaleness $current $live).is_stale | Should -Be $false
            (Get-AuditInstalledSnapshotStaleness $current $hostChanged).host_projection_stale | Should -Be $true
        }

        It "Rejects a missing snapshot instead of substituting live state" {
            $path = Join-Path $TestDrive "missing-snapshot.json"

            { Get-AuditInstalledSnapshotState $path | Out-Null } | Should -Throw "*缺少 snapshot.json*"
        }
    }

    Context "Recommendations" {
        It "Documents audit entry in help source" {
            $raw = Get-Content -LiteralPath (Join-Path $script:Root "src/Commands/Utils.ps1") -Raw
            $menuBody = Get-FunctionBody $raw "菜单"
            $menuBody | Should -Match "7\) 目标仓审查"
        }

        It "Returns a built-in prompt with the guarded recommendation workflow" {
            $prompt = Get-AuditOuterAiPromptContent
            $prompt | Should -Not -BeNullOrEmpty
            $prompt | Should -Match 'reports[\\/]skill-audit[\\/]<run-id>[\\/]recommendations\.json'
            $prompt | Should -Match "snapshot.json"
            $prompt | Should -Match "recommendations.json"
            $prompt | Should -Match ([regex]::Escape("--dry-run-ack"))
            $prompt | Should -Match ([regex]::Escape("--apply --yes"))
        }

        It "Builds a loadable zero-change recommendations baseline" {
            $template = New-AuditRecommendationsTemplate "r1" "demo"
            $path = Join-Path $TestDrive "recommendations-zero-change.json"
            Write-AuditJsonFile $path $template
            $rec = Load-AuditRecommendations $path

            $rec.schema_version | Should -Be 3
            $rec.recommendation_mode | Should -Be "target-repo"
            $rec.decision_basis.target_scan_used | Should -Be $true
            $rec.decision_basis.summary | Should -Match "no skill or MCP lifecycle change"
            @($rec.source_observations).Count | Should -Be 0
            @($rec.new_skills).Count | Should -Be 0
            @($rec.removal_candidates).Count | Should -Be 0
            @($rec.mcp_new_servers).Count | Should -Be 0
            @($rec.mcp_removal_candidates).Count | Should -Be 0
            @($rec.empty_recommendation_reasons) | Should -Be @("no_lifecycle_change_without_invocation_or_reachability_evidence")
            (Test-AuditPlaceholderToken ($template | ConvertTo-Json -Depth 20)) | Should -BeFalse
        }

        It "Builds profile-only recommendations template with target_scan_used false" -Skip {
            $template = New-AuditRecommendationsTemplate "r1" "profile-only" "profile-only" "powershell testing"

            $template.recommendation_mode | Should -Be "profile-only"
            $template.discovery_query | Should -Be "powershell testing"
            $template.decision_basis.target_scan_used | Should -Be $false
            $template.new_skills[0].reason_target_repo | Should -Match "profile-only"
        }

        It "Builds source strategy with default discovery sources" {
            $strategy = New-AuditSourceStrategy "target-repo" ""

            $strategy.mode | Should -Be "target-repo"
            $strategy.query | Should -Be ""
            @($strategy.sources | Where-Object { $_.id -eq "official-docs" }).Count | Should -Be 1
            @($strategy.sources | Where-Object { $_.id -eq "mcp-provider-docs" }).Count | Should -Be 1
            @($strategy.sources | Where-Object { $_.id -eq "skills-sh" }).Count | Should -Be 1
            @($strategy.sources | Where-Object { $_.id -eq "security-and-permission-notes" }).Count | Should -Be 1
            @($strategy.sources | Where-Object { $_.id -eq "find-skills" }).Count | Should -Be 1
            $strategy.evidence_policy.min_unique_sources_for_changes | Should -Be 1
            $strategy.evidence_policy.require_http_source_for_changes | Should -Be $false
            $strategy.evidence_policy.require_source_observations_for_changes | Should -Be $true
            $strategy.decision_quality_policy.require_keyword_trace_for_changes | Should -Be $true
            $strategy.decision_quality_policy.require_keyword_trace_membership | Should -Be $true
            $strategy.decision_quality_policy.min_target_profile_keywords_per_change | Should -Be 0
            $strategy.decision_quality_policy.min_target_repo_keywords_per_change | Should -Be 0
            $strategy.decision_quality_policy.min_installed_state_keywords_per_change | Should -Be 0
        }

        It "Applies source-strategy override from overrides directory" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-source-strategy-override"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $script:Root "overrides") -Force | Out-Null
                Set-ContentUtf8 (Join-Path $script:Root "overrides\audit-source-strategy.json") @'
{
  "all": {
    "evidence_policy": {
      "min_unique_sources_for_changes": 3
    }
  },
  "target-repo": {
    "decision_quality_policy": {
      "min_target_repo_keywords_per_change": 0
    }
  }
}
'@
                $strategy = New-AuditSourceStrategy "target-repo" ""
                $strategy.evidence_policy.min_unique_sources_for_changes | Should -Be 3
                $strategy.decision_quality_policy.min_target_repo_keywords_per_change | Should -Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Adds default empty recommendation reason code when all categories are empty" {
            $path = Join-Path $TestDrive "recommendations-empty-reasons.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-empty","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            $rec = Load-AuditRecommendations $path

            @($rec.empty_recommendation_reasons).Count | Should -Be 1
            $rec.empty_recommendation_reasons[0] | Should -Be "insufficient_reliable_evidence"
        }

        It "Validates and normalizes structured overlap routing" {
            $path = Join-Path $TestDrive "recommendations-overlap-routing.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-overlap","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[{"name":"ppt stack","reason_target_profile":"courseware","sources":["https://example.com/ppt"],"note":"router plus executor","source_preference":{"plugin_installed":true,"standalone_duplicate":true,"native_source_preferred":true,"action":"report_only_do_not_import_duplicate"},"routing":{"router":"teacher-ppt","selection_policy":"router first","members":[{"name":"teacher-ppt","role":"ROUTER"},{"name":"presentations","role":"executor"}]}}],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            $rec = Load-AuditRecommendations $path

            $rec.overlap_findings[0].routing.members[0].role | Should -Be "router"
            @($rec.overlap_findings[0].sources).Count | Should -Be 1
            $rec.overlap_findings[0].source_preference.native_source_preferred | Should -BeTrue
        }

        It "Rejects structured overlap routing when the declared router is not a router member" {
            $path = Join-Path $TestDrive "recommendations-overlap-invalid-router.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-overlap-invalid-router","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[{"name":"ppt stack","reason_target_profile":"courseware","sources":["https://example.com/ppt"],"note":"router plus executor","routing":{"router":"presentations","selection_policy":"router first","members":[{"name":"teacher-ppt","role":"router"},{"name":"presentations","role":"executor"}]}}],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            { Load-AuditRecommendations $path } | Should -Throw
        }

        It "Rejects overlap findings without a report note" {
            $path = Join-Path $TestDrive "recommendations-overlap-no-note.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-overlap-invalid","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[{"name":"ppt stack","reason_target_profile":"courseware","sources":["https://example.com/ppt"]}],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            { Load-AuditRecommendations $path } | Should -Throw
        }

        It "Rejects missing recommendations file" {
            $thrown = $false
            try {
                Load-AuditRecommendations (Join-Path $TestDrive "missing.json") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects duplicate repo skill mode entries" {
            $path = Join-Path $TestDrive "recommendations.json"
            Set-Content -Path $path -Value '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u1","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["local"]},{"name":"a2","reason_target_profile":"u2","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects recommendation without explicit skill path" {
            $path = Join-Path $TestDrive "recommendations-missing-skill.json"
            Set-Content -Path $path -Value '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects recommendations without decision_basis for user profile and target scan" {
            $path = Join-Path $TestDrive "recommendations-no-basis.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects non-boolean decision_basis flags" {
            $path = Join-Path $TestDrive "recommendations-invalid-basis-types.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":"true","target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "decision_basis.target_profile_used"
            }
            $thrown | Should -Be $true
        }

        It "Allows profile-only recommendations when target_scan_used is false" -Skip {
            $path = Join-Path $TestDrive "recommendations-profile-only.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"profile-only","recommendation_mode":"profile-only","decision_basis":{"target_profile_used":true,"target_scan_used":false,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["https://example.com/a"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path

            $rec.recommendation_mode | Should -Be "profile-only"
            $rec.decision_basis.target_scan_used | Should -Be $false
        }

        It "Rejects profile-only recommendations when target_scan_used is true" -Skip {
            $path = Join-Path $TestDrive "recommendations-profile-only-invalid.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"profile-only","recommendation_mode":"profile-only","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "profile-only"
            }
            $thrown | Should -Be $true
        }

        It "Normalizes recommendation sources by trimming and de-duplicating" {
            $path = Join-Path $TestDrive "recommendations-source-normalize.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["  https://example.com/a  ","https://example.com/a",""]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path
            @($rec.new_skills[0].sources).Count | Should -Be 1
            $rec.new_skills[0].sources[0] | Should -Be "https://example.com/a"
        }

        It "Rejects recommendations when sources are blank-only" {
            $path = Join-Path $TestDrive "recommendations-source-empty.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["   ",""]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "source"
            }
            $thrown | Should -Be $true
        }

        It "Rejects a removal candidate that only infers non-use from the target profile" {
            $path = Join-Path $TestDrive "recommendations-removal.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[{"name":"old-skill","reason_target_profile":"user no longer needs it","sources":["https://example.com"],"installed":{"vendor":"manual","from":"old-skill"}}],"do_not_install":[]}'

            { Load-AuditRecommendations $path } | Should -Throw '*缺少 semantic_review*'
        }

        It "Calculates per-change source-observation and HTTP coverage" {
            $rec = [pscustomobject]@{
                new_skills = @([pscustomobject]@{ name = "skill-a"; sources = @("https://example.com/skill-a") })
                removal_candidates = @()
                mcp_new_servers = @()
                mcp_removal_candidates = @()
                source_observations = @([pscustomobject]@{ source = "https://example.com/skill-a"; summary = "Documents the supported skill trigger." })
            }

            $coverage = Get-AuditRecommendationSourceCoverage $rec

            $coverage.unique_source_count | Should -Be 1
            $coverage.http_source_count | Should -Be 1
            $coverage.source_observation_count | Should -Be 1
            $coverage.items_with_source_observation | Should -Be 1
            @($coverage.change_items_missing_source_observation).Count | Should -Be 0

            $rec.source_observations = @()
            $policy = [pscustomobject]@{ enabled = $true; min_unique_sources_for_changes = 1; require_http_source_for_changes = $false; require_source_observations_for_changes = $true }
            $check = Test-AuditRecommendationSourceCoveragePolicy $rec $policy
            $check.pass | Should -Be $false
            @($check.issues) | Should -Match "source_observations"
        }

        It "Preserves keyword trace from recommendations in supported change plan categories" {
            $path = Join-Path $TestDrive "recommendations-keyword-trace.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"add-skill","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["local"],"keyword_trace":{"target_profile":["ai/content_generation"],"target_repo":["demo"],"installed_state":["add-skill"]}}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[{"name":"new-mcp","reason_target_profile":"u","confidence":"medium","sources":["local"],"server":{"name":"new-mcp","transport":"stdio","command":"node","args":[]},"keyword_trace":{"target_profile":["ai/content_generation"],"target_repo":["demo"],"installed_state":["new-mcp"]}}],"mcp_removal_candidates":[]}'
            $cfg = [pscustomobject]@{ vendors=@(); targets=@(); mappings=@(); imports=@(); mcp_servers=@(); mcp_targets=@(); update_force=$false; sync_mode="sync" }

            $plan = New-AuditInstallPlan (Load-AuditRecommendations $path) $cfg

            $plan.items[0].keyword_trace.target_profile[0] | Should -Be "ai/content_generation"
            $plan.mcp_items[0].keyword_trace.target_repo[0] | Should -Be "demo"
        }

        It "Supports MCP add recommendations in plan output" {
            $path = Join-Path $TestDrive "recommendations-mcp.json"
            Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[{"name":"context7","reason_target_profile":"u","confidence":"high","sources":["https://example.com/context7"],"server":{"name":"context7","transport":"stdio","command":"npx","args":["-y","@upstash/context7-mcp"]}}],"mcp_removal_candidates":[]}'

            $cfg = [pscustomobject]@{
                vendors = @()
                targets = @()
                mappings = @()
                imports = @()
                mcp_servers = @(
                    [pscustomobject]@{
                        name = "legacy-fetch"
                        transport = "stdio"
                        command = "node"
                        args = @("server.js")
                    }
                )
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }

            $rec = Load-AuditRecommendations $path
            $plan = New-AuditInstallPlan $rec $cfg

            @($plan.mcp_items).Count | Should -Be 1
            $plan.mcp_items[0].status | Should -Be "planned"
            @($plan.mcp_removal_candidates).Count | Should -Be 0
        }

        It "Builds install plan without modifying config" {
            $path = Join-Path $TestDrive "recommendations-ok.json"
            Set-Content -Path $path -Value '{"schema_version":3,"run_id":"r1","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"user likes deterministic docs","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path
            $plan = New-AuditInstallPlan $rec

            @($plan.items).Count | Should -Be 1
            $plan.items[0].reason_target_profile | Should -Be "user likes deterministic docs"
            $plan.items[0].tokens[0] | Should -Be "owner/repo"
            (@($plan.items[0].tokens) -contains "--skill") | Should -Be $true
            (@($plan.items[0].tokens) -contains "skills\a") | Should -Be $true
        }

        It "Records dry-run persisted state and requires acknowledgment token" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-dryrun-ack"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                $path = Join-Path $script:Root "recommendations-dryrun-ack.json"
                Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-dry","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'
                New-TestAuditSnapshot (Join-Path $script:Root "snapshot.json") "r-dry"

                $report = Invoke-AuditRecommendationsApply -RecommendationsPath $path -DryRunAck "我知道未落盘"

                $report.success | Should -Be $true
                $report.mode | Should -Be "dry_run"
                $report.persisted | Should -Be $false
                $report.changed_counts.add_planned | Should -Be 1
                $report.changed_counts.add_installed | Should -Be 0
                $report.dry_run_acknowledged | Should -Be $true
                Test-Path -LiteralPath (Get-AuditDryRunSummaryPath $path) | Should -Be $true
                $summaryRaw = Get-ContentUtf8 (Get-AuditDryRunSummaryPath $path)
                $summaryRaw | Should -Match '"source_observations":\s*\[\]'
                @(Get-ChildItem -LiteralPath $script:Root -File).Name | Should -Not -Match '^runtime-evidence-'
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Preserves explicit original indexes in the machine-readable dry-run summary" {
            $plan = [pscustomobject]([ordered]@{
                run_id = "r-original-index"
                target = "demo"
                decision_basis = [pscustomobject]@{ summary = "index contract" }
                empty_recommendation_reasons = @()
                source_observations = @()
                items = @([pscustomobject]@{
                    original_index = 4
                    name = "skill-four"
                    reason_target_profile = "u"
                    sources = @("local")
                    keyword_trace = $null
                    status = "planned"
                })
                removal_candidates = @([pscustomobject]@{
                    original_index = 3
                    name = "remove-three"
                    vendor = "manual"
                    from = "remove-three"
                    reason_target_profile = "u"
                    sources = @("local")
                    keyword_trace = $null
                    status = "planned"
                })
                mcp_items = @([pscustomobject]@{
                    original_index = 2
                    name = "mcp-two"
                    reason_target_profile = "u"
                    sources = @("local")
                    keyword_trace = $null
                    status = "planned"
                })
                mcp_removal_candidates = @([pscustomobject]@{
                    original_index = 5
                    name = "mcp-remove-five"
                    installed_name = "mcp-remove-five"
                    reason_target_profile = "u"
                    sources = @("local")
                    keyword_trace = $null
                    status = "planned"
                })
            })

            $summary = New-AuditDryRunSummary $plan "recommendations.json"

            $summary.add[0].index | Should -Be 4
            $summary.add[0].original_index | Should -Be 4
            $summary.remove[0].index | Should -Be 3
            $summary.mcp_add[0].index | Should -Be 2
            $summary.mcp_remove[0].index | Should -Be 5
        }

        It "Treats --apply --yes as all selections when indexes are omitted" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-apply-yes-all"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null

                $path = Join-Path $script:Root "recommendations-apply-yes.json"
                Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-apply","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[{"name":"playwright","reason_target_profile":"u","confidence":"medium","sources":["local"],"server":{"name":"playwright","transport":"stdio","command":"npx","args":["@playwright/mcp@latest"]}}],"mcp_removal_candidates":[]}'
                New-TestAuditSnapshot (Join-Path $script:Root "snapshot.json") "r-apply"

                Mock Add-ImportFromArgs { return $true }
                Mock Ensure-AuditNewManualImportsMapped { return $true }
                Mock Apply-AuditMcpSelections {
                    foreach ($item in @($selectedAddItems)) { $item.status = "added" }
                    return [pscustomobject]@{ changed = $true }
                }
                Mock 构建生效 { }
                Mock Invoke-Doctor { return [pscustomobject]@{ pass = $true } }
                New-AuditValidatedWorkflowReceiptFixture $path

                $report = Invoke-AuditRecommendationsApply -RecommendationsPath $path -Apply -Yes

                $report.success | Should -Be $true
                $report.persisted | Should -Be $true
                $report.changed_counts.add_installed | Should -Be 1
                $report.changed_counts.mcp_add_added | Should -Be 1
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks dry-run on a stale snapshot without an override path" {
            $oldRoot = $script:Root
            try {
                $root = Join-Path $TestDrive "ws-stale-apply-block"
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                $script:Root = $root
                $path = Join-Path $root "recommendations.json"
                Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-stale-apply","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
                $installedState = [pscustomobject]@{
                    snapshot_kind = "audit_input"; captured_at = (Get-Date).ToString("o")
                    live_fingerprint = "deadbeef"; live_external_skill_fingerprint = "unit-empty-external-skills"; live_mcp_fingerprint = "deadbeef"
                    skills = @(); external_skills = @(); mcp_servers = @(); host_projection = $null
                }
                New-TestAuditSnapshot (Join-Path $root "snapshot.json") "r-stale-apply" $installedState

                { Invoke-AuditRecommendationsApply -RecommendationsPath $path -DryRunAck "我知道未落盘" } | Should -Throw "*stale_snapshot*"

                $report = (Get-ContentUtf8 (Get-AuditReceiptPath $path) | ConvertFrom-Json).dry_run
                $report.error_code | Should -Be "stale_snapshot"
                $report.persisted | Should -BeFalse
                $report.allow_stale_snapshot | Should -BeNullOrEmpty
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Preflight passes when snapshot and prompt contract are aligned" {
            $runId = "r-preflight-ok"
            $runDir = Join-Path $TestDrive $runId
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null

            $recPath = Join-Path $runDir "recommendations.json"
            Set-ContentUtf8 $recPath '{"schema_version":3,"run_id":"r-preflight-ok","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            New-TestAuditSnapshot (Join-Path $runDir "snapshot.json") $runId

            $report = Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath
            $receipt = Get-ContentUtf8 (Join-Path $runDir "receipt.json") | ConvertFrom-Json
            $report.success | Should -Be $true
            $report.prompt_contract.matched | Should -Be $true
            $receipt.preflight.success | Should -Be $true
        }

        It "Preflight blocks stale snapshot before dry-run" {
            $runId = "r-preflight-stale"
            $runDir = Join-Path $TestDrive $runId
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null

            $recPath = Join-Path $runDir "recommendations.json"
            Set-ContentUtf8 $recPath '{"schema_version":3,"run_id":"r-preflight-stale","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
            $installedState = [pscustomobject]@{
                snapshot_kind = "audit_input"; captured_at = (Get-Date).ToString("o")
                live_fingerprint = "deadbeef"; live_external_skill_fingerprint = "unit-empty-external-skills"; live_mcp_fingerprint = "deadbeef"
                skills = @(); external_skills = @(); mcp_servers = @(); host_projection = $null
            }
            New-TestAuditSnapshot (Join-Path $runDir "snapshot.json") $runId $installedState

            $thrown = $false
            try {
                Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "stale_snapshot"
            }
            $thrown | Should -Be $true
            $receipt = Get-ContentUtf8 (Join-Path $runDir "receipt.json") | ConvertFrom-Json
            $receipt.preflight.error_code | Should -Be "stale_snapshot"
        }

        It "Preflight by run-id reads the complete three-file bundle" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-preflight-bundle"
                $runId = "r-preflight-bundle"
                $runDir = Join-Path $script:Root (Join-Path "reports\skill-audit" $runId)
                New-Item -ItemType Directory -Path $runDir -Force | Out-Null

                New-TestAuditSnapshot (Join-Path $runDir "snapshot.json") $runId
                Set-ContentUtf8 (Join-Path $runDir "recommendations.json") '{"schema_version":3,"run_id":"r-preflight-bundle","target":"*","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"no changes"},"source_observations":[],"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[],"empty_recommendation_reasons":["new_skills: no gap","removal_candidates: no removal","mcp_new_servers: no gap","mcp_removal_candidates: no removal"]}'
                Write-AuditJsonFile (Join-Path $runDir "receipt.json") ([pscustomobject]@{ schema_version=1; run_id=$runId; success=$true; persisted=$false })

                $report = Invoke-AuditRecommendationsPreflight -RunId $runId

                $report.success | Should -Be $true
                $report.preflight_mode | Should -Be "recommendations"
                $report.recommendations_exists | Should -Be $true
                $report.run_id | Should -Be $runId
                (Get-ContentUtf8 (Join-Path $runDir "receipt.json") | ConvertFrom-Json).preflight.success | Should -Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Preflight resolves run-id placeholders to the latest run directory" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-preflight-placeholder"
                $auditRoot = Join-Path $script:Root "reports\skill-audit"
                $runOld = Join-Path $auditRoot "r-old"
                $runNew = Join-Path $auditRoot "r-new"
                New-Item -ItemType Directory -Path $runOld -Force | Out-Null
                New-Item -ItemType Directory -Path $runNew -Force | Out-Null
                New-TestAuditSnapshot (Join-Path $runOld "snapshot.json") "r-old"
                New-TestAuditSnapshot (Join-Path $runNew "snapshot.json") "r-new"
                Write-AuditJsonFile (Join-Path $runOld "recommendations.json") (New-AuditRecommendationsTemplate "r-old" "*")
                Write-AuditJsonFile (Join-Path $runNew "recommendations.json") (New-AuditRecommendationsTemplate "r-new" "*")
                Write-AuditJsonFile (Join-Path $runOld "receipt.json") ([pscustomobject]@{ schema_version=1; run_id="r-old" })
                Write-AuditJsonFile (Join-Path $runNew "receipt.json") ([pscustomobject]@{ schema_version=1; run_id="r-new" })
                (Get-Item $runOld).LastWriteTimeUtc = [datetime]"2026-01-01T00:00:00Z"
                (Get-Item $runNew).LastWriteTimeUtc = [datetime]"2026-01-02T00:00:00Z"

                $resolvedByRunId = Resolve-AuditRecommendationsPathForPreflight "" "<run-id>"
                $resolvedByPath = Resolve-AuditRecommendationsPathForPreflight "reports/skill-audit/<run-id>/recommendations.json" ""

                $resolvedByRunId | Should -Be (Join-Path $runNew "recommendations.json")
                $resolvedByPath | Should -Be (Join-Path $runNew "recommendations.json")
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks direct apply when no validated dry-run workflow receipt exists" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-apply-receipt-required"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                $path = Join-Path $script:Root "recommendations.json"
                Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-receipt","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
                New-TestAuditSnapshot (Join-Path $script:Root "snapshot.json") "r-receipt"

                $thrown = $false
                try { Invoke-AuditRecommendationsApply -RecommendationsPath $path -Apply -Yes | Out-Null }
                catch { $thrown = $true; $_.Exception.Message | Should -Match 'validated_dry_run_required' }
                $thrown | Should -Be $true
            }
            finally { $script:Root = $oldRoot }
        }

        It "Restores managed config and projections when MCP fails after a skill write" {
            $oldRoot = $script:Root
            $oldCfgPath = $script:CfgPath
            try {
                $script:Root = Join-Path $TestDrive "ws-apply-transaction"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                $script:CfgPath = Join-Path $script:Root 'skills.json'
                $CfgPath = $script:CfgPath
                $fixtureCfgPath = $CfgPath
                $initial = '{"schema_version":1,"imports":[],"mappings":[],"mcp_servers":[]}'
                Set-ContentUtf8 $script:CfgPath $initial
                $path = Join-Path $script:Root "recommendations.json"
                Set-ContentUtf8 $path '{"schema_version":3,"run_id":"r-transaction","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_target_profile":"u","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[{"name":"playwright","reason_target_profile":"u","confidence":"medium","sources":["local"],"server":{"name":"playwright","transport":"stdio","command":"npx","args":["@playwright/mcp@latest"]}}],"mcp_removal_candidates":[]}'
                New-TestAuditSnapshot (Join-Path $script:Root "snapshot.json") "r-transaction"
                New-AuditValidatedWorkflowReceiptFixture $path

                Mock LoadCfg { return [pscustomobject]@{ imports=@(); mappings=@(); vendors=@(); mcp_servers=@() } }
                Mock Add-ImportFromArgs { Set-ContentUtf8 $fixtureCfgPath '{"mutated":"skill"}'; return $true }
                Mock Ensure-AuditNewManualImportsMapped { return $true }
                Mock Apply-AuditMcpSelections { Set-ContentUtf8 $fixtureCfgPath '{"mutated":"mcp"}'; throw 'mcp projection failed' }
                Mock 构建生效 { }
                Mock 同步MCP { }

                $thrown = $false
                try { Invoke-AuditRecommendationsApply -RecommendationsPath $path -Apply -Yes | Out-Null }
                catch { $thrown = $true; $_.Exception.Message | Should -Match 'mcp projection failed' }
                $thrown | Should -Be $true

                (Get-ContentUtf8 $script:CfgPath) | Should -Be $initial
                Should -Invoke 构建生效 -Times 1 -Exactly -Scope It
                Should -Invoke 同步MCP -Times 1 -Exactly -Scope It
                $saved = (Get-ContentUtf8 (Get-AuditReceiptPath $path) | ConvertFrom-Json).apply
                $saved.persisted | Should -Be $false
                $saved.compensation.status | Should -Be 'restored'
                $saved.items[0].status | Should -Be 'rolled_back'
            }
            finally {
                $script:Root = $oldRoot
                $script:CfgPath = $oldCfgPath
            }
        }

        It "Attempts MCP compensation even when skill projection compensation fails" {
            $oldCfgPath = $script:CfgPath
            try {
                $script:CfgPath = Join-Path $TestDrive 'transaction-independent-compensation.json'
                $CfgPath = $script:CfgPath
                Set-ContentUtf8 $script:CfgPath '{"before":true}'
                $snapshot = New-AuditApplyTransactionSnapshot
                Set-ContentUtf8 $script:CfgPath '{"after":true}'
                Mock 构建生效 { throw 'build restore failed' }
                Mock 同步MCP { }

                $result = Restore-AuditApplyTransaction -Snapshot $snapshot -SkillProjectionAttempted $true -McpProjectionAttempted $true

                (Get-ContentUtf8 $script:CfgPath) | Should -Be '{"before":true}'
                $result.status | Should -Be 'failed'
                $result.config_restored | Should -Be $true
                @($result.errors) -join '|' | Should -Match 'skill_projection_restore_failed'
                Should -Invoke 同步MCP -Times 1 -Exactly -Scope It
            }
            finally { $script:CfgPath = $oldCfgPath }
        }

        It "Runs validated dry-run in order and writes one fail-closed workflow report" {
            $runDir = Join-Path $TestDrive "r-validate-dry-run"
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null
            $recPath = Join-Path $runDir "recommendations.json"
            Set-ContentUtf8 $recPath '{"schema_version":3,"run_id":"r-validate-dry-run","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
            New-TestAuditSnapshot (Join-Path $runDir "snapshot.json") "r-validate-dry-run"

            Mock Invoke-AuditRecommendationsPreflight {
                return [pscustomobject]@{
                    success = $true
                    run_id = "r-validate-dry-run"
                    live_state = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external" }
                }
            }
            Mock Invoke-AuditRecommendationsApply {
                return [pscustomobject]@{
                    success = $true
                    persisted = $false
                    run_id = "r-validate-dry-run"
                    target = "demo"
                    changed_counts = New-AuditChangedCounts @() @()
                    snapshot_state = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external" }
                    live_state = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external" }
                    items = @()
                    removal_candidates = @()
                    mcp_items = @()
                    mcp_removal_candidates = @()
                    dry_run_summary_path = (Join-Path $runDir "receipt.json")
                }
            }

            $result = Invoke-AuditRecommendationsValidateDryRun -RecommendationsPath $recPath -DryRunAck "我知道未落盘"
            $saved = (Get-ContentUtf8 (Get-AuditWorkflowReportPath $recPath) | ConvertFrom-Json).workflow

            $result.success | Should -Be $true
            $result.persisted | Should -Be $false
            $saved.input_stability.matched | Should -Be $true
            $saved.stages.recommendations_validation.status | Should -Be "passed"
            $saved.stages.preflight.status | Should -Be "passed"
            $saved.stages.dry_run.status | Should -Be "passed"
            @($saved.categories).Count | Should -Be 4
            $saved.categories[0].key | Should -Be "add"
            $saved.categories[1].key | Should -Be "remove"
            $saved.categories[2].key | Should -Be "mcp_add"
            $saved.categories[3].key | Should -Be "mcp_remove"
            $saved.categories[0].empty_reason | Should -Not -BeNullOrEmpty
            $saved.categories[1].empty_reason | Should -Not -BeNullOrEmpty
            $saved.categories[2].empty_reason | Should -Not -BeNullOrEmpty
            $saved.categories[3].empty_reason | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-AuditRecommendationsPreflight -Times 1 -Exactly -Scope It
            Should -Invoke Invoke-AuditRecommendationsApply -Times 1 -Exactly -Scope It
        }

        It "Stops validated dry-run when preflight fails and records the failing stage" {
            $runDir = Join-Path $TestDrive "r-validate-preflight-failed"
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null
            $recPath = Join-Path $runDir "recommendations.json"
            Set-ContentUtf8 $recPath '{"schema_version":3,"run_id":"r-validate-preflight-failed","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
            New-TestAuditSnapshot (Join-Path $runDir "snapshot.json") "r-validate-preflight-failed"

            Mock Invoke-AuditRecommendationsPreflight { throw "预检失败：prompt_contract_mismatch" }
            Mock Invoke-AuditRecommendationsApply { throw "dry-run must not execute" }

            $thrown = $false
            try {
                Invoke-AuditRecommendationsValidateDryRun -RecommendationsPath $recPath -DryRunAck "我知道未落盘" | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "prompt_contract_mismatch"
            }

            $saved = (Get-ContentUtf8 (Get-AuditWorkflowReportPath $recPath) | ConvertFrom-Json).workflow
            $thrown | Should -Be $true
            $saved.success | Should -Be $false
            $saved.persisted | Should -Be $false
            $saved.error_code | Should -Be "prompt_contract_mismatch"
            $saved.failed_stage | Should -Be "preflight"
            $saved.stages.dry_run.status | Should -Be "not_run"
            Should -Invoke Invoke-AuditRecommendationsApply -Times 0 -Exactly -Scope It
        }

        It "Reports recommendations missing without pretending the command can generate AI decisions" {
            $runDir = Join-Path $TestDrive "r-recommendations-missing"
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null
            $recPath = Join-Path $runDir "recommendations.json"

            $thrown = $false
            try {
                Invoke-AuditRecommendationsValidateDryRun -RecommendationsPath $recPath -DryRunAck "我知道未落盘" | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "recommendations_missing"
            }

            $saved = (Get-ContentUtf8 (Get-AuditWorkflowReportPath $recPath) | ConvertFrom-Json).workflow
            $thrown | Should -Be $true
            $saved.error_code | Should -Be "recommendations_missing"
            $saved.failed_stage | Should -Be "recommendations_validation"
            $saved.next_command | Should -Match "snapshot.json"
            $saved.stages.preflight.status | Should -Be "not_run"
            $saved.stages.dry_run.status | Should -Be "not_run"
        }

        It "Stops before dry-run when a preflight input changes" {
            $runDir = Join-Path $TestDrive "r-workflow-input-changed"
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null
            $recPath = Join-Path $runDir "recommendations.json"
            Set-ContentUtf8 $recPath '{"schema_version":3,"run_id":"r-workflow-input-changed","target":"demo","decision_basis":{"target_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
            New-TestAuditSnapshot (Join-Path $runDir "snapshot.json") "r-workflow-input-changed"

            Mock Invoke-AuditRecommendationsPreflight {
                $snapshot = Get-ContentUtf8 (Join-Path $runDir "snapshot.json") | ConvertFrom-Json
                $snapshot | Add-Member -NotePropertyName test_mutation -NotePropertyValue $true -Force
                Write-AuditJsonFile (Join-Path $runDir "snapshot.json") $snapshot
                return [pscustomobject]@{
                    success = $true
                    run_id = "r-workflow-input-changed"
                    live_state = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external" }
                }
            }
            Mock Invoke-AuditRecommendationsApply { throw "dry-run must not execute" }

            $thrown = $false
            try {
                Invoke-AuditRecommendationsValidateDryRun -RecommendationsPath $recPath -DryRunAck "我知道未落盘" | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "workflow_input_changed"
            }

            $saved = (Get-ContentUtf8 (Get-AuditWorkflowReportPath $recPath) | ConvertFrom-Json).workflow
            $thrown | Should -Be $true
            $saved.error_code | Should -Be "workflow_input_changed"
            $saved.failed_stage | Should -Be "input_stability"
            $saved.input_stability.preflight_matched | Should -Be $false
            $saved.stages.dry_run.status | Should -Be "not_run"
            Should -Invoke Invoke-AuditRecommendationsApply -Times 0 -Exactly -Scope It
        }
    }
}
