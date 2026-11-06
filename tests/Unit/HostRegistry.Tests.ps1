BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Application\HostRegistry.ps1')
}

Describe 'Agent host registry' {
    It 'keeps the ordered host list stable' {
        Get-AgentHostIds | Should -Be @('codex', 'claude', 'zcode', 'antigravity', 'workbuddy', 'dsh')
    }

    It 'binds every host fact to the repository rule tree' {
        foreach ($fact in (Get-AgentHostFacts)) {
            (Test-Path -LiteralPath (Join-Path $repoRoot ("rules/global/{0}/{1}" -f $fact.id, $fact.file))) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $repoRoot ("rules/global/platforms/{0}.md" -f $fact.id))) | Should -BeTrue
            @($fact.discovery_files) | Should -Contain $fact.file
            [string]::IsNullOrWhiteSpace([string]$fact.root_dir) | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$fact.label) | Should -BeFalse
        }
    }

    It 'resolves a known host fact and rejects unknown hosts' {
        (Get-AgentHostFact 'zcode').file | Should -Be 'AGENTS.md'
        @(Get-AgentHostFact 'workbuddy').discovery_files | Should -Be @('CODEBUDDY.md', 'CODEBUDDY.mdc')
        { Get-AgentHostFact 'unknown-host' } | Should -Throw
    }

    It 'declares the dsh shared skill and unverified MCP boundary' {
        $surface = @(Get-AgentHostSupportSurface)
        $surface.Count | Should -Be 6
        (@($surface | Where-Object host -eq 'dsh')[0]).skill_projection | Should -Be 'shared_agents_root'
        (@($surface | Where-Object host -eq 'dsh')[0]).mcp_projection | Should -Be 'not_verified'
        @($surface | Where-Object { $_.host -ne 'dsh' -and $_.skill_projection -ne 'profiled' }).Count | Should -Be 0
        @($surface | Where-Object live_acceptance -ne 'separate_probe').Count | Should -Be 0
    }

    It 'reports compatibility freshness without claiming host loading or live acceptance' {
        $current = @(Get-AgentHostCompatibilityStatus -AsOf ([datetime]'2026-11-09') -MaxAgeDays 30)
        $current.Count | Should -Be 6
        @($current | Where-Object status -ne 'current').Count | Should -Be 0
        @($current | Where-Object host_loaded).Count | Should -Be 0
        @($current | Where-Object live_accepted).Count | Should -Be 0

        $stale = @(Get-AgentHostCompatibilityStatus -AsOf ([datetime]'2026-12-15') -MaxAgeDays 30)
        @($stale | Where-Object status -eq 'stale').Count | Should -Be 6
    }

    It 'treats same-day verified_on as current at any hour, not future' {
        # 回归钉：verified_on 是本地日历日期。UTC+ 时区当天清晨曾因
        # AssumeUniversal+ToUniversalTime 折算被误判为 future。
        $sameDay = @(Get-AgentHostCompatibilityStatus -AsOf ([datetime]'2026-11-05 06:30') -MaxAgeDays 30)
        @($sameDay | Where-Object status -ne 'current').Count | Should -Be 0
        @($sameDay | Where-Object { $_.host -eq 'dsh' }).age_days | Should -Be 0

        $future = @(Get-AgentHostCompatibilityStatus -AsOf ([datetime]'2026-10-20') -MaxAgeDays 30)
        @($future | Where-Object status -eq 'future').Count | Should -Be 6
    }

    It 'declares DSH skill sharing without implying a model adapter' {
        $surfaces = @(Get-AgentHostSupportSurface)
        @($surfaces.host) | Should -Be @('codex', 'claude', 'zcode', 'antigravity', 'workbuddy', 'dsh')
        @($surfaces | Where-Object host -eq 'dsh').skill_projection | Should -Be 'shared_agents_root'
        @($surfaces | Where-Object host -eq 'dsh').mcp_projection | Should -Be 'not_verified'
        @($surfaces | Where-Object host -eq 'dsh').live_acceptance | Should -Be 'separate_probe'
    }

    It 'keeps every host ValidateSet in product source in sync with its surface' {
        # AST 校验已知函数参数的 ValidateSet；再扫描 src 源文本，任何以
        # codex 起头的宿主 ValidateSet 字面量都必须与其表面的宿主清单全等，
        # 防止出现新的平行枚举。规则面=注册表全量；技能面包含共享技能根
        # 覆盖的 dsh，但不要求为它制造独立技能 target。
        $ruleSurface = @(Get-AgentHostIds)
        $skillSurface = @('codex', 'claude', 'zcode', 'antigravity', 'workbuddy', 'dsh')
        $reflectionTargets = @(
            @{ Command = 'Get-RuleDiscovery'; Parameter = 'HostName'; File = 'src\Application\RuleDiscovery.ps1'; Expected = $ruleSurface }
            @{ Command = 'Resolve-SkillProjectionSelection'; Parameter = 'HostName'; File = 'src\Application\SkillProjection.ps1'; Expected = $skillSurface }
            @{ Command = 'Get-SkillProjectionEffectiveSelection'; Parameter = 'DefaultHost'; File = 'src\Application\SkillProjection.ps1'; Expected = $skillSurface }
        )
        foreach ($target in $reflectionTargets) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $target.File), [ref]$tokens, [ref]$errors)
            $fnDef = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object Name -eq $target.Command)[0]
            $fnDef | Should -Not -BeNullOrEmpty
            # 参数可能是 param() 块或函数名后圆括号两种风格。
            $allParams = if ($null -ne $fnDef.Body.ParamBlock) { @($fnDef.Body.ParamBlock.Parameters) } else { @($fnDef.Parameters) }
            $paramDef = @($allParams | Where-Object { $_.Name.VariablePath.UserPath -eq $target.Parameter })[0]
            $paramDef | Should -Not -BeNullOrEmpty
            $validateSet = @($paramDef.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' })[0]
            $validateSet | Should -Not -BeNullOrEmpty
            @($validateSet.PositionalArguments | ForEach-Object { $_.Value }) | Should -Be $target.Expected
        }
        $sourceRoot = Join-Path $repoRoot 'src'
        $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.ps1' -File | Where-Object { $_.FullName -notlike '*model-orchestration*' })
        $sourceFiles.Count | Should -BeGreaterThan 0
        $allowedSurfaces = @(
            ($ruleSurface -join '|'),
            ($skillSurface -join '|')
        )
        foreach ($file in $sourceFiles) {
            $text = [IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, "ValidateSet\('codex',\s*'claude'[^)]*\)")) {
                $values = @([regex]::Matches($match.Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
                ($values -join '|') | Should -BeIn $allowedSurfaces
            }
        }
    }
}
