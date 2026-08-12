function Ensure-AuditArrayProperty($obj, [string]$name) {
    if (-not $obj.PSObject.Properties.Match($name).Count -or $null -eq $obj.$name) {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue @() -Force
    }
    elseif (-not (Assert-IsArray $obj.$name)) {
        $obj.$name = @($obj.$name)
    }
}

function Normalize-AuditStringArray($value) {
    if ($null -eq $value) { return @() }
    $items = if (Assert-IsArray $value) { @($value) } else { @($value) }
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $text = ([string]$item).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.Add($text)) {
            $normalized.Add($text) | Out-Null
        }
    }
    return @($normalized)
}

function Get-AuditRecommendationChangeItemCount($rec) {
    return @($rec.new_skills).Count + @($rec.removal_candidates).Count + @($rec.mcp_new_servers).Count + @($rec.mcp_removal_candidates).Count
}

function Normalize-AuditSourceObservationDecision([string]$decision) {
    $text = ([string]$decision).Trim().ToLowerInvariant()
    switch ($text) {
        "install" { return "add" }
        "selected" { return "add" }
        "uninstall" { return "remove" }
        "removed" { return "remove" }
        "skip" { return "do_not_install" }
        "reject" { return "do_not_install" }
        "rejected" { return "do_not_install" }
        "duplicate" { return "overlap" }
        default { return $text }
    }
}

function Assert-AuditSourceObservation($item) {
    Need ($null -ne $item) "source_observations 项不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "source_observations 缺少 name"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.candidate_type)) ("source_observations 缺少 candidate_type：{0}" -f [string]$item.name)
    $candidateType = ([string]$item.candidate_type).Trim().ToLowerInvariant()
    Need ($candidateType -eq "skill" -or $candidateType -eq "mcp") ("source_observations.candidate_type 仅支持 skill/mcp：{0}" -f $candidateType)
    $item.candidate_type = $candidateType

    Need (-not [string]::IsNullOrWhiteSpace([string]$item.decision)) ("source_observations 缺少 decision：{0}" -f [string]$item.name)
    $decision = Normalize-AuditSourceObservationDecision ([string]$item.decision)
    Need (@("add", "remove", "keep", "do_not_install", "overlap", "ignore") -contains $decision) ("source_observations.decision 不支持：{0}" -f [string]$item.decision)
    $item.decision = $decision

    Need (-not [string]::IsNullOrWhiteSpace([string]$item.rationale)) ("source_observations 缺少 rationale：{0}" -f [string]$item.name)
    Normalize-AuditSources $item "source_observations"
    if ($item.PSObject.Properties.Match("source_categories").Count -eq 0 -or $null -eq $item.source_categories) {
        $item | Add-Member -NotePropertyName source_categories -NotePropertyValue @() -Force
    }
    else {
        $item.source_categories = @(Normalize-AuditStringArray $item.source_categories)
    }
}

function Test-AuditHasSourceObservationForChange($rec, [string]$candidateType, [string]$decision, [string]$name) {
    $normalizedType = ([string]$candidateType).Trim().ToLowerInvariant()
    $normalizedDecision = Normalize-AuditSourceObservationDecision $decision
    $normalizedName = ([string]$name).Trim()
    foreach ($observation in @($rec.source_observations)) {
        if ($null -eq $observation) { continue }
        $obsType = ([string]$observation.candidate_type).Trim().ToLowerInvariant()
        $obsDecision = Normalize-AuditSourceObservationDecision ([string]$observation.decision)
        $obsName = ([string]$observation.name).Trim()
        if ($obsType -eq $normalizedType -and $obsDecision -eq $normalizedDecision -and $obsName -eq $normalizedName -and @($observation.sources).Count -gt 0) {
            return $true
        }
    }
    return $false
}

function Get-AuditRecommendationSourceCoverage($rec) {
    $allSources = New-Object System.Collections.Generic.List[string]
    foreach ($collection in @($rec.new_skills, $rec.removal_candidates, $rec.mcp_new_servers, $rec.mcp_removal_candidates)) {
        foreach ($item in @($collection)) {
            foreach ($source in @(Normalize-AuditStringArray $item.sources)) {
                $allSources.Add($source) | Out-Null
            }
        }
    }
    $uniqueSources = @(Normalize-AuditStringArray $allSources)
    $httpSources = @($uniqueSources | Where-Object { [regex]::IsMatch([string]$_, "^(?i)https?://") })
    $missingObservation = New-Object System.Collections.Generic.List[string]
    $itemsWithObservation = 0
    $changeGroups = @(
        @{ type = "skill"; decision = "add"; items = @($rec.new_skills) },
        @{ type = "skill"; decision = "remove"; items = @($rec.removal_candidates) },
        @{ type = "mcp"; decision = "add"; items = @($rec.mcp_new_servers) },
        @{ type = "mcp"; decision = "remove"; items = @($rec.mcp_removal_candidates) }
    )
    foreach ($group in @($changeGroups)) {
        foreach ($item in @($group.items)) {
            $itemName = [string]$item.name
            if (Test-AuditHasSourceObservationForChange $rec ([string]$group.type) ([string]$group.decision) $itemName) {
                $itemsWithObservation++
            }
            else {
                $missingObservation.Add(("{0}:{1}:{2}" -f [string]$group.type, [string]$group.decision, $itemName)) | Out-Null
            }
        }
    }
    return [pscustomobject]([ordered]@{
        total_change_items = Get-AuditRecommendationChangeItemCount $rec
        unique_sources = @($uniqueSources)
        unique_source_count = @($uniqueSources).Count
        http_source_count = @($httpSources).Count
        source_observation_count = @($rec.source_observations).Count
        items_with_source_observation = $itemsWithObservation
        change_items_missing_source_observation = @($missingObservation)
    })
}

