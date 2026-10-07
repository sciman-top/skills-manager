#requires -Version 7.0
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Src = Join-Path $Root "src"
$Dist = Join-Path $Root "skills.ps1"

$Files = @(
    "Version.ps1",
    "Infrastructure/AtomicFile.ps1",
    "Infrastructure/CodexCli.ps1",
    "Domain/SkillMetadata.ps1",
    "Core.ps1",
    "Application/SkillSupply.ps1",
    "Domain/OperationPlan.ps1",
    "Domain/ExecutionAdmission.ps1",
    "Domain/SkillCatalog.ps1",
    "Domain/Receipt.ps1",
    "Domain/RuleDocument.ps1",
    "Domain/RuleResponsibility.ps1",
    "Domain/RulePatchPlan.ps1",
    "Application/SkillProjectionPlanning.ps1",
    "Application/CapabilityInventory.ps1",
    "Application/SkillCatalogCompiler.ps1",
    "Application/SkillEligibilityPolicy.ps1",
    "Application/SkillProjection.ps1",
    "Application/NativeSkillProjection.ps1",
    "Application/NativeSkillProjectionCoordinator.ps1",
    "Application/NativeAgentBridge.ps1",
    "Application/RuleDiscovery.ps1",
    "Application/RuleDiagnostics.ps1",
    "Application/RuleAdvisor.ps1",
    "Application/RuleAudit.ps1",
    "Application/RuleEstate.ps1",
    "Application/RuleEstateMutation.ps1",
    "Application/GlobalRuleProjection.ps1",
    "Application/RulePatchGuard.ps1",
    "Application/RulePatchExecutor.ps1",
    "Git.ps1",
    "Config.ps1",
    "Commands/Doctor.ps1",
    "Commands/AiCoding.ps1",
    "Commands/AiRiskControl.ps1",
    "Commands/Install.ps1",
    "Commands/Update.ps1",
    "Commands/Mcp.ProfileAndSafety.ps1",
    "Commands/Mcp.ps1",
    "Commands/Migration.ps1",
    "Commands/ReleaseUpdate.ps1",
    "Commands/Capability.ps1",
    "Commands/RuleAudit.ps1",
    "Commands/RuleEstate.ps1",
    "Commands/GlobalRules.ps1",
    "Commands/RulePatch.ps1",
    "Commands/AuditTargets.ps1",
    "Commands/AuditTargets.Template.ps1",
    "Commands/AuditTargets.Snapshot.ps1",
    "Commands/AuditTargets.TargetState.ps1",
    "Commands/AuditTargets.Plan.ps1",
    "Commands/AuditTargets.Bundle.ps1",
    "Commands/AuditTargets.Apply.ps1",
    "Commands/AuditTargets.Workflow.ps1",
    "Commands/AuditTargets.Args.ps1",
    "Commands/SkillProjection.ps1",
    "Commands/Utils.ps1",
    "Main.ps1"
)

