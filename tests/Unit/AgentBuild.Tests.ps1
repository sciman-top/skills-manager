BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Agent build" {
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
            Rollback-BuildTransaction $txn

            Test-Path -LiteralPath (Join-Path $AgentDir "old.txt") | Should -Be $true
            Test-Path -LiteralPath (Join-Path $AgentDir "new.txt") | Should -Be $false
        }
        finally {
            $Root = $oldRoot
            $AgentDir = $oldAgent
        }
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
