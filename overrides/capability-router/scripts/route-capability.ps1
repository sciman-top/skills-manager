[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Query,
    [string]$ManifestPath = "",
    [string]$PolicyPath = "",
    [string]$ConfigPath = "",
    [string]$CapabilitySnapshotPath = "",
    [string]$HostSnapshotPath = "",
    [string]$SessionSnapshotPath = "",
    [ValidateRange(1, 10080)][int]$MaxSnapshotAgeMinutes = 60,
    [string[]]$SkillRoot = @(),
    [ValidateRange(1, 5)][int]$TopK = 3,
    [ValidateRange(1, 100)][int]$MinScore = 7
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith("~/") -or $expanded.StartsWith("~\")) { $expanded = Join-Path $HOME $expanded.Substring(2) }
    if (Test-Path -LiteralPath $expanded -PathType Leaf) { return [IO.Path]::GetFullPath($expanded) }
    return ""
}

function Find-Manifest {
    $explicit = Resolve-ExistingFile $ManifestPath
    if ($explicit) { return $explicit }
    $fromEnv = Resolve-ExistingFile $env:SKILLS_MANAGER_PROJECTION_MANIFEST
    if ($fromEnv) { return $fromEnv }
    foreach ($start in @($PSScriptRoot, (Get-Location).Path)) {
        $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($start))
        while ($null -ne $cursor) {
            $candidate = Join-Path $cursor.FullName "reports\skill-projection\current.json"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            $cursor = $cursor.Parent
        }
    }
    return ""
}

function Test-Contained([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Read-SkillMetadata([string]$Path, [string]$Root, [bool]$Active) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or -not (Test-Contained $Path $Root)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $frontmatter = [regex]::Match($text, '(?s)\A---\s*\r?\n(?<yaml>.*?)\r?\n---')
    if (-not $frontmatter.Success) { return $null }
    $yaml = $frontmatter.Groups['yaml'].Value
    $nameMatch = [regex]::Match($yaml, '(?m)^name:\s*["'']?(?<value>[^\r\n"'']+)')
    $descriptionMatch = [regex]::Match($yaml, '(?m)^description:\s*["'']?(?<value>[^\r\n]+)')
    if (-not $nameMatch.Success -or -not $descriptionMatch.Success) { return $null }
    return [pscustomobject]@{
        kind = 'skill'
        name = $nameMatch.Groups['value'].Value.Trim()
        description = $descriptionMatch.Groups['value'].Value.Trim().Trim('"', "'")
        path = [IO.Path]::GetFullPath($Path)
        source_root = [IO.Path]::GetFullPath($Root)
        active = $Active
        availability = if ($Active) { 'available' } else { 'cold_load' }
        side_effect = 'read_only'
    }
}

function Get-StringArray($Value) {
    $result = [Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        $text = ([string]$item).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($text) -and -not $result.Contains($text)) { $result.Add($text) | Out-Null }
    }
    return @($result.ToArray())
}

function Get-QueryIntents([string]$Text) {
    $lower = $Text.ToLowerInvariant()
    $intents = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $patterns = [ordered]@{
        implement = '实现|重构|修改|更新|落盘|编码|修复|执行|自动自主|连续执行|implement|refactor|modify|update|write|execute|build'
        draft = '草拟|起草|草案|初稿|仅供审阅|review.only|draft'
        grill = '拷问|质询|追问|挑战方案|设计访谈|grill|interview|challenge.*design'
        research = '调研|研究|查证|官方文档|最佳实践|社区项目|research|official docs|best practice'
        diagnose = '诊断|调试|报错|错误|失败|故障|debug|diagnos|troubleshoot|failure|error'
        create = '创建|生成|制作|create|generate|make'
        publish = '发布|提交到追踪器|创建工单|publish|tracker|issue'
        setup = '初始化|安装|配置技能|setup|install|configure'
        scan = '架构扫描|扫描代码库|architecture scan|scan.*architecture'
    }
    foreach ($intent in $patterns.Keys) { if ($lower -match $patterns[$intent]) { $intents.Add($intent) | Out-Null } }
    return @($intents | Sort-Object)
}

