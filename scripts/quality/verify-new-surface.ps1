[CmdletBinding()]
param(
    [string]$EventPath = $env:GITHUB_EVENT_PATH
)

# Deterministic new-surface gate: a PR that adds files to runtime, gate, test or CI
# paths must carry the `new-surface` label, which a human sets. Docs and fixtures
# are not gated, so replacing a doc does not need the label.
$ErrorActionPreference = 'Stop'
$gatedAddedPath = '^(src/|scripts/|tests/(?!fixtures/)|\.github/)'

if ([string]::IsNullOrWhiteSpace($EventPath) -or -not (Test-Path -LiteralPath $EventPath -PathType Leaf)) {
    Write-Host 'New-surface check: not applicable (no GitHub event file).' -ForegroundColor Yellow
    exit 0
}
$event = Get-Content -LiteralPath $EventPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if ($null -eq $event.pull_request) {
    Write-Host 'New-surface check: not applicable (not a pull_request event).' -ForegroundColor Yellow
    exit 0
}

$baseSha = [string]$event.pull_request.base.sha
$labels = @($event.pull_request.labels | ForEach-Object { [string]$_.name })
if ([string]::IsNullOrWhiteSpace($baseSha)) { throw 'New-surface check: pull_request.base.sha is missing.' }
& git cat-file -e ($baseSha + '^{commit}') 2>$null
if ($LASTEXITCODE -ne 0) { & git fetch --no-tags --depth=1 origin $baseSha; if ($LASTEXITCODE -ne 0) { throw "New-surface check: cannot fetch base $baseSha" } }

$added = @(& git diff --name-only --diff-filter=A $baseSha HEAD | Where-Object { $_ -match $gatedAddedPath })
if ($added.Count -eq 0) {
    Write-Host 'New-surface check passed: no new runtime, gate, test or CI files.' -ForegroundColor Green
    exit 0
}
if ($labels -contains 'new-surface') {
    Write-Host ("New-surface check passed: label set for {0} new file(s)." -f $added.Count) -ForegroundColor Green
    exit 0
}
throw ("New-surface check failed: {0} new file(s) under gated paths without the 'new-surface' label: {1}" -f $added.Count, ($added -join ', '))