# 清单完整性守卫：新增 src 文件漏登记时 bundle 内容不变，-Check 漂移检测对
# 清单外的输入天然失明。src/model-orchestration/ 按仓库契约独立于主构建链，
# 其余 .ps1 必须全部登记在 $Files。
$buildListed = @($Files | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)
$buildActual = @(
    Get-ChildItem -LiteralPath $Src -Recurse -Filter '*.ps1' -File |
        ForEach-Object { [IO.Path]::GetRelativePath($Src, $_.FullName).Replace('\', '/') } |
        Where-Object { $_ -notlike 'model-orchestration/*' } |
        Sort-Object
)
$buildUnlisted = @($buildActual | Where-Object { $buildListed -notcontains $_ })
if ($buildUnlisted.Count -gt 0) {
    throw ("build_manifest_incomplete: source files missing from `$Files: {0}" -f ($buildUnlisted -join ', '))
}

# ---------------------------------------------------------------------------
# 多文件生成布局：根 skills.ps1 = 薄入口（Version + 惰性加载器 + Main 分发），
# skills.lib/ = 与源文件 1:1 对应的库文件；base 常载，pack 按命令闭包惰性加载。
# 单次调用只解析/编译实际需要的库文件，消除整包 1.7MB 的固定启动编译税。
# ---------------------------------------------------------------------------
if ($Files[0] -ne 'Version.ps1' -or $Files[-1] -ne 'Main.ps1') {
    throw 'build_manifest_order: Version.ps1 must be first and Main.ps1 last in $Files.'
}
# 菜单/帮助入口常载（Utils 小且被轻命令复用）；Application 全部惰性。
$AlwaysLoadedCommandFiles = @('Commands/Utils.ps1')
$ThinEntryFiles = @('Version.ps1', 'Main.ps1')
$PackFiles = @(
    $Files | Where-Object {
        ($_ -like 'Application/*' -or $_ -like 'Commands/*') -and $AlwaysLoadedCommandFiles -notcontains $_
    }
)
$BaseLibFiles = @($Files | Where-Object { $ThinEntryFiles -notcontains $_ -and $PackFiles -notcontains $_ })

function Get-BundleFileAst {
    param([string]$RelativePath)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $Src ($RelativePath -replace '/', '\')), [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ("bundle_src_parse_failed: {0}: {1}" -f $RelativePath, $errors[0].Message)
    }
    return $ast
}

# --- 函数级闭包分析：Main 每个 switch 分支的入口函数出发，收集传递引用到的
# 库文件，生成 命令 -> 库清单 的加载计划。除函数调用边外，还追踪"函数引用了
# 其他文件顶层赋值的变量"这类边（静态可见性受限，漏边会以 CommandNotFound
# 立即暴露；Application 顶层的自愈 guard 会回退加载真实 src 兜底）。
$FunctionFile = @{}
$FunctionRefs = @{}
$FunctionVarRefs = @{}
$TopLevelVarOwners = @{}
$FileIndex = @{}
for ($i = 0; $i -lt $Files.Count; $i++) { $FileIndex[$Files[$i]] = $i }
$automaticVars = @('_', 'null', 'true', 'false', 'args', 'input', 'PSItem', 'this', 'PSScriptRoot', 'MyInvocation', 'ErrorActionPreference', 'LASTEXITCODE', 'matches')
foreach ($f in $Files) {
    if ($f -eq 'Main.ps1') { continue }
    $ast = Get-BundleFileAst $f
    $functionDefs = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    foreach ($fnDef in $functionDefs) {
        $FunctionFile[$fnDef.Name] = $f
        $FunctionRefs[$fnDef.Name] = @(
            $fnDef.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $FunctionVarRefs[$fnDef.Name] = @(
            $fnDef.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
                ForEach-Object { $_.VariablePath.UserPath } | Where-Object { $_ } | Sort-Object -Unique |
                Where-Object { $automaticVars -notcontains $_ })
    }
    # 顶层（函数体外）赋值的变量名：延迟加载的文件里，这些赋值随文件一起生效。
    $topAssignments = @(
        $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
            Where-Object {
                $owner = $_
                -not (@($functionDefs) | Where-Object { $owner.Extent.StartLineNumber -ge $_.Body.Extent.StartLineNumber -and $owner.Extent.StartLineNumber -le $_.Body.Extent.EndLineNumber })
            })
    foreach ($assign in $topAssignments) {
        $left = $assign.Left
        if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $name = $left.VariablePath.UserPath
            if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[:$]') { continue }
            if ($automaticVars -notcontains $name) {
                if (-not $TopLevelVarOwners.ContainsKey($name)) { $TopLevelVarOwners[$name] = @() }
                $TopLevelVarOwners[$name] = @($TopLevelVarOwners[$name] + $f)
            }
        }
    }
}

# 失效防线：base/入口外文件的顶层语句（加载即执行）禁止调用 pack 函数——
# 惰性加载前不可见（Application 顶层自愈 guard 走 src 路径 dot-source，不属违规）。
foreach ($f in @($BaseLibFiles + @('Version.ps1'))) {
    $ast = Get-BundleFileAst $f
    if ($null -eq $ast.EndBlock) { continue }
    $topLevelCommands = @(
        $ast.EndBlock.Statements |
            Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] } |
            ForEach-Object { $_.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) } |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    foreach ($name in $topLevelCommands) {
        if ($FunctionFile.ContainsKey($name) -and ($PackFiles -contains $FunctionFile[$name])) {
            throw ("lazy_pack_base_violation: {0} 顶层语句引用包内函数 {1}()（定义于 {2}）" -f $f, $name, $FunctionFile[$name])
        }
    }
}

