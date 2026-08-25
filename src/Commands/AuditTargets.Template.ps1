function Get-AuditSourceStrategyOverridePath {
    return (Join-Path $script:Root "overrides\audit-source-strategy.json")
}

function Convert-AuditMergeValue($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [System.Collections.IDictionary]) {
        $obj = [ordered]@{}
        foreach ($key in $value.Keys) {
            $obj[[string]$key] = Convert-AuditMergeValue $value[$key]
        }
        return $obj
    }
    if ($value -is [pscustomobject]) {
        $obj = [ordered]@{}
        foreach ($prop in $value.PSObject.Properties) {
            $obj[[string]$prop.Name] = Convert-AuditMergeValue $prop.Value
        }
        return $obj
    }
    if (Assert-IsArray $value) {
        $arr = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $arr.Add((Convert-AuditMergeValue $item)) | Out-Null
        }
        return $arr.ToArray()
    }
    return $value
}

function Convert-AuditMergeToObject($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [System.Collections.IDictionary]) {
        $obj = [ordered]@{}
        foreach ($key in $value.Keys) {
            $obj[[string]$key] = Convert-AuditMergeToObject $value[$key]
        }
        return [pscustomobject]$obj
    }
    if (Assert-IsArray $value) {
        $arr = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $arr.Add((Convert-AuditMergeToObject $item)) | Out-Null
        }
        return $arr.ToArray()
    }
    return $value
}

function Merge-AuditHashtableDeep($base, $patch) {
    if (-not (Test-AuditObjectLike $base)) {
        return (Convert-AuditMergeValue $patch)
    }
    if (-not (Test-AuditObjectLike $patch)) {
        return (Convert-AuditMergeValue $patch)
    }
    $baseMap = Convert-AuditMergeValue $base
    $patchMap = Convert-AuditMergeValue $patch
    foreach ($key in $patchMap.Keys) {
        $next = $patchMap[$key]
        if ($baseMap.Contains($key) -and (Test-AuditObjectLike $baseMap[$key]) -and (Test-AuditObjectLike $next)) {
            $baseMap[$key] = Merge-AuditHashtableDeep $baseMap[$key] $next
        }
        else {
            $baseMap[$key] = $next
        }
    }
    return $baseMap
}

function Apply-AuditSourceStrategyOverride($strategy, [string]$mode) {
    $path = Get-AuditSourceStrategyOverridePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $strategy
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $strategy
        }
        $override = $raw | ConvertFrom-Json
    }
    catch {
        Log ("audit-source-strategy override 解析失败，忽略覆盖：{0}" -f $_.Exception.Message) "WARN"
        return $strategy
    }
    if (-not (Test-AuditObjectLike $override)) {
        return $strategy
    }

    $patches = New-Object System.Collections.Generic.List[object]
    if (Test-AuditJsonProperty $override "all" -and (Test-AuditObjectLike $override.all)) {
        $patches.Add($override.all) | Out-Null
    }
    if (Test-AuditJsonProperty $override $mode -and (Test-AuditObjectLike $override.$mode)) {
        $patches.Add($override.$mode) | Out-Null
    }
    if ($patches.Count -eq 0) {
        $patches.Add($override) | Out-Null
    }

    $merged = Convert-AuditMergeValue $strategy
    foreach ($patch in $patches) {
        $merged = Merge-AuditHashtableDeep $merged $patch
    }
    return (Convert-AuditMergeToObject $merged)
}