function Get-TaskModel([string]$Text, [string[]]$Intents) {
    $lower = $Text.ToLowerInvariant()
    $taskType = 'general_task'
    $domain = 'general'
    $goal = 'complete_task'
    $operations = [Collections.Generic.List[string]]::new()
    $requestedKinds = [Collections.Generic.List[string]]::new()

    if ($lower -match '架构|architecture|工程终态|全局状态|全局最优|更优') {
        $taskType = 'architecture_assessment'
        $goal = 'evaluate_global_optimum'
        foreach ($operation in @('inspect', 'compare', 'recommend')) { $operations.Add($operation) }
    }
    if ($lower -match 'capabilit|技能|skills?|mcp|plugin|connector|native tool|profile|无感|无缝|路由|selector') {
        $domain = 'capability_orchestration'
    }
    elseif ($lower -match '\.net|dotnet|wpf|代码|仓库|实现|修复|测试|debug|implement|repository') {
        $domain = 'software_engineering'
    }
    foreach ($pair in @(
        @('skill', 'skills?|技能'), @('mcp', '\bmcp\b'), @('plugin', 'plugin|插件'),
        @('app', '\bapp\b|应用'), @('connector', 'connector|连接器'), @('native_tool', 'native tool|原生工具')
    )) {
        if ($lower -match $pair[1] -and -not $requestedKinds.Contains($pair[0])) { $requestedKinds.Add($pair[0]) }
    }
    if ($operations.Count -eq 0) {
        if ('research' -in $Intents -or $lower -match '调研|检查|分析|inspect|research') { $operations.Add('inspect') }
        if ('diagnose' -in $Intents) { $operations.Add('diagnose') }
        if ('implement' -in $Intents -or $lower -match '修复|实现|修改|refactor') { $operations.Add('implement') }
        if ($lower -match '测试|验证|verify|test') { $operations.Add('verify') }
    }
    $risk = if ($lower -match '删除|发布|退款|付款|写入|提交|push|delete|publish|refund') { 'controlled_write' } else { 'read_only' }
    [pscustomobject]@{
        task_type = $taskType; domain = $domain; goal = $goal
        operations = @($operations | Select-Object -Unique)
        requested_kinds = @($requestedKinds)
        risk = $risk; constraints = @(); confidence = if ($domain -eq 'general') { 0.55 } else { 0.9 }
    }
}

function Get-CapabilityGraph($TaskModel) {
    $stageIds = [Collections.Generic.List[string]]::new()
    foreach ($operation in @($TaskModel.operations)) {
        $stage = switch ([string]$operation) {
            'compare' { 'assess' }
            'recommend' { 'recommend' }
            default { [string]$operation }
        }
        if (-not $stageIds.Contains($stage)) { $stageIds.Add($stage) }
    }
    if ($stageIds.Count -eq 0) { $stageIds.Add('execute') }
    $stages = foreach ($id in $stageIds) { [pscustomobject]@{ id = $id; capability_refs = @() } }
    $edges = for ($i = 0; $i -lt ($stageIds.Count - 1); $i++) { [pscustomobject]@{ from = $stageIds[$i]; to = $stageIds[$i + 1] } }
    [pscustomobject]@{ stages = @($stages); edges = @($edges) }
}

function Test-IntentIntersection([string[]]$Left, [string[]]$Right) {
    foreach ($item in @($Left)) { if (@($Right) -contains $item) { return $true } }
    return $false
}