function Normalize-AuditSources($item, [string]$kind) {
    Ensure-AuditArrayProperty $item "sources"
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @($item.sources)) {
        if ($null -eq $source) { continue }
        $text = ([string]$source).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.Add($text)) {
            $normalized.Add($text) | Out-Null
        }
    }
    $item.sources = @($normalized)
    Need (@($item.sources).Count -gt 0) ("{0} 至少需要一个非空 source：{1}" -f $kind, [string]$item.name)
}

function Normalize-AuditKeywordTrace($item) {
    $defaultTrace = [pscustomobject]([ordered]@{
            user_profile = @()
            target_repo_or_context = @()
            installed_state = @()
        })
    if ($item.PSObject.Properties.Match("keyword_trace").Count -eq 0 -or $null -eq $item.keyword_trace) {
        $item | Add-Member -NotePropertyName keyword_trace -NotePropertyValue $defaultTrace -Force
        return
    }
    Need (Test-AuditObjectLike $item.keyword_trace) ("keyword_trace 必须是对象：{0}" -f [string]$item.name)
    foreach ($field in @("user_profile", "target_repo_or_context", "installed_state")) {
        if ($item.keyword_trace.PSObject.Properties.Match($field).Count -eq 0 -or $null -eq $item.keyword_trace.$field) {
            $item.keyword_trace | Add-Member -NotePropertyName $field -NotePropertyValue @() -Force
        }
        else {
            $item.keyword_trace.$field = @(Normalize-AuditStringArray $item.keyword_trace.$field)
        }
    }
}

function Assert-AuditRequiredBooleanTrue($value, [string]$fieldName) {
    Need ($value -is [bool]) ("{0} 必须是布尔值 true" -f $fieldName)
    Need ([bool]$value) ("{0} 必须为 true" -f $fieldName)
}

function Assert-AuditReasonPair($item, [string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_user_profile)) ("{0} 缺少 reason_user_profile：{1}" -f $name, [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_target_repo)) ("{0} 缺少 reason_target_repo：{1}" -f $name, [string]$item.name)
    Normalize-AuditSources $item $name
    Normalize-AuditKeywordTrace $item
}

function Assert-AuditOverlapFinding($item) {
    Need ($null -ne $item) "重叠发现不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "重叠发现缺少 name"
    Assert-AuditReasonPair $item "重叠发现"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.note)) ("重叠发现缺少 note：{0}" -f [string]$item.name)
    if ($item.PSObject.Properties.Match("routing").Count -eq 0 -or $null -eq $item.routing) { return }

    Need (Test-AuditObjectLike $item.routing) ("重叠发现 routing 必须是对象：{0}" -f [string]$item.name)
    $decisionOwner = if ($item.routing.PSObject.Properties.Match("decision_owner").Count -gt 0) { ([string]$item.routing.decision_owner).Trim().ToLowerInvariant() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($decisionOwner)) {
        Need ($decisionOwner -eq "host_ai") ("重叠发现 routing.decision_owner 仅支持 host_ai：{0}/{1}" -f [string]$item.name, $decisionOwner)
        $item.routing.decision_owner = $decisionOwner
    }
    $router = if ($item.routing.PSObject.Properties.Match("router").Count -gt 0) { ([string]$item.routing.router).Trim() } else { "" }
    $fallbackRouter = if ($item.routing.PSObject.Properties.Match("fallback_router").Count -gt 0) { ([string]$item.routing.fallback_router).Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($decisionOwner)) {
        Need (-not [string]::IsNullOrWhiteSpace($router)) ("重叠发现 routing 缺少 router：{0}" -f [string]$item.name)
    }
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.routing.selection_policy)) ("重叠发现 routing 缺少 selection_policy：{0}" -f [string]$item.name)
    Need ($item.routing.PSObject.Properties.Match("members").Count -gt 0 -and (Assert-IsArray $item.routing.members)) ("重叠发现 routing.members 必须是数组：{0}" -f [string]$item.name)
    Need (@($item.routing.members).Count -ge 2) ("重叠发现 routing.members 至少需要两个成员：{0}" -f [string]$item.name)
    $allowedRoles = @("router", "executor", "validator", "operator", "workflow", "reference")
    $seenMembers = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $memberRoles = @{}
    foreach ($member in @($item.routing.members)) {
        Need ($null -ne $member) ("重叠发现 routing.member 不能为空：{0}" -f [string]$item.name)
        $memberName = ([string]$member.name).Trim()
        $role = ([string]$member.role).Trim().ToLowerInvariant()
        Need (-not [string]::IsNullOrWhiteSpace($memberName)) ("重叠发现 routing.member 缺少 name：{0}" -f [string]$item.name)
        Need ($allowedRoles -contains $role) ("重叠发现 routing.member role 不支持：{0}/{1}" -f [string]$item.name, $role)
        Need ($seenMembers.Add($memberName)) ("重叠发现 routing.member 重复：{0}/{1}" -f [string]$item.name, $memberName)
        $member.role = $role
        $memberRoles[$memberName] = $role
    }
    if (-not [string]::IsNullOrWhiteSpace($router)) {
        Need ($seenMembers.Contains($router)) ("重叠发现 routing.router 必须出现在 members：{0}/{1}" -f [string]$item.name, $router)
        Need ([string]$memberRoles[$router] -eq "router") ("重叠发现 routing.router 对应成员必须使用 role=router：{0}/{1}" -f [string]$item.name, $router)
    }
    if (-not [string]::IsNullOrWhiteSpace($fallbackRouter)) {
        Need ($seenMembers.Contains($fallbackRouter)) ("重叠发现 routing.fallback_router 必须出现在 members：{0}/{1}" -f [string]$item.name, $fallbackRouter)
        Need ([string]$memberRoles[$fallbackRouter] -eq "router") ("重叠发现 routing.fallback_router 对应成员必须使用 role=router：{0}/{1}" -f [string]$item.name, $fallbackRouter)
    }
}

