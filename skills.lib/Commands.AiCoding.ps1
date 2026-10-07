# Templates are advisory input; this command never scans a target repository
# or executes the commands, placeholders, or instructions in a template.
function Get-AiCodingTemplates {
    return [ordered]@{
        implementation = @'
Goal: <要实现或修复的用户可见结果>
Context: <仓库根、相关文件/模块、当前错误或复现步骤>
Constraints: <兼容性、不得触碰的目录、秘密和并发改动约束>
Exact write set: <允许修改的精确文件/目录；未知时先只读调查>
Minimum proof: <build、受影响测试、contract 或其他最低充分验证>
Done when: <用户操作、输入和期望结果>
Stop: <达到什么条件后停止，不做额外重构>

先读取当前目录、git status、项目规则、相关源码、调用方和测试。
复杂或模糊任务先探索和计划；范围明确的小改动直接执行。
完成后报告改动、验证命令、退出码、结果和剩余限制。
涉及投影或实际运行时分别报告 repo_verified / filesystem_projected /
host_loaded / live_accepted，不把低层证明当成高层验收。
'@
        review = @'
请只审查当前 diff/commit 的正确性、回归、安全、兼容和测试充分性。
先读取需求、当前仓库状态、实际源码、相关测试和项目规则。
Report gaps, not style preferences；不要为了提出建议而扩大范围。
只报告可由证据支持的 actionable findings，标明文件、触发条件、影响
和验证办法；实现者的总结只作为线索。没有发现问题时明确说明。
除非明确授权，不修改文件。
'@
        failure = @'
目标行为: <具体操作、输入与预期结果>
实际行为: <原始错误、相关日志或截图；去除秘密>
复现条件: <命令/步骤、版本、持续还是偶发>
已尝试: <改动或假设，以及各自失败证据>
请沿实际调用路径诊断，区分输入缺失、工具/环境失败与代码错误。
修复后用原复现验证，并检查一个与该缺陷相关的边界情况。
保留原需求与测试意图；不以放宽断言、扩大权限或换模型代替诊断。
同一问题连续失败两次时，先整理已证实事实、失败尝试和未决问题，
再决定澄清、压缩上下文或交接；认证/限流故障先按对应错误处置。
'@
        handoff = @'
Task capsule:
Goal: <目标>
Current status/evidence: <仓库路径、分支、commit、未提交修改与归属、关键证据>
Decisions already made: <已确定的接口、行为和取舍>
Exact write set: <精确写集>
Remaining work: <尚未完成的实现、验证或阻塞>
Minimum proof: <最低验证>
Stop: <停止条件>
请重新读取当前仓库状态与相关改动，再在上述写集内推进剩余工作。
不要根据模型名称猜测 API、provider、权限或宿主能力；不要扩大写集。
如果发现契约冲突或真实失败与胶囊不符，先停下并报告证据。
'@
        checklist = @'
[ ] 当前目录、项目规则、分支、HEAD 和 git status 已确认
[ ] Goal / Context / Constraints / Done when 明确
[ ] Exact write set / Minimum proof / Stop 已确定
[ ] 已沿真实入口读取相关源码、调用方和测试
[ ] 复杂或模糊任务先探索和计划，小改直接实现
[ ] 修改保留无关工作，不迁就实现放宽测试
[ ] 已运行覆盖当前失败模式的最低充分验证
[ ] 已检查 diff、生成物、秘密和临时文件
[ ] 已报告命令、退出码、实际结果和未验证边界
[ ] 达到目标后收口，复用未失效证据，不吸收无关优化
'@
    }
}

function Invoke-AiCodingCommand([object[]]$Tokens = @()) {
    $template = 'checklist'
    $asJson = $false
    $showHelp = $false
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        switch ($token.ToLowerInvariant()) {
            '--json' { $asJson = $true }
            { $_ -in @('--help', '-h') } { $showHelp = $true }
            '--template' {
                if ($i + 1 -ge @($Tokens).Count -or [string]$Tokens[$i + 1] -like '--*') {
                    throw '--template requires implementation|review|failure|handoff|checklist.'
                }
                $i++; $template = ([string]$Tokens[$i]).ToLowerInvariant()
            }
            default { throw ('Unknown ai-coding option: {0}' -f $token) }
        }
    }
    $templates = Get-AiCodingTemplates
    if (-not $templates.Contains($template)) { throw ('Unknown ai-coding template: {0}' -f $template) }
    $content = [string]$templates[$template]
    if ($showHelp) {
        $template = 'help'
        $content = @'
ai-coding：只读输出日常 AI 编码模板，不执行任务、不扫描目标仓、不修改宿主。
用法：.\skills.ps1 ai-coding [--template <name>] [--json]
模板：implementation | review | failure | handoff | checklist（默认）
别名：AI编码
文本和 JSON 均走 stdout，可复制或通过管道读取。
'@
    }
    $envelope = [pscustomobject][ordered]@{
        schema_version = 1; command = 'ai-coding'; template = $template
        truth_boundary = 'read_only_template'; writes = 0; provider_calls = 0; native_mutations = 0
        content = $content.TrimEnd()
    }
    return [pscustomobject]@{
        exit_code = 0; json = $asJson
        output = $(if ($asJson) { $envelope | ConvertTo-Json -Depth 5 -Compress } else { $envelope.content })
    }
}
