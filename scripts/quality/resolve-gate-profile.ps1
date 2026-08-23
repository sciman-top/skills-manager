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

$riskPath = '^(tests/E2E/|rules/|overrides/|vendor/|imports/|\.github/workflows/|scripts/(quality/|release/|hooks/|verify-)|config/(skills\.schema\.json|skill-dependency-closure\.json)$|(?:AGENTS|CLAUDE|GEMINI)\.md$|build\.ps1$|install\.ps1$|skills\.json$|skills\.lock\.json$|audit-targets\.json$)'
$sourcePath = '^(src/|tests/Unit/)'
$docsOnlyPath = '^(README(?:\.zh-CN|\.en)?\.md$|CONTRIBUTING\.md$|docs/.*\.md$)'
$fixedFocusedTests = @(
    'tests/Unit/CiWorkflow.Tests.ps1'
    'tests/Unit/InfrastructureSeam.Tests.ps1'
    'tests/Unit/ReadOnlyCli.Tests.ps1'
    'tests/Unit/BuildScript.Tests.ps1'
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
if ($Mode -eq 'local') {
    $untracked = Resolve-GitOutput @('ls-files', '--others', '--exclude-standard')
    if ($untracked.exit_code -ne 0) {
        $result = Get-GateProfileResult 'full' 'untracked_scan_failed' $baseShaValue $headShaValue $false @() 0 0
        if ($Json) { $result | ConvertTo-Json } else { $result }
        exit 0
    }
    $untrackedFiles = @($untracked.lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $untrackedCount = $untrackedFiles.Count
    if ($untrackedCount -gt 0) {
        $result = Get-GateProfileResult 'full' 'untracked_file' $baseShaValue $headShaValue $false @() 0 $untrackedCount
        if ($Json) { $result | ConvertTo-Json } else { $result }
        exit 0
    }
}

$diffArgs = if ($Mode -eq 'ci') { @('diff', '--name-only', $baseShaValue, $headShaValue, '--') } else { @('diff', '--name-only', $baseShaValue, '--') }
$diff = Resolve-GitOutput $diffArgs
if ($diff.exit_code -ne 0) {
    $result = Get-GateProfileResult 'full' 'diff_failed' $baseShaValue $headShaValue $false @() 0 $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}
$changed = @($diff.lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$changedCount = $changed.Count

$riskRegex = [regex]::new($riskPath)
$sourceRegex = [regex]::new($sourcePath)
$docsRegex = [regex]::new($docsOnlyPath)

if ($changedCount -eq 0) {
    $result = Get-GateProfileResult 'docs' 'empty_diff' $baseShaValue $headShaValue $false @() 0 $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

$docsOnly = ($changed | Where-Object { -not $docsRegex.IsMatch($_) }).Count -eq 0
if ($docsOnly) {
    $result = Get-GateProfileResult 'docs' 'docs_only' $baseShaValue $headShaValue $true @() $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

if (($changed | Where-Object { $riskRegex.IsMatch($_) }).Count -gt 0) {
    $result = Get-GateProfileResult 'full' 'risk_path' $baseShaValue $headShaValue $false @() $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

if (($changed | Where-Object { $sourceRegex.IsMatch($_) }).Count -gt 0) {
    $focused = @($fixedFocusedTests) + @($changed | Where-Object { $_ -match '^tests/Unit/.*\.Tests\.ps1$' })
    $focused = @($focused | Sort-Object -Unique)
    $result = Get-GateProfileResult 'focused' 'source_path' $baseShaValue $headShaValue $false $focused $changedCount $untrackedCount
    if ($Json) { $result | ConvertTo-Json } else { $result }
    exit 0
}

$result = Get-GateProfileResult 'quick' 'default' $baseShaValue $headShaValue $false @() $changedCount $untrackedCount
if ($Json) { $result | ConvertTo-Json } else { $result }
exit 0