function Add-AuditExactJsonValueReferences($value, [string]$needle, [string]$jsonPath, [string]$file, $references) {
    if ($null -eq $value) { return }
    if ($value -is [string]) {
        if ([string]::Equals([string]$value, $needle, [System.StringComparison]::OrdinalIgnoreCase)) {
            $references.Add([pscustomobject]([ordered]@{ file = $file; path = $jsonPath })) | Out-Null
        }
        return
    }
    if ($value -is [System.Collections.IDictionary]) {
        foreach ($key in $value.Keys) {
            Add-AuditExactJsonValueReferences $value[$key] $needle ("{0}.{1}" -f $jsonPath, [string]$key) $file $references
        }
        return
    }
    if ((Assert-IsArray $value) -or ($value -is [System.Collections.IList])) {
        $index = 0
        foreach ($entry in @($value)) {
            Add-AuditExactJsonValueReferences $entry $needle ("{0}[{1}]" -f $jsonPath, $index) $file $references
            $index++
        }
        return
    }
    if (Test-AuditObjectLike $value) {
        foreach ($property in $value.PSObject.Properties) {
            Add-AuditExactJsonValueReferences $property.Value $needle ("{0}.{1}" -f $jsonPath, [string]$property.Name) $file $references
        }
    }
}

function Test-AuditRemovalDependencyClosure {
    param(
        $Config,
        $RemovalCandidates,
        [string]$RepositoryRoot = $Root
    )
    $blocked = New-Object System.Collections.Generic.List[object]
    $issues = New-Object System.Collections.Generic.List[string]
    $checkedFiles = @(
        "skills.json",
        "config/skill-dependency-closure.json",
        "config/skill-routing-policy.json",
        "config/override-skill-activation-corpus.json",
        "config/capability-routing-golden.json",
        "overrides/patches/provenance.json"
    )
    $candidateIndex = 0
    foreach ($candidate in @($RemovalCandidates)) {
        $candidateIndex++
        $name = ([string]$candidate.name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $references = New-Object System.Collections.Generic.List[object]
        if ($null -ne $Config -and $Config.PSObject.Properties.Match("skill_projection").Count -gt 0 -and $null -ne $Config.skill_projection) {
            $projection = $Config.skill_projection
            if ($projection.PSObject.Properties.Match("aliases").Count -gt 0) {
                $aliasIndex = 0
                foreach ($alias in @($projection.aliases)) {
                    if ($null -ne $alias -and [string]::Equals([string]$alias.replacement, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $references.Add([pscustomobject]([ordered]@{ file = "skills.json"; path = "$.skill_projection.aliases[$aliasIndex].replacement" })) | Out-Null
                    }
                    $aliasIndex++
                }
            }
            if ($projection.PSObject.Properties.Match("discovery_catalog").Count -gt 0 -and $null -ne $projection.discovery_catalog) {
                Add-AuditExactJsonValueReferences $projection.discovery_catalog $name '$.skill_projection.discovery_catalog' "skills.json" $references
            }
        }
        foreach ($relativePath in @($checkedFiles | Select-Object -Skip 1)) {
            $fullPath = Join-Path $RepositoryRoot $relativePath
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
            try {
                $json = Get-ContentUtf8 $fullPath | ConvertFrom-Json
                Add-AuditExactJsonValueReferences $json $name '$' ($relativePath -replace '\\', '/') $references
            }
            catch {
                $references.Add([pscustomobject]([ordered]@{ file = ($relativePath -replace '\\', '/'); path = '$'; error = "json_parse_failed: $($_.Exception.Message)" })) | Out-Null
            }
        }
        if ($references.Count -gt 0) {
            $originalIndex = if ($candidate.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$candidate.original_index } else { $candidateIndex }
            $entry = [pscustomobject]([ordered]@{
                    original_index = $originalIndex
                    name = $name
                    references = $references.ToArray()
                })
            $blocked.Add($entry) | Out-Null
            $referenceText = ($references.ToArray() | ForEach-Object { "{0}{1}" -f [string]$_.file, [string]$_.path }) -join ", "
            $issues.Add(("removal_dependency_blocked：{0}) {1} <- {2}" -f $originalIndex, $name, $referenceText)) | Out-Null
        }
    }
    return [pscustomobject]([ordered]@{
            ok = ($blocked.Count -eq 0)
            checked_files = $checkedFiles
            blocked = $blocked.ToArray()
            issues = $issues.ToArray()
        })
}

function Assert-AuditRecommendationItem($item) {
    Need ($null -ne $item) "推荐项不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "推荐项缺少 name"
    Assert-AuditReasonPair $item "推荐项"
    Need ($item.PSObject.Properties.Match("install").Count -gt 0 -and $null -ne $item.install) ("推荐项缺少 install：{0}" -f [string]$item.name)

    $install = $item.install
    Need (-not [string]::IsNullOrWhiteSpace([string]$install.repo)) ("推荐项缺少 install.repo：{0}" -f [string]$item.name)
    Need (Looks-LikeRepoInput ([string]$install.repo)) ("install.repo 不是有效仓库输入：{0}" -f [string]$install.repo)

    Need ($install.PSObject.Properties.Match("skill").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.skill)) ("推荐项缺少 install.skill：{0}" -f [string]$item.name)
    $skillPath = [string]$install.skill
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need (Test-SafeRelativePath $normalizedSkill -AllowDot) ("install.skill 路径非法：{0}" -f $skillPath)
    $install.skill = $normalizedSkill

    Need ($install.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.mode)) ("推荐项缺少 install.mode：{0}" -f [string]$item.name)
    $mode = [string]$install.mode
    $mode = $mode.ToLowerInvariant()
    Need ($mode -eq "manual" -or $mode -eq "vendor") ("install.mode 仅支持 manual 或 vendor：{0}" -f $mode)
    $install.mode = $mode

    $confidence = ([string]$item.confidence).ToLowerInvariant()
    Need ($confidence -eq "low" -or $confidence -eq "medium" -or $confidence -eq "high") ("confidence 仅支持 low/medium/high：{0}" -f [string]$item.confidence)
    $item.confidence = $confidence
    $item | Add-Member -NotePropertyName reason -NotePropertyValue ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo) -Force
}

