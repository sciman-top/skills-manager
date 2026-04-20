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

            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes")
            $apply.action | Should Be "apply"
            $apply.recommendations | Should Be "r.json"
            $apply.apply | Should Be $true
            $apply.yes | Should Be $true

            $status = Parse-AuditTargetsArgs @("status")
            $status.action | Should Be "status"
        }

        It "Parses apply selection indexes for add and remove lists" {
            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes", "--add-indexes", "1,3", "--remove-indexes", "2", "--dry-run-ack", "我知道未落盘")
            $apply.add_selection | Should Be "1,3"
            $apply.remove_selection | Should Be "2"
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
            (Parse-AuditTargetsArgs @("扫描")).action | Should Be "scan"
            (Parse-AuditTargetsArgs @("状态")).action | Should Be "status"
            (Parse-AuditTargetsArgs @("应用确认", "--recommendations", "r.json")).action | Should Be "apply_flow"
            (Parse-AuditTargetsArgs @("应用", "--recommendations", "r.json")).action | Should Be "apply"
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
            $auditBody | Should Match "=== 目标仓审查 ==="
            $auditBody | Should Match "5\) 应用建议（推荐）"
            $auditBody | Should Match "12\) 查看 AI 提示词"
            $auditBody | Should Match "13\) 编辑 AI 提示词"
            $auditBody | Should Match "14\) 直接执行建议（高级）"
        }

        It "Documents audit help source with self-check and prompt-source guidance" {
            $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
            $auditBody = Get-FunctionBody $raw "审查目标菜单"
            $raw | Should Match "先写并自检 recommendations"
            $raw | Should Match "不要直接手改 run 目录产物"
            $raw | Should Match "沿用原序号"
            $auditBody | Should Not Match "17\) 审查目标（需求 / 目标仓 / 审查包 / 自检后 dry-run / 按原序号选择增删）"
            $auditBody | Should Match "4\) 生成审查包"
        }

        It "Documents audit runtime summary wording with original-index and empty-list guidance" {
            $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/AuditTargets.ps1") -Raw
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
        }

        It "Keeps built-in prompt markdown inline code literal without control-character corruption" {
            $prompt = Get-AuditOuterAiPromptContent
            $prompt | Should Match '`reason_user_profile`'
            $prompt | Should Match '`reason_target_repo`'
            $prompt | Should Match '`recommendations.json`'
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
        }

        It "Builds recommendations template with placeholder examples" {
            $template = New-AuditRecommendationsTemplate "r1" "demo"

            $template.schema_version | Should Be 2
            $template.new_skills[0].install.repo | Should Be "<owner/repo-or-local-path>"
            $template.removal_candidates[0].installed.vendor | Should Be "<installed-vendor>"
            $template.do_not_install[0].name | Should Be "<skill-not-recommended>"
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
        }
    }
}
