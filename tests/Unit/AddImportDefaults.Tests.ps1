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

    It "Registers repo-only add as vendor library without installing skills" {
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
            Mock Resolve-SkillsWithProbe {}
            Mock Get-SkillCandidatesFromGitRepo {}
            Mock Ensure-Repo {}
            Mock Ensure-ImportVendorMapping {
                param($cfg, $vendorName, $skillPath, $targetName)
                $cfg.mappings += [pscustomobject]@{
                    vendor = $vendorName
                    from = $skillPath
                    to = $targetName
                }
            }
            Mock Test-IsSkillDir { $true }
            $script:savedCfg = $null
            Mock SaveCfgSafe {
                param($cfg, $cfgRaw)
                $script:savedCfg = $cfg
            }
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

            Assert-MockCalled Get-SkillCandidatesFromGitRepo -Times 0 -Exactly
            Assert-MockCalled Resolve-SkillsWithProbe -Times 0 -Exactly
            Assert-MockCalled Ensure-Repo -Times 1 -Exactly
            Assert-MockCalled 构建生效 -Times 1 -Exactly
            $script:vendorMappings.Count | Should Be 0
            @($script:importWrites | Where-Object { $_.mode -eq "vendor" }).Count | Should Be 0
            @($script:importWrites | Where-Object { $_.mode -eq "manual" }).Count | Should Be 0
            @($script:savedCfg.vendors).Count | Should Be 1
            ((@($script:savedCfg.imports).Count) -le 1) | Should Be $true
            @($script:savedCfg.mappings).Count | Should Be 0
            $script:savedCfg.vendors[0].name | Should Be "web-quality-skills"
        }
        finally {
            $script:CfgPath = $oldCfgPath
            $script:ImportDir = $oldImportDir
            $script:VendorDir = $oldVendorDir
        }
    }

    It "Repo-only add links existing manual skills from same repo to the new vendor" {
        $oldCfgPath = $script:CfgPath
        $oldImportDir = $script:ImportDir
        $oldVendorDir = $script:VendorDir
        $oldManualDir = $script:ManualDir
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $script:ImportDir = Join-Path $TestDrive "imports"
            $script:VendorDir = Join-Path $TestDrive "vendor"
            $script:ManualDir = Join-Path $TestDrive "manual"
            New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:ManualDir -Force | Out-Null

            Mock Preflight {}
            Mock Assert-RepoReachable {}
            Mock Get-RepoDefaultBranch { "main" }
            Mock LoadCfg {
                [pscustomobject]@{
                    vendors = @()
                    mappings = @(
                        [pscustomobject]@{ vendor = "manual"; from = "content-strategy"; to = "content-strategy" }
                    )
                    imports = @(
                        [pscustomobject]@{
                            name = "content-strategy"
                            repo = "https://github.com/coreyhaines31/marketingskills.git"
                            ref = "main"
                            skill = "skills\\content-strategy"
                            mode = "manual"
                            sparse = $false
                        }
                    )
                    targets = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    update_force = $false
                    sync_mode = "link"
                }
            }
            Mock Resolve-SkillsWithProbe {}
            Mock Get-SkillCandidatesFromGitRepo {}
            Mock Ensure-Repo {}
            Mock Test-IsSkillDir { $true }
            $script:savedCfg2 = $null
            Mock SaveCfgSafe {
                param($cfg, $cfgRaw)
                $script:savedCfg2 = $cfg
            }
            Mock Clear-SkillsCache {}
            Mock 构建生效 {}

            Add-ImportFromArgs @("https://github.com/coreyhaines31/marketingskills")

            @($script:savedCfg2.vendors | Where-Object { $_.name -eq "marketingskills" }).Count | Should Be 1
            @($script:savedCfg2.imports | Where-Object { $_.mode -eq "manual" -and $_.name -eq "content-strategy" }).Count | Should Be 0
            @($script:savedCfg2.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "content-strategy" }).Count | Should Be 0
        }
        finally {
            $script:CfgPath = $oldCfgPath
            $script:ImportDir = $oldImportDir
            $script:VendorDir = $oldVendorDir
            $script:ManualDir = $oldManualDir
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