function Assert-AuditRemovalCandidate($item) {
    Need ($null -ne $item) "卸载建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "卸载建议缺少 name"
    Assert-AuditReasonPair $item "卸载建议"
    Need ($item.PSObject.Properties.Match("installed").Count -gt 0 -and $null -ne $item.installed) ("卸载建议缺少 installed：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.vendor)) ("卸载建议缺少 installed.vendor：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.from)) ("卸载建议缺少 installed.from：{0}" -f [string]$item.name)
}

function Assert-AuditMcpServerPayload($server, [string]$itemName) {
    Need ($null -ne $server) ("MCP 新增建议缺少 server：{0}" -f $itemName)
    Need (-not [string]::IsNullOrWhiteSpace([string]$server.name)) ("MCP 新增建议缺少 server.name：{0}" -f $itemName)
    $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.transport)) {
        ([string]$server.transport).Trim().ToLowerInvariant()
    }
    else {
        "stdio"
    }
    Need ($transport -eq "stdio" -or $transport -eq "sse" -or $transport -eq "http") ("MCP transport 仅支持 stdio/sse/http：{0}" -f $transport)
    $server.transport = $transport
    if ($transport -eq "stdio") {
        Need ($server.PSObject.Properties.Match("command").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.command)) ("MCP stdio 缺少 command：{0}" -f $itemName)
        if ($server.PSObject.Properties.Match("args").Count -eq 0 -or $null -eq $server.args) {
            $server | Add-Member -NotePropertyName args -NotePropertyValue @() -Force
        }
        elseif (-not (Assert-IsArray $server.args)) {
            $server.args = @($server.args)
        }
    }
    else {
        Need ($server.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.url)) ("MCP {0} 缺少 url：{1}" -f $transport, $itemName)
    }
}

