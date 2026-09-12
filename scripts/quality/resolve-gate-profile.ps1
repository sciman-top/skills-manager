[CmdletBinding()]
param(
    [string]$BaseSha = '',
    [string]$HeadSha = 'HEAD',
    [ValidateSet('local', 'ci')][string]$Mode = 'local',
    [switch]$Json
)

# Shared gate profile classifier. This script is the single authoritative copy
# of the docs/focused/full path classification; CI and the local quality gate
# both consume it. Read-only: git rev-parse / diff / symbolic-ref / ls-files
# only. Classification failure is expressed as profile=full plus a reason and
# exit code 0; only parameter usage errors exit 1.

$riskPath = '^(tests/E2E/|overrides/(README\.md|resources/|(?:custom|patches)/[^/]+/scripts/)|overrides/patches/provenance\.json$|vendor/|imports/|\.github/workflows/|scripts/(quality/|release/|hooks/|verify-)|config/(skills\.schema\.json|skill-dependency-closure\.json)$|build\.ps1$|install\.ps1$|skills\.lock\.json$|audit-targets\.json$)'
$rulePath = '^(?:rules/global/(?:codex/AGENTS|claude/CLAUDE|zcode/AGENTS)\.md|(?:AGENTS|CLAUDE|GEMINI)\.md)$'
$sourcePath = '^(src/|tests/Unit/)'
$docsOnlyPath = '^(README(?:\.zh-CN|\.en)?\.md$|CONTRIBUTING\.md$|docs/.*\.md$)'
$skillFocusedPath = '^overrides/(custom|patches)/[^/]+/(?:SKILL\.md|agents/openai\.yaml|references/.*\.md)$'
$skillsConfigPath = '^skills\.json$'
# Explicit behavior coverage, not a smoke-test substitute. Unmapped source
# falls back to full until its affected tests are known.
$sourceTests = @{
    'src/Core.ps1' = @('Core', 'InfrastructureSeam', 'ReadOnlyCli')
    'src/Commands/Migration.ps1' = @('Migration')
    'src/Commands/ReleaseUpdate.ps1' = @('ReleaseUpdate', 'ReleaseUpdateWorker')
    'src/Domain/SkillMetadata.ps1' = @('SkillMetadata')
    'src/Infrastructure/AtomicFile.ps1' = @('InfrastructureSeam')
}
$skillFocusedTests = @(
    'tests/Unit/SkillProjection.Tests.ps1'
    'tests/Unit/SkillProjectionProfiles.Tests.ps1'
)

function Resolve-GitOutput([string[]]$GitArgs) {
    $output = & git @GitArgs 2>$null
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; lines = @($output) }
}

function Get-GateProfileResult([string]$Profile, [string]$Reason, [string]$BaseSha, [string]$HeadSha, [bool]$DocsOnly, [string[]]$FocusedTestPaths, [int]$ChangedCount, [int]$UntrackedCount) {
    return [pscustomobject]@{
        profile            = $Profile
        reason             = $Reason
        base_sha           = $BaseSha
        head_sha           = $HeadSha
        docs_only          = $DocsOnly
        focused_test_paths = @($FocusedTestPaths)
        changed_count      = $ChangedCount
        untracked_count    = $UntrackedCount
    }
}

function Get-GitFileText([string]$Path, [string]$Revision = '') {
    $show = Resolve-GitOutput @('show', ('{0}:{1}' -f $Revision, $Path))
    if ($show.exit_code -ne 0) { return $null }
    return ($show.lines -join "`n")
}

function Get-CurrentFileText([string]$Path) {
    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if (-not $file.PSIsContainer) { return [IO.File]::ReadAllText($file.FullName) }
    }
    catch { return $null }
    return $null
}

function Get-SkillsConfigComparableText([string]$Text) {
    if ($null -eq $Text) { return $null }
    try { $config = $Text | ConvertFrom-Json }
    catch { return $null }

    $projection = $config.PSObject.Properties['skill_projection']
    if ($null -ne $projection -and $null -ne $projection.Value) {
        $projectionValue = $projection.Value
        foreach ($safeProperty in @('projection_profiles', 'discovery_catalog', 'external_skill_inventory')) {
            if ($projectionValue.PSObject.Properties.Name -contains $safeProperty) {
                $projectionValue.$safeProperty = $null
            }
        }
    }
    return ($config | ConvertTo-Json -Depth 100 -Compress)
}

