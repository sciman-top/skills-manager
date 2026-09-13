BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Add Import Defaults" {
    It 'removes only retired projection references when deleting a vendor' {
        $CfgPath = Join-Path $TestDrive 'vendor-references.json'
        $VendorDir = Join-Path $TestDrive 'vendor-references'
        $vendor = [pscustomobject]@{ name='demo'; repo='https://example.com/demo.git' }
        $cfg = [pscustomobject]@{
            vendors=@($vendor); imports=@()
            mappings=@(
                [pscustomobject]@{ vendor='demo'; from='one'; to='retired' },
                [pscustomobject]@{ vendor='demo'; from='two'; to='shared' },
                [pscustomobject]@{ vendor='other'; from='two'; to='shared' }
            )
            skill_projection=[pscustomobject]@{
                discovery_catalog=[pscustomobject]@{ domain_memberships=[pscustomobject]@{ content=@('retired','shared') } }
                projection_profiles=[pscustomobject]@{ profiles=[pscustomobject]@{ core=[pscustomobject]@{ include=@('retired','shared') } } }
            }
        }
        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock Select-Items { ,@($vendor) }
        Mock Confirm-WithSummary { $true }
        Mock Confirm-Action { $false }
        Mock SaveCfgSafe {}
        Mock 构建生效 {}
        删除技能库
        $cfg.skill_projection.discovery_catalog.domain_memberships.content | Should -Be @('shared')
        $cfg.skill_projection.projection_profiles.profiles.core.include | Should -Be @('shared')
    }

    It 'preserves externally modified configuration when adding a vendor fails before saving' {
        $CfgPath = Join-Path $TestDrive 'vendor-failure.json'
        $VendorDir = Join-Path $TestDrive 'new-vendors'
        New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
        [IO.File]::WriteAllText($CfgPath, '{"original":true}')
        $cfg = [pscustomobject]@{ vendors=@(); mappings=@(); imports=@() }
        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock Read-Host { 'https://github.com/example/demo.git' } -ParameterFilter { $Prompt -like '*地址*' }
        Mock Read-Host { 'main' } -ParameterFilter { $Prompt -like '*分支*' }
        Mock Read-Host { 'demo' } -ParameterFilter { $Prompt -like '*名称*' }
        Mock Invoke-Git {
            [IO.File]::WriteAllText($CfgPath, '{"external":true}')
            throw 'clone failed'
        }
        { 新增技能库 } | Should -Throw '*clone failed*'
        [IO.File]::ReadAllText($CfgPath) | Should -Be '{"external":true}'
    }

    It 'restores the working directory when initialization checkout fails' {
        $VendorDir = Join-Path $TestDrive 'init-vendor'
        $cfg = [pscustomobject]@{ vendors=@([pscustomobject]@{ name='demo'; repo='https://example.com/demo.git'; ref='main' }) }
        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock Test-InstalledVendorPath { $false }
        Mock Invoke-Git {
            param($GitArgs)
            if ($GitArgs[0] -eq 'clone') { New-Item -ItemType Directory -Path $GitArgs[2] -Force | Out-Null }
            else { throw 'checkout failed' }
        }
        $before = (Get-Location).Path
        { 初始化 } | Should -Throw '*checkout failed*'
        (Get-Location).Path | Should -Be $before
    }

    It 'restores a failed import before considering any cross-repository fallback' {
        $CfgPath = Join-Path $TestDrive 'build-recovery.json'
        $VendorDir = Join-Path $TestDrive 'vendor'
        [IO.File]::WriteAllText($CfgPath, '{"original":true}')
        $cfg = [pscustomobject]@{ vendors=@(); mappings=@(); imports=@(); update_force=$false }
        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock Assert-RepoReachable {}
        Mock Ensure-Repo {}
        Mock Migrate-ManualToVendor { 0 }
        Mock Write-CfgChangeSummary {}
        Mock 构建生效 { throw 'build failed' }
        Mock Get-CrossRepoInstallFallbackPlan { throw 'must not retry another repository after writing config' }
        Mock Write-InstallErrorHint {}
        Add-ImportFromArgs @('example/demo', '--ref', 'main') | Should -BeFalse
        [IO.File]::ReadAllText($CfgPath) | Should -Be '{"original":true}'
        Should -Invoke Get-CrossRepoInstallFallbackPlan -Times 0 -Exactly
    }

    It 'retains converted sources when vendor deletion compensation sees external config' {
        $CfgPath = Join-Path $TestDrive 'delete-config.json'
        $created = Join-Path $TestDrive 'converted'
        New-Item -ItemType Directory -Path $created | Out-Null
        [IO.File]::WriteAllText($CfgPath, '{"original":true}')
        $vendor = [pscustomobject]@{ name='demo'; repo='https://example.com/demo.git' }
        $cfg = [pscustomobject]@{ vendors=@($vendor); mappings=@(); imports=@() }
        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock Select-Items { ,@($vendor) }
        Mock Confirm-WithSummary { $true }
        Mock Confirm-Action { $true }
        Mock Write-CfgChangeSummary {}
        Mock Convert-InstalledVendorSkillsToManual { [pscustomobject]@{ converted=1; skipped=0; created_paths=@($created) } }
        Mock 构建生效 {
            [IO.File]::WriteAllText($CfgPath, '{"external":true}')
            throw 'build failed'
        }
        { 删除技能库 } | Should -Throw '*config_restore_conflict*'
        [IO.File]::ReadAllText($CfgPath) | Should -Be '{"external":true}'
        Test-Path -LiteralPath $created | Should -BeTrue
    }

    It 'preserves external configuration after import failure at <Stage>' -ForEach @(
        @{ Stage = 'probe' }, @{ Stage = 'build' }
    ) {
        $CfgPath = Join-Path $TestDrive "$Stage-config.json"
        $VendorDir = Join-Path $TestDrive "$Stage-vendor"
        [IO.File]::WriteAllText($CfgPath, '{"original":true}')
        $cfg = [pscustomobject]@{ vendors=@(); mappings=@(); imports=@(); update_force=$false }
        Mock Preflight {}
        Mock LoadCfg { $cfg }
        Mock Assert-RepoReachable {
            if ($Stage -eq 'probe') {
                [IO.File]::WriteAllText($CfgPath, '{"external":true}')
                throw 'probe failed'
            }
        }
        Mock Ensure-Repo {}
        Mock Migrate-ManualToVendor { 0 }
        Mock 构建生效 {
            [IO.File]::WriteAllText($CfgPath, '{"external":true}')
            throw 'build failed'
        }
        Mock Get-CrossRepoInstallFallbackPlan { $null }
        Mock Write-InstallErrorHint {}
        Mock Write-CfgChangeSummary {}
        Add-ImportFromArgs @('example/demo', '--ref', 'main') | Should -BeFalse
        [IO.File]::ReadAllText($CfgPath) | Should -Be '{"external":true}'
    }

    It "Treats repo-only add as vendor-intent with no explicit skill" {
        $parsed = Parse-AddArgs @("addyosmani/web-quality-skills")

        $parsed.skillSpecified | Should -Be $false
        $parsed.modeSpecified | Should -Be $false
        $parsed.skills.Count | Should -Be 1
        $parsed.skills[0] | Should -Be "."
    }

    It "Keeps explicit root skill as a skill selection" {
        $parsed = Parse-AddArgs @("addyosmani/web-quality-skills", "--skill", ".")

        $parsed.skillSpecified | Should -Be $true
        $parsed.modeSpecified | Should -Be $false
        $parsed.skills.Count | Should -Be 1
        $parsed.skills[0] | Should -Be "."
    }

    It "Builds an add/import execution plan without touching workspace state" {
        $repoOnly = Get-AddImportPlanFromParsedArgs (Parse-AddArgs @("addyosmani/web-quality-skills"))
        $repoOnly.repo | Should -Be "https://github.com/addyosmani/web-quality-skills.git"
        $repoOnly.ref | Should -Be "main"
        $repoOnly.refIsAuto | Should -Be $true
        $repoOnly.mode | Should -Be "vendor"
        $repoOnly.registerVendorOnly | Should -Be $true

        $explicitSkill = Get-AddImportPlanFromParsedArgs (Parse-AddArgs @("owner/repo", "--skill", ".", "--mode", "manual", "--ref", "dev"))
        $explicitSkill.repo | Should -Be "https://github.com/owner/repo.git"
        $explicitSkill.ref | Should -Be "dev"
        $explicitSkill.refIsAuto | Should -Be $false
        $explicitSkill.mode | Should -Be "manual"
        $explicitSkill.registerVendorOnly | Should -Be $false
    }

    It "Registers repo-only add as vendor library without installing skills" {
        $oldCfgPath = $CfgPath
        $oldImportDir = $ImportDir
        $oldVendorDir = $VendorDir
        try {
            $CfgPath = Join-Path $TestDrive "skills.json"
            $ImportDir = Join-Path $TestDrive "imports"
            $VendorDir = Join-Path $TestDrive "vendor"
            New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null

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

            Should -Invoke Get-SkillCandidatesFromGitRepo -Times 0 -Exactly
            Should -Invoke Resolve-SkillsWithProbe -Times 0 -Exactly
            Should -Invoke Ensure-Repo -Times 1 -Exactly
            Should -Invoke 构建生效 -Times 1 -Exactly
            $script:vendorMappings.Count | Should -Be 0
            @($script:importWrites | Where-Object { $_.mode -eq "vendor" }).Count | Should -Be 0
            @($script:importWrites | Where-Object { $_.mode -eq "manual" }).Count | Should -Be 0
            @($script:savedCfg.vendors).Count | Should -Be 1
            ((@($script:savedCfg.imports).Count) -le 1) | Should -Be $true
            @($script:savedCfg.mappings).Count | Should -Be 0
            $script:savedCfg.vendors[0].name | Should -Be "web-quality-skills"
        }
        finally {
            $CfgPath = $oldCfgPath
            $ImportDir = $oldImportDir
            $VendorDir = $oldVendorDir
        }
    }

    It "Repo-only add links existing manual skills from same repo to the new vendor" {
        $oldCfgPath = $CfgPath
        $oldImportDir = $ImportDir
        $oldVendorDir = $VendorDir
        $oldManualDir = $ManualDir
        try {
            $CfgPath = Join-Path $TestDrive "skills.json"
            $ImportDir = Join-Path $TestDrive "imports"
            $VendorDir = Join-Path $TestDrive "vendor"
            $ManualDir = Join-Path $TestDrive "manual"
            New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
            New-Item -ItemType Directory -Path $ManualDir -Force | Out-Null

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

            @($script:savedCfg2.vendors | Where-Object { $_.name -eq "marketingskills" }).Count | Should -Be 1
            @($script:savedCfg2.imports | Where-Object { $_.mode -eq "manual" -and $_.name -eq "content-strategy" }).Count | Should -Be 0
            @($script:savedCfg2.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "content-strategy" }).Count | Should -Be 0
        }
        finally {
            $CfgPath = $oldCfgPath
            $ImportDir = $oldImportDir
            $VendorDir = $oldVendorDir
            $ManualDir = $oldManualDir
        }
    }

    It "Keeps full skill path when adding a single skill to an existing vendor" {
        $oldCfgPath = $CfgPath
        $oldImportDir = $ImportDir
        $oldVendorDir = $VendorDir
        try {
            $CfgPath = Join-Path $TestDrive "skills.json"
            $ImportDir = Join-Path $TestDrive "imports"
            $VendorDir = Join-Path $TestDrive "vendor"
            New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null

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

            @($script:importWrites).Count | Should -Be 1
            $script:importWrites[0].skill | Should -Be "skills\\requesting-code-review"
        }
        finally {
            $CfgPath = $oldCfgPath
            $ImportDir = $oldImportDir
            $VendorDir = $oldVendorDir
        }
    }

    It "Uses declared SKILL name with one repository preparation (sparse=<Sparse>)" -ForEach @(
        @{ Sparse=$false }, @{ Sparse=$true }
    ) {
        $oldCfgPath = $CfgPath
        $oldImportDir = $ImportDir
        $oldVendorDir = $VendorDir
        try {
            $CfgPath = Join-Path $TestDrive "skills.json"
            $ImportDir = Join-Path $TestDrive "imports"
            $VendorDir = Join-Path $TestDrive "vendor"
            New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null
            New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null

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
            $script:savedCfg = $null
            Mock SaveCfgSafe {
                param($cfg, $cfgRaw)
                $script:savedCfg = $cfg
            }
            Mock Clear-SkillsCache {}
            Mock 构建生效 {}

            $script:importWrites = @()
            Mock Upsert-Import {
                param($cfg, $import)
                $script:importWrites += $import
            }

            $tokens = @("https://github.com/remotion-dev/skills", "--skill", "remotion-best-practices")
            if ($Sparse) { $tokens += '--sparse' }
            Add-ImportFromArgs $tokens | Should -BeTrue
            Should -Invoke Ensure-Repo -Times 1 -Exactly

            @($script:importWrites).Count | Should -Be 1
            $script:importWrites[0].name | Should -Be "remotion-best-practices"
            $script:importWrites[0].skill | Should -Be "skills\\remotion"
            @($script:savedCfg.mappings).Count | Should -Be 1
            $script:savedCfg.mappings[0].vendor | Should -Be "manual"
            $script:savedCfg.mappings[0].from | Should -Be "remotion-best-practices"
            $script:savedCfg.mappings[0].to | Should -Be "remotion-best-practices"
        }
        finally {
            $CfgPath = $oldCfgPath
            $ImportDir = $oldImportDir
            $VendorDir = $oldVendorDir
        }
    }
}
