function Get-AuditTargetsConfigPath {
    return (Join-Path $script:Root "audit-targets.json")
}

function New-DefaultAuditTargetsConfig {
    return [pscustomobject]@{
        version = 1
        path_base = "skills_manager_root"
        targets = @()
    }
}

function Save-AuditTargetsConfig($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 20
    Set-ContentUtf8 (Get-AuditTargetsConfigPath) $json
}

function Initialize-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $false }
    Save-AuditTargetsConfig (New-DefaultAuditTargetsConfig)
    return $true
}

function Load-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    Need (Test-Path -LiteralPath $path -PathType Leaf) "缺少 audit-targets.json，请先运行：./skills.ps1 审查目标 初始化"
    try {
        $cfg = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        throw ("audit-targets.json 解析失败：{0}" -f $_.Exception.Message)
    }

    if (-not $cfg.PSObject.Properties.Match("version").Count) {
        $cfg | Add-Member -NotePropertyName version -NotePropertyValue 1
    }
    if (-not $cfg.PSObject.Properties.Match("path_base").Count) {
        $cfg | Add-Member -NotePropertyName path_base -NotePropertyValue "skills_manager_root"
    }
    if (-not $cfg.PSObject.Properties.Match("targets").Count -or $null -eq $cfg.targets) {
        $cfg | Add-Member -NotePropertyName targets -NotePropertyValue @() -Force
    }

    Need ([int]$cfg.version -eq 1) "audit-targets.json version 仅支持 1"
    Need ([string]$cfg.path_base -eq "skills_manager_root") "audit-targets.json path_base 仅支持 skills_manager_root"
    if (-not (Assert-IsArray $cfg.targets)) { $cfg.targets = @($cfg.targets) }
    return $cfg
}

function Resolve-AuditTargetPath([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "目标仓路径不能为空"
    $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
    if ($expanded -eq "~" -or $expanded.StartsWith("~\") -or $expanded.StartsWith("~/")) {
        $userHome = [Environment]::GetFolderPath("UserProfile")
        if ($expanded.Length -eq 1) {
            $expanded = $userHome
        }
        else {
            $expanded = Join-Path $userHome $expanded.Substring(2)
        }
    }
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $script:Root $expanded))
}

function Add-AuditTargetConfigEntry([string]$name, [string]$path, [string[]]$tags = @(), [string]$notes = "") {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    Need (-not [string]::IsNullOrWhiteSpace($path)) "target path 不能为空"

    $entry = [pscustomobject]@{
        name = $normName
        path = $path
        enabled = $true
        tags = @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        notes = $notes
    }

    $existing = @($cfg.targets | Where-Object { $_.name -eq $normName })
    if ($existing.Count -gt 0) {
        $existing[0].path = $entry.path
        $existing[0].enabled = $entry.enabled
        $existing[0].tags = $entry.tags
        $existing[0].notes = $entry.notes
    }
    else {
        $cfg.targets += $entry
    }
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Parse-AuditTargetsArgs([string[]]$tokens) {
    $result = [ordered]@{
        action = "list"
        name = $null
        path = $null
        target = $null
        out = $null
        recommendations = $null
        apply = $false
        yes = $false
        tags = @()
        notes = ""
    }

    $items = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -gt 0) {
        $head = ([string]$items[0]).ToLowerInvariant()
        switch ($head) {
            "初始化" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "init" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "添加" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "add" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "列表" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "list" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "扫描" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "scan" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "应用" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            "apply" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            default { throw ("未知审查目标子命令：{0}" -f $items[0]) }
        }
    }

    $positional = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        $t = [string]$items[$i]
        $key = $t.ToLowerInvariant()
        switch ($key) {
            "--target" {
                Need ($i + 1 -lt $items.Count) "--target 缺少值"
                $result.target = [string]$items[++$i]
                continue
            }
            "--out" {
                Need ($i + 1 -lt $items.Count) "--out 缺少值"
                $result.out = [string]$items[++$i]
                continue
            }
            "--recommendations" {
                Need ($i + 1 -lt $items.Count) "--recommendations 缺少值"
                $result.recommendations = [string]$items[++$i]
                continue
            }
            "--apply" {
                $result.apply = $true
                continue
            }
            "--yes" {
                $result.yes = $true
                continue
            }
            "--tag" {
                Need ($i + 1 -lt $items.Count) "--tag 缺少值"
                $result.tags += [string]$items[++$i]
                continue
            }
            "--notes" {
                Need ($i + 1 -lt $items.Count) "--notes 缺少值"
                $result.notes = [string]$items[++$i]
                continue
            }
            default {
                $positional += $t
            }
        }
    }

    if ($result.action -eq "add") {
        Need ($positional.Count -ge 2) "添加目标仓需要 name 和 path"
        $result.name = [string]$positional[0]
        $result.path = [string]$positional[1]
    }
    return [pscustomobject]$result
}

