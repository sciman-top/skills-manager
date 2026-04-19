. $PSScriptRoot\..\..\skills.ps1

function Set-AuditTestWorkspace([string]$root) {
    $script:Root = $root
    $script:CfgPath = Join-Path $root "skills.json"
    $script:LogPath = Join-Path $root "build.log"
    $script:VendorDir = Join-Path $root "vendor"
    $script:AgentDir = Join-Path $root "agent"
    $script:OverridesDir = Join-Path $root "overrides"
    $script:ManualDir = Join-Path $root "manual"
    $script:ImportDir = Join-Path $root "imports"
    $script:DryRun = $false
    $global:Root = $script:Root
    $global:CfgPath = $script:CfgPath
    $global:LogPath = $script:LogPath
    $global:VendorDir = $script:VendorDir
    $global:AgentDir = $script:AgentDir
    $global:OverridesDir = $script:OverridesDir
    $global:ManualDir = $script:ManualDir
    $global:ImportDir = $script:ImportDir
    $global:DryRun = $false
    EnsureDir $script:VendorDir
    EnsureDir $script:AgentDir
    EnsureDir $script:OverridesDir
    EnsureDir $script:ManualDir
    EnsureDir $script:ImportDir
}

Describe "Skill Audit E2E" {
    Context "Recommendation apply" {
        It "Applies a local recommended skill through existing install flow and writes report" {
            $root = Join-Path $TestDrive "ws-skill-audit-apply"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-AuditTestWorkspace $root

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "placeholder"; repo = "https://example.com/placeholder.git"; ref = "main" })
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @()
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }
            SaveCfg $cfg

            $skillRepo = Join-Path $TestDrive "skill-source"
            New-Item -ItemType Directory -Path $skillRepo -Force | Out-Null
            Set-Content -Path (Join-Path $skillRepo "SKILL.md") -Value "---`nname: demo-skill`ndescription: Demo skill.`n---`nUse when testing audit apply."
            $zip = Join-Path $TestDrive "skill-source.zip"
            Compress-Archive -Path (Join-Path $skillRepo "*") -DestinationPath $zip -Force

            $recommendationsPath = Join-Path $root "recommendations.json"
            $recommendations = [pscustomobject]@{
                schema_version = 1
                run_id = "r1"
                target = "demo-target"
                new_skills = @(
                    [pscustomobject]@{
                        name = "demo-skill"
                        reason = "Local fixture for audit apply."
                        install = [pscustomobject]@{
                            repo = $zip
                            skill = "."
                            ref = "main"
                            mode = "manual"
                        }
                        confidence = "high"
                        sources = @("local-fixture")
                    }
                )
                overlap_findings = @()
                do_not_install = @()
            }
            Set-ContentUtf8 $recommendationsPath ($recommendations | ConvertTo-Json -Depth 20)

            Mock 构建生效 {}
            Mock Invoke-Doctor { [pscustomobject]@{ pass = $true } }

            $report = Invoke-AuditRecommendationsApply -RecommendationsPath $recommendationsPath -Apply -Yes
            $saved = LoadCfg

            $report.success | Should Be $true
            (Test-Path (Join-Path $root "apply-report.json")) | Should Be $true
            @($saved.imports).Count | Should Be 1
            @($saved.mappings).Count | Should Be 1
            $saved.mappings[0].to | Should Be "demo-skill"
            Assert-MockCalled 构建生效 -Times 1 -Exactly
            Assert-MockCalled Invoke-Doctor -Times 1 -Exactly
        }
    }
}