function New-AuditSourceStrategy([string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo") ("审查来源模式必须为 target-repo：{0}" -f $Mode)
    $strategy = [pscustomobject]([ordered]@{
            schema_version = 1
            mode = $normalizedMode
            query = [string]$Query
            sources = @(
                [ordered]@{
                    id = "official-docs"
                    name = "Official documentation"
                    use_for = "Verify current APIs, platform rules, support status, and recommended implementation patterns."
                },
                [ordered]@{
                    id = "mcp-provider-docs"
                    name = "MCP provider documentation"
                    use_for = "Verify MCP server availability, transport, auth model, required args, permissions, and support status before recommending install or removal."
                },
                [ordered]@{
                    id = "skills-sh"
                    name = "skills.sh"
                    use_for = "Discover skill-packaged implementations and compare skill metadata quality."
                },
                [ordered]@{
                    id = "github-trending-monthly"
                    name = "GitHub Trending monthly"
                    url = "https://github.com/trending?since=monthly"
                    use_for = "Find active, recently relevant community projects; never treat popularity alone as enough evidence."
                },
                [ordered]@{
                    id = "strong-community-projects"
                    name = "High-quality community projects"
                    use_for = "Check maintenance activity, examples, issues, releases, and adoption fit."
                },
                [ordered]@{
                    id = "best-practices"
                    name = "Best-practice guides"
                    use_for = "Compare proposed skills against mature workflow and operational guidance."
                },
                [ordered]@{
                    id = "security-and-permission-notes"
                    name = "Security and permission notes"
                    use_for = "Check auth, token scope, data access, network exposure, and rollback concerns, especially for MCP servers."
                },
                [ordered]@{
                    id = "find-skills"
                    name = "Installed find-skills workflow"
                    use_for = "Use the local skill discovery workflow as an input source when available."
                }
            )
            scoring = [ordered]@{
                authority = "Prefer first-party documentation and maintained source repositories."
                fit = "Match only the scan-derived target profile and concrete repository scan facts."
                duplication_risk = "Penalize recommendations that duplicate installed skills without a clear incremental benefit."
                maintenance = "Prefer projects with recent activity, clear license, and usable documentation."
                operational_cost = "Prefer skills that are easy to install, verify, and roll back."
            }
            evidence_policy = [ordered]@{
                min_unique_sources_for_changes = 0
                require_http_source_for_changes = $false
                require_source_observations_for_changes = $false
            }
            decision_quality_policy = [ordered]@{
                require_keyword_trace_for_changes = $false
                require_keyword_trace_membership = $false
                min_target_profile_keywords_per_change = 0
                min_target_repo_keywords_per_change = 0
                min_installed_state_keywords_per_change = 0
            }
            required_evidence = @(
                "Every add/remove recommendation must cite sources inspected in this run.",
                "Do not fabricate repository facts, source links, or source conclusions.",
                "Keep one or more real sources on each recommendation; local fixtures and local paths are valid when they are the actual input.",
                "For MCP recommendations, prefer provider documentation and security/permission notes over popularity signals.",
                "Every recommendation must be justified by the scan-derived target profile; do not introduce personal preferences or unscanned repository facts."
            )
        })
    $strategy = Apply-AuditSourceStrategyOverride $strategy $normalizedMode
    if ($strategy.PSObject.Properties.Match("mode").Count -eq 0) {
        $strategy | Add-Member -NotePropertyName mode -NotePropertyValue $normalizedMode -Force
    }
    else {
        $strategy.mode = $normalizedMode
    }
    if ($strategy.PSObject.Properties.Match("query").Count -eq 0) {
        $strategy | Add-Member -NotePropertyName query -NotePropertyValue ([string]$Query) -Force
    }
    else {
        $strategy.query = [string]$Query
    }
    return $strategy
}

function Test-AuditJsonProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    return ($obj.PSObject.Properties.Match($name).Count -gt 0)
}

function Assert-AuditBundleFileContent([string]$path, [string]$label) {
    $raw = Get-ContentUtf8 $path
    Need (-not [string]::IsNullOrWhiteSpace($raw)) ("审查包文件为空：{0} -> {1}" -f $label, $path)

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -eq ".md") { return }
    if ($ext -ne ".json") { return }

    try {
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw ("审查包 JSON 解析失败：{0} -> {1}；{2}" -f $label, $path, $_.Exception.Message)
    }
    Need ($null -ne $data) ("审查包 JSON 为空对象：{0} -> {1}" -f $label, $path)

    switch ($label) {
        "snapshot.json" {
            Need ([int]$data.schema_version -eq 2) ("snapshot schema_version 必须为 2：{0}" -f $path)
            foreach ($field in @("run_id", "mode", "prompt_contract_version", "installed_state", "target_scans", "target_profile", "source_strategy", "decision_insights", "native_ai_review")) {
                Need (Test-AuditJsonProperty $data $field) ("snapshot 缺少 {0}：{1}" -f $field, $path)
            }
            Need (Assert-IsArray $data.target_scans) ("snapshot.target_scans 必须为数组：{0}" -f $path)
            Need (Test-AuditJsonProperty $data.installed_state "skills") ("snapshot.installed_state 缺少 skills：{0}" -f $path)
            Need (Assert-IsArray $data.installed_state.skills) ("snapshot.installed_state.skills 必须为数组：{0}" -f $path)
            Need (Assert-IsArray $data.installed_state.external_skills) ("snapshot.installed_state.external_skills 必须为数组：{0}" -f $path)
            Need (Assert-IsArray $data.installed_state.mcp_servers) ("snapshot.installed_state.mcp_servers 必须为数组：{0}" -f $path)
            Need ([string]$data.target_profile.derivation -eq "target_scans_only") ("snapshot.target_profile 必须由 target_scans_only 派生：{0}" -f $path)
            Need (Assert-IsArray $data.target_profile.artifact_capabilities) ("snapshot.target_profile.artifact_capabilities 必须为数组：{0}" -f $path)
            Need (Assert-IsArray $data.target_profile.requirement_signals) ("snapshot.target_profile.requirement_signals 必须为数组：{0}" -f $path)
            Need ([string]$data.native_ai_review.decision_owner -eq "host_ai") ("snapshot.native_ai_review.decision_owner 必须为 host_ai：{0}" -f $path)
            Need (@($data.target_scans).Count -gt 0) ("snapshot.target_scans 不能为空：{0}" -f $path)
        }
        "recommendations.json" {
            Need ([int]$data.schema_version -eq 3) ("recommendations schema_version 必须为 3：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "decision_basis") ("recommendations 缺少 decision_basis：{0}" -f $path)
        }
        "receipt.json" {
            Need ([int]$data.schema_version -eq 1) ("receipt schema_version 必须为 1：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "persisted") ("receipt 缺少 persisted：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "truth_boundary") ("receipt 缺少 truth_boundary：{0}" -f $path)
        }
    }
}