function Test-TermMatch([string]$Haystack, [string]$Term) {
    if ([string]::IsNullOrWhiteSpace($Haystack) -or [string]::IsNullOrWhiteSpace($Term)) { return $false }
    if ($Term -match '^[a-z0-9]+$' -and $Term.Length -le 4) {
        return [regex]::IsMatch($Haystack, ('(^|[^a-z0-9]){0}([^a-z0-9]|$)' -f [regex]::Escape($Term)), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $Haystack.Contains($Term)
}

$manifestFile = Find-Manifest
$manifest = if ($manifestFile) { Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$repoRoot = ''
if ($manifestFile) { $repoRoot = Split-Path (Split-Path (Split-Path $manifestFile -Parent) -Parent) -Parent }

$policyFile = Resolve-ExistingFile $PolicyPath
if (-not $policyFile -and $repoRoot) { $policyFile = Resolve-ExistingFile (Join-Path $repoRoot 'config\skill-routing-policy.json') }
$configFile = Resolve-ExistingFile $ConfigPath
if (-not $configFile -and $repoRoot) { $configFile = Resolve-ExistingFile (Join-Path $repoRoot 'skills.json') }
$snapshotFile = Resolve-ExistingFile $(if ([string]::IsNullOrWhiteSpace($HostSnapshotPath)) { $CapabilitySnapshotPath } else { $HostSnapshotPath })
$sessionFile = Resolve-ExistingFile $SessionSnapshotPath

$policy = if ($policyFile) { Get-Content -LiteralPath $policyFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$config = if ($configFile) { Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$queryLower = $Query.ToLowerInvariant()
$queryIntents = @(Get-QueryIntents $Query)
$taskModel = Get-TaskModel $Query $queryIntents
$snapshotStatus = 'not_provided'
$snapshotSource = ''
$snapshotCapturedAt = $null
$snapshotExclusions = [Collections.Generic.List[object]]::new()

$routing = @{}
if ($null -ne $policy) {
    foreach ($group in @($policy.groups)) {
        foreach ($member in @($group.members)) {
            $required = Get-StringArray $member.required_intents
            $excluded = Get-StringArray $member.excluded_intents
            $negativeText = ([string]$member.negative_activation).ToLowerInvariant()
            if ($negativeText -match 'implementation|refactor|repository write|autonomous execution' -and $excluded -notcontains 'implement') { $excluded += 'implement' }
            $routing[('skill|{0}' -f [string]$member.name)] = [pscustomobject]@{
                activation = [string]$member.activation
                negative_activation = [string]$member.negative_activation
                required_intents = @($required)
                excluded_intents = @($excluded)
                role = [string]$member.role
                group = [string]$group.id
                context = "{0} {1}" -f [string]$group.purpose, [string]$group.selection_policy
            }
        }
    }
}

$entries = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$activeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($null -ne $manifest) { foreach ($name in @($manifest.active | ForEach-Object name)) { $activeNames.Add([string]$name) | Out-Null } }
if ($null -ne $manifest) {
    foreach ($item in @($manifest.canonical)) {
        $entry = Read-SkillMetadata ([string]$item.path) ([string]$item.source_root) ($activeNames.Contains([string]$item.name))
        if ($null -ne $entry -and $entry.name -ne 'capability-router' -and $seen.Add(('skill|{0}' -f $entry.name))) { $entries.Add($entry) }
    }
}
else {
    $roots = [Collections.Generic.List[string]]::new()
    foreach ($root in @($SkillRoot + @((Join-Path $HOME '.agents\skills'), (Join-Path $HOME '.codex\skills')))) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root -PathType Container)) { $roots.Add([IO.Path]::GetFullPath($root)) }
    }
    foreach ($root in $roots) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'SKILL.md' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) {
            $entry = Read-SkillMetadata $file $root $false
            if ($null -ne $entry -and $entry.name -ne 'capability-router' -and $seen.Add(('skill|{0}' -f $entry.name))) { $entries.Add($entry) }
        }
    }
}

$mcpEnabled = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($null -ne $config -and $config.PSObject.Properties.Match('mcp_profiles').Count -gt 0 -and $null -ne $config.mcp_profiles) {
    $profileName = [string]$config.mcp_profiles.active
    $profile = @($config.mcp_profiles.profiles.PSObject.Properties | Where-Object { $_.Name -eq $profileName } | Select-Object -First 1)
    if ($profile.Count -eq 1) { foreach ($name in @($profile[0].Value.enabled)) { $mcpEnabled.Add([string]$name) | Out-Null } }
}

if ($null -ne $policy) {
    foreach ($capability in @($policy.capabilities)) {
        $kind = ([string]$capability.kind).Trim().ToLowerInvariant()
        $name = ([string]$capability.name).Trim()
        if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($name)) { continue }
        $key = '{0}|{1}' -f $kind, $name
        if (-not $seen.Add($key)) { continue }
        $available = if ($kind -eq 'mcp') { $mcpEnabled.Contains($name) } else { [bool]$capability.available }
        $entries.Add([pscustomobject]@{
            kind = $kind
            name = $name
            description = [string]$capability.description
            path = ''
            source_root = ''
            active = $available
            availability = if ($available) { 'available' } else { 'needs_activation' }
            side_effect = if ([string]::IsNullOrWhiteSpace([string]$capability.side_effect)) { 'unknown' } else { [string]$capability.side_effect }
        })
        $routing[$key] = [pscustomobject]@{
            activation = [string]$capability.activation
            negative_activation = [string]$capability.negative_activation
            required_intents = @(Get-StringArray $capability.required_intents)
            excluded_intents = @(Get-StringArray $capability.excluded_intents)
            role = 'capability'
            group = 'unified-capabilities'
            context = 'Select an installed or declared capability without mutating host state.'
        }
    }
}