function Test-SkillsConfigFocusedChange([string]$BaseSha, [string]$HeadSha, [string]$Mode) {
    $baseText = Get-GitFileText 'skills.json' $BaseSha
    $headText = if ($Mode -eq 'ci') { Get-GitFileText 'skills.json' $HeadSha } else { Get-CurrentFileText 'skills.json' }
    $baseComparable = Get-SkillsConfigComparableText $baseText
    $headComparable = Get-SkillsConfigComparableText $headText
    if ($null -eq $baseComparable -or $null -eq $headComparable) { return $false }
    return [string]::Equals($baseComparable, $headComparable, [StringComparison]::Ordinal)
}

$headShaValue = $HeadSha

# Base resolution: explicit BaseSha wins; otherwise derive origin/main then @{u}.
$baseShaValue = ''
if (-not [string]::IsNullOrWhiteSpace($BaseSha)) {
    $verify = Resolve-GitOutput @('rev-parse', '--verify', ('{0}^{{commit}}' -f $BaseSha))
    if ($verify.exit_code -ne 0) {
        $result = Get-GateProfileResult 'full' 'unresolvable_base' $BaseSha $headShaValue $false @() 0 0
        if ($Json) { $result | ConvertTo-Json } else { $result }
        exit 0
    }
    $baseShaValue = [string]$verify.lines[0]
}
else {
    $origin = Resolve-GitOutput @('rev-parse', '--verify', 'origin/main^{commit}')
    if ($origin.exit_code -eq 0) {
        $baseShaValue = [string]$origin.lines[0]
    }
    else {
        $upstream = Resolve-GitOutput @('rev-parse', '--verify', '@{u}^{commit}')
        if ($upstream.exit_code -eq 0) {
            $baseShaValue = [string]$upstream.lines[0]
        }
        else {
            $result = Get-GateProfileResult 'full' 'no_base' '' $headShaValue $false @() 0 0
            if ($Json) { $result | ConvertTo-Json } else { $result }
            exit 0
        }
    }
}

