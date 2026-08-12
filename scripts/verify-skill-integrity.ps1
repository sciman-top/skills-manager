[CmdletBinding()]
param(
    [string]$AgentRoot,
    [string]$ConfigPath,
    [string]$DependencyContractPath,
    [string]$CodexSkillRoot,
    [string]$ReportPath,
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = "Stop"
$resolvedScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repoRoot = Split-Path $resolvedScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($AgentRoot)) { $AgentRoot = Join-Path $repoRoot "agent" }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $repoRoot "skills.json" }
if ([string]::IsNullOrWhiteSpace($DependencyContractPath)) { $DependencyContractPath = Join-Path $repoRoot "config\skill-dependency-closure.json" }
if ([string]::IsNullOrWhiteSpace($CodexSkillRoot)) { $CodexSkillRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex\skills" }

function Get-SkillFrontmatterValue([string]$content, [string]$key) {
    $frontmatterMatch = [regex]::Match(
        $content,
        '\A(?:\uFEFF)?---[ \t]*\r?\n(?<body>.*?)(?:\r?\n)---[ \t]*(?:\r?\n|\z)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $frontmatterMatch.Success) { return "" }
    $frontmatter = $frontmatterMatch.Groups['body'].Value
    $pattern = ('(?m)^{0}:\s*["'']?([^\r\n"'']+)["'']?\s*$' -f [regex]::Escape($key))
    $match = [regex]::Match($frontmatter, $pattern)
    if (-not $match.Success) { return "" }
    return $match.Groups[1].Value.Trim()
}

function Test-PathWithinRoot([string]$path, [string]$root) {
    $fullPath = [IO.Path]::GetFullPath($path)
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([string]::Equals($fullPath, $fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $rootPrefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Add-IntegrityFinding($list, [string]$code, [string]$skill, [string]$message, [string]$path = "") {
    $list.Add([pscustomobject][ordered]@{
            code = $code
            skill = $skill
            message = $message
            path = $path
        }) | Out-Null
}

function Add-IntegritySkillNames([Collections.Generic.HashSet[string]]$set, $values) {
    foreach ($value in @($values)) {
        $name = ([string]$value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) { $set.Add($name) | Out-Null }
    }
}

function Add-IntegritySkillPathLeaf([Collections.Generic.HashSet[string]]$set, [string]$value) {
    $normalized = $value.Trim().Replace('\', '/').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return }
    Add-IntegritySkillNames $set (($normalized -split '/')[-1])
}

function ConvertFrom-OpenAiYamlScalar([string]$value) {
    $trimmed = $value.Trim()
    if ($trimmed.Length -ge 2) {
        if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
            ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }
    return $trimmed
}

function Get-OpenAiToolDependencyEntries([string[]]$lines) {
    $entries = New-Object System.Collections.Generic.List[object]
    $inDependencies = $false
    $inTools = $false
    $current = $null

    foreach ($line in $lines) {
        if ($line -match '^dependencies:\s*(?:#.*)?$') {
            $inDependencies = $true
            $inTools = $false
            continue
        }
        if ($line -match '^\S' -and $line -notmatch '^dependencies:') {
            if ($null -ne $current) { $entries.Add([pscustomobject]$current) | Out-Null }
            $current = $null
            $inDependencies = $false
            $inTools = $false
            continue
        }
        if (-not $inDependencies) { continue }
        if ($line -match '^  tools:\s*(?:#.*)?$') {
            $inTools = $true
            continue
        }
        if (-not $inTools) { continue }

        if ($line -match '^    -(?:\s+(?<key>[A-Za-z0-9_]+):\s*(?<value>.*))?\s*$') {
            if ($null -ne $current) { $entries.Add([pscustomobject]$current) | Out-Null }
            $current = [ordered]@{}
            if (-not [string]::IsNullOrWhiteSpace($Matches.key)) {
                $current[$Matches.key] = ConvertFrom-OpenAiYamlScalar $Matches.value
            }
            continue
        }
        if ($null -ne $current -and $line -match '^      (?<key>[A-Za-z0-9_]+):\s*(?<value>.*)\s*$') {
            $current[$Matches.key] = ConvertFrom-OpenAiYamlScalar $Matches.value
            continue
        }
        if ($line -match '^\s{0,2}\S') {
            if ($null -ne $current) { $entries.Add([pscustomobject]$current) | Out-Null }
            $current = $null
            $inTools = $false
        }
    }

    if ($null -ne $current) { $entries.Add([pscustomobject]$current) | Out-Null }
    return @($entries.GetEnumerator())
}

$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$declaredMcpDependencies = New-Object System.Collections.Generic.List[object]
$skills = @()
$openAiManifestCount = 0
$openAiToolDependencyCount = 0

if (-not (Test-Path -LiteralPath $AgentRoot -PathType Container)) {
    Add-IntegrityFinding $errors "missing_agent_root" "" ("agent root does not exist: {0}" -f $AgentRoot) $AgentRoot
}
else {
    foreach ($directory in (Get-ChildItem -LiteralPath $AgentRoot -Directory | Sort-Object Name)) {
        $skillFile = Join-Path $directory.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }

        $content = Get-Content -Raw -LiteralPath $skillFile
        $name = Get-SkillFrontmatterValue $content "name"
        if ([string]::IsNullOrWhiteSpace($name)) {
            Add-IntegrityFinding $errors "missing_skill_name" $directory.Name "SKILL.md frontmatter has no name" $skillFile
            continue
        }

        $skills += [pscustomobject]@{
            name = $name
            directory = $directory.Name
            path = $skillFile
        }

        foreach ($match in [regex]::Matches($content, '!??\[[^\]]*\]\(([^)]+)\)')) {
            $target = $match.Groups[1].Value.Trim().Trim('<', '>')
            if ($target -match '^(https?://|mailto:|#|data:|javascript:)') { continue }
            if ($target -match '[{}]' -or $target.StartsWith('$')) { continue }

            $pathPart = ($target -split '#', 2)[0]
            if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }

            try {
                $decoded = [uri]::UnescapeDataString($pathPart)
                $candidate = [IO.Path]::GetFullPath((Join-Path $directory.FullName $decoded))
            }
            catch {
                Add-IntegrityFinding $errors "invalid_relative_link" $name ("invalid relative link: {0}" -f $target) $skillFile
                continue
            }

            if (-not (Test-PathWithinRoot $candidate $AgentRoot)) {
                Add-IntegrityFinding $errors "relative_link_outside_agent_root" $name ("relative resource escapes agent root: {0}" -f $target) $skillFile
                continue
            }

            if (-not (Test-Path -LiteralPath $candidate)) {
                Add-IntegrityFinding $errors "broken_relative_link" $name ("missing local resource: {0}" -f $target) $skillFile
            }
        }

        $openAiManifestPath = Join-Path $directory.FullName "agents\openai.yaml"
        if (Test-Path -LiteralPath $openAiManifestPath -PathType Leaf) {
            $openAiManifestCount++
            $openAiContent = Get-Content -Raw -LiteralPath $openAiManifestPath
            foreach ($match in [regex]::Matches($openAiContent, '(?m)^\s{2}icon_(?:small|large):\s*(["'']?)([^\r\n"'']+)\1\s*$')) {
                $target = $match.Groups[2].Value.Trim()
                if ($target -match '^(https?://|data:)') {
                    Add-IntegrityFinding $errors "invalid_openai_resource" $name ("OpenAI icon must be relative to the skill directory: {0}" -f $target) $openAiManifestPath
                    continue
                }
                $normalizedTarget = ($target -replace '^\./', '').Replace('/', [IO.Path]::DirectorySeparatorChar)
                try {
                    $candidate = [IO.Path]::GetFullPath((Join-Path $directory.FullName $normalizedTarget))
                }
                catch {
                    Add-IntegrityFinding $errors "invalid_openai_resource" $name ("invalid OpenAI metadata resource: {0}" -f $target) $openAiManifestPath
                    continue
                }
                if (-not (Test-PathWithinRoot $candidate $directory.FullName)) {
                    Add-IntegrityFinding $errors "openai_resource_outside_skill" $name ("OpenAI metadata resource escapes skill directory: {0}" -f $target) $openAiManifestPath
                    continue
                }
                if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                    Add-IntegrityFinding $errors "broken_openai_resource" $name ("missing OpenAI metadata resource: {0}" -f $target) $openAiManifestPath
                }
            }

            $toolDependencies = @(Get-OpenAiToolDependencyEntries (Get-Content -LiteralPath $openAiManifestPath))
            $openAiToolDependencyCount += $toolDependencies.Count
            foreach ($toolDependency in $toolDependencies) {
                $type = ([string]$toolDependency.type).Trim()
                $value = ([string]$toolDependency.value).Trim()
                if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($value)) {
                    Add-IntegrityFinding $errors "invalid_openai_tool_dependency" $name "OpenAI tool dependency requires type and value" $openAiManifestPath
                    continue
                }
                if (-not [string]::Equals($type, "mcp", [System.StringComparison]::OrdinalIgnoreCase)) {
                    Add-IntegrityFinding $errors "unsupported_openai_tool_dependency" $name ("unsupported OpenAI tool dependency type: {0}" -f $type) $openAiManifestPath
                    continue
                }
                $declaredMcpDependencies.Add([pscustomobject]@{
                        skill = $name
                        value = $value
                        path = $openAiManifestPath
                    }) | Out-Null
            }
        }
    }
}

$duplicateGroups = @($skills | Group-Object name | Where-Object Count -gt 1)
foreach ($group in $duplicateGroups) {
    Add-IntegrityFinding $errors "duplicate_skill_name" $group.Name ("skill name resolves to {0} packages" -f $group.Count)
}

$misplacedCodexUserSkillCount = 0
if (Test-Path -LiteralPath $CodexSkillRoot -PathType Container) {
    foreach ($directory in (Get-ChildItem -LiteralPath $CodexSkillRoot -Directory -Force | Sort-Object Name)) {
        if ([string]::Equals($directory.Name, ".system", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $skillFile = Join-Path $directory.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
        $misplacedCodexUserSkillCount++
        Add-IntegrityFinding $errors "misplaced_codex_user_skill" $directory.Name "custom skill bypasses the governed overrides -> agent -> user_skill_root projection" $skillFile
    }
}

$skillNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($skill in $skills) { $skillNames.Add([string]$skill.name) | Out-Null }

$dependencyCount = 0
if (-not (Test-Path -LiteralPath $DependencyContractPath -PathType Leaf)) {
    Add-IntegrityFinding $errors "missing_dependency_contract" "" ("dependency contract does not exist: {0}" -f $DependencyContractPath) $DependencyContractPath
}
elseif (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Add-IntegrityFinding $errors "missing_config" "" ("skills config does not exist: {0}" -f $ConfigPath) $ConfigPath
}
else {
    try {
        $contract = Get-Content -Raw -LiteralPath $DependencyContractPath | ConvertFrom-Json
        $config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
        $dependencies = @($contract.dependencies)
        $dependencyCount = $dependencies.Count

        # agent/ is generated from both tracked sources and locally materialized gitlinks.
        # A clean checkout intentionally lacks the latter, so dependency existence must use
        # tracked source declarations as well as any materialized package frontmatter. Profile,
        # catalog and alias references are consumers and must never self-prove existence.
        $availableSkillNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        Add-IntegritySkillNames $availableSkillNames $skillNames
        foreach ($import in @($config.imports)) {
            Add-IntegritySkillPathLeaf $availableSkillNames ([string]$import.skill)
        }
        foreach ($mapping in @($config.mappings)) {
            Add-IntegritySkillPathLeaf $availableSkillNames ([string]$mapping.from)
        }

        $configuredMcpServers = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($server in @($config.mcp_servers)) {
            $serverName = ([string]$server.name).Trim()
            if (-not [string]::IsNullOrWhiteSpace($serverName)) { $configuredMcpServers.Add($serverName) | Out-Null }
        }
        foreach ($declaredMcpDependency in $declaredMcpDependencies) {
            if (-not $configuredMcpServers.Contains([string]$declaredMcpDependency.value)) {
                Add-IntegrityFinding $errors "missing_required_mcp" ([string]$declaredMcpDependency.skill) ("required MCP server is not configured: {0}" -f [string]$declaredMcpDependency.value) ([string]$declaredMcpDependency.path)
            }
        }

        foreach ($dependency in $dependencies) {
            $caller = ([string]$dependency.skill).Trim()
            $requiredNames = @($dependency.requires | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ([string]::IsNullOrWhiteSpace($caller)) {
                Add-IntegrityFinding $errors "invalid_dependency_entry" "" "dependency entry has no skill name" $DependencyContractPath
                continue
            }
            if (-not $availableSkillNames.Contains($caller)) {
                Add-IntegrityFinding $errors "missing_declared_skill" $caller "dependency contract caller is absent from the materialized and tracked portable inventories" $DependencyContractPath
                continue
            }

            foreach ($requiredName in $requiredNames) {
                if (-not $availableSkillNames.Contains($requiredName)) {
                    Add-IntegrityFinding $errors "missing_required_skill" $caller ("required skill is absent from the materialized and tracked portable inventories: {0}" -f $requiredName) $DependencyContractPath
                }
            }

        }
    }
    catch {
        Add-IntegrityFinding $errors "invalid_integrity_config" "" $_.Exception.Message $DependencyContractPath
    }
}

$errorItems = @($errors.GetEnumerator())
$warningItems = @($warnings.GetEnumerator())
$report = [pscustomobject][ordered]@{
    schema_version = 1
    generated_at = [DateTime]::UtcNow.ToString("o")
    ok = ($errors.Count -eq 0)
    skill_count = @($skills).Count
    checks = [pscustomobject][ordered]@{
        package_entrypoints = @($skills).Count
        duplicate_name_groups = $duplicateGroups.Count
        dependency_entries = $dependencyCount
        openai_manifests = $openAiManifestCount
        openai_tool_dependencies = $openAiToolDependencyCount
        misplaced_codex_user_skills = $misplacedCodexUserSkillCount
    }
    errors = $errorItems
    warnings = $warningItems
}

$serialized = $report | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $parent = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $serialized | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if ($Json) {
    Write-Output $serialized
}
elseif ($report.ok) {
    Write-Host ("skill integrity verified: {0} skills" -f $report.skill_count)
}
else {
    Write-Host ("skill integrity failed: {0} error(s)" -f $errors.Count) -ForegroundColor Red
    foreach ($finding in $errors) {
        Write-Host ("- [{0}] {1}: {2}" -f $finding.code, $finding.skill, $finding.message)
    }
}

$exitCode = if ($report.ok) { 0 } else { 1 }
if ($NoExit) { $global:LASTEXITCODE = $exitCode; return }
exit $exitCode
