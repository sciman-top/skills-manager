BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Agent build" {
    It 'does not clear the only agent copy when its transaction backup failed' {
        $oldAgent = $AgentDir
        try {
            $AgentDir = Join-Path $TestDrive 'backup-failed-agent'
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'old.txt') 'only copy'
            Mock Log {}
            Mock 清空Agent目录 {}
            Mock 收集ManualSkills { @() }
            Mock Get-OverridesDirs { @() }
            Mock Remove-VendorRootMappingOutputsFromAgent { 0 }
            Mock Repair-AgentSkillMarkdownFiles { [pscustomobject]@{ normalized = 0; removed = 0; failed = 0 } }
            $txn = [pscustomobject]@{ backup_error = 'fixture move failure'; agent_after_fingerprint = ''; agent_after_fingerprint_error = '' }
            $cfg = [pscustomobject]@{ mappings = @(); imports = @() }

            $failures = @(构建Agent $cfg -SkipPreflight -SkipLock -Txn $txn)

            $failures -join ';' | Should -Match 'build-txn:agent-backup'
            Should -Invoke 清空Agent目录 -Times 0 -Exactly
            Get-ContentUtf8 (Join-Path $AgentDir 'old.txt') | Should -Be 'only copy'
        }
        finally { $AgentDir = $oldAgent }
    }

    It 'blocks import optimization and building when transaction backup failed' {
        Mock Preflight {}
        Mock LoadCfg { [pscustomobject]@{ imports = @(); mappings = @() } }
        Mock Start-BuildTransaction { [pscustomobject]@{ path = 'fixture-retained'; backup_error = 'fixture move failure' } }
        Mock Optimize-Imports {}
        Mock SaveCfg {}
        Mock Get-CfgChangeSummaryLines { @() }
        Mock Write-BuildSummary {}
        Mock New-SkillDiscoveryCatalogTransaction { $null }
        Mock Sync-SkillDiscoveryCatalog { [pscustomobject]@{ enabled = $false } }
        Mock Complete-BuildTransaction {}
        Mock 构建Agent { @() }
        Mock Rollback-BuildTransaction { $false }
        Mock Log {}

        { 构建生效 -SkipHostProjection -SkipLock } | Should -Throw '*构建生效失败*'

        Should -Invoke Optimize-Imports -Times 0 -Exactly
        Should -Invoke 构建Agent -Times 0 -Exactly
    }

    It 'reports partial mapping loss even when another skill was built' -ForEach @(
        @{ Failure = 'missing' }, @{ Failure = 'invalid-marker' }
    ) {
        $oldAgent = $AgentDir
        try {
            $AgentDir = Join-Path $TestDrive ('partial-' + $Failure)
            Mock Log {}
            Mock Resolve-AgentMappingForAgent {
                param($cfg, $mapping, $context)
                [pscustomobject]@{
                    sync = $true; source_valid = ($mapping.to -eq 'healthy' -or $Failure -eq 'invalid-marker')
                    vendor = 'fixture'; from = $mapping.to; to = $mapping.to
                    src_full = Join-Path $TestDrive $mapping.to; containment_root = $TestDrive
                    dst = Join-Path $AgentDir $mapping.to; reason = 'source missing'
                }
            }
            Mock Test-ResolvedAgentMappingSkillDir { param($resolved, $context) $resolved.to -eq 'healthy' }
            Mock Get-ResolvedAgentMappingInvalidReason { 'invalid marker' }
            Mock Assert-SkillPackageSafe {}
            Mock RoboMirror {
                param($src, $dst)
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
                Set-ContentUtf8 (Join-Path $dst 'SKILL.md') "---`nname: healthy`ndescription: fixture`n---"
            }
            Mock 收集ManualSkills { @() }
            Mock Get-OverridesDirs { @() }
            Mock Remove-VendorRootMappingOutputsFromAgent { 0 }
            $cfg = [pscustomobject]@{ mappings = @(
                [pscustomobject]@{ vendor = 'fixture'; from = 'healthy'; to = 'healthy' }
                [pscustomobject]@{ vendor = 'fixture'; from = 'broken'; to = 'broken' }
            ); imports = @() }

            $failures = @(构建Agent $cfg -SkipPreflight -SkipLock)

            Test-Path -LiteralPath (Join-Path $AgentDir 'healthy/SKILL.md') | Should -BeTrue
            $failures -join ';' | Should -Match 'build-agent-invalid-mappings'
        }
        finally { $AgentDir = $oldAgent }
    }

    It "resolves UTF-8 relative-path SKILL placeholders" {
        $root = Join-Path $TestDrive "placeholder"
        $targetDir = Join-Path $root "plugin\skills\plan"
        $placeholderPath = Join-Path $root "openclaw\skills\plan\SKILL.md"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $placeholderPath -Parent) -Force | Out-Null
        $content = "---`nname: plan`ndescription: 中文占位目标 — verified`n---`n"
        Set-ContentUtf8 (Join-Path $targetDir "SKILL.md") $content
        Set-ContentUtf8 $placeholderPath "../../../plugin/skills/plan/SKILL.md"

        Expand-RelativeSkillPlaceholders $root | Should -Be 1
        Get-ContentUtf8 $placeholderPath | Should -Be $content
    }

    It "restores the previous agent directory on rollback" {
        $oldRoot = $Root
        $oldAgent = $AgentDir
        try {
            $Root = Join-Path $TestDrive "repo"
            $AgentDir = Join-Path $Root "agent"
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $AgentDir "old.txt") -Value "old"

            $txn = Start-BuildTransaction
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $AgentDir "new.txt") -Value "new"
            $txn.agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
            $txn.agent_after_fingerprint_error = ''
            Rollback-BuildTransaction $txn

            Test-Path -LiteralPath (Join-Path $AgentDir "old.txt") | Should -Be $true
            Test-Path -LiteralPath (Join-Path $AgentDir "new.txt") | Should -Be $false
        }
        finally {
            $Root = $oldRoot
            $AgentDir = $oldAgent
        }
    }

    It "restores config and staged manual source when the build transaction rolls back" {
        $oldRoot = $Root
        $oldAgentDir = $AgentDir
        $oldCfgPath = $CfgPath
        $oldManualDir = $ManualDir
        $oldVendorDir = $VendorDir
        $oldImportDir = $ImportDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $Root = Join-Path $TestDrive 'migration-build-rollback'
            $AgentDir = Join-Path $Root 'agent'
            $CfgPath = Join-Path $Root 'skills.json'
            $ManualDir = Join-Path $Root 'manual'
            $VendorDir = Join-Path $Root 'vendor'
            $ImportDir = Join-Path $Root 'imports'
            New-Item -ItemType Directory -Path $AgentDir, $ManualDir, $VendorDir, $ImportDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'old.txt') 'old agent'
            $originalConfig = '{"vendors":[],"imports":[],"mappings":[]}'
            Set-ContentUtf8 $CfgPath $originalConfig

            $vendorSkill = Join-Path $VendorDir 'myvendor\skills\demo'
            $manualSkill = Join-Path $ManualDir 'demo-legacy'
            New-Item -ItemType Directory -Path $vendorSkill, $manualSkill -Force | Out-Null
            Set-ContentUtf8 (Join-Path $vendorSkill 'SKILL.md') 'vendor'
            Set-ContentUtf8 (Join-Path $manualSkill 'SKILL.md') 'manual'
            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = 'myvendor'; repo = 'https://example.com/repo.git' })
                imports = @([pscustomobject]@{ name = 'demo-legacy'; mode = 'manual'; repo = 'https://example.com/repo.git'; ref = 'main'; skill = 'skills\demo'; sparse = $false })
                mappings = @()
            }

            $txn = Start-BuildTransaction
            Migrate-ManualToVendor $cfg 'myvendor' 'https://example.com/repo.git' (Join-Path $txn.path 'manual-migrations') $txn.manual_migrations | Should -Be 1
            Set-ContentUtf8 $CfgPath '{"vendors":[{"name":"myvendor"}],"imports":[],"mappings":[]}'
            $txn.config_after_hash = (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash.ToLowerInvariant()
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'new.txt') 'new agent'
            $txn.agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
            $txn.agent_after_fingerprint_error = ''

            Rollback-BuildTransaction $txn | Should -BeTrue
            Get-ContentUtf8 $CfgPath | Should -Be $originalConfig
            Test-Path -LiteralPath (Join-Path $ManualDir 'demo-legacy') -PathType Container | Should -BeTrue
            Get-ContentUtf8 (Join-Path $AgentDir 'old.txt') | Should -Be 'old agent'
            Test-Path -LiteralPath (Join-Path $AgentDir 'new.txt') | Should -BeFalse
        }
        finally {
            $Root = $oldRoot
            $AgentDir = $oldAgentDir
            $CfgPath = $oldCfgPath
            $ManualDir = $oldManualDir
            $VendorDir = $oldVendorDir
            $ImportDir = $oldImportDir
            $DryRun = $oldDryRun
        }
    }

    It "preserves the moved agent backup when its fingerprint cannot be read" {
        $oldRoot = $Root
        $oldAgent = $AgentDir
        try {
            $Root = Join-Path $TestDrive "repo-fingerprint-failure"
            $AgentDir = Join-Path $Root "agent"
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $AgentDir "old.txt") -Value "old"
            $script:buildFingerprintCalls = 0
            Mock Get-DirectoryFingerprint {
                $script:buildFingerprintCalls++
                if ($script:buildFingerprintCalls -eq 1) { return 'before-fingerprint' }
                throw 'fixture fingerprint read failure'
            }

            $txn = Start-BuildTransaction

            $txn.has_backup_agent | Should -BeTrue
            $txn.agent_before_state | Should -Be 'backed_up'
            $txn.backup_error | Should -Be 'fixture fingerprint read failure'
            Test-Path -LiteralPath $txn.backup_agent -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $AgentDir | Should -BeFalse
        }
        finally {
            $Root = $oldRoot
            $AgentDir = $oldAgent
        }
    }

    It 'preserves current agent when the backup is <Failure>' -TestCases @(
        @{ Failure = 'missing' }, @{ Failure = 'changed' }
    ) {
        param($Failure)
        $oldRoot = $Root; $oldAgent = $AgentDir
        try {
            $Root = Join-Path $TestDrive ('backup-' + $Failure)
            $AgentDir = Join-Path $Root 'agent'
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'old.txt') 'old'
            $txn = Start-BuildTransaction
            New-Item -ItemType Directory -Path $AgentDir | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'new.txt') 'usable current'
            $txn.agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
            if ($Failure -eq 'missing') { Remove-Item -LiteralPath $txn.backup_agent -Recurse -Force }
            else { Set-ContentUtf8 (Join-Path $txn.backup_agent 'old.txt') 'changed' }
            Rollback-BuildTransaction $txn | Should -BeFalse
            Get-ContentUtf8 (Join-Path $AgentDir 'new.txt') | Should -Be 'usable current'
            Test-Path -LiteralPath $txn.path | Should -BeTrue
        }
        finally { $Root = $oldRoot; $AgentDir = $oldAgent }
    }

    It 'restores the quarantined current agent when the backup move fails' {
        $oldRoot = $Root; $oldAgent = $AgentDir
        try {
            $Root = Join-Path $TestDrive 'backup-move-failure'
            $AgentDir = Join-Path $Root 'agent'
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'old.txt') 'old'
            $txn = Start-BuildTransaction
            New-Item -ItemType Directory -Path $AgentDir | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir 'new.txt') 'usable current'
            $txn.agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
            Mock Invoke-MoveItem { throw 'fixture restore move failure' } -ParameterFilter { $src -eq $txn.backup_agent }
            Rollback-BuildTransaction $txn | Should -BeFalse
            Get-ContentUtf8 (Join-Path $AgentDir 'new.txt') | Should -Be 'usable current'
            Get-ContentUtf8 (Join-Path $txn.backup_agent 'old.txt') | Should -Be 'old'
        }
        finally { $Root = $oldRoot; $AgentDir = $oldAgent }
    }

    It "uses retry-capable deletion when clearing agent output" {
        $oldAgent = $AgentDir
        try {
            $AgentDir = Join-Path $TestDrive "agent-clean"
            New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null
            Mock Invoke-RemoveItemWithRetry { $true }
            Mock EnsureDir {}

            清空Agent目录

            Should -Invoke Invoke-RemoveItemWithRetry -Times 1 -Exactly -ParameterFilter { $path -eq $AgentDir -and $Recurse }
            Should -Invoke EnsureDir -Times 1 -Exactly -ParameterFilter { $p -eq $AgentDir }
        }
        finally { $AgentDir = $oldAgent }
    }

    It "reuses source resolution only within one mapping pass" {
        $cfg = [pscustomobject]@{
            vendors = @([pscustomobject]@{ name = "vendor-a" })
            mappings = @(
                [pscustomobject]@{ vendor = "manual"; from = "shared"; to = "manual-a" },
                [pscustomobject]@{ vendor = "manual"; from = "shared"; to = "manual-b" },
                [pscustomobject]@{ vendor = "vendor-a"; from = "skill"; to = "vendor-a" },
                [pscustomobject]@{ vendor = "vendor-a"; from = "skill"; to = "vendor-b" }
            )
        }
        Mock Resolve-ManualImportSkillPath { Join-Path $TestDrive "manual" }
        Mock Resolve-SourceBase { Join-Path $TestDrive "vendor" }
        $context = New-AgentMappingResolveContext

        foreach ($mapping in $cfg.mappings) { Resolve-AgentMappingForAgent $cfg $mapping $context | Out-Null }

        Should -Invoke Resolve-ManualImportSkillPath -Times 1 -Exactly
        Should -Invoke Resolve-SourceBase -Times 1 -Exactly
    }

    It 'preserves schema v1 mapping targets and fails closed for schema v2 drift' {
        $oldAgent = $AgentDir
        try {
            $source = Join-Path $TestDrive 'canonical-source'
            $AgentDir = Join-Path $TestDrive 'canonical-agent'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            Set-ContentUtf8 (Join-Path $source 'SKILL.md') "---`nname: canonical-name`ndescription: fixture`n---"
            $cfgV1 = [pscustomobject]@{ schema_version = 1; vendors = @(); imports = @(); mappings = @() }
            $cfgV2 = [pscustomobject]@{ schema_version = 2; vendors = @(); imports = @(); mappings = @() }
            $mapping = [pscustomobject]@{ vendor = 'manual'; from = 'demo'; to = 'legacy-name' }
            Mock Resolve-ManualImportSkillPath { $source }

            $legacy = Resolve-AgentMappingForAgent $cfgV1 $mapping (New-AgentMappingResolveContext)
            $legacy.to | Should -Be 'legacy-name'
            Split-Path -Leaf $legacy.dst | Should -Be 'legacy-name'
            { Resolve-AgentMappingForAgent $cfgV2 $mapping (New-AgentMappingResolveContext) } |
                Should -Throw '*schema v2 要求 mapping.to 与 SKILL.md name 一致*'
        }
        finally { $AgentDir = $oldAgent }
    }

    It "allows byte-identical skill aliases but rejects divergent duplicates" {
        $agent = Join-Path $TestDrive "agent"
        $a = Join-Path $agent "a\SKILL.md"
        $b = Join-Path $agent "b\SKILL.md"
        New-Item -ItemType Directory -Path (Split-Path $a -Parent), (Split-Path $b -Parent) -Force | Out-Null
        Set-ContentUtf8 $a "---`nname: same`ndescription: same`n---"
        Set-ContentUtf8 $b "---`nname: same`ndescription: same`n---"

        Test-SkillNameDuplicateContentAllowed @($a, $b) | Should -Be $true
        Set-ContentUtf8 $b "---`nname: same`ndescription: changed`n---"
        Test-SkillNameDuplicateContentAllowed @($a, $b) | Should -Be $false
    }
}