function Assert-AuditMcpNewServer($item) {
    Need ($null -ne $item) "MCP 新增建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "MCP 新增建议缺少 name"
    Assert-AuditReasonPair $item "MCP 新增建议"
    Need ($item.PSObject.Properties.Match("server").Count -gt 0) ("MCP 新增建议缺少 server：{0}" -f [string]$item.name)
    Assert-AuditMcpServerPayload $item.server ([string]$item.name)
    Need ([string]$item.server.name -eq [string]$item.name) ("MCP 新增建议 name 与 server.name 不一致：{0}" -f [string]$item.name)
    $confidence = ([string]$item.confidence).ToLowerInvariant()
    Need ($confidence -eq "low" -or $confidence -eq "medium" -or $confidence -eq "high") ("MCP confidence 仅支持 low/medium/high：{0}" -f [string]$item.confidence)
    $item.confidence = $confidence
    $item | Add-Member -NotePropertyName reason -NotePropertyValue ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo) -Force
}

function Assert-AuditMcpRemovalCandidate($item) {
    Need ($null -ne $item) "MCP 卸载建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "MCP 卸载建议缺少 name"
    Assert-AuditReasonPair $item "MCP 卸载建议"
    Need ($item.PSObject.Properties.Match("installed").Count -gt 0 -and $null -ne $item.installed) ("MCP 卸载建议缺少 installed：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.name)) ("MCP 卸载建议缺少 installed.name：{0}" -f [string]$item.name)
}

function Load-AuditRecommendations([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "--recommendations 缺少值"
    Need (Test-Path -LiteralPath $path -PathType Leaf) ("recommendations 文件不存在：{0}" -f $path)
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("recommendations 文件为空：{0}" -f $path)
        $rec = $raw | ConvertFrom-Json
    }
    catch {
        throw ("recommendations JSON 解析失败：{0}" -f $_.Exception.Message)
    }

    Need ([int]$rec.schema_version -eq 2) "recommendations.schema_version 仅支持 2"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.run_id)) "recommendations 缺少 run_id"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.target)) "recommendations 缺少 target"
    Need ($rec.PSObject.Properties.Match("decision_basis").Count -gt 0 -and $null -ne $rec.decision_basis) "recommendations 缺少 decision_basis"
    Need (Test-AuditJsonProperty $rec.decision_basis "user_profile_used") "decision_basis 缺少 user_profile_used"
    Need (Test-AuditJsonProperty $rec.decision_basis "target_scan_used") "decision_basis 缺少 target_scan_used"
    Need (Test-AuditJsonProperty $rec.decision_basis "source_strategy_used") "decision_basis 缺少 source_strategy_used"
    $recommendationMode = "target-repo"
    if ($rec.PSObject.Properties.Match("recommendation_mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$rec.recommendation_mode)) {
        $recommendationMode = ([string]$rec.recommendation_mode).ToLowerInvariant()
    }
    Need ($recommendationMode -eq "target-repo" -or $recommendationMode -eq "profile-only") ("recommendation_mode 仅支持 target-repo 或 profile-only：{0}" -f $recommendationMode)
    Assert-AuditRequiredBooleanTrue $rec.decision_basis.user_profile_used "decision_basis.user_profile_used"
    Need ($rec.decision_basis.target_scan_used -is [bool]) "decision_basis.target_scan_used 必须是布尔值"
    if ($recommendationMode -eq "profile-only") {
        Need (-not [bool]$rec.decision_basis.target_scan_used) "profile-only 模式下 decision_basis.target_scan_used 必须为 false"
    }
    else {
        Assert-AuditRequiredBooleanTrue $rec.decision_basis.target_scan_used "decision_basis.target_scan_used"
    }
    Assert-AuditRequiredBooleanTrue $rec.decision_basis.source_strategy_used "decision_basis.source_strategy_used"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.decision_basis.summary)) "decision_basis.summary 不能为空"
    Ensure-AuditArrayProperty $rec "new_skills"
    Ensure-AuditArrayProperty $rec "overlap_findings"
    Ensure-AuditArrayProperty $rec "removal_candidates"
    Ensure-AuditArrayProperty $rec "do_not_install"
    Ensure-AuditArrayProperty $rec "mcp_new_servers"
    Ensure-AuditArrayProperty $rec "mcp_removal_candidates"
    Ensure-AuditArrayProperty $rec "empty_recommendation_reasons"
    Ensure-AuditArrayProperty $rec "source_observations"

    foreach ($item in @($rec.source_observations)) {
        Assert-AuditSourceObservation $item
    }

    $seenOverlapFindings = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.overlap_findings)) {
        Assert-AuditOverlapFinding $item
        Need ($seenOverlapFindings.Add(([string]$item.name).Trim())) ("重复重叠发现：{0}" -f [string]$item.name)
    }

    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.new_skills)) {
        Assert-AuditRecommendationItem $item
        $install = $item.install
        $key = "{0}|{1}|{2}" -f (Normalize-RepoUrl ([string]$install.repo)), (Normalize-SkillPath ([string]$install.skill)), ([string]$install.mode)
        Need ($seen.Add($key)) ("重复推荐安装项：{0}" -f $key)
    }

    $seenRemovals = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.removal_candidates)) {
        Assert-AuditRemovalCandidate $item
        $key = "{0}|{1}" -f [string]$item.installed.vendor, [string]$item.installed.from
        Need ($seenRemovals.Add($key)) ("重复卸载建议：{0}" -f $key)
    }

    $seenMcpAdds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.mcp_new_servers)) {
        Assert-AuditMcpNewServer $item
        $key = [string]$item.server.name
        Need ($seenMcpAdds.Add($key)) ("重复 MCP 新增建议：{0}" -f $key)
    }

    $seenMcpRemovals = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.mcp_removal_candidates)) {
        Assert-AuditMcpRemovalCandidate $item
        $key = [string]$item.installed.name
        Need ($seenMcpRemovals.Add($key)) ("重复 MCP 卸载建议：{0}" -f $key)
    }

    $changeItemCount = Get-AuditRecommendationChangeItemCount $rec
    $emptyReasonCodes = @(Normalize-AuditStringArray $rec.empty_recommendation_reasons)
    if ($changeItemCount -eq 0 -and $emptyReasonCodes.Count -eq 0) {
        $emptyReasonCodes = @("insufficient_reliable_evidence")
    }
    $rec.empty_recommendation_reasons = @($emptyReasonCodes)

    return $rec
}