if ($snapshotFile) {
    $snapshot = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $snapshotItems = if ($snapshot.PSObject.Properties.Match('capabilities').Count -gt 0) { @($snapshot.capabilities) } else { @($snapshot) }
    $snapshotSource = if ($snapshot.PSObject.Properties.Match('source').Count -gt 0) { [string]$snapshot.source } else { 'caller-provided' }
    $snapshotStatus = 'current'
    if ($snapshot.PSObject.Properties.Match('captured_at').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.captured_at)) {
        $snapshotCapturedAt = [DateTimeOffset]::Parse([string]$snapshot.captured_at)
        if (([DateTimeOffset]::UtcNow - $snapshotCapturedAt).TotalMinutes -gt $MaxSnapshotAgeMinutes) { $snapshotStatus = 'stale' }
    }
    foreach ($capability in $snapshotItems) {
        $kind = ([string]$capability.kind).Trim().ToLowerInvariant()
        $name = ([string]$capability.name).Trim()
        $key = '{0}|{1}' -f $kind, $name
        if ($kind -notin @('plugin', 'app', 'connector', 'native_tool', 'tool') -or [string]::IsNullOrWhiteSpace($name)) { continue }
        if ($snapshotStatus -eq 'stale') {
            $snapshotExclusions.Add([pscustomobject]@{ kind = $kind; name = $name; reason = 'stale_snapshot' }) | Out-Null
            continue
        }
        if (-not $seen.Add($key)) { continue }
        $availability = if ([string]::IsNullOrWhiteSpace([string]$capability.availability)) { 'unknown' } else { [string]$capability.availability }
        if ($capability.PSObject.Properties.Match('callable').Count -gt 0 -and -not [bool]$capability.callable) { $availability = 'not_callable' }
        if ($capability.PSObject.Properties.Match('accessible').Count -gt 0 -and -not [bool]$capability.accessible) { $availability = 'inaccessible' }
        $entries.Add([pscustomobject]@{
            kind = $kind; name = $name; description = [string]$capability.description; path = ''; source_root = ''
            active = ($availability -eq 'available'); availability = $availability
            side_effect = if ([string]::IsNullOrWhiteSpace([string]$capability.side_effect)) { 'unknown' } else { [string]$capability.side_effect }
        })
        $routing[$key] = [pscustomobject]@{
            activation = [string]$capability.activation; negative_activation = [string]$capability.negative_activation
            required_intents = @(Get-StringArray $capability.required_intents); excluded_intents = @(Get-StringArray $capability.excluded_intents)
            role = 'external'; group = 'runtime-snapshot'; context = 'Caller-provided current runtime capability snapshot.'
        }
    }
}

$terms = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($match in [regex]::Matches($queryLower, '[\p{L}\p{Nd}:+.-]{2,}')) { $terms.Add($match.Value) | Out-Null }
$expansions = [ordered]@{
    'ppt|pptx|课件|幻灯片' = @('ppt', 'pptx', 'slide', 'deck', 'courseware', 'presentation')
    '物理|动画|仿真|模拟' = @('physics', 'animation', 'simulation', 'manim', 'remotion')
    '\.net|dotnet|asp\.net|wpf|c#' = @('dotnet', '.net', 'asp.net', 'wpf', 'debug')
    '调试|报错|错误|失败|故障' = @('debug', 'failure', 'error', 'troubleshoot', 'diagnostic')
    '拷问|质询|追问|挑战方案|设计访谈' = @('grill', 'interview', 'assumption', 'tradeoff', 'adr', 'glossary')
    '草拟|起草|草案|初稿|draft' = @('draft', 'spec', 'document', 'review')
    '官方文档|开发文档|文档' = @('docs', 'documentation', 'developer', 'search', 'fetch')
    'openai|codex|chatgpt' = @('openai', 'codex', 'chatgpt')
    '数据库|postgres|sql' = @('database', 'postgres', 'sql')
    '网页|浏览器|网站|playwright' = @('browser', 'web', 'playwright', 'automation')
}
foreach ($pattern in $expansions.Keys) { if ($queryLower -match $pattern) { foreach ($term in $expansions[$pattern]) { $terms.Add($term) | Out-Null } } }
foreach ($word in @('the', 'and', 'with', 'for', 'use', 'this', 'that', 'help', 'please', '一个', '进行', '使用', '帮我', '实现')) { $terms.Remove($word) | Out-Null }

