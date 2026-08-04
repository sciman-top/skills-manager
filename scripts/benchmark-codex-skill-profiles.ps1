[CmdletBinding()]
param(
    [string]$CorpusPath,
    [string]$OutputRoot,
    [string[]]$Profiles,
    [string[]]$CaseId,
    [ValidateRange(1, 5)][int]$Repeat = 1,
    [string]$Model = "gpt-5.6-sol",
    [switch]$Execute,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($CorpusPath)) { $CorpusPath = Join-Path $repoRoot "config\codex-skill-profile-benchmark.json" }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot "artifacts\skill-profile-benchmark" }
$schemaPath = Join-Path $repoRoot "config\codex-skill-profile-benchmark-output.schema.json"
$skillsScript = Join-Path $repoRoot "skills.ps1"

function Set-BenchmarkProfile([string]$Name) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $skillsScript "技能配置" "使用" $Name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "profile switch failed: $Name" }
}

function Get-Expectation($Case, [string]$Profile) {
    $property = @($Case.expectations.PSObject.Properties | Where-Object Name -eq $Profile)
    if ($property.Count -ne 1) { throw "case '$($Case.id)' has no expectation for profile '$Profile'" }
    return $property[0].Value
}

$corpus = Get-Content -LiteralPath $CorpusPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath (Join-Path $repoRoot "skills.json") -Raw | ConvertFrom-Json
$originalProfile = [string]$config.skill_projection.active_profile
$configuredProfiles = @($config.skill_projection.profiles.PSObject.Properties.Name)
$normalizedProfiles = @($Profiles | ForEach-Object { @(([string]$_) -split ',') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$normalizedCaseIds = @($CaseId | ForEach-Object { @(([string]$_) -split ',') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$selectedProfiles = if ($normalizedProfiles.Count -gt 0) { $normalizedProfiles } else { @($corpus.profiles) }
$cases = @($corpus.cases)
if ($normalizedCaseIds.Count -gt 0) { $cases = @($cases | Where-Object { $normalizedCaseIds -contains $_.id }) }
if ($cases.Count -eq 0) { throw "no benchmark cases selected" }

foreach ($profile in $selectedProfiles) {
    if ($profile -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "unsafe profile name: $profile" }
    if ($configuredProfiles -notcontains $profile) { throw "unknown profile: $profile" }
    foreach ($case in $cases) { Get-Expectation $case $profile | Out-Null }
}
$selectedCaseIds = @($cases | ForEach-Object { [string]$_.id })
foreach ($selectedCaseId in $selectedCaseIds) {
    if ($selectedCaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "unsafe benchmark case id: $selectedCaseId" }
}
if (@($selectedCaseIds | Sort-Object -Unique).Count -ne $selectedCaseIds.Count) { throw "duplicate benchmark case ids" }

$plannedCalls = $selectedProfiles.Count * $cases.Count * $Repeat
if (-not $Execute) {
    $plan = [ordered]@{ valid = $true; execute = $false; execution_boundary = "fresh_ephemeral_task"; profiles = $selectedProfiles; cases = $selectedCaseIds; repeat = $Repeat; planned_calls = $plannedCalls }
    if ($Json) { $plan | ConvertTo-Json -Depth 5 } else { Write-Host ("benchmark corpus valid: profiles={0}, cases={1}, repeat={2}, planned_calls={3}" -f $selectedProfiles.Count, $cases.Count, $Repeat, $plannedCalls) }
    exit 0
}

$runId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]

try {
    foreach ($profile in $selectedProfiles) {
        Set-BenchmarkProfile $profile
        foreach ($case in $cases) {
            $expectation = Get-Expectation $case $profile
            for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
                $prompt = @"
This is a read-only skill-routing benchmark for profile '$profile'. Do not call tools and do not modify files.
Given the request below, return the exact visible skill names that should be invoked before any implementation action.
Also report whether the workflow would create a plan, delegate to subagents, or use a git worktree.

Request: $($case.request)
"@
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
                $raw = @(& codex exec --ephemeral --json --sandbox read-only --model $Model -c 'model_provider="openai"' --output-schema $schemaPath $prompt 2>&1)
                $exitCode = $LASTEXITCODE
                $timer.Stop()
                $events = @($raw | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $null -ne $_ })
                $usageEvent = $events | Where-Object type -eq "turn.completed" | Select-Object -Last 1
                $messageEvent = $events | Where-Object { $_.type -eq "item.completed" -and $_.item.type -eq "agent_message" } | Select-Object -Last 1
                $usage = $usageEvent.usage
                $message = [string]$messageEvent.item.text
                $parsed = $null
                try { $parsed = $message | ConvertFrom-Json } catch { }
                $selected = if ($null -ne $parsed) { @($parsed.selected_skills) } else { @() }
                $missing = @($expectation.required | Where-Object { $selected -notcontains $_ })
                $forbidden = @($expectation.forbidden | Where-Object { $selected -contains $_ })
                $result = [ordered]@{
                    profile = $profile; case_id = [string]$case.id; iteration = $iteration; exit_code = $exitCode
                    parse_ok = ($null -ne $parsed)
                    duration_ms = $timer.ElapsedMilliseconds; input_tokens = [int]$usage.input_tokens; output_tokens = [int]$usage.output_tokens
                    selected_skills = @($selected); would_create_plan = $parsed.would_create_plan; would_delegate = $parsed.would_delegate
                    would_use_worktree = $parsed.would_use_worktree; missing_required = $missing; selected_forbidden = $forbidden
                    expectation_pass = ($exitCode -eq 0 -and $null -ne $parsed -and $missing.Count -eq 0 -and $forbidden.Count -eq 0)
                    reason = [string]$parsed.reason
                }
                $results.Add([pscustomobject]$result) | Out-Null
                $raw | Set-Content -LiteralPath (Join-Path $runRoot ("{0}-{1}-{2}.jsonl" -f $profile, $case.id, $iteration)) -Encoding utf8
            }
        }
    }
}
finally {
    Set-BenchmarkProfile $originalProfile
}

$restoredConfig = Get-Content -LiteralPath (Join-Path $repoRoot "skills.json") -Raw | ConvertFrom-Json
$restoredProfile = [string]$restoredConfig.skill_projection.active_profile
if (-not [string]::Equals($restoredProfile, $originalProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "benchmark did not restore the original profile: expected=$originalProfile actual=$restoredProfile"
}

$summary = @($selectedProfiles | ForEach-Object {
    $profile = $_
    $items = @($results.ToArray() | Where-Object profile -eq $profile)
    [ordered]@{
        profile = $profile; calls = $items.Count; expectation_passed = @($items | Where-Object expectation_pass).Count
        input_tokens = ($items | Measure-Object input_tokens -Sum).Sum; output_tokens = ($items | Measure-Object output_tokens -Sum).Sum
        duration_ms = ($items | Measure-Object duration_ms -Sum).Sum; plans = @($items | Where-Object would_create_plan).Count
        delegations = @($items | Where-Object would_delegate).Count; worktrees = @($items | Where-Object would_use_worktree).Count
    }
})
$resultItems = @($results.ToArray())
$report = [ordered]@{ schema_version = 1; run_id = $runId; model = $Model; execution_boundary = "fresh_ephemeral_task"; repeat = $Repeat; original_profile = $originalProfile; restored_profile = $restoredProfile; summary = $summary; results = $resultItems }
$reportPath = Join-Path $runRoot "report.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding utf8
if ($Json) { $report | ConvertTo-Json -Depth 10 } else { Write-Host ("benchmark complete: {0}" -f $reportPath); $summary | Format-Table }
if (@($resultItems | Where-Object { -not $_.expectation_pass }).Count -gt 0) { exit 1 }