# Main switch 分支 -> 标签与入口函数 -> 闭包 -> pack 文件清单。
$mainAst = Get-BundleFileAst 'Main.ps1'
$mainSwitch = @($mainAst.FindAll({ $args[0] -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))[0]
$PackPlan = [ordered]@{}
if ($null -ne $mainSwitch) {
    foreach ($clause in @($mainSwitch.Clauses)) {
        $conditionAst = $clause.Item1
        $bodyAst = $clause.Item2
        $labels = @()
        if ($conditionAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $labels = @($conditionAst.Value)
        }
        else {
            $labels = @(
                $conditionAst.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                    ForEach-Object Value)
        }
        if ($labels.Count -eq 0) { continue }
        $entryNames = @(
            $bodyAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $visited = New-Object 'System.Collections.Generic.HashSet[string]'
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($entry in $entryNames) {
            if ($FunctionFile.ContainsKey($entry)) { $queue.Enqueue($entry) }
        }
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            if (-not $visited.Add($current)) { continue }
            foreach ($refName in @($FunctionRefs[$current])) {
                if ($FunctionFile.ContainsKey($refName) -and -not $visited.Contains($refName)) {
                    $queue.Enqueue($refName)
                }
            }
            foreach ($varName in @($FunctionVarRefs[$current])) {
                if (-not $TopLevelVarOwners.ContainsKey($varName)) { continue }
                foreach ($ownerFile in @($TopLevelVarOwners[$varName])) {
                    foreach ($ownerFn in @($FunctionFile.Keys | Where-Object { $FunctionFile[$_] -eq $ownerFile })) {
                        if (-not $visited.Contains($ownerFn)) { $queue.Enqueue($ownerFn) }
                    }
                }
            }
        }
        $packList = @(
            $visited |
                ForEach-Object { $FunctionFile[$_] } |
                Sort-Object -Unique |
                Where-Object { $PackFiles -contains $_ } |
                Sort-Object { $FileIndex[$_] })
        # 交互式菜单按全量加载：子菜单以字符串交互为主，闭包不可靠。
        if ($labels -contains 'menu') { $packList = @($PackFiles) }
        foreach ($label in $labels) { $PackPlan[$label] = $packList }
    }
}

# 弃用别名在 Main 里先重映射再进 switch，本身无分支；让其继承规范命令的包清单，
# 保证 计划表 ⊇ ValidateSet 是全函数（加载期无需依赖重映射顺序）。
$aliasAssignment = @(
    $mainAst.FindAll({
        $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $args[0].Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $args[0].Left.VariablePath.UserPath -eq 'deprecatedCommandAliases'
    }, $true))[0]
$aliasRight = $aliasAssignment.Right
if ($aliasRight -is [System.Management.Automation.Language.CommandExpressionAst]) { $aliasRight = $aliasRight.Expression }
if ($null -ne $aliasAssignment -and $aliasRight -is [System.Management.Automation.Language.HashtableAst]) {
    foreach ($kv in @($aliasRight.KeyValuePairs)) {
        # 裸字符串字面量在表达式位会被包成 PipelineAst，统一取首个字符串常量。
        $aliasName = @($kv.Item1.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $false) | Select-Object -First 1)
        $aliasName = if ($aliasName.Count -gt 0) { $aliasName[0].Value } else { $null }
        $canonicalValues = @($kv.Item2.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $false) | Select-Object -First 1)
        $canonical = if ($canonicalValues.Count -gt 0) { $canonicalValues[0].Value } else { $null }
        if ($aliasName -and $canonical -and $PackPlan.Contains($canonical)) {
            $PackPlan[$aliasName] = @($PackPlan[$canonical])
        }
    }
}

