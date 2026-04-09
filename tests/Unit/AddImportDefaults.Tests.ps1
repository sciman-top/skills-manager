. $PSScriptRoot\..\..\skills.ps1

Describe "Add Import Defaults" {
    It "Treats repo-only add as vendor-intent with no explicit skill" {
        $parsed = Parse-AddArgs @("addyosmani/web-quality-skills")

        $parsed.skillSpecified | Should Be $false
        $parsed.modeSpecified | Should Be $false
        $parsed.skills.Count | Should Be 1
        $parsed.skills[0] | Should Be "."
    }

    It "Keeps explicit root skill as a skill selection" {
        $parsed = Parse-AddArgs @("addyosmani/web-quality-skills", "--skill", ".")

        $parsed.skillSpecified | Should Be $true
        $parsed.modeSpecified | Should Be $false
        $parsed.skills.Count | Should Be 1
        $parsed.skills[0] | Should Be "."
    }

    It "Imports repo-only add as vendor library" {
        $oldCfgPath = $script:CfgPath
        $oldImportDir = $script:ImportDir
        $oldVendorDir = $script:VendorDir
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $script:ImportDir = Join-Path $TestDrive "imports"
            $script:VendorDir = Join-Path $TestDrive "vendor"
            New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null

            Mock Preflight {}
            Mock Assert-RepoReachable {}
            Mock Get-RepoDefaultBranch { "main" }
            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    mappings = @()
                    imports = @()
                    targets = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "link"
                }
            }
            Mock Get-SkillCandidatesFromGitRepo {
                @(
                    [pscustomobject]@{ rel = "."; leaf = "web-quality-skills" }
                    [pscustomobject]@{ rel = "skills\web-quality-audit"; leaf = "web-quality-audit" }
                )
            }
            Mock Resolve-SkillsWithProbe {}
            Mock Ensure-Repo {}
            Mock Test-IsSkillDir { $true }
            Mock SaveCfgSafe {}
            Mock Clear-SkillsCache {}
            Mock 构建生效 {}

            $script:vendorMappings = @()
            Mock Ensure-ImportVendorMapping {
                param($cfg, $vendorName, $skillPath, $targetName)
                $script:vendorMappings += [pscustomobject]@{
                    vendor = $vendorName
                    skill = $skillPath
                    target = $targetName
                }
            }

            $script:importWrites = @()
            Mock Upsert-Import {
                param($cfg, $import)
                $script:importWrites += $import
            }

            Add-ImportFromArgs @("addyosmani/web-quality-skills")

            Assert-MockCalled Get-SkillCandidatesFromGitRepo -Times 1 -Exactly
            Assert-MockCalled Resolve-SkillsWithProbe -Times 0 -Exactly
            Assert-MockCalled Ensure-Repo -Times 1 -Exactly
            Assert-MockCalled 构建生效 -Times 1 -Exactly
            $script:vendorMappings.Count | Should Be 2
            @($script:importWrites | Where-Object { $_.mode -eq "vendor" }).Count | Should Be 1
            @($script:importWrites | Where-Object { $_.mode -eq "manual" }).Count | Should Be 0
        }
        finally {
            $script:CfgPath = $oldCfgPath
            $script:ImportDir = $oldImportDir
            $script:VendorDir = $oldVendorDir
        }
    }

    It "Keeps full skill path when adding a single skill to an existing vendor" {
        $oldCfgPath = $script:CfgPath
        $oldImportDir = $script:ImportDir
        $oldVendorDir = $script:VendorDir
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $script:ImportDir = Join-Path $TestDrive "imports"
            $script:VendorDir = Join-Path $TestDrive "vendor"
            New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null

            Mock Preflight {}
            Mock Assert-RepoReachable {}
            Mock Get-RepoDefaultBranch { "main" }
            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @(
                        [pscustomobject]@{ name = "superpowers"; repo = "https://github.com/obra/superpowers.git"; ref = "main" }
                    )
                    mappings = @()
                    imports = @(
                        [pscustomobject]@{ name = "superpowers"; repo = "https://github.com/obra/superpowers.git"; ref = "main"; skill = "skills\\executing-plans"; mode = "vendor"; sparse = $false }
                    )
                    targets = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "link"
                }
            }
            Mock Resolve-SkillsWithProbe { "skills\\requesting-code-review" }
            Mock Ensure-Repo {}
            Mock Test-IsSkillDir { $true }
            Mock SaveCfgSafe {}
            Mock Clear-SkillsCache {}
            Mock 构建生效 {}
            Mock Ensure-ImportVendorMapping {}

            $script:importWrites = @()
            Mock Upsert-Import {
                param($cfg, $import)
                $script:importWrites += $import
            }

            Add-ImportFromArgs @("https://github.com/obra/superpowers", "--skill", "requesting-code-review")

            @($script:importWrites).Count | Should Be 1
            $script:importWrites[0].skill | Should Be "skills\\requesting-code-review"
        }
        finally {
            $script:CfgPath = $oldCfgPath
            $script:ImportDir = $oldImportDir
            $script:VendorDir = $oldVendorDir
        }
    }

    It "Uses declared SKILL name for manual import when it differs from path leaf" {
        $oldCfgPath = $script:CfgPath
        $oldImportDir = $script:ImportDir
        $oldVendorDir = $script:VendorDir
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $script:ImportDir = Join-Path $TestDrive "imports"
            $script:VendorDir = Join-Path $TestDrive "vendor"
            New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null

            Mock Preflight {}
            Mock Assert-RepoReachable {}
            Mock Get-RepoDefaultBranch { "main" }
            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    mappings = @()
                    imports = @()
                    targets = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "link"
                }
            }
            Mock Resolve-SkillsWithProbe { "skills\\remotion" }
            Mock Ensure-Repo {
                param($path)
                $skillDir = Join-Path $path "skills\\remotion"
                New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value "---`nname: remotion-best-practices`ndescription: x`n---"
            }
            Mock Test-IsSkillDir { $true }
            Mock SaveCfgSafe {}
            Mock Clear-SkillsCache {}
            Mock 构建生效 {}

            $script:importWrites = @()
            Mock Upsert-Import {
                param($cfg, $import)
                $script:importWrites += $import
            }

            Add-ImportFromArgs @("https://github.com/remotion-dev/skills", "--skill", "remotion-best-practices")

            @($script:importWrites).Count | Should Be 1
            $script:importWrites[0].name | Should Be "remotion-best-practices"
            $script:importWrites[0].skill | Should Be "skills\\remotion"
        }
        finally {
            $script:CfgPath = $oldCfgPath
            $script:ImportDir = $oldImportDir
            $script:VendorDir = $oldVendorDir
        }
    }
}
