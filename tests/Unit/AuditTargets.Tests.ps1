# Dot-source the main script to load functions
. $PSScriptRoot\..\..\skills.ps1

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
        It "Parses init/add/list/scan/apply subcommands" {
            (Parse-AuditTargetsArgs @("init")).action | Should Be "init"

            $add = Parse-AuditTargetsArgs @("add", "demo", "..\demo")
            $add.action | Should Be "add"
            $add.name | Should Be "demo"
            $add.path | Should Be "..\demo"

            (Parse-AuditTargetsArgs @("list")).action | Should Be "list"
            (Parse-AuditTargetsArgs @("scan", "--target", "demo")).target | Should Be "demo"

            $apply = Parse-AuditTargetsArgs @("apply", "--recommendations", "r.json", "--apply", "--yes")
            $apply.action | Should Be "apply"
            $apply.recommendations | Should Be "r.json"
            $apply.apply | Should Be $true
            $apply.yes | Should Be $true
        }

        It "Accepts Chinese subcommands" {
            (Parse-AuditTargetsArgs @("初始化")).action | Should Be "init"
            (Parse-AuditTargetsArgs @("添加", "demo", "..\demo")).action | Should Be "add"
            (Parse-AuditTargetsArgs @("列表")).action | Should Be "list"
            (Parse-AuditTargetsArgs @("扫描")).action | Should Be "scan"
            (Parse-AuditTargetsArgs @("应用", "--recommendations", "r.json")).action | Should Be "apply"
        }
    }

    Context "Repository scan" {
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
}