function New-AuditInstallPlan($recommendations, $cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $installedFacts = @(Get-InstalledSkillFacts $cfg)
    $installedMcpServers = @()
    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) {
        $installedMcpServers = @($cfg.mcp_servers)
    }
    $items = @()
    $originalIndex = 0
    foreach ($item in @($recommendations.new_skills)) {
        $originalIndex++
        $install = $item.install
        $tokens = @([string]$install.repo, "--skill", [string]$install.skill)
        if ($install.PSObject.Properties.Match("ref").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.ref)) {
            $tokens += @("--ref", [string]$install.ref)
        }
        if ($install.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.mode)) {
            $tokens += @("--mode", [string]$install.mode)
        }
        $items += [pscustomobject]([ordered]@{
            original_index = $originalIndex
            name = [string]$item.name
            reason = [string]$item.reason
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            confidence = [string]$item.confidence
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            tokens = @($tokens)
            status = "planned"
        })
    }

    $removals = @()
    $originalIndex = 0
    foreach ($item in @($recommendations.removal_candidates)) {
        $originalIndex++
        $match = @($installedFacts | Where-Object { $_.vendor -eq [string]$item.installed.vendor -and $_.from -eq [string]$item.installed.from })
        $status = if ($match.Count -eq 1) { "planned" } elseif ($match.Count -eq 0) { "not_found" } else { "ambiguous" }
        $matched = if ($match.Count -gt 0) { $match[0] } else { $null }
        $removals += [pscustomobject]([ordered]@{
            original_index = $originalIndex
            name = [string]$item.name
            vendor = [string]$item.installed.vendor
            from = [string]$item.installed.from
            reason = ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo)
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            matched_skill = $matched
            status = $status
        })
    }
    $mcpItems = @()
    $originalIndex = 0
    foreach ($item in @($recommendations.mcp_new_servers)) {
        $originalIndex++
        $server = $item.server
        $existing = @($installedMcpServers | Where-Object { [string]$_.name -eq [string]$server.name })
        $status = if ($existing.Count -eq 0) {
            "planned"
        }
        elseif ($existing.Count -eq 1 -and (Test-McpServerEquivalent $existing[0] $server)) {
            "already_present"
        }
        else {
            "planned"
        }
        $mcpItems += [pscustomobject]([ordered]@{
            original_index = $originalIndex
            name = [string]$item.name
            reason = [string]$item.reason
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            confidence = [string]$item.confidence
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            server = $server
            status = $status
        })
    }

    $mcpRemovals = @()
    $originalIndex = 0
    foreach ($item in @($recommendations.mcp_removal_candidates)) {
        $originalIndex++
        $match = @($installedMcpServers | Where-Object { [string]$_.name -eq [string]$item.installed.name })
        $status = if ($match.Count -eq 1) { "planned" } elseif ($match.Count -eq 0) { "not_found" } else { "ambiguous" }
        $matched = if ($match.Count -gt 0) { $match[0] } else { $null }
        $mcpRemovals += [pscustomobject]([ordered]@{
            original_index = $originalIndex
            name = [string]$item.name
            installed_name = [string]$item.installed.name
            reason = ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo)
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            matched_server = $matched
            status = $status
        })
    }
    return [pscustomobject]([ordered]@{
        schema_version = 2
        run_id = [string]$recommendations.run_id
        target = [string]$recommendations.target
        decision_basis = $recommendations.decision_basis
        source_observations = ConvertTo-AuditJsonArray $recommendations.source_observations
        items = @($items)
        overlap_findings = @($recommendations.overlap_findings)
        removal_candidates = @($removals)
        do_not_install = @($recommendations.do_not_install)
        mcp_items = @($mcpItems)
        mcp_removal_candidates = @($mcpRemovals)
        empty_recommendation_reasons = ConvertTo-AuditJsonArray $recommendations.empty_recommendation_reasons
    })
}