$excludedResults = [Collections.Generic.List[object]]::new()
foreach ($excluded in $snapshotExclusions) { $excludedResults.Add($excluded) | Out-Null }
$ranked = foreach ($entry in $entries) {
    $key = '{0}|{1}' -f $entry.kind, $entry.name
    $route = if ($routing.ContainsKey($key)) { $routing[$key] } else { $null }
    $name = $entry.name.ToLowerInvariant()
    $description = $entry.description.ToLowerInvariant()
    $compactName = $name -replace '[:._-]', ' '
    $explicit = $queryLower.Contains($name) -or $queryLower.Contains($compactName)
    if (-not $explicit -and $taskModel.task_type -eq 'architecture_assessment' -and
        ($name -match '(builder|cli|custom-windows|teacher-app)' -or ($null -ne $route -and $route.role -in @('operator', 'executor')))) {
        $excludedResults.Add([pscustomobject]@{ kind = $entry.kind; name = $entry.name; reason = 'task_type_mismatch' }) | Out-Null
        continue
    }
    if (-not $explicit -and $null -ne $route) {
        if (@($route.required_intents).Count -gt 0 -and -not (Test-IntentIntersection $queryIntents @($route.required_intents))) {
            $excludedResults.Add([pscustomobject]@{ kind = $entry.kind; name = $entry.name; reason = 'required_intent_missing' }) | Out-Null
            continue
        }
        if (Test-IntentIntersection $queryIntents @($route.excluded_intents)) {
            $excludedResults.Add([pscustomobject]@{ kind = $entry.kind; name = $entry.name; reason = 'negative_intent' }) | Out-Null
            continue
        }
    }
    $activation = if ($null -eq $route) { '' } else { ([string]$route.activation).ToLowerInvariant() }
    $context = if ($null -eq $route) { '' } else { ([string]$route.context).ToLowerInvariant() }
    $score = 0
    $reasons = [Collections.Generic.List[string]]::new()
    if ($explicit) { $score += 30; $reasons.Add('name_exact') }
    foreach ($term in $terms) {
        if (Test-TermMatch $name $term) { $score += 8; $reasons.Add("name:$term") }
        if (Test-TermMatch $description $term) { $score += 3; $reasons.Add("description:$term") }
        if (Test-TermMatch $activation $term) { $score += 4; $reasons.Add("activation:$term") }
        if (Test-TermMatch $context $term) { $score += 1; $reasons.Add("group:$term") }
    }
    if ($score -gt 0 -and $entry.active) { $score += 2; $reasons.Add('active_preference') }
    if ($score -gt 0 -and $null -ne $route -and $route.role -eq 'router') { $score += 2; $reasons.Add('domain_router') }
    if ($score -gt 0) {
        [pscustomobject]@{
            kind = $entry.kind; name = $entry.name; path = $entry.path; score = $score; active = [bool]$entry.active
            availability = $entry.availability
            side_effect = if ($null -ne $route -and $route.role -eq 'operator') { 'controlled_write' } else { $entry.side_effect }
            role = if ($null -eq $route) { '' } else { $route.role }
            group = if ($null -eq $route) { '' } else { $route.group }
            reason = @($reasons | Select-Object -Unique)
        }
    }
}

$ranked = @($ranked | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'active'; Descending = $true }, kind, name)
$abstained = $ranked.Count -eq 0 -or [int]$ranked[0].score -lt $MinScore
$selected = if ($abstained) { @() } else { @($ranked | Where-Object { [int]$_.score -ge $MinScore -and [int]$_.score -ge ([int]$ranked[0].score - 5) } | Select-Object -First $TopK) }