function Write-AuditTargetsList {
    $cfg = Load-AuditTargetsConfig
    $items = @($cfg.targets)
    if ($items.Count -eq 0) {
        Write-Host "未登记目标仓。"
        return
    }
    foreach ($t in $items) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $exists = Test-Path -LiteralPath $resolved
        $enabled = if ($t.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$t.enabled } else { $true }
        $enabledText = if ($enabled) { "enabled" } else { "disabled" }
        Write-Host ("- {0} [{1}] {2} -> {3} exists={4}" -f [string]$t.name, $enabledText, [string]$t.path, $resolved, $exists)
    }
}

function Get-AuditRunId {
    return (Get-Date -Format "yyyyMMdd-HHmmss")
}

function Get-AuditReportRoot([string]$runId) {
    return (Join-Path $script:Root (Join-Path "reports\skill-audit" $runId))
}

function Test-AuditFile([string]$root, [string]$relative) {
    return (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)
}

function Add-AuditUniqueValue([System.Collections.Generic.List[string]]$items, [string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    if (-not $items.Contains($value)) { $items.Add($value) | Out-Null }
}

function Get-AuditPackageJson([string]$root) {
    $path = Join-Path $root "package.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
    catch { return $null }
}

function Get-AuditPackagePropertyNames($obj, [string]$propertyName) {
    if ($null -eq $obj) { return @() }
    if (-not $obj.PSObject.Properties.Match($propertyName).Count) { return @() }
    $value = $obj.$propertyName
    if ($null -eq $value) { return @() }
    return @($value.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-AuditPackageScriptNames($pkg) {
    if ($null -eq $pkg) { return @() }
    if (-not $pkg.PSObject.Properties.Match("scripts").Count -or $null -eq $pkg.scripts) { return @() }
    return @($pkg.scripts.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-AuditGitInfo([string]$resolvedPath) {
    $info = [ordered]@{
        is_repo = $false
        branch = ""
        commit = ""
        dirty = $false
    }
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) { return [pscustomobject]$info }

    Push-Location $resolvedPath
    try {
        $inside = (& git rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -eq 0 -and [string]$inside -eq "true") {
            $info.is_repo = $true
            $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.branch = ([string]$branch).Trim() }
            $commit = (& git rev-parse HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.commit = ([string]$commit).Trim() }
            $status = @(& git status --porcelain 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.dirty = ($status.Count -gt 0) }
        }
    }
    finally {
        Pop-Location
    }
    return [pscustomobject]$info
}

function New-AuditRepoScan([string]$targetName, [string]$resolvedPath, [string]$inputPath) {
    $exists = Test-Path -LiteralPath $resolvedPath -PathType Container
    $risks = New-Object System.Collections.Generic.List[string]
    $languages = New-Object System.Collections.Generic.List[string]
    $packageManagers = New-Object System.Collections.Generic.List[string]
    $frameworks = New-Object System.Collections.Generic.List[string]
    $buildCommands = New-Object System.Collections.Generic.List[string]
    $testCommands = New-Object System.Collections.Generic.List[string]
    $agentRuleFiles = New-Object System.Collections.Generic.List[string]
    $notableFiles = New-Object System.Collections.Generic.List[string]

    if (-not $exists) {
        Add-AuditUniqueValue $risks "target_missing"
    }

    $gitInfo = Get-AuditGitInfo $resolvedPath
    if ($exists -and -not $gitInfo.is_repo) {
        Add-AuditUniqueValue $risks "not_a_git_repo"
    }
    if ($gitInfo.dirty) {
        Add-AuditUniqueValue $risks "git_dirty"
    }

    if ($exists) {
        $pkg = Get-AuditPackageJson $resolvedPath
        if ($pkg) {
            Add-AuditUniqueValue $packageManagers "npm"
            Add-AuditUniqueValue $languages "javascript"
            Add-AuditUniqueValue $notableFiles "package.json"

            $deps = @()
            $deps += Get-AuditPackagePropertyNames $pkg "dependencies"
            $deps += Get-AuditPackagePropertyNames $pkg "devDependencies"
            foreach ($dep in $deps) {
                switch -Regex ($dep) {
                    "^vite$" { Add-AuditUniqueValue $frameworks "vite" }
                    "^next$" { Add-AuditUniqueValue $frameworks "nextjs" }
                    "^react$" { Add-AuditUniqueValue $frameworks "react" }
                    "^vue$" { Add-AuditUniqueValue $frameworks "vue" }
                    "^svelte$" { Add-AuditUniqueValue $frameworks "svelte" }
                    "^@playwright/test$" { Add-AuditUniqueValue $frameworks "playwright" }
                }
            }

            $scripts = Get-AuditPackageScriptNames $pkg
            if ($scripts -contains "build") { Add-AuditUniqueValue $buildCommands "npm run build" }
            if ($scripts -contains "test") { Add-AuditUniqueValue $testCommands "npm test" }
        }

        if (Test-AuditFile $resolvedPath "pnpm-lock.yaml") { Add-AuditUniqueValue $packageManagers "pnpm"; Add-AuditUniqueValue $notableFiles "pnpm-lock.yaml" }
        if (Test-AuditFile $resolvedPath "yarn.lock") { Add-AuditUniqueValue $packageManagers "yarn"; Add-AuditUniqueValue $notableFiles "yarn.lock" }
        if (Test-AuditFile $resolvedPath "package-lock.json") { Add-AuditUniqueValue $packageManagers "npm"; Add-AuditUniqueValue $notableFiles "package-lock.json" }
        if (Test-AuditFile $resolvedPath "pyproject.toml") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "pyproject.toml" }
        if (Test-AuditFile $resolvedPath "requirements.txt") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "requirements.txt" }
        if (Test-AuditFile $resolvedPath "uv.lock") { Add-AuditUniqueValue $packageManagers "uv"; Add-AuditUniqueValue $notableFiles "uv.lock" }
        if (Test-AuditFile $resolvedPath "go.mod") { Add-AuditUniqueValue $languages "go"; Add-AuditUniqueValue $notableFiles "go.mod" }
        if (Test-AuditFile $resolvedPath "Cargo.toml") { Add-AuditUniqueValue $languages "rust"; Add-AuditUniqueValue $notableFiles "Cargo.toml" }

        foreach ($viteFile in @("vite.config.js", "vite.config.ts", "vite.config.mjs", "vite.config.mts")) {
            if (Test-AuditFile $resolvedPath $viteFile) {
                Add-AuditUniqueValue $frameworks "vite"
                Add-AuditUniqueValue $notableFiles $viteFile
            }
        }
        foreach ($nextFile in @("next.config.js", "next.config.ts", "next.config.mjs")) {
            if (Test-AuditFile $resolvedPath $nextFile) {
                Add-AuditUniqueValue $frameworks "nextjs"
                Add-AuditUniqueValue $notableFiles $nextFile
            }
        }
        foreach ($playwrightFile in @("playwright.config.js", "playwright.config.ts", "playwright.config.mjs")) {
            if (Test-AuditFile $resolvedPath $playwrightFile) {
                Add-AuditUniqueValue $frameworks "playwright"
                Add-AuditUniqueValue $notableFiles $playwrightFile
            }
        }
        foreach ($ruleFile in @("AGENTS.md", "CLAUDE.md", "GEMINI.md")) {
            if (Test-AuditFile $resolvedPath $ruleFile) {
                Add-AuditUniqueValue $agentRuleFiles $ruleFile
                Add-AuditUniqueValue $notableFiles $ruleFile
            }
        }
        $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue)
        $csprojFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10)
        if ($slnFiles.Count -gt 0 -or $csprojFiles.Count -gt 0) { Add-AuditUniqueValue $languages "dotnet" }
    }

    return [pscustomobject]([ordered]@{
        schema_version = 1
        scanned_at = (Get-Date).ToString("o")
        target = [ordered]@{
            name = $targetName
            path = $inputPath
            resolved_path = $resolvedPath
            exists = $exists
        }
        git = $gitInfo
        detected = [ordered]@{
            languages = @($languages)
            package_managers = @($packageManagers)
            frameworks = @($frameworks)
            build_commands = @($buildCommands)
            test_commands = @($testCommands)
            agent_rule_files = @($agentRuleFiles)
            notable_files = @($notableFiles)
        }
        risks = @($risks)
    })
}