function Get-AuditApplyReportPath([string]$recommendationsPath) {
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    return (Join-Path $dir "apply-report.json")
}

function Get-AuditItemsStatusCount($items, [string]$status) {
    return @($items | Where-Object { [string]$_.status -eq $status }).Count
}

function New-AuditChangedCounts($items, $removals, $mcpItems = @(), $mcpRemovals = @()) {
    return [pscustomobject]([ordered]@{
        add_total = @($items).Count
        add_planned = Get-AuditItemsStatusCount $items "planned"
        add_installed = Get-AuditItemsStatusCount $items "installed"
        add_failed = Get-AuditItemsStatusCount $items "failed"
        remove_total = @($removals).Count
        remove_planned = Get-AuditItemsStatusCount $removals "planned"
        remove_removed = Get-AuditItemsStatusCount $removals "removed"
        remove_not_found = Get-AuditItemsStatusCount $removals "not_found"
        remove_ambiguous = Get-AuditItemsStatusCount $removals "ambiguous"
        mcp_add_total = @($mcpItems).Count
        mcp_add_planned = Get-AuditItemsStatusCount $mcpItems "planned"
        mcp_add_added = Get-AuditItemsStatusCount $mcpItems "added"
        mcp_add_updated = Get-AuditItemsStatusCount $mcpItems "updated"
        mcp_add_already_present = Get-AuditItemsStatusCount $mcpItems "already_present"
        mcp_add_failed = Get-AuditItemsStatusCount $mcpItems "failed"
        mcp_remove_total = @($mcpRemovals).Count
        mcp_remove_planned = Get-AuditItemsStatusCount $mcpRemovals "planned"
        mcp_remove_removed = Get-AuditItemsStatusCount $mcpRemovals "removed"
        mcp_remove_not_found = Get-AuditItemsStatusCount $mcpRemovals "not_found"
        mcp_remove_ambiguous = Get-AuditItemsStatusCount $mcpRemovals "ambiguous"
        mcp_remove_failed = Get-AuditItemsStatusCount $mcpRemovals "failed"
    })
}

