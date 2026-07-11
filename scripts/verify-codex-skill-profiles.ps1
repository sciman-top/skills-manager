[CmdletBinding()]
param(
    [string]$SkillsScript = (Join-Path (Split-Path $PSScriptRoot -Parent) "skills.ps1")
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot "skills.json"
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$originalProfile = [string]$config.skill_projection.active_profile

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

function Test-SkillProfile([string]$Profile, [string[]]$Expected, [string[]]$Absent = @()) {
    Set-SkillProfile $Profile
    $promptText = Get-CodexPromptText
    foreach ($name in $Expected) {
        if ($promptText -notmatch [regex]::Escape("- ${name}:")) { throw "$Profile missing $name" }
    }
    foreach ($name in $Absent) {
        if ($promptText -match [regex]::Escape("- ${name}:")) { throw "$Profile unexpectedly includes $name" }
    }
    return [pscustomobject]@{
        profile = $Profile
        expected_count = $Expected.Count
        absent_count = $Absent.Count
        pass = $true
    }
}

try {
    Test-SkillProfile "coding" @(
        "using-superpowers",
        "systematic-debugging",
        "dispatching-parallel-agents",
        "subagent-driven-development",
        "using-git-worktrees"
    )
    Test-SkillProfile "ppt" @(
        "custom-teacher-courseware-ppt",
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
    Test-SkillProfile "default" @(
        "custom-windows-wpf-teacher-app",
        "custom-teacher-courseware-ppt",
        "custom-creator-publishing",
        "custom-junior-physics-animation",
        "chrome:control-chrome",
        "computer-use:computer-use"
    ) @("dispatching-parallel-agents")
}
finally {
    Set-SkillProfile $originalProfile
}
