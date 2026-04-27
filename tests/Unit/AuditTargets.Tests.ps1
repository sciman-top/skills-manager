# Dot-source the main script to load functions
. $PSScriptRoot\..\..\skills.ps1

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

Describe "Audit Targets" {
    Context "Target config" {
        It "Creates default audit target config without overwriting existing file" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-init"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                $path = Get-AuditTargetsConfigPath

                $created = Initialize-AuditTargetsConfig
                $created | Should Be $true
                (Test-Path $path) | Should Be $true

                $raw = Get-Content $path -Raw
                $raw | Should Match '"version"'
                $raw | Should Match '"targets"'

                $createdAgain = Initialize-AuditTargetsConfig
                $createdAgain | Should Be $false
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Creates audit-targets config with user_profile in version 2" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-v2-init"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null

                Initialize-AuditTargetsConfig | Out-Null
                $cfg = Load-AuditTargetsConfig

                $cfg.version | Should Be 2
                $cfg.user_profile | Should Not BeNullOrEmpty
                $cfg.user_profile.raw_text | Should Be ""
                $cfg.user_profile.summary | Should Be ""
                $cfg.user_profile.structured.primary_work_types.Count | Should Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Migrates version 1 audit config to version 2 with empty user_profile" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-audit-v1-migrate"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Set-ContentUtf8 (Join-Path $script:Root "audit-targets.json") '{"version":1,"path_base":"skills_manager_root","targets":[]}'

                $cfg = Load-AuditTargetsConfig

                $cfg.version | Should Be 2
                $cfg.user_profile.raw_text | Should Be ""
                $cfg.user_profile.summary | Should Be ""
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

                @($cfg.targets).Count | Should Be 1
                $cfg.targets[0].name | Should Be "my-repo"
                $cfg.targets[0].path | Should Be "..\my-repo"
                $cfg.targets[0].enabled | Should Be $true
                $cfg.targets[0].tags[0] | Should Be "typescript"
                $cfg.targets[0].notes | Should Be "demo notes"
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

                @($cfg.targets).Count | Should Be 1
                $cfg.targets[0].name | Should Be "demo"
                $cfg.targets[0].path | Should Be "..\demo-v2"
                $cfg.targets[0].tags[0] | Should Be "new"
                $cfg.targets[0].notes | Should Be "new notes"
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

                @($cfg.targets).Count | Should Be 1
                $cfg.targets[0].name | Should Be "demo-2"
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

                (Resolve-AuditTargetPath "..\target").StartsWith((Resolve-Path (Join-Path $script:Root "..")).Path) | Should Be $true
                Resolve-AuditTargetPath $script:Root | Should Be ([System.IO.Path]::GetFullPath($script:Root))
                (Resolve-AuditTargetPath "~").Length -gt 0 | Should Be $true
                Resolve-AuditTargetPath "%SKILLS_AUDIT_TEST_ROOT%\repo" | Should Be ([System.IO.Path]::GetFullPath((Join-Path $env:SKILLS_AUDIT_TEST_ROOT "repo")))
            }
            finally {
                $script:Root = $oldRoot
                $env:SKILLS_AUDIT_TEST_ROOT = $oldEnv
            }
        }
    }

    Context "Command parsing" {
        It "Parses init/profile/add/update/remove/list/scan/apply subcommands" {
            (Parse-AuditTargetsArgs @("init")).action | Should Be "init"
            (Parse-AuditTargetsArgs @("profile-set")).action | Should Be "profile_set"
            (Parse-AuditTargetsArgs @("profile-show")).action | Should Be "profile_show"
            (Parse-AuditTargetsArgs @("profile-structure")).action | Should Be "profile_structure"

            $add = Parse-AuditTargetsArgs @("add", "demo", "..\demo")
            $add.action | Should Be "add"
            $add.name | Should Be "demo"
            $add.path | Should Be "..\demo"

            $update = Parse-AuditTargetsArgs @("update", "demo", "..\demo-v2")
            $update.action | Should Be "update"
            $update.name | Should Be "demo"
            $update.path | Should Be "..\demo-v2"

            $remove = Parse-AuditTargetsArgs @("remove", "demo")
            $remove.action | Should Be "remove"
            $remove.name | Should Be "demo"

            (Parse-AuditTargetsArgs @("list")).action | Should Be "list"
            (Parse-AuditTargetsArgs @("scan", "--target", "demo")).target | Should Be "demo"
            $discover = Parse-AuditTargetsArgs @("discover-skills", "--query", "python testing")
            $discover.action | Should Be "discover_skills"
            $discover.query | Should Be "python testing"

            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes")
            $apply.action | Should Be "apply"
            $apply.recommendations | Should Be "r.json"
            $apply.apply | Should Be $true
            $apply.yes | Should Be $true

            $status = Parse-AuditTargetsArgs @("status")
            $status.action | Should Be "status"

            $preflight = Parse-AuditTargetsArgs @("preflight", "--run-id", "20260422-010101-001")
            $preflight.action | Should Be "preflight"
            $preflight.run_id | Should Be "20260422-010101-001"
        }

        It "Parses apply selection indexes for add and remove lists" {
            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes", "--add-indexes", "1,3", "--remove-indexes", "2", "--mcp-add-indexes", "1", "--mcp-remove-indexes", "2", "--dry-run-ack", "我知道未落盘")
            $apply.add_selection | Should Be "1,3"
            $apply.remove_selection | Should Be "2"
            $apply.mcp_add_selection | Should Be "1"
            $apply.mcp_remove_selection | Should Be "2"
            $apply.dry_run_ack | Should Be "我知道未落盘"
        }

        It "Parses apply-flow subcommand aliases" {
            $flow = Parse-AuditTargetsArgs @("apply-flow", "--recommendations", "r.json")
            $flow.action | Should Be "apply_flow"
            $flow.recommendations | Should Be "r.json"

            $flowCn = Parse-AuditTargetsArgs @("应用确认", "--recommendations", "r.json")
            $flowCn.action | Should Be "apply_flow"
            $flowCn.recommendations | Should Be "r.json"
        }

        It "Accepts Chinese subcommands" {
            (Parse-AuditTargetsArgs @("初始化")).action | Should Be "init"
            (Parse-AuditTargetsArgs @("需求设置")).action | Should Be "profile_set"
            (Parse-AuditTargetsArgs @("需求查看")).action | Should Be "profile_show"
            (Parse-AuditTargetsArgs @("需求结构化")).action | Should Be "profile_structure"
            (Parse-AuditTargetsArgs @("添加", "demo", "..\demo")).action | Should Be "add"
            (Parse-AuditTargetsArgs @("修改", "demo", "..\demo-v2")).action | Should Be "update"
            (Parse-AuditTargetsArgs @("删除", "demo")).action | Should Be "remove"
            (Parse-AuditTargetsArgs @("列表")).action | Should Be "list"
            (Parse-AuditTargetsArgs @("列出")).action | Should Be "list"
            (Parse-AuditTargetsArgs @("目标列表")).action | Should Be "list"
            (Parse-AuditTargetsArgs @("扫描")).action | Should Be "scan"
            (Parse-AuditTargetsArgs @("发现新技能")).action | Should Be "discover_skills"
            (Parse-AuditTargetsArgs @("状态")).action | Should Be "status"
            (Parse-AuditTargetsArgs @("预检", "--run-id", "demo-run")).action | Should Be "preflight"
            (Parse-AuditTargetsArgs @("应用确认", "--recommendations", "r.json")).action | Should Be "apply_flow"
            (Parse-AuditTargetsArgs @("应用", "--recommendations", "r.json")).action | Should Be "apply"
        }

        It "Auto-resolves <run-id> placeholder for --run-id and --recommendations" {
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
                Set-ContentUtf8 (Join-Path $runOld "installed-skills.json") ('{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"' + [string]$live.fingerprint + '","live_mcp_fingerprint":"' + [string]$live.mcp_fingerprint + '"}')
                Set-ContentUtf8 (Join-Path $runNew "installed-skills.json") ('{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"' + [string]$live.fingerprint + '","live_mcp_fingerprint":"' + [string]$live.mcp_fingerprint + '"}')
                Set-ContentUtf8 (Join-Path $runOld "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')
                Set-ContentUtf8 (Join-Path $runNew "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')
                (Get-Item $runOld).LastWriteTimeUtc = [datetime]"2026-01-01T00:00:00Z"
                (Get-Item $runNew).LastWriteTimeUtc = [datetime]"2026-01-02T00:00:00Z"

                $preflight = Parse-AuditTargetsArgs @("preflight", "--run-id", "<run-id>")
                $preflight.run_id | Should Be "r-new"

                $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "reports/skill-audit/<run-id>/recommendations.json")
                $apply.recommendations | Should Be "reports/skill-audit/r-new/recommendations.json"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Prefers latest fresh run over newer stale run when resolving <run-id>" {
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
                Set-ContentUtf8 (Join-Path $runFresh "installed-skills.json") ('{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"' + [string]$live.fingerprint + '","live_mcp_fingerprint":"' + [string]$live.mcp_fingerprint + '"}')
                Set-ContentUtf8 (Join-Path $runFresh "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')

                Set-ContentUtf8 (Join-Path $runStale "recommendations.json") '{}'
                Set-ContentUtf8 (Join-Path $runStale "installed-skills.json") '{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"deadbeef","live_mcp_fingerprint":"deadbeef"}'
                Set-ContentUtf8 (Join-Path $runStale "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')

                (Get-Item $runFresh).LastWriteTimeUtc = [datetime]"2026-01-01T00:00:00Z"
                (Get-Item $runStale).LastWriteTimeUtc = [datetime]"2026-01-02T00:00:00Z"

                $resolved = Resolve-AuditPathRunIdPlaceholder "reports/skill-audit/<run-id>/recommendations.json" "--recommendations" @("recommendations.json")
                $resolved | Should Be "reports/skill-audit/r-fresh/recommendations.json"
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
                Set-ContentUtf8 (Join-Path $runStale "installed-skills.json") '{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"deadbeef","live_mcp_fingerprint":"deadbeef"}'
                Set-ContentUtf8 (Join-Path $runStale "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')

                $thrown = $false
                try {
                    Resolve-AuditPathRunIdPlaceholder "reports/skill-audit/<run-id>/recommendations.json" "--recommendations" @("recommendations.json") | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should Match "未找到可用 run"
                    $_.Exception.Message | Should Match "stale run-id"
                    $_.Exception.Message | Should Match "先执行 .*审查目标 扫描"
                }
                $thrown | Should Be $true
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
                Set-ContentUtf8 (Join-Path $run "installed-skills.json") '{"schema_version":1,"skills":[],"mcp_servers":[]}'

                $thrown = $false
                try {
                    Resolve-AuditPathRunIdPlaceholder "reports/skill-audit/<run-id>/recommendations.json" "--recommendations" @("recommendations.json", "installed-skills.json", "audit-meta.json") | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should Match "先执行 .*审查目标 扫描"
                    $_.Exception.Message | Should Match "r-missing-meta"
                }
                $thrown | Should Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }
    }

    Context "Repository scan" {
        It "Saves raw user profile text and clears stale structured fields" {
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

                $saved.user_profile.raw_text | Should Match "multi-agent automation"
                $saved.user_profile.summary | Should Be ""
                $saved.user_profile.structured.primary_work_types.Count | Should Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Imports structured profile JSON from file" {
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

                $saved.user_profile.summary | Should Be "repo-governance focus"
                $saved.user_profile.structured.primary_work_types[0] | Should Be "repo-governance"
                $saved.user_profile.structured_by | Should Be "outer-ai"

                $snapshotPath = Join-Path $script:Root "reports\skill-audit\user-profile.json"
                (Test-Path -LiteralPath $snapshotPath) | Should Be $true
                $snapshot = Get-ContentUtf8 $snapshotPath | ConvertFrom-Json
                $snapshot.summary | Should Be "repo-governance focus"
                $snapshot.structured.primary_work_types[0] | Should Be "repo-governance"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Normalizes scalar structured fields into arrays during import" {
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

                @($saved.user_profile.structured.primary_work_types).Count | Should Be 1
                $saved.user_profile.structured.primary_work_types[0] | Should Be "repo-governance"
                @($saved.user_profile.structured.preferred_agents).Count | Should Be 1
                $saved.user_profile.structured.preferred_agents[0] | Should Be "codex"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Rejects structured profile when structured is not an object" {
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
                    $_.Exception.Message | Should Match "profile.structured"
                }
                $thrown | Should Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Imports structured profile from default path when profile is omitted" {
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

                $saved.user_profile.summary | Should Be "default-path profile"
                $saved.user_profile.structured.primary_work_types[0] | Should Be "repo-governance"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Creates structured profile draft at default path when no file exists" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-profile-default-draft"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null
                Set-AuditUserProfileRawText "I maintain repo governance workflows."

                Invoke-AuditStructuredProfileFlow ""
                $draftPath = Get-AuditStructuredProfileDefaultPath
                $draft = Get-Content -LiteralPath $draftPath -Raw | ConvertFrom-Json

                $draft.raw_text | Should Be "I maintain repo governance workflows."
                $draft.structured_by | Should Be "outer-ai"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks scan when user_profile.raw_text is missing" {
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
                $thrown | Should Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Auto-fills empty summary during profile precheck before scan" {
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
                $saved.user_profile.summary | Should Not Be ""
                $saved.user_profile.structured_by | Should Be "outer-ai"
                ([string]$saved.user_profile.last_structured_at).Length -gt 0 | Should Be $true

                $draftPath = Get-AuditStructuredProfileDefaultPath
                (Test-Path -LiteralPath $draftPath) | Should Be $true
                $draft = Get-ContentUtf8 $draftPath | ConvertFrom-Json
                $draft.summary | Should Not Be ""
                $draft.structured_by | Should Be "outer-ai"
                ([string]$draft.last_structured_at).Length -gt 0 | Should Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Fails scan when installed skill facts cannot be collected" {
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
                    $_.Exception.Message | Should Match "installed-skills.json"
                }
                $thrown | Should Be $true
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Generates a profile-only discovery bundle without repo scan files" {
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

                $result.mode | Should Be "profile-only"
                Test-Path (Join-Path $out "user-profile.json") | Should Be $true
                Test-Path (Join-Path $out "installed-skills.json") | Should Be $true
                Test-Path (Join-Path $out "source-strategy.json") | Should Be $true
                Test-Path (Join-Path $out "decision-insights.json") | Should Be $true
                Test-Path (Join-Path $out "recommendations.template.json") | Should Be $true
                Test-Path (Join-Path $out "ai-brief.md") | Should Be $true
                Test-Path (Join-Path $out "outer-ai-prompt.md") | Should Be $true
                Test-Path (Join-Path $out "audit-meta.json") | Should Be $true
                Test-Path (Join-Path $out "repo-scan.json") | Should Be $false
                Test-Path (Join-Path $out "repo-scans.json") | Should Be $false

                $template = Get-ContentUtf8 (Join-Path $out "recommendations.template.json") | ConvertFrom-Json
                $template.recommendation_mode | Should Be "profile-only"
                $template.decision_basis.target_scan_used | Should Be $false

                $meta = Get-ContentUtf8 (Join-Path $out "audit-meta.json") | ConvertFrom-Json
                $meta.mode | Should Be "profile-only"
                $meta.prompt_contract_version | Should Be (Get-AuditPromptContractVersion)

                $brief = Get-Content -LiteralPath (Join-Path $out "ai-brief.md") -Raw
                $brief | Should Match "profile-only skill discovery"
                $brief | Should Match "target_scan_used`` as boolean ``false``"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Fails when a required audit bundle file is missing" {
            $presentPath = Join-Path $TestDrive "audit-present.md"
            Set-ContentUtf8 $presentPath "ok"
            $missingPath = Join-Path $TestDrive "outer-ai-prompt.md"

            $thrown = $false
            try {
                Assert-AuditBundleRequiredFiles @(
                    [pscustomobject]@{ label = "ai-brief.md"; path = $presentPath }
                    [pscustomobject]@{ label = "outer-ai-prompt.md"; path = $missingPath }
                )
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "outer-ai-prompt.md"
            }
            $thrown | Should Be $true
        }

        It "Fails when required audit JSON exists but misses required fields" {
            $invalidProfile = Join-Path $TestDrive "user-profile.json"
            Set-ContentUtf8 $invalidProfile '{"schema_version":1,"summary":"missing raw text"}'

            $thrown = $false
            try {
                Assert-AuditBundleRequiredFiles @(
                    [pscustomobject]@{ label = "user-profile.json"; path = $invalidProfile }
                )
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "raw_text"
            }
            $thrown | Should Be $true
        }

        It "Generates run id with millisecond precision" {
            $runId = Get-AuditRunId
            $runId | Should Match "^\d{8}-\d{6}-\d{3}$"
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

            $scan.target.name | Should Be "demo"
            $scan.target.exists | Should Be $true
            $scan.git.is_repo | Should Be $true
            (@($scan.detected.package_managers) -contains "npm") | Should Be $true
            (@($scan.detected.frameworks) -contains "vite") | Should Be $true
            (@($scan.detected.frameworks) -contains "react") | Should Be $true
            (@($scan.detected.build_commands) -contains "npm run build") | Should Be $true
            (@($scan.detected.test_commands) -contains "npm test") | Should Be $true
            (@($scan.detected.agent_rule_files) -contains "AGENTS.md") | Should Be $true
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

            (@($scan.detected.languages) -contains "dotnet") | Should Be $true
            (@($scan.detected.languages) -contains "python") | Should Be $true
            (@($scan.detected.package_managers) -contains "nuget") | Should Be $true
            (@($scan.detected.package_managers) -contains "poetry") | Should Be $true
            (@($scan.detected.frameworks) -contains "aspnetcore") | Should Be $true
            (@($scan.detected.frameworks) -contains "efcore") | Should Be $true
            (@($scan.detected.build_commands) -contains "dotnet build") | Should Be $true
            (@($scan.detected.test_commands) -contains "dotnet test") | Should Be $true
            (@($scan.detected.test_commands) -contains "pytest") | Should Be $true
            (@($scan.detected.notable_files) | Where-Object { [string]$_ -match "ci\.yml$" }).Count -gt 0 | Should Be $true
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

            (@($scan.detected.languages) -contains "java") | Should Be $true
            (@($scan.detected.languages) -contains "ruby") | Should Be $true
            (@($scan.detected.languages) -contains "php") | Should Be $true
            (@($scan.detected.package_managers) -contains "maven") | Should Be $true
            (@($scan.detected.package_managers) -contains "bundler") | Should Be $true
            (@($scan.detected.package_managers) -contains "composer") | Should Be $true
            (@($scan.detected.frameworks) -contains "spring-boot") | Should Be $true
            (@($scan.detected.frameworks) -contains "rails") | Should Be $true
            (@($scan.detected.frameworks) -contains "laravel") | Should Be $true
            (@($scan.detected.frameworks) -contains "docker") | Should Be $true
            (@($scan.detected.frameworks) -contains "monorepo") | Should Be $true
            (@($scan.detected.build_commands) -contains "mvn -B -DskipTests package") | Should Be $true
            (@($scan.detected.test_commands) -contains "bundle exec rspec") | Should Be $true
            (@($scan.detected.test_commands) -contains "composer test") | Should Be $true
            (@($scan.detected.build_commands) -contains "make build") | Should Be $true
            (@($scan.detected.test_commands) -contains "make test") | Should Be $true
        }
    }

    Context "Installed skill facts" {
        It "Extracts declared name and description from installed manual skills" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports"
                New-Item -ItemType Directory -Path (Join-Path $script:ImportDir "demo-skill") -Force | Out-Null
                Set-Content -Path (Join-Path $script:ImportDir "demo-skill\SKILL.md") -Value "---`nname: demo-skill`ndescription: Demo description.`n---`nBody trigger text."
                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @([pscustomobject]@{ name = "demo-skill"; repo = "https://example.com/demo.git"; ref = "main"; skill = "."; mode = "manual" })
                    mappings = @([pscustomobject]@{ vendor = "manual"; from = "demo-skill"; to = "demo-skill" })
                }

                $facts = Get-InstalledSkillFacts $cfg

                @($facts).Count | Should Be 1
                $facts[0].declared_name | Should Be "demo-skill"
                $facts[0].description | Should Be "Demo description."
                $facts[0].source_kind | Should Be "manual"
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }
    }

    Context "Recommendations" {
        It "Documents audit entry in help source" {
            $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
            $menuBody = Get-FunctionBody $raw "菜单"
            $menuBody | Should Match "7\) 目标仓审查"
        }

        It "Documents audit prompt menu entries in help source" {
            $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
            $auditBody = Get-FunctionBody $raw "审查目标菜单"
            $targetAdminBody = Get-FunctionBody $raw "目标仓管理菜单"
            $advancedBody = Get-FunctionBody $raw "审查高级菜单"
            $auditBody | Should Match "=== 目标仓审查 ==="
            $auditBody | Should Match "流程：需求 -> 审查包 -> 预检 -> 应用"
            $auditBody | Should Match "5\) 预检建议"
            $auditBody | Should Match "6\) 应用建议（先 dry-run）"
            $auditBody | Should Match "8\) 发现新技能"
            $auditBody | Should Match "9\) 目标仓管理"
            $targetAdminBody | Should Match "4\) 删除目标仓"
            $advancedBody | Should Match "3\) 查看 AI 提示词"
            $advancedBody | Should Match "4\) 编辑 AI 提示词"
            $advancedBody | Should Match "5\) 直接执行建议（高级）"
        }

        It "Documents audit help source with self-check and prompt-source guidance" {
            $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
            $auditBody = Get-FunctionBody $raw "审查目标菜单"
            $raw | Should Match "先写完并自检 .*recommendations\.json"
            $raw | Should Match "不要直接手改 run 目录产物"
            $raw | Should Match "沿用原序号"
            $raw | Should Match "发现新技能.*profile-only"
            $auditBody | Should Not Match "17\) 审查目标（需求 / 目标仓 / 审查包 / 自检后 dry-run / 按原序号选择增删）"
            $auditBody | Should Match "4\) 生成审查包"
        }

        It "Documents audit runtime summary wording with original-index and empty-list guidance" {
            $raw = Get-Content -LiteralPath (Join-Path $Root "skills.ps1") -Raw
            $raw | Should Match "以下序号为原序号"
            $raw | Should Match "无新增建议："
            $raw | Should Match "无卸载建议："
            $raw | Should Match "dry-run 预览（沿用原序号）"
            $raw | Should Match "应用确认结束：dry-run 未完成确认"
        }

        It "Returns a built-in outer AI prompt" {
            $prompt = Get-AuditOuterAiPromptContent
            $prompt | Should Match "Outer AI Audit Prompt"
            $prompt | Should Match "recommendations.template.json"
            $prompt | Should Match "dry-run"
            $prompt | Should Match "do_not_install"
            $prompt | Should Match "N/A"
            $prompt | Should Match "installed-skills.json"
            $prompt | Should Match "name==server.name"
            $prompt | Should Match "预检"
            $prompt | Should Match "source_observations"
            $prompt | Should Match "不得把 dry-run 建议描述成已安装"
        }

        It "Keeps built-in prompt markdown inline code literal without control-character corruption" {
            $prompt = Get-AuditOuterAiPromptContent
            $prompt | Should Match '`reason_user_profile`'
            $prompt | Should Match '`reason_target_repo`'
            $prompt | Should Match "reports/skill-audit/<run-id>/recommendations.json"
            ($prompt.IndexOf([char]11) -lt 0) | Should Be $true
            $hasBareCr = $false
            for ($i = 0; $i -lt $prompt.Length; $i++) {
                if ($prompt[$i] -ne [char]13) { continue }
                if ($i + 1 -ge $prompt.Length -or $prompt[$i + 1] -ne [char]10) {
                    $hasBareCr = $true
                    break
                }
            }
            $hasBareCr | Should Be $false
        }

        It "Writes audit brief with explicit self-check and blocker guidance" {
            $path = Join-Path $TestDrive "ai-brief.md"
            $scanData = @([pscustomobject]@{
                target = [pscustomobject]@{
                    name = "demo"
                }
            })

            Write-AuditAiBrief $path $scanData "user-profile.json" "repo-scan.json" "repo-scans.json" "installed-skills.json" "recommendations.template.json"
            $brief = Get-Content -LiteralPath $path -Raw

            $brief | Should Match "Pre-dry-run self-check"
            $brief | Should Match "do_not_install"
            $brief | Should Match "Cite only sources you actually inspected during this run"
            $brief | Should Match "User-facing dry-run summary format"
            $brief | Should Match "Stop before dry-run if any self-check item fails"
            $brief | Should Match "installed-skills.json as the audit snapshot"
            $brief | Should Match "decision_basis.summary"
            $brief | Should Match "name == server.name"
            $brief | Should Match "No duplicate skill add/remove or MCP add/remove recommendations"
            $brief | Should Match "Decision insights JSON: N/A"
            $brief | Should Match "Only write ``recommendations.json``"
            $brief | Should Match "Execute preflight"
        }

        It "Writes profile-only audit brief with explicit target-scan false guidance" {
            $path = Join-Path $TestDrive "ai-brief-profile-only.md"

            Write-AuditAiBrief $path @() "user-profile.json" "" "" "installed-skills.json" "recommendations.template.json" "profile-only" "powershell testing" "source-strategy.json" "decision-insights.json"
            $brief = Get-Content -LiteralPath $path -Raw

            $brief | Should Match "profile-only skill discovery"
            $brief | Should Match "Discovery query: powershell testing"
            $brief | Should Match "target_scan_used`` as boolean ``false``"
            $brief | Should Match "Source strategy JSON: source-strategy.json"
            $brief | Should Match "Decision insights JSON: decision-insights.json"
            $brief | Should Match "Only write ``recommendations.json``"
            $brief | Should Match "Execute preflight"
        }

        It "Writes runtime outer AI prompt with blocker and summary format sections" {
            $path = Join-Path $TestDrive "outer-ai-prompt.md"
            $reportRoot = Join-Path $TestDrive "skill-audit-run"

            Write-AuditOuterAiPromptFile $path $reportRoot "ai-brief.md" "user-profile.json" "repo-scan.json" "repo-scans.json" "installed-skills.json" "recommendations.template.json"
            $prompt = Get-Content -LiteralPath $path -Raw

            $prompt | Should Match "## Blocking Conditions"
            $prompt | Should Match "do_not_install"
            $prompt | Should Match "无新增建议"
            $prompt | Should Match "install.mode"
            $prompt | Should Match "sources`` 只能填写本轮真实查看过的来源"
            $prompt | Should Match "ai-brief.md、user-profile.json、installed-skills.json"
            $prompt | Should Match "decision_basis.summary`` 非空"
            $prompt | Should Match "name`` 必须等于 ``server.name``"
            $prompt | Should Match "不得保留重复的技能新增/卸载建议或重复的 MCP 新增/卸载建议"
            $prompt | Should Match "决策洞察"
            $prompt | Should Match "执行预检"
            $prompt | Should Match "除 ``recommendations.json`` 外，不得修改本轮审查包输入文件"
        }

        It "Writes profile-only runtime outer AI prompt without requiring repo scan" {
            $path = Join-Path $TestDrive "outer-ai-prompt-profile-only.md"
            $reportRoot = Join-Path $TestDrive "skill-discovery-run"

            Write-AuditOuterAiPromptFile $path $reportRoot "ai-brief.md" "user-profile.json" "" "" "installed-skills.json" "recommendations.template.json" "profile-only" "powershell testing" "source-strategy.json" "decision-insights.json"
            $prompt = Get-Content -LiteralPath $path -Raw

            $prompt | Should Match "模式：profile-only"
            $prompt | Should Match "发现查询：powershell testing"
            $prompt | Should Match "target_scan_used`` 为 ``false``"
            $prompt | Should Match "不得编造目标仓事实"
            $prompt | Should Match "decision-insights.json"
            $prompt | Should Match "执行预检"
            $prompt | Should Match "这些文件只能读，不能改"
        }

        It "Builds recommendations template with placeholder examples" {
            $template = New-AuditRecommendationsTemplate "r1" "demo"

            $template.schema_version | Should Be 2
            $template.recommendation_mode | Should Be "target-repo"
            $template.decision_basis.target_scan_used | Should Be $true
            $template.new_skills[0].install.repo | Should Be "<owner/repo-or-local-path>"
            $template.removal_candidates[0].installed.vendor | Should Be "<installed-vendor>"
            $template.do_not_install[0].name | Should Be "<skill-not-recommended>"
            $template.source_observations[0].candidate_type | Should Be "skill"
            $template.source_observations[1].source_categories[0] | Should Be "mcp-provider-docs"
            $template.mcp_new_servers[0].server.transport | Should Be "stdio"
            $template.mcp_removal_candidates[0].installed.name | Should Be "<installed-mcp-name>"
        }

        It "Builds profile-only recommendations template with target_scan_used false" {
            $template = New-AuditRecommendationsTemplate "r1" "profile-only" "profile-only" "powershell testing"

            $template.recommendation_mode | Should Be "profile-only"
            $template.discovery_query | Should Be "powershell testing"
            $template.decision_basis.target_scan_used | Should Be $false
            $template.new_skills[0].reason_target_repo | Should Match "profile-only"
        }

        It "Builds source strategy with default discovery sources" {
            $strategy = New-AuditSourceStrategy "profile-only" "powershell testing"

            $strategy.mode | Should Be "profile-only"
            $strategy.query | Should Be "powershell testing"
            @($strategy.sources | Where-Object { $_.id -eq "official-docs" }).Count | Should Be 1
            @($strategy.sources | Where-Object { $_.id -eq "mcp-provider-docs" }).Count | Should Be 1
            @($strategy.sources | Where-Object { $_.id -eq "skills-sh" }).Count | Should Be 1
            @($strategy.sources | Where-Object { $_.id -eq "security-and-permission-notes" }).Count | Should Be 1
            @($strategy.sources | Where-Object { $_.id -eq "find-skills" }).Count | Should Be 1
            $strategy.evidence_policy.min_unique_sources_for_changes | Should Be 2
            $strategy.evidence_policy.require_http_source_for_changes | Should Be $true
            $strategy.evidence_policy.require_source_observations_for_changes | Should Be $true
            $strategy.decision_quality_policy.require_keyword_trace_for_changes | Should Be $true
            $strategy.decision_quality_policy.min_user_profile_keywords_per_change | Should Be 1
            $strategy.decision_quality_policy.min_target_repo_keywords_per_change | Should Be 1
            $strategy.decision_quality_policy.min_installed_state_keywords_per_change | Should Be 1
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
  "profile-only": {
    "decision_quality_policy": {
      "min_target_repo_keywords_per_change": 0
    }
  }
}
'@
                $strategy = New-AuditSourceStrategy "profile-only" "powershell testing"
                $strategy.evidence_policy.min_unique_sources_for_changes | Should Be 3
                $strategy.decision_quality_policy.min_target_repo_keywords_per_change | Should Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Adds default empty recommendation reason code when all categories are empty" {
            $path = Join-Path $TestDrive "recommendations-empty-reasons.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r-empty","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            $rec = Load-AuditRecommendations $path

            @($rec.empty_recommendation_reasons).Count | Should Be 1
            $rec.empty_recommendation_reasons[0] | Should Be "insufficient_reliable_evidence"
        }

        It "Rejects missing recommendations file" {
            $thrown = $false
            try {
                Load-AuditRecommendations (Join-Path $TestDrive "missing.json") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects duplicate repo skill mode entries" {
            $path = Join-Path $TestDrive "recommendations.json"
            Set-Content -Path $path -Value '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u1","reason_target_repo":"t1","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["local"]},{"name":"a2","reason_user_profile":"u2","reason_target_repo":"t2","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects recommendation without explicit skill path" {
            $path = Join-Path $TestDrive "recommendations-missing-skill.json"
            Set-Content -Path $path -Value '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects recommendations without decision_basis for user profile and target scan" {
            $path = Join-Path $TestDrive "recommendations-no-basis.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects non-boolean decision_basis flags" {
            $path = Join-Path $TestDrive "recommendations-invalid-basis-types.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":"true","target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "decision_basis.user_profile_used"
            }
            $thrown | Should Be $true
        }

        It "Allows profile-only recommendations when target_scan_used is false" {
            $path = Join-Path $TestDrive "recommendations-profile-only.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"profile-only","recommendation_mode":"profile-only","decision_basis":{"user_profile_used":true,"target_scan_used":false,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"installed inventory context","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["https://example.com/a"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path

            $rec.recommendation_mode | Should Be "profile-only"
            $rec.decision_basis.target_scan_used | Should Be $false
        }

        It "Normalizes source observations for audited candidates" {
            $path = Join-Path $TestDrive "recommendations-source-observations.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"source_observations":[{"candidate_type":"Skill","name":"a","decision":"install","rationale":"matches user and repo","sources":[" https://example.com/a ","https://example.com/a"],"source_categories":["official-docs","skills.sh"]}],"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path

            $rec.source_observations[0].candidate_type | Should Be "skill"
            $rec.source_observations[0].decision | Should Be "add"
            @($rec.source_observations[0].sources).Count | Should Be 1
            $rec.source_observations[0].sources[0] | Should Be "https://example.com/a"
        }

        It "Rejects profile-only recommendations when target_scan_used is true" {
            $path = Join-Path $TestDrive "recommendations-profile-only-invalid.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"profile-only","recommendation_mode":"profile-only","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "profile-only"
            }
            $thrown | Should Be $true
        }

        It "Normalizes recommendation sources by trimming and de-duplicating" {
            $path = Join-Path $TestDrive "recommendations-source-normalize.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["  https://example.com/a  ","https://example.com/a",""]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path
            @($rec.new_skills[0].sources).Count | Should Be 1
            $rec.new_skills[0].sources[0] | Should Be "https://example.com/a"
        }

        It "Rejects recommendations when sources are blank-only" {
            $path = Join-Path $TestDrive "recommendations-source-empty.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","mode":"manual"},"confidence":"high","sources":["   ",""]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $thrown = $false
            try {
                Load-AuditRecommendations $path | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "source"
            }
            $thrown | Should Be $true
        }

        It "Allows removal candidates but does not create uninstall plan items" {
            $path = Join-Path $TestDrive "recommendations-removal.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[{"name":"old-skill","reason_user_profile":"user no longer needs it","reason_target_repo":"repo stack no longer matches","sources":["https://example.com"],"installed":{"vendor":"manual","from":"old-skill"}}],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path
            $plan = New-AuditInstallPlan $rec

            @($plan.items).Count | Should Be 0
            @($plan.removal_candidates).Count | Should Be 1
        }

        It "Supports MCP add/remove recommendations in plan output" {
            $path = Join-Path $TestDrive "recommendations-mcp.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[{"name":"context7","reason_user_profile":"u","reason_target_repo":"t","confidence":"high","sources":["https://example.com/context7"],"server":{"name":"context7","transport":"stdio","command":"npx","args":["-y","@upstash/context7-mcp"]}}],"mcp_removal_candidates":[{"name":"legacy-fetch","reason_user_profile":"u2","reason_target_repo":"t2","sources":["https://example.com/legacy"],"installed":{"name":"legacy-fetch"}}]}'

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

            @($plan.mcp_items).Count | Should Be 1
            $plan.mcp_items[0].status | Should Be "planned"
            @($plan.mcp_removal_candidates).Count | Should Be 1
            $plan.mcp_removal_candidates[0].status | Should Be "planned"
        }

        It "Builds install plan without modifying config" {
            $path = Join-Path $TestDrive "recommendations-ok.json"
            Set-Content -Path $path -Value '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"user likes deterministic docs","reason_target_repo":"repo uses this stack","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $rec = Load-AuditRecommendations $path
            $plan = New-AuditInstallPlan $rec

            @($plan.items).Count | Should Be 1
            $plan.items[0].reason_user_profile | Should Be "user likes deterministic docs"
            $plan.items[0].reason_target_repo | Should Be "repo uses this stack"
            $plan.items[0].tokens[0] | Should Be "owner/repo"
            (@($plan.items[0].tokens) -contains "--skill") | Should Be $true
            (@($plan.items[0].tokens) -contains "skills\a") | Should Be $true
        }

        It "Records dry-run persisted state and requires acknowledgment token" {
            $path = Join-Path $TestDrive "recommendations-dryrun-ack.json"
            Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r-dry","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

            $report = Invoke-AuditRecommendationsApply -RecommendationsPath $path -DryRunAck "我知道未落盘"

            $report.success | Should Be $true
            $report.mode | Should Be "dry_run"
            $report.persisted | Should Be $false
            $report.changed_counts.add_planned | Should Be 1
            $report.changed_counts.add_installed | Should Be 0
            $report.dry_run_acknowledged | Should Be $true
            Test-Path (Get-AuditDryRunSummaryPath $path) | Should Be $true
        }

        It "Treats --apply --yes as all selections when indexes are omitted" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-apply-yes-all"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                Initialize-AuditTargetsConfig | Out-Null

                $path = Join-Path $script:Root "recommendations-apply-yes.json"
                Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r-apply","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[{"name":"playwright","reason_user_profile":"u","reason_target_repo":"t","confidence":"medium","sources":["local"],"server":{"name":"playwright","transport":"stdio","command":"npx","args":["@playwright/mcp@latest"]}}],"mcp_removal_candidates":[]}'

                Mock Add-ImportFromArgs { return $true }
                Mock Ensure-AuditNewManualImportsMapped { return $true }
                Mock Apply-AuditMcpSelections {
                    foreach ($item in @($selectedAddItems)) { $item.status = "added" }
                    return [pscustomobject]@{ changed = $true }
                }
                Mock 构建生效 { }
                Mock Invoke-Doctor { return [pscustomobject]@{ pass = $true } }

                $report = Invoke-AuditRecommendationsApply -RecommendationsPath $path -Apply -Yes

                $report.success | Should Be $true
                $report.persisted | Should Be $true
                $report.changed_counts.add_installed | Should Be 1
                $report.changed_counts.mcp_add_added | Should Be 1
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks dry-run when source evidence policy is not satisfied" {
            $oldRoot = $script:Root
            try {
                $root = Join-Path $TestDrive "ws-source-coverage-block"
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                $script:Root = $root
                $path = Join-Path $root "recommendations.json"
                Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r-source","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["local-only"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
                Set-ContentUtf8 (Join-Path $root "source-strategy.json") '{"schema_version":1,"mode":"target-repo","query":"","sources":[{"id":"official-docs"}],"evidence_policy":{"min_unique_sources_for_changes":2,"require_http_source_for_changes":true}}'

                $thrown = $false
                try {
                    Invoke-AuditRecommendationsApply -RecommendationsPath $path -DryRunAck "我知道未落盘" | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should Match "insufficient_source_coverage"
                }
                $thrown | Should Be $true

                $report = Get-ContentUtf8 (Get-AuditApplyReportPath $path) | ConvertFrom-Json
                $report.error_code | Should Be "insufficient_source_coverage"
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks dry-run when source observation policy is not satisfied" {
            $oldRoot = $script:Root
            try {
                $root = Join-Path $TestDrive "ws-source-observation-block"
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                $script:Root = $root
                $path = Join-Path $root "recommendations.json"
                Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r-source-observation","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"source_observations":[],"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["https://example.com/a"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
                Set-ContentUtf8 (Join-Path $root "source-strategy.json") '{"schema_version":1,"mode":"target-repo","query":"","sources":[{"id":"official-docs"}],"evidence_policy":{"min_unique_sources_for_changes":1,"require_http_source_for_changes":true,"require_source_observations_for_changes":true}}'

                $thrown = $false
                try {
                    Invoke-AuditRecommendationsApply -RecommendationsPath $path -DryRunAck "我知道未落盘" | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should Match "source_observations"
                }
                $thrown | Should Be $true

                $report = Get-ContentUtf8 (Get-AuditApplyReportPath $path) | ConvertFrom-Json
                $report.error_code | Should Be "insufficient_source_coverage"
                $report.source_coverage.items_with_source_observation | Should Be 0
            }
            finally {
                $script:Root = $oldRoot
            }
        }

        It "Blocks dry-run when decision-quality policy requires keyword_trace evidence" {
            $oldRoot = $script:Root
            try {
                $root = Join-Path $TestDrive "ws-decision-quality-block"
                New-Item -ItemType Directory -Path $root -Force | Out-Null
                $script:Root = $root
                $path = Join-Path $root "recommendations.json"
                Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r-quality","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[{"name":"a","reason_user_profile":"u","reason_target_repo":"t","install":{"repo":"owner/repo","skill":"skills/a","ref":"main","mode":"manual"},"confidence":"high","sources":["https://example.com/a"]}],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
                Set-ContentUtf8 (Join-Path $root "source-strategy.json") '{"schema_version":1,"mode":"target-repo","query":"","sources":[{"id":"official-docs"}],"evidence_policy":{"min_unique_sources_for_changes":1,"require_http_source_for_changes":true},"decision_quality_policy":{"require_keyword_trace_for_changes":true,"require_keyword_trace_membership":true,"min_user_profile_keywords_per_change":1,"min_target_repo_keywords_per_change":1,"min_installed_state_keywords_per_change":1}}'
                Set-ContentUtf8 (Join-Path $root "decision-insights.json") '{"schema_version":1,"mode":"target-repo","keywords":{"user_profile":["ppt"],"target_repo":["react"],"installed_state":["codex"],"profile_only_context":["ppt","codex"]}}'

                $thrown = $false
                try {
                    Invoke-AuditRecommendationsApply -RecommendationsPath $path -DryRunAck "我知道未落盘" | Out-Null
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should Match "insufficient_decision_quality"
                }
                $thrown | Should Be $true

                $report = Get-ContentUtf8 (Get-AuditApplyReportPath $path) | ConvertFrom-Json
                $report.error_code | Should Be "insufficient_decision_quality"
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
            Set-ContentUtf8 $recPath '{"schema_version":2,"run_id":"r-preflight-ok","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

            $live = Get-AuditLiveInstalledState
            Set-ContentUtf8 (Join-Path $runDir "installed-skills.json") ('{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"' + [string]$live.fingerprint + '","live_mcp_fingerprint":"' + [string]$live.mcp_fingerprint + '"}')
            Set-ContentUtf8 (Join-Path $runDir "audit-meta.json") ('{"schema_version":1,"run_id":"r-preflight-ok","mode":"target-repo","prompt_contract_version":"' + (Get-AuditPromptContractVersion) + '"}')
            Set-ContentUtf8 (Join-Path $runDir "outer-ai-prompt.md") ("Prompt-Contract-Version: " + (Get-AuditPromptContractVersion))

            $report = Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath
            $report.success | Should Be $true
            $report.prompt_contract.matched | Should Be $true
            (Test-Path (Join-Path $runDir "preflight-report.json")) | Should Be $true
        }

        It "Preflight blocks stale snapshot before dry-run" {
            $runId = "r-preflight-stale"
            $runDir = Join-Path $TestDrive $runId
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null

            $recPath = Join-Path $runDir "recommendations.json"
            Set-ContentUtf8 $recPath '{"schema_version":2,"run_id":"r-preflight-stale","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
            Set-ContentUtf8 (Join-Path $runDir "installed-skills.json") '{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"deadbeef","live_mcp_fingerprint":"deadbeef"}'
            Set-ContentUtf8 (Join-Path $runDir "audit-meta.json") ('{"schema_version":1,"run_id":"r-preflight-stale","mode":"target-repo","prompt_contract_version":"' + (Get-AuditPromptContractVersion) + '"}')
            Set-ContentUtf8 (Join-Path $runDir "outer-ai-prompt.md") ("Prompt-Contract-Version: " + (Get-AuditPromptContractVersion))

            $thrown = $false
            try {
                Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "stale_snapshot"
            }
            $thrown | Should Be $true
            (Test-Path (Join-Path $runDir "preflight-report.json")) | Should Be $true
        }

        It "Preflight resolves <run-id> placeholders to the latest run directory" {
            $oldRoot = $script:Root
            try {
                $script:Root = Join-Path $TestDrive "ws-preflight-placeholder"
                $auditRoot = Join-Path $script:Root "reports\skill-audit"
                $runOld = Join-Path $auditRoot "r-old"
                $runNew = Join-Path $auditRoot "r-new"
                New-Item -ItemType Directory -Path $runOld -Force | Out-Null
                New-Item -ItemType Directory -Path $runNew -Force | Out-Null
                $live = Get-AuditLiveInstalledState
                $promptVersion = Get-AuditPromptContractVersion
                Set-ContentUtf8 (Join-Path $runOld "recommendations.json") '{}'
                Set-ContentUtf8 (Join-Path $runNew "recommendations.json") '{}'
                Set-ContentUtf8 (Join-Path $runOld "installed-skills.json") ('{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"' + [string]$live.fingerprint + '","live_mcp_fingerprint":"' + [string]$live.mcp_fingerprint + '"}')
                Set-ContentUtf8 (Join-Path $runNew "installed-skills.json") ('{"schema_version":1,"skills":[],"mcp_servers":[],"live_fingerprint":"' + [string]$live.fingerprint + '","live_mcp_fingerprint":"' + [string]$live.mcp_fingerprint + '"}')
                Set-ContentUtf8 (Join-Path $runOld "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')
                Set-ContentUtf8 (Join-Path $runNew "audit-meta.json") ('{"schema_version":1,"prompt_contract_version":"' + $promptVersion + '"}')
                (Get-Item $runOld).LastWriteTimeUtc = [datetime]"2026-01-01T00:00:00Z"
                (Get-Item $runNew).LastWriteTimeUtc = [datetime]"2026-01-02T00:00:00Z"

                $resolvedByRunId = Resolve-AuditRecommendationsPathForPreflight "" "<run-id>"
                $resolvedByPath = Resolve-AuditRecommendationsPathForPreflight "reports/skill-audit/<run-id>/recommendations.json" ""

                $resolvedByRunId | Should Be (Join-Path $runNew "recommendations.json")
                $resolvedByPath | Should Be (Join-Path $runNew "recommendations.json")
            }
            finally {
                $script:Root = $oldRoot
            }
        }
    }
}