function Write-AuditRecommendationSummary($plan, $snapshotState = $null, $liveState = $null) {
    Write-Host ""
    Write-Host "=== 审查建议摘要 ==="
    Write-Host ("决策依据: {0}" -f [string]$plan.decision_basis.summary)
    if ($null -ne $snapshotState -and $null -ne $liveState) {
        Write-Host ("口径: live={0} (source_of_truth), snapshot={1} (audit_input)" -f [int]$liveState.skill_count, [int]$snapshotState.skill_count)
        if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0 -or $snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) {
            $liveMcpCount = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            $snapshotMcpCount = if ($snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$snapshotState.mcp_server_count } else { 0 }
            Write-Host ("MCP 口径: live={0} (source_of_truth), snapshot={1} (audit_input)" -f $liveMcpCount, $snapshotMcpCount)
        }
    }
    Write-Host "提示：以下序号为原序号；后续 dry-run 汇报与 apply 选择必须沿用原序号。"
    $totalChanges = @($plan.items).Count + @($plan.removal_candidates).Count + @($plan.mcp_items).Count + @($plan.mcp_removal_candidates).Count
    if ($totalChanges -eq 0 -and $plan.PSObject.Properties.Match("empty_recommendation_reasons").Count -gt 0 -and @($plan.empty_recommendation_reasons).Count -gt 0) {
        Write-Host ("空建议原因码: {0}" -f ((@($plan.empty_recommendation_reasons) | ForEach-Object { [string]$_ }) -join ", "))
    }
    Write-Host ""
    Write-Host ("新增建议: {0} 项" -f @($plan.items).Count)
    if (@($plan.items).Count -eq 0) {
        Write-Host "无新增建议：当前输入证据未形成可执行新增项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.items)) {
            $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
            Write-Host ("{0}) {1}" -f $itemIndex, [string]$item.name)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("卸载建议: {0} 项" -f @($plan.removal_candidates).Count)
    if (@($plan.removal_candidates).Count -eq 0) {
        Write-Host "无卸载建议：当前输入证据未形成可执行卸载项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.removal_candidates)) {
            $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
            Write-Host ("{0}) {1} [{2}|{3}] status={4}" -f $itemIndex, [string]$item.name, [string]$item.vendor, [string]$item.from, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("MCP 新增建议: {0} 项" -f @($plan.mcp_items).Count)
    if (@($plan.mcp_items).Count -eq 0) {
        Write-Host "无 MCP 新增建议：当前输入证据未形成可执行 MCP 新增项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.mcp_items)) {
            $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
            $transport = if ($item.server.PSObject.Properties.Match("transport").Count -gt 0) { [string]$item.server.transport } else { "stdio" }
            Write-Host ("{0}) {1} transport={2} status={3}" -f $itemIndex, [string]$item.name, $transport, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("MCP 卸载建议: {0} 项" -f @($plan.mcp_removal_candidates).Count)
    if (@($plan.mcp_removal_candidates).Count -eq 0) {
        Write-Host "无 MCP 卸载建议：当前输入证据未形成可执行 MCP 卸载项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.mcp_removal_candidates)) {
            $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
            Write-Host ("{0}) {1} [name={2}] status={3}" -f $itemIndex, [string]$item.name, [string]$item.installed_name, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
}

function Resolve-AuditSelection([string]$selectionText, $items, [string]$prompt, [string]$invalidMsg) {
    $items = @($items)
    if ($items.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    if ([string]::IsNullOrWhiteSpace($selectionText)) {
        Write-SelectionHint
        $selection = Read-SelectionIndices $prompt $items.Count $invalidMsg
        if ($selection.canceled) { return [pscustomobject]@{ items = @(); canceled = $true } }
        $idx = @($selection.indices)
    }
    else {
        $idx = @(Parse-IndexSelection $selectionText $items.Count)
        if ($idx.Count -eq 0 -and $selectionText.Trim().ToLowerInvariant() -eq "0") {
            return [pscustomobject]@{ items = @(); canceled = $true }
        }
        if ($idx.Count -eq 0) { throw $invalidMsg }
    }
    $selected = @()
    foreach ($n in $idx) { $selected += $items[$n - 1] }
    return [pscustomobject]@{ items = @($selected); canceled = $false }
}

function Remove-AuditSelectedInstalledSkills($selectedItems) {
    $cfg = LoadCfg
    $removedMappings = 0
    $removedVendorImports = 0
    $deletedManualImports = 0
    $deletedLegacyManualDirs = 0
    $deletedOverrides = 0
    $backedOverrides = 0
    foreach ($item in @($selectedItems)) {
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ($vendor -eq "manual") {
            $before = @($cfg.imports).Count
            $cfg.imports = @($cfg.imports | Where-Object { -not ($_.mode -eq "manual" -and $_.name -eq $from) })
            $deletedManualImports += ($before - @($cfg.imports).Count)

            $legacyPath = Join-Path $ManualDir $from
            if (Test-Path $legacyPath) {
                Invoke-RemoveItem $legacyPath -Recurse
                $deletedLegacyManualDirs++
            }
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "manual|$from") })
        }
        elseif ($vendor -eq "overrides") {
            $bak = Backup-OverrideDir $from
            if ($bak) { $backedOverrides++ }
            $deletedOverrides++
        }
        else {
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "$vendor|$from") })
            $removedMappings++

            $skillPath = Normalize-SkillPath $from
            $hasSameMapping = @($cfg.mappings | Where-Object { $_.vendor -eq $vendor -and $_.from -eq $skillPath }).Count -gt 0
            if (-not $hasSameMapping) {
                $beforeImports = @($cfg.imports).Count
                $cfg.imports = @($cfg.imports | Where-Object {
                        $mode = if ($_.PSObject.Properties.Match("mode").Count -gt 0) { [string]$_.mode } else { "manual" }
                        if ($mode -ne "vendor") { return $true }
                        if ([string]$_.name -ne $vendor) { return $true }
                        $importSkill = Normalize-SkillPath ([string]$_.skill)
                        return ($importSkill -ne $skillPath)
                    })
                $removedVendorImports += ($beforeImports - @($cfg.imports).Count)
            }
        }
        $item.status = "removed"
    }
    SaveCfg $cfg
    if (@($selectedItems).Count -gt 0) {
        Clear-SkillsCache
    }
    return [pscustomobject]@{
        removed_mappings = $removedMappings
        removed_vendor_imports = $removedVendorImports
        deleted_manual_imports = $deletedManualImports
        deleted_legacy_manual_dirs = $deletedLegacyManualDirs
        deleted_overrides = $deletedOverrides
        backed_overrides = $backedOverrides
    }
}

function Ensure-AuditNewManualImportsMapped($beforeCfg) {
    $before = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in @($beforeCfg.imports)) {
        if ($null -eq $i) { continue }
        $before.Add([string]$i.name) | Out-Null
    }

    $cfg = LoadCfg
    $existingMappings = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        $existingMappings.Add(("{0}|{1}" -f [string]$m.vendor, [string]$m.from)) | Out-Null
    }

    $changed = $false
    foreach ($i in @($cfg.imports)) {
        if ($null -eq $i) { continue }
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]$i.mode } else { "manual" }
        if ($mode -ne "manual") { continue }
        $name = [string]$i.name
        if ($before.Contains($name)) { continue }
        $key = "manual|{0}" -f $name
        if ($existingMappings.Contains($key)) { continue }
        $cfg.mappings += @{ vendor = "manual"; from = $name; to = $name }
        $existingMappings.Add($key) | Out-Null
        $changed = $true
    }
    if ($changed) { SaveCfg $cfg }
    return $changed
}
