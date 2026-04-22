function New-AuditSourceStrategy([string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo" -or $normalizedMode -eq "profile-only") ("未知审查来源模式：{0}" -f $Mode)
    return [pscustomobject]([ordered]@{
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
                id = "find-skills"
                name = "Installed find-skills workflow"
                use_for = "Use the local skill discovery workflow as an input source when available."
            }
        )
        scoring = [ordered]@{
            authority = "Prefer first-party documentation and maintained source repositories."
            fit = "Match the user's structured profile and, in target-repo mode, concrete repo scan facts."
            duplication_risk = "Penalize recommendations that duplicate installed skills without a clear incremental benefit."
            maintenance = "Prefer projects with recent activity, clear license, and usable documentation."
            operational_cost = "Prefer skills that are easy to install, verify, and roll back."
        }
        required_evidence = @(
            "Every add/remove recommendation must cite sources inspected in this run.",
            "Do not fabricate repository facts, source links, or source conclusions.",
            "For profile-only mode, explain reason_target_repo as installed-skill inventory / profile-only context, not as a target repository claim."
        )
    })
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
        "user-profile.json" {
            Need (Test-AuditJsonProperty $data "raw_text") ("user-profile 缺少 raw_text：{0}" -f $path)
            Need (-not [string]::IsNullOrWhiteSpace([string]$data.raw_text)) ("user-profile.raw_text 不能为空：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "structured") ("user-profile 缺少 structured：{0}" -f $path)
        }
        "installed-skills.json" {
            Need (Test-AuditJsonProperty $data "skills") ("installed-skills 缺少 skills：{0}" -f $path)
            Need (Assert-IsArray $data.skills) ("installed-skills.skills 必须为数组：{0}" -f $path)
            if (Test-AuditJsonProperty $data "mcp_servers") {
                Need (Assert-IsArray $data.mcp_servers) ("installed-skills.mcp_servers 必须为数组：{0}" -f $path)
            }
            if (Test-AuditJsonProperty $data "snapshot_kind") {
                Need ([string]$data.snapshot_kind -eq "audit_input") ("installed-skills.snapshot_kind 必须为 audit_input：{0}" -f $path)
            }
        }
        "source-strategy.json" {
            Need (Test-AuditJsonProperty $data "mode") ("source-strategy 缺少 mode：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "sources") ("source-strategy 缺少 sources：{0}" -f $path)
            Need (Assert-IsArray $data.sources) ("source-strategy.sources 必须为数组：{0}" -f $path)
            Need (@($data.sources).Count -gt 0) ("source-strategy.sources 不能为空：{0}" -f $path)
        }
        "recommendations.template.json" {
            Need (Test-AuditJsonProperty $data "schema_version") ("recommendations.template 缺少 schema_version：{0}" -f $path)
            Need ([int]$data.schema_version -eq 2) ("recommendations.template schema_version 必须为 2：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "decision_basis") ("recommendations.template 缺少 decision_basis：{0}" -f $path)
        }
        "repo-scan.json" {
            Need (Test-AuditJsonProperty $data "target") ("repo-scan 缺少 target：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "detected") ("repo-scan 缺少 detected：{0}" -f $path)
        }
        "repo-scans.json" {
            Need (Test-AuditJsonProperty $data "scans") ("repo-scans 缺少 scans：{0}" -f $path)
            Need (Assert-IsArray $data.scans) ("repo-scans.scans 必须为数组：{0}" -f $path)
            Need (@($data.scans).Count -gt 0) ("repo-scans.scans 不能为空：{0}" -f $path)
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
    Need ($normalizedMode -eq "target-repo" -or $normalizedMode -eq "profile-only") ("未知 recommendations 模式：{0}" -f $Mode)
    $isProfileOnly = ($normalizedMode -eq "profile-only")
    $targetScanUsed = -not $isProfileOnly
    $templateNotes = if ($isProfileOnly) {
        @(
            "Replace placeholder values wrapped in <> before using this file.",
            "Delete example entries that are not needed, but keep the schema shape unchanged.",
            "This is profile-only skill discovery: reason_target_repo means installed-skill inventory / profile-only context, not target repository facts."
        )
    }
    else {
        @(
            "Replace placeholder values wrapped in <> before using this file.",
            "Delete example entries that are not needed, but keep the schema shape unchanged.",
            "All install/remove decisions must cite both user-profile and target-repo reasons."
        )
    }
    $basisSummary = if ($isProfileOnly) {
        "<why these recommendations reflect the user profile, installed-skill inventory, and source strategy without target repo facts>"
    }
    else {
        "<why these recommendations reflect both the user profile and the target repo facts>"
    }
    $targetReasonInstall = if ($isProfileOnly) { "<which installed-skill inventory or profile-only context justifies this skill>" } else { "<which detected target-repo facts justify this skill>" }
    $targetReasonRemoval = if ($isProfileOnly) { "<why the installed-skill inventory or profile-only context no longer justifies this skill>" } else { "<why the target repo no longer justifies this skill>" }
    $targetReasonDoNotInstall = if ($isProfileOnly) { "<why the profile-only context does not justify it>" } else { "<why the target repo does not justify it>" }
    return [pscustomobject]([ordered]@{
        schema_version = 2
        run_id = $runId
        target = $targetName
        recommendation_mode = $normalizedMode
        discovery_query = [string]$Query
        template_notes = @($templateNotes)
        decision_basis = [ordered]@{
            user_profile_used = $true
            target_scan_used = $targetScanUsed
            source_strategy_used = $true
            summary = $basisSummary
        }
        new_skills = @(
            [ordered]@{
                name = "<new-skill-name>"
                reason_user_profile = "<why the user's long-term workflow benefits from this skill>"
                reason_target_repo = $targetReasonInstall
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
                reason_user_profile = "<why overlap matters for the user's workflow>"
                reason_target_repo = $targetReasonInstall
                sources = @("<source-url-1>")
                note = "<report-only observation; no automatic uninstall>"
            }
        )
        removal_candidates = @(
            [ordered]@{
                name = "<installed-skill-name>"
                reason_user_profile = "<why the user profile no longer justifies this skill>"
                reason_target_repo = $targetReasonRemoval
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
                reason_user_profile = "<why the user profile does not justify it>"
                reason_target_repo = $targetReasonDoNotInstall
                sources = @("<source-url-1>")
                note = "<why it should not be added now>"
            }
        )
        mcp_new_servers = @(
            [ordered]@{
                name = "<mcp-server-name>"
                reason_user_profile = "<why the user's long-term workflow benefits from this MCP server>"
                reason_target_repo = $targetReasonInstall
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
                reason_user_profile = "<why the user profile no longer justifies this MCP server>"
                reason_target_repo = $targetReasonRemoval
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                installed = [ordered]@{
                    name = "<installed-mcp-name>"
                }
            }
        )
    })
}
