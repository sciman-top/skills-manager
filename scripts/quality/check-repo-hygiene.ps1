[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-TrackedFiles {
    $output = git ls-files 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed. Ensure the repository is available and Git is installed."
    }

    return $output | Where-Object { $_ -and $_.Trim() }
}

$patterns = @(
    '^\.claude(?:/|$)',
    '^\.codex(?:/|$)',
    '^\.gemini(?:/|$)',
    '^\.trae(?:/|$)',
    '^\.gitmessage\.txt$',
    '^\.tmp_',
    '^reports/.*\.log$',
    '^docs/governance/merge-report\.md$',
    '^scripts/governance(?:/|$)',
    '^imports/_debug_[^/]+(?:/|$)',
    '^imports/_probe_[^/]+(?:/|$)',
    '^imports/_tree_[^/]+(?:/|$)',
    '^imports/.*\.zip$'
)

$trackedFiles = Get-TrackedFiles
$violations = foreach ($file in $trackedFiles) {
    foreach ($pattern in $patterns) {
        if ($file -match $pattern) {
            [pscustomobject]@{
                path = $file
                pattern = $pattern
            }
            break
        }
    }
}

if ($violations) {
    Write-Host 'Repository hygiene check failed. The following tracked paths are local-only or temporary artifacts:' -ForegroundColor Red
    $violations | Sort-Object path | ForEach-Object {
        Write-Host (" - {0}  [{1}]" -f $_.path, $_.pattern)
    }
    exit 1
}

Write-Host 'Repository hygiene check passed.' -ForegroundColor Green