$activationPlan = foreach ($item in $selected) {
    $action = 'request_activation'
    $autoAllowed = $false
    $policyDecision = 'activation_required'
    if ($item.kind -eq 'skill' -and $item.side_effect -eq 'read_only') {
        $action = if ($item.active) { 'use_active_skill' } else { 'load_skill' }
        $autoAllowed = $true
        $policyDecision = 'allow'
    }
    elseif ($item.kind -eq 'skill') {
        $action = 'load_skill_with_approval'
        $policyDecision = 'approval_required'
    }
    elseif ($item.availability -eq 'available' -and $item.side_effect -in @('read_only', 'external_read')) {
        $action = if ($item.kind -eq 'mcp') { 'use_available_mcp' } else { 'use_available_capability' }
        $autoAllowed = $true
        $policyDecision = 'allow'
    }
    elseif ($item.availability -eq 'available') {
        $action = 'request_approval'
        $policyDecision = 'approval_required'
    }
    elseif ($item.kind -eq 'mcp') { $action = 'request_mcp_activation' }
    [pscustomobject]@{
        kind = $item.kind; name = $item.name; action = $action; auto_allowed = $autoAllowed
        policy_decision = $policyDecision; side_effect = $item.side_effect; path = $item.path
    }
}

$selectionMode = 'abstain'
if ($selected.Count -gt 0) {
    if (@($selected | Where-Object { $_.kind -ne 'skill' }).Count -gt 0) { $selectionMode = 'unified' }
    elseif (@($selected | Where-Object { -not $_.active }).Count -gt 0) { $selectionMode = 'cold_load' }
    else { $selectionMode = 'active' }
}

$session = if ($sessionFile) { Get-Content -LiteralPath $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$reuse = [Collections.Generic.List[object]]::new()
$load = [Collections.Generic.List[object]]::new()
foreach ($item in $selected) {
    $loadedMatch = if ($null -eq $session) { @() } else { @($session.loaded | Where-Object { [string]$_.kind -eq [string]$item.kind -and [string]$_.name -eq [string]$item.name }) }
    if ($loadedMatch.Count -gt 0 -and ([string]$session.task_domain -eq [string]$taskModel.domain -or [string]::IsNullOrWhiteSpace([string]$session.task_domain))) {
        $reuse.Add([pscustomobject]@{ kind = $item.kind; name = $item.name }) | Out-Null
    }
    else { $load.Add([pscustomobject]@{ kind = $item.kind; name = $item.name }) | Out-Null }
}
$profileRecommendation = switch ($taskModel.domain) {
    'software_engineering' { if ($queryLower -match '\.net|dotnet|wpf') { 'dotnet' } else { 'engineering' } }
    'capability_orchestration' { 'engineering' }
    default { 'default' }
}
$capabilityGraph = Get-CapabilityGraph $taskModel

[ordered]@{
    schema_version = 3
    query = $Query
    task_model = $taskModel
    intents = @($queryIntents)
    manifest_path = $manifestFile
    policy_path = $policyFile
    config_path = $configFile
    current_profile = if ($null -eq $manifest) { '' } else { [string]$manifest.active_profile }
    current_mcp_profile = if ($null -eq $config -or $config.PSObject.Properties.Match('mcp_profiles').Count -eq 0) { '' } else { [string]$config.mcp_profiles.active }
    host_snapshot = [ordered]@{ status = $snapshotStatus; source = $snapshotSource; captured_at = $snapshotCapturedAt; path = $snapshotFile }
    retrieval = [ordered]@{ strategy = 'hybrid_metadata_policy'; candidate_count = $entries.Count; top_candidates = @($ranked | Select-Object -First 5) }
    capability_graph = $capabilityGraph
    session_plan = [ordered]@{ reuse = @($reuse); load = @($load); release = @(); state_update = [ordered]@{ task_domain = $taskModel.domain } }
    preheat_recommendation = [ordered]@{ profile = $profileRecommendation; add = @($load); remove = @(); apply = $false }
    selection_mode = $selectionMode
    selected = @($selected)
    activation_plan = @($activationPlan)
    excluded = @($excludedResults.ToArray())
    abstained = $abstained
    candidate_count = $entries.Count
    capability_count = $entries.Count
    writes_performed = $false
} | ConvertTo-Json -Depth 10
