[CmdletBinding()]
param(
    [switch]$ReportUntrackedRuntimeArtifacts,
    [switch]$FailOnUntrackedRuntimeArtifacts
)

$ErrorActionPreference = 'Stop'

function Get-TrackedFiles {
    $output = git ls-files 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed. Ensure the repository is available and Git is installed."
    }

    return $output | Where-Object { $_ -and $_.Trim() }
}

function Get-UntrackedFiles {
    $output = git ls-files --others --exclude-standard 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files --others failed. Ensure the repository is available and Git is installed."
    }

    return $output | Where-Object { $_ -and $_.Trim() }
}

function Find-MatchingPaths($files, $patterns) {
    foreach ($file in @($files)) {
        foreach ($pattern in @($patterns)) {
            if ($file -match $pattern) {
                [pscustomobject]@{
                    path = $file
                    pattern = $pattern
                }
                break
            }
        }
    }
}

$trackedArtifactPatterns = @(
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

$untrackedRuntimeArtifactPatterns = @(
    '^\.claude(?:/|$)',
    '^\.codex(?:/|$)',
    '^\.gemini(?:/|$)',
    '^\.trae(?:/|$)',
    '^\.txn(?:/|$)',
    '^agent(?:/|$)',
    '^reports/.*\.log$',
    '^docs/change-evidence/\d{8}-audit-runtime-.*\.md$',
    '^imports/_debug_[^/]+(?:/|$)',
    '^imports/_probe_[^/]+(?:/|$)',
    '^imports/_tree_[^/]+(?:/|$)',
    '^imports/_zip_[^/]+(?:/|$)',
    '^imports/.*\.zip$',
    '^.*\.tmp-[0-9a-fA-F]+$',
    '^.*\.bak-[0-9a-fA-F]+$'
)

$trackedFiles = Get-TrackedFiles
$violations = @(Find-MatchingPaths $trackedFiles $trackedArtifactPatterns)

if ($violations) {
    Write-Host 'Repository hygiene check failed. The following tracked paths are local-only or temporary artifacts:' -ForegroundColor Red
    $violations | Sort-Object path | ForEach-Object {
        Write-Host (" - {0}  [{1}]" -f $_.path, $_.pattern)
    }
    exit 1
}

if ($ReportUntrackedRuntimeArtifacts -or $FailOnUntrackedRuntimeArtifacts) {
    $untrackedRuntimeArtifacts = @(Find-MatchingPaths (Get-UntrackedFiles) $untrackedRuntimeArtifactPatterns)
    if ($untrackedRuntimeArtifacts.Count -gt 0) {
        Write-Host 'Repository hygiene warning. The following untracked runtime artifacts were found:' -ForegroundColor Yellow
        $untrackedRuntimeArtifacts | Sort-Object path | ForEach-Object {
            Write-Host (" - {0}  [{1}]" -f $_.path, $_.pattern) -ForegroundColor Yellow
        }
        if ($FailOnUntrackedRuntimeArtifacts) {
            exit 1
        }
    }
}

Write-Host 'Repository hygiene check passed.' -ForegroundColor Green
