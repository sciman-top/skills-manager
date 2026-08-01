[CmdletBinding()]
param(
    [string]$SkillsScript = (Join-Path (Split-Path $PSScriptRoot -Parent) "skills.ps1")
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot "skills.json"
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$originalProfile = [string]$config.skill_projection.active_profile
$testedProfiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Set-SkillProfile([string]$Name) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $SkillsScript "技能配置" "使用" $Name
    if ($LASTEXITCODE -ne 0) { throw "profile switch failed: $Name" }
}

function Get-CodexPromptText {
    $raw = & codex debug prompt-input -c 'model_provider="openai"' "fresh-loading-probe"
    if ($LASTEXITCODE -ne 0) { throw "codex debug prompt-input failed" }
    $items = $raw | ConvertFrom-Json
    return (($items | ForEach-Object { $_.content | ForEach-Object { $_.text } }) -join "`n")
}

function Get-ProjectionManifest {
    $manifestPath = Join-Path $repoRoot "reports\skill-projection\current.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "projection manifest missing: $manifestPath" }
    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Test-SkillProfile([string]$Profile, [string[]]$Expected, [string[]]$Absent = @(), [string[]]$Projected = @()) {
    Set-SkillProfile $Profile
    $promptText = Get-CodexPromptText
    $manifest = Get-ProjectionManifest
    if ([string]$manifest.active_profile -ne $Profile) { throw "$Profile manifest active profile mismatch: $($manifest.active_profile)" }
    $projectedNames = @($manifest.skills | ForEach-Object { [string]$_.name })
    foreach ($name in $Expected) {
        if ($promptText -notmatch [regex]::Escape("- ${name}:")) { throw "$Profile missing $name" }
    }
    foreach ($name in $Absent) {
        if ($promptText -match [regex]::Escape("- ${name}:")) { throw "$Profile unexpectedly includes $name" }
    }
    foreach ($name in $Projected) {
        if ($projectedNames -notcontains $name) { throw "$Profile projection missing $name" }
    }
    $testedProfiles.Add($Profile) | Out-Null
    return [pscustomobject]@{
        profile = $Profile
        expected_count = $Expected.Count
        absent_count = $Absent.Count
        projected_count = $Projected.Count
        pass = $true
    }
}

try {
    Test-SkillProfile "coding" @(
        "systematic-debugging",
        "verification-before-completion",
        "code-review-and-quality"
    ) @(
        "using-superpowers",
        "research",
        "brainstorming",
        "dispatching-parallel-agents",
        "subagent-driven-development",
        "using-git-worktrees"
    )
    Test-SkillProfile "coding-strict" @(
        "systematic-debugging",
        "test-driven-development",
        "verification-before-completion",
        "code-review-and-quality",
        "domain-modeling"
    ) @(
        "using-superpowers",
        "brainstorming",
        "writing-plans",
        "executing-plans",
        "dispatching-parallel-agents",
        "subagent-driven-development",
        "using-git-worktrees"
    ) @("grill-with-docs", "grilling")
    Test-SkillProfile "engineering" @(
        "research",
        "domain-modeling",
        "codebase-design"
    ) @("using-superpowers") @(
        "grill-with-docs",
        "draft-spec",
        "draft-tickets",
        "setup-matt-pocock-skills",
        "to-spec",
        "to-tickets",
        "improve-codebase-architecture"
    )
    Test-SkillProfile "python" @(
        "modern-python",
        "python-testing-patterns",
        "security-and-hardening"
    ) @("using-superpowers")
    Test-SkillProfile "mcp" @(
        "mcp-builder",
        "mcp-cli",
        "api-and-interface-design"
    ) @("using-superpowers")
    Test-SkillProfile "review" @(
        "code-review-and-quality",
        "receiving-code-review",
        "code-simplification"
    ) @("using-superpowers")
    Test-SkillProfile "ppt" @(
        "custom-teacher-courseware-ppt",
        "custom-powerpoint-accessibility",
        "powerpoint-automation",
        "presentations:Presentations",
        "documents:documents"
    ) @("dispatching-parallel-agents")
    Test-SkillProfile "dotnet" @(
        "microsoft-code-reference",
        "custom-windows-wpf-teacher-app",
        "dotnet-backend-patterns",
        "debug:dotnet"
    ) @("dispatching-parallel-agents")
    Test-SkillProfile "content" @(
        "custom-creator-publishing",
        "copy-editing",
        "baoyu-format-markdown"
    ) @("using-superpowers")
    Test-SkillProfile "marketing" @(
        "content-strategy",
        "copywriting",
        "copy-editing"
    ) @("using-superpowers")
    Test-SkillProfile "physics" @(
        "custom-junior-physics-animation",
        "manim-composer",
        "playwright"
    ) @("using-superpowers")
    Test-SkillProfile "video" @(
        "storyboard-creation",
        "remotion-best-practices",
        "manimce-best-practices"
    ) @("using-superpowers")
    Test-SkillProfile "design" @(
        "frontend-design",
        "frontend-ui-engineering",
        "web-design-guidelines"
    ) @("using-superpowers")
    Test-SkillProfile "browser" @(
        "playwright",
        "playwright-best-practices",
        "webapp-testing"
    ) @("using-superpowers")
    Test-SkillProfile "database" @(
        "supabase-postgres-best-practices",
        "api-and-interface-design",
        "security-and-hardening"
    ) @("using-superpowers")
    Test-SkillProfile "default" @(
        "custom-windows-wpf-teacher-app",
        "custom-teacher-courseware-ppt",
        "custom-creator-publishing",
        "custom-junior-physics-animation",
        "chrome:control-chrome",
        "computer-use:computer-use"
    ) @(
        "using-superpowers",
        "research",
        "brainstorming",
        "planning-and-task-breakdown",
        "dispatching-parallel-agents"
    )

    $configuredProfiles = @($config.skill_projection.profiles.PSObject.Properties.Name | Sort-Object)
    $missingProbes = @($configuredProfiles | Where-Object { -not $testedProfiles.Contains($_) })
    if ($missingProbes.Count -gt 0) { throw "profiles missing fresh prompt probes: $($missingProbes -join ', ')" }
}
finally {
    Set-SkillProfile $originalProfile
}