# Local mode scans non-ignored untracked files so that brand-new source,
# config, or governance files cannot bypass classification. CI mode must not:
# its change set is defined by <base>..<head>.
$untrackedCount = 0
$untrackedFiles = @()
if ($Mode -eq 'local') {
    $untracked = Resolve-GitOutput @('ls-files', '--others', '--exclude-standard')
    if ($untracked.exit_code -ne 0) {
        $result = Get-GateProfileResult 'full' 'untracked_scan_failed' $baseShaValue $headShaValue $false @() 0 0
        if ($Json) { $result | ConvertTo-Json } else { $result }
        exit 0
    }
    $untrackedFiles = @($untracked.lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $untrackedCount = $untrackedFiles.Count
}

$diffArgs = if ($Mode -eq 'ci') { @('diff', '--name-only', $baseShaValue, $headShaValue, '--') } else { @('diff', '--name-only', $baseShaValue, '--') }
$diff = Resolve-GitOutput $diffArgs
if ($diff.exit_code -ne 0) {
    $result = Get-GateProfileResult 'full' 'diff_failed' $baseShaValue $headShaValue $false @() 0 $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}
$changed = @(@($diff.lines) + $untrackedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$changedCount = $changed.Count

$riskRegex = [regex]::new($riskPath)
$sourceRegex = [regex]::new($sourcePath)
$docsRegex = [regex]::new($docsOnlyPath)
$skillFocusedRegex = [regex]::new($skillFocusedPath)
$skillsConfigRegex = [regex]::new($skillsConfigPath)
$ruleRegex = [regex]::new($rulePath)

if ($changedCount -eq 0) {
    $result = Get-GateProfileResult 'docs' 'empty_diff' $baseShaValue $headShaValue $false @() 0 $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

# skills.json is content-sensitive: only projection/discovery inventory edits
# can use the focused path; source, MCP, target, lock, and host-write changes
# remain full. Unknown override shapes also fail closed to full.
$riskChanged = @($changed | Where-Object { $riskRegex.IsMatch($_) })
$unknownOverrideChanged = @($changed | Where-Object {
        $_ -like 'overrides/*' -and -not $riskRegex.IsMatch($_) -and -not $skillFocusedRegex.IsMatch($_)
    })
$configRiskChanged = @($changed | Where-Object {
        $skillsConfigRegex.IsMatch($_) -and -not (Test-SkillsConfigFocusedChange $baseShaValue $headShaValue $Mode)
    })
if ($riskChanged.Count -gt 0 -or $unknownOverrideChanged.Count -gt 0 -or $configRiskChanged.Count -gt 0) {
    $result = Get-GateProfileResult 'full' 'risk_path' $baseShaValue $headShaValue $false @() $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

$docsOnly = ($changed | Where-Object { -not $docsRegex.IsMatch($_) }).Count -eq 0
if ($docsOnly) {
    $result = Get-GateProfileResult 'docs' 'docs_only' $baseShaValue $headShaValue $true @() $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

 $sourceChanged = @($changed | Where-Object { $sourceRegex.IsMatch($_) })
 $skillFocusedChanged = @($changed | Where-Object { $skillFocusedRegex.IsMatch($_) })
 $configFocusedChanged = @($changed | Where-Object { $skillsConfigRegex.IsMatch($_) })
 $ruleChanged = @($changed | Where-Object { $ruleRegex.IsMatch($_) })
 $unknownChanged = @($changed | Where-Object {
    $_ -ne 'skills.ps1' -and -not ($sourceRegex.IsMatch($_) -or $skillFocusedRegex.IsMatch($_) -or $skillsConfigRegex.IsMatch($_) -or $ruleRegex.IsMatch($_) -or $docsRegex.IsMatch($_))
 })
if ($unknownChanged.Count -gt 0) {
    $result = Get-GateProfileResult 'full' 'unknown_path' $baseShaValue $headShaValue $false @() $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}
if ($sourceChanged.Count -gt 0 -or $skillFocusedChanged.Count -gt 0 -or $configFocusedChanged.Count -gt 0 -or $ruleChanged.Count -gt 0) {
    $focused = @()
    $reason = 'source_path'
    foreach ($path in @($sourceChanged | Where-Object { $_ -like 'src/*' })) {
        if (-not $sourceTests.ContainsKey($path)) {
            $result = Get-GateProfileResult 'full' 'unmapped_source' $baseShaValue $headShaValue $false @() $changedCount $untrackedCount
            if ($Json) { $result | ConvertTo-Json } else { $result }
            exit 0
        }
        $focused += @($sourceTests[$path] | ForEach-Object { 'tests/Unit/{0}.Tests.ps1' -f $_ })
    }
    if ($ruleChanged.Count -gt 0) {
        $focused += @('tests/Unit/GlobalRuleProjection.Tests.ps1', 'tests/Unit/RuleDiagnostics.Tests.ps1')
        if ($sourceChanged.Count -eq 0) { $reason = 'rule_path' }
    }
    if ($skillFocusedChanged.Count -gt 0 -or $configFocusedChanged.Count -gt 0) {
        $focused += @($skillFocusedTests)
        if ($sourceChanged.Count -eq 0) {
            $reason = if ($skillFocusedChanged.Count -gt 0) { 'skill_path' } else { 'config_projection_path' }
        }
    }
    $focused += @($changed | Where-Object { $_ -match '^tests/Unit/.*\.Tests\.ps1$' })
    $focused = @($focused | Sort-Object -Unique)
    $result = Get-GateProfileResult 'focused' $reason $baseShaValue $headShaValue $false $focused $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

$result = Get-GateProfileResult 'full' 'generated_only' $baseShaValue $headShaValue $false @() $changedCount $untrackedCount
if ($Json) { $result | ConvertTo-Json } else { $result }
exit 0
