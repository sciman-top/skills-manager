BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Application\HostRegistry.ps1')
}

Describe 'Agent host registry' {
    It 'keeps the ordered host list stable' {
        Get-AgentHostIds | Should -Be @('codex', 'claude', 'zcode', 'antigravity', 'workbuddy')
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

    It 'keeps every host ValidateSet in product source in sync with the registry' {
        # AST 校验已知函数参数的 ValidateSet；再扫描 src 源文本，任何以
        # codex 起头的宿主 ValidateSet 字面量都必须与注册表全等，防止出现
        # 新的平行枚举。
        $expected = @(Get-AgentHostIds)
        $reflectionTargets = @(
            @{ Command = 'Get-RuleEstateGlobalDocument'; Parameter = 'HostName'; File = 'src\Application\RuleEstate.ps1' }
            @{ Command = 'Get-RuleDiscovery'; Parameter = 'HostName'; File = 'src\Application\RuleDiscovery.ps1' }
            @{ Command = 'Resolve-SkillProjectionSelection'; Parameter = 'HostName'; File = 'src\Application\SkillProjection.ps1' }
            @{ Command = 'Get-SkillProjectionEffectiveSelection'; Parameter = 'DefaultHost'; File = 'src\Application\SkillProjection.ps1' }
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
            @($validateSet.PositionalArguments | ForEach-Object { $_.Value }) | Should -Be $expected
        }
        $sourceRoot = Join-Path $repoRoot 'src'
        $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.ps1' -File | Where-Object { $_.FullName -notlike '*model-orchestration*' })
        $sourceFiles.Count | Should -BeGreaterThan 0
        foreach ($file in $sourceFiles) {
            $text = [IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, "ValidateSet\('codex',\s*'claude'[^)]*\)")) {
                $values = @([regex]::Matches($match.Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
                $values | Should -Be $expected
            }
        }
    }
}
