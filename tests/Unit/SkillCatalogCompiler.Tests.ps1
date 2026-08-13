$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')

$catalogDomainPath = Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1'
$catalogCompilerPath = Join-Path $repoRoot 'src\Application\SkillCatalogCompiler.ps1'
if (Test-Path -LiteralPath $catalogDomainPath -PathType Leaf) { . $catalogDomainPath }
if (Test-Path -LiteralPath $catalogCompilerPath -PathType Leaf) { . $catalogCompilerPath }

Describe 'Skill catalog compiler' {
    It 'compiles every managed root deterministically' {
        $compiler = Get-Command Compile-SkillCatalog -ErrorAction SilentlyContinue
        $compiler | Should Not BeNullOrEmpty
        if ($null -eq $compiler) { return }

        $rootA = Join-Path $TestDrive 'root-a'
        $rootB = Join-Path $TestDrive 'root-b'
        foreach ($item in @(
            [pscustomobject]@{ root = $rootA; directory = 'alpha'; name = 'alpha-skill'; description = 'Alpha capability.' },
            [pscustomobject]@{ root = $rootB; directory = 'beta'; name = 'beta-skill'; description = 'Beta capability.' }
        )) {
            $skillDirectory = Join-Path $item.root $item.directory
            New-Item -ItemType Directory -Path $skillDirectory -Force | Out-Null
            @("---", "name: $($item.name)", "description: $($item.description)", "---", "# $($item.name)") | Set-Content -LiteralPath (Join-Path $skillDirectory 'SKILL.md') -Encoding utf8
        }

        $catalog = Compile-SkillCatalog -Roots @($rootA, $rootB) -GeneratedAt '2026-08-07T05:00:00Z'

        $catalog.schema_version | Should Be 1
        @($catalog.entries).Count | Should Be 2
        @($catalog.entries | ForEach-Object name) | Should Be @('alpha-skill', 'beta-skill')
        $catalog.semantic_selection_applied | Should Be $false
        $catalog.decision_owner | Should Be 'host_ai'
        $catalog.provider_calls | Should Be 0
        $catalog.writes | Should Be 0
        (Test-SkillCatalogContract $catalog).pass | Should Be $true
    }

    It 'keeps duplicate canonical identities deterministic without silently omitting a root' {
        $compiler = Get-Command Compile-SkillCatalog -ErrorAction SilentlyContinue
        $compiler | Should Not BeNullOrEmpty
        if ($null -eq $compiler) { return }

        $entries = @(
            [pscustomobject]@{ name = 'same-skill'; description = 'first'; path = 'D:\fixture\one\SKILL.md'; source_root = 'D:\fixture\one'; enabled = $true; availability = 'available' },
            [pscustomobject]@{ name = 'same-skill'; description = 'second'; path = 'D:\fixture\two\SKILL.md'; source_root = 'D:\fixture\two'; enabled = $true; availability = 'available' }
        )

        $catalog = Compile-SkillCatalog -Entries $entries -GeneratedAt '2026-08-07T05:00:00Z'

        @($catalog.entries).Count | Should Be 1
        $catalog.entries[0].path | Should Be 'D:\fixture\one\SKILL.md'
        @($catalog.decisions | Where-Object disposition -eq 'duplicate').Count | Should Be 1
        $catalog.semantic_selection_applied | Should Be $false
        (Test-SkillCatalogContract $catalog).pass | Should Be $true
    }
}