function Assert-AuditBundleRequiredFiles([object[]]$files) {
    foreach ($file in @($files)) {
        Need ($null -ne $file) "审查包关键产物定义不能为空"
        $path = [string]$file.path
        $label = [string]$file.label
        if ([string]::IsNullOrWhiteSpace($label)) { $label = $path }
        Need (-not [string]::IsNullOrWhiteSpace($path)) ("审查包关键产物路径不能为空：{0}" -f $label)
        Need (Test-Path -LiteralPath $path -PathType Leaf) ("审查包缺少关键产物：{0} -> {1}" -f $label, $path)
        Assert-AuditBundleFileContent $path $label
    }
}

function New-AuditRecommendationsTemplate([string]$runId, [string]$targetName, [string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo") ("recommendations 模式必须为 target-repo：{0}" -f $Mode)
    $templateNotes = @(
        "Replace placeholder values wrapped in <> before using this file.",
        "Delete example entries that are not needed, but keep the schema shape unchanged.",
        "Keep one or more real sources on each recommendation; local fixtures and local paths are valid when they are the actual input.",
        "All install/remove decisions must cite scan-derived target-profile reasons only."
    )
    $basisSummary = "<why these recommendations reflect the scan-derived target profile, installed inventory, and source strategy>"
    $targetReasonInstall = "<which scan-derived target-profile facts justify this skill>"
    $targetReasonRemoval = "<why the scan-derived target profile no longer justifies this skill>"
    $targetReasonDoNotInstall = "<why the scan-derived target profile does not justify it>"
    return [pscustomobject]([ordered]@{
        schema_version = 3
        run_id = $runId
        target = $targetName
        recommendation_mode = $normalizedMode
        discovery_query = [string]$Query
        template_notes = @($templateNotes)
        decision_basis = [ordered]@{
            target_profile_used = $true
            target_scan_used = $true
            source_strategy_used = $true
            summary = $basisSummary
        }
        empty_recommendation_reasons = @("insufficient_reliable_evidence")
        new_skills = @(
            [ordered]@{
                name = "<new-skill-name>"
                reason_target_profile = $targetReasonInstall
                install = [ordered]@{
                    repo = "<owner/repo-or-local-path>"
                    skill = "<relative-skill-path-or-.>"
                    ref = "<branch-or-tag>"
                    mode = "manual"
                }
                confidence = "medium"
                sources = @("<source-url-1>")
                source_categories = @("official-docs", "skills.sh")
            }
        )
        overlap_findings = @(
            [ordered]@{
                name = "<existing-skill-or-skill-pair>"
                reason_target_profile = $targetReasonInstall
                sources = @("<source-url-1>")
                note = "<report-only observation; no automatic uninstall>"
                source_preference = [ordered]@{
                    plugin_installed = $true
                    standalone_duplicate = $true
                    native_source_preferred = $true
                    action = "report_only_do_not_import_duplicate"
                }
                routing = [ordered]@{
                    decision_owner = "host_ai"
                    selection_policy = "<how to choose executors without invoking every overlapping skill>"
                    members = @(
                        [ordered]@{ name = "<primary-skill>"; role = "executor" }
                        [ordered]@{ name = "<alternative-or-validator>"; role = "validator" }
                    )
                }
            }
        )
        removal_candidates = @(
            [ordered]@{
                name = "<installed-skill-name>"
                reason_target_profile = $targetReasonRemoval
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                installed = [ordered]@{
                    vendor = "<installed-vendor>"
                    from = "<installed-from>"
                }
            }
        )
        do_not_install = @(
            [ordered]@{
                name = "<skill-not-recommended>"
                reason_target_profile = $targetReasonDoNotInstall
                sources = @("<source-url-1>")
                note = "<why it should not be added now>"
            }
        )
        mcp_new_servers = @(
            [ordered]@{
                name = "<mcp-server-name>"
                reason_target_profile = $targetReasonInstall
                confidence = "medium"
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                server = [ordered]@{
                    name = "<mcp-server-name>"
                    transport = "stdio"
                    command = "<command>"
                    args = @("<arg1>")
                }
            }
        )
        mcp_removal_candidates = @(
            [ordered]@{
                name = "<installed-mcp-name>"
                reason_target_profile = $targetReasonRemoval
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                installed = [ordered]@{
                    name = "<installed-mcp-name>"
                }
            }
        )
    })
}