function Get-LibFlatName([string]$RelativePath) { $RelativePath.Replace('/', '.') }
function Convert-ToBundleNewlines([string]$Text) { $Text.Replace("`r`n", "`n").Replace("`n", "`r`n") }

# 薄入口 = Version（param/编码/EAP）+ 惰性加载器 + Main（分发）。
$versionRaw = Get-Content -Path (Join-Path $Src 'Version.ps1') -Raw -Encoding UTF8
$mainRaw = Get-Content -Path (Join-Path $Src 'Main.ps1') -Raw -Encoding UTF8
$allPackLibNames = @($PackFiles | ForEach-Object { Get-LibFlatName $_ })
$baseLibNames = @($BaseLibFiles | ForEach-Object { Get-LibFlatName $_ })
$loaderLines = [System.Collections.Generic.List[string]]::new()
$loaderLines.Add('# --- 惰性库加载器（由 build.ps1 生成；改 src/，勿改此块）---')
$loaderLines.Add('$script:SkillsLibPackPlan = @{')
foreach ($planKey in @($PackPlan.Keys)) {
    $packNames = @($PackPlan[$planKey] | ForEach-Object { Get-LibFlatName $_ })
    $loaderLines.Add(("'{0}' = @({1})" -f $planKey, (($packNames | ForEach-Object { "'{0}'" -f $_ }) -join ', ')))
}
$loaderLines.Add('}')
$loaderLines.Add('$script:SkillsLibRoot = Join-Path $PSScriptRoot ''skills.lib''')
$loaderLines.Add('if (-not (Test-Path -LiteralPath $script:SkillsLibRoot -PathType Container)) { throw ("skills_lib_missing: {0}；请先运行 build.ps1 重新生成或重新安装" -f $script:SkillsLibRoot) }')
$loaderLines.Add(('$script:SkillsLibBase = @({0})' -f (($baseLibNames | ForEach-Object { "'{0}'" -f $_ }) -join ', ')))
$loaderLines.Add('foreach ($__lib in $script:SkillsLibBase) { . (Join-Path $script:SkillsLibRoot $__lib) }')
$loaderLines.Add('$script:SkillsLibPacks = @({0})' -f (($allPackLibNames | ForEach-Object { "'{0}'" -f $_ }) -join ', '))
$loaderLines.Add('if ($MyInvocation.InvocationName -eq ''.'') {')
$loaderLines.Add('    # Dot-source 模式（测试加载）保持全量函数面。')
$loaderLines.Add('    foreach ($__lib in $script:SkillsLibPacks) { . (Join-Path $script:SkillsLibRoot $__lib) }')
$loaderLines.Add('}')
$loaderLines.Add('else {')
$loaderLines.Add('    # 计划缺失时回退全量（fail-closed）。')
$loaderLines.Add('    $__packs = $script:SkillsLibPackPlan[$Cmd]')
$loaderLines.Add('    if ($null -eq $__packs) { $__packs = $script:SkillsLibPacks }')
$loaderLines.Add('    foreach ($__lib in @($__packs)) { . (Join-Path $script:SkillsLibRoot $__lib) }')
$loaderLines.Add('}')
$loaderText = Convert-ToBundleNewlines (($loaderLines -join "`r`n") + "`r`n")

$thinText = Convert-ToBundleNewlines ($versionRaw + "`r`n" + $loaderText + "`r`n" + $mainRaw)