function Write-AuditJsonFile([string]$path, $data) {
    EnsureDir (Split-Path $path -Parent)
    Set-ContentUtf8 $path ($data | ConvertTo-Json -Depth 40)
}

function Write-AuditAiBrief([string]$path, $scanData, $installedSkillsPath, $templatePath) {
    $targetNames = @($scanData | ForEach-Object { $_.target.name })
    $content = @"
# Skill Audit Brief

Run ID: $(Split-Path (Split-Path $path -Parent) -Leaf)
Targets: $($targetNames -join ", ")

Use the generated repo scan JSON and installed skills JSON to decide:

- Which installed skills are appropriate for each target repository.
- Which installed skills have obvious functional overlap and should be reviewed.
- Which missing skills are strongly justified for these targets.

External research is intentionally performed by the outer AI agent. Search official documentation, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow. Write final recommendations to:

`$templatePath`

Rules:

- New installs require source links, reason, confidence, repo, skill path, ref, and mode.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Keep recommendations machine-readable JSON matching the template.

Installed skills JSON: `$installedSkillsPath`
"@
    Set-ContentUtf8 $path $content
}

function New-AuditRecommendationsTemplate([string]$runId, [string]$targetName) {
    return [pscustomobject]([ordered]@{
        schema_version = 1
        run_id = $runId
        target = $targetName
        new_skills = @()
        overlap_findings = @()
        do_not_install = @()
    })
}

function Invoke-AuditTargetsScan {
    param(
        [string]$Target,
        [string]$OutDir
    )
    $cfg = Load-AuditTargetsConfig
    $targets = @($cfg.targets)
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $targets = @($targets | Where-Object { $_.name -eq (Normalize-Name $Target) })
        Need ($targets.Count -gt 0) ("未找到目标仓：{0}" -f $Target)
    }
    else {
        $targets = @($targets | Where-Object {
                if ($_.PSObject.Properties.Match("enabled").Count -eq 0) { return $true }
                return [bool]$_.enabled
            })
    }
    Need ($targets.Count -gt 0) "没有可扫描的目标仓。"

    $runId = Get-AuditRunId
    $reportRoot = if ([string]::IsNullOrWhiteSpace($OutDir)) {
        Get-AuditReportRoot $runId
    }
    else {
        Resolve-AuditTargetPath $OutDir
    }
    EnsureDir $reportRoot

    $scans = @()
    foreach ($t in $targets) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $scans += New-AuditRepoScan ([string]$t.name) $resolved ([string]$t.path)
    }

    if ($scans.Count -eq 1) {
        Write-AuditJsonFile (Join-Path $reportRoot "repo-scan.json") $scans[0]
    }
    else {
        Write-AuditJsonFile (Join-Path $reportRoot "repo-scans.json") ([pscustomobject]@{ schema_version = 1; run_id = $runId; scans = @($scans) })
    }

    $installedPath = Join-Path $reportRoot "installed-skills.json"
    Write-AuditJsonFile $installedPath ([pscustomobject]@{ schema_version = 1; skills = @() })

    $templatePath = Join-Path $reportRoot "recommendations.template.json"
    $templateTarget = if ($scans.Count -eq 1) { [string]$scans[0].target.name } else { "*" }
    Write-AuditJsonFile $templatePath (New-AuditRecommendationsTemplate $runId $templateTarget)

    Write-AuditAiBrief (Join-Path $reportRoot "ai-brief.md") $scans $installedPath $templatePath
    Write-Host ("审查包已生成：{0}" -f $reportRoot) -ForegroundColor Green
    return [pscustomobject]@{
        run_id = $runId
        path = $reportRoot
        scans = @($scans)
    }
}

function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [switch]$Apply,
        [switch]$Yes
    )
    throw "审查目标应用尚未实现。"
}

function Invoke-AuditTargetsCommand([string[]]$tokens = @()) {
    $opts = Parse-AuditTargetsArgs $tokens
    switch ($opts.action) {
        "init" {
            if (Initialize-AuditTargetsConfig) {
                Write-Host "已创建 audit-targets.json" -ForegroundColor Green
            }
            else {
                Write-Host "audit-targets.json 已存在，未覆盖。" -ForegroundColor Yellow
            }
        }
        "add" {
            Add-AuditTargetConfigEntry $opts.name $opts.path $opts.tags $opts.notes | Out-Null
            Write-Host ("已登记目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "list" { Write-AuditTargetsList }
        "scan" { Invoke-AuditTargetsScan -Target $opts.target -OutDir $opts.out | Out-Null }
        "apply" { Invoke-AuditRecommendationsApply -RecommendationsPath $opts.recommendations -Apply:$opts.apply -Yes:$opts.yes | Out-Null }
    }
}