# 库文件与源 1:1（仅规范化换行），保持文本可 grep 与 -Check 粒度。
$libOutputs = [ordered]@{}
foreach ($f in @($BaseLibFiles + $PackFiles)) {
    $raw = Get-Content -Path (Join-Path $Src $f) -Raw -Encoding UTF8
    $libOutputs[(Get-LibFlatName $f)] = Convert-ToBundleNewlines $raw
}

# 生成物自检：薄入口必须零解析错误。
$parseTokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($thinText, [ref]$parseTokens, [ref]$parseErrors) | Out-Null
if (@($parseErrors).Count -gt 0) {
    $details = @($parseErrors | ForEach-Object { '{0} at line {1}, column {2}' -f $_.Message, $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber }) -join '; '
    throw ("thin_entry_parse_failed: {0}" -f $details)
}

. (Join-Path $Src 'Infrastructure/AtomicFile.ps1')
. (Join-Path $Src 'Application/GlobalRuleProjection.ps1')
Sync-GlobalRuleGeneratedFiles -RepoRoot $Root -Check:$Check

# Keep a deterministic UTF-8 BOM for Windows distribution. This is an encoding
# choice for predictable file detection, not a Windows PowerShell 5.1 contract.
$utf8NoBom = [System.Text.Encoding]::UTF8
function Convert-ToBomBytes([string]$Text) {
    $bom = (New-Object System.Text.UTF8Encoding($true)).GetPreamble()
    $payload = $utf8NoBom.GetBytes($Text)
    $bytes = New-Object byte[] ($bom.Length + $payload.Length)
    [Array]::Copy($bom, 0, $bytes, 0, $bom.Length)
    [Array]::Copy($payload, 0, $bytes, $bom.Length, $payload.Length)
    return $bytes
}

$LibDir = Join-Path $Root 'skills.lib'
$expectedLibFiles = [System.Collections.Generic.HashSet[string]]::new()
foreach ($name in @($libOutputs.Keys)) { [void]$expectedLibFiles.Add($name) }
$staleLibs = @()
if (Test-Path -LiteralPath $LibDir -PathType Container) {
    $staleLibs = @(Get-ChildItem -LiteralPath $LibDir -File -Filter '*.ps1' | Where-Object Name | ForEach-Object Name | Where-Object { -not $expectedLibFiles.Contains($_) })
}

$thinBytes = Convert-ToBomBytes $thinText
if ($Check) {
    $drift = @()
    if (-not [IO.File]::Exists($Dist) -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($Dist)) -cne [Convert]::ToBase64String($thinBytes)) {
        $drift += 'skills.ps1'
    }
    foreach ($name in @($libOutputs.Keys)) {
        $libPath = Join-Path $LibDir $name
        if (-not [IO.File]::Exists($libPath) -or
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($libPath)) -cne [Convert]::ToBase64String((Convert-ToBomBytes $libOutputs[$name]))) {
            $drift += "skills.lib/$name"
        }
    }
    if ($staleLibs.Count -gt 0) {
        throw ("generated_bundle_stale_libs: skills.lib 存在清单外文件（重跑 build.ps1 清理）：{0}" -f ($staleLibs -join ', '))
    }
    if ($drift.Count -gt 0) {
        throw ("generated_bundle_drift: run build.ps1 and include the change: {0}" -f ($drift -join ', '))
    }
    Write-Host "Build check passed: $Dist + skills.lib ($(@($libOutputs.Keys).Count) files)" -ForegroundColor Green
}
else {
    New-Item -ItemType Directory -Path $LibDir -Force | Out-Null
    [System.IO.File]::WriteAllBytes($Dist, $thinBytes)
    foreach ($name in @($libOutputs.Keys)) {
        [System.IO.File]::WriteAllBytes((Join-Path $LibDir $name), (Convert-ToBomBytes $libOutputs[$name]))
    }
    foreach ($stale in $staleLibs) {
        Remove-Item -LiteralPath (Join-Path $LibDir $stale) -Force
    }
    Write-Host "Build success: $Dist (thin) + skills.lib ($(@($libOutputs.Keys).Count) files)" -ForegroundColor Green
}
