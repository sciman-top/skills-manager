[CmdletBinding()]
param(
    [ValidateSet('docs', 'quick', 'focused', 'full', 'auto')]
    [string]$Profile = 'quick',
    [switch]$AllowDirtyWorktree,
    [switch]$ResolveOnly,
    [string[]]$TestPath = @(),
    [string[]]$TestName = @(),
    [ValidateSet('lock', 'integrity', 'config', 'scheduler', 'mor')]
    [string[]]$Verifier = @(),
    [string]$DiffBase = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Invoke-QualityGate([string]$Name, [scriptblock]$Action) {
    Write-Host ("== {0} ==" -f $Name)
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $global:LASTEXITCODE = 0
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) { throw ("Quality gate failed: {0} (exit={1})" -f $Name, $LASTEXITCODE) }
    }
    finally {
        $stopwatch.Stop()
        Write-Host ("Gate {0} elapsed={1:N3}s" -f $Name, $stopwatch.Elapsed.TotalSeconds)
    }
}

function Assert-HostSchedulerOwnershipContract {
    $gatePath = [IO.Path]::GetFullPath($PSCommandPath)
    $approvedSchedulerPath = [IO.Path]::GetFullPath((Join-Path $root 'scripts\release\register-release-update-task.ps1'))
    if (-not (Test-Path -LiteralPath $approvedSchedulerPath -PathType Leaf)) { throw 'Approved release update scheduler entrypoint is missing.' }
    $approvedText = [IO.File]::ReadAllText($approvedSchedulerPath)
    foreach ($required in @("`$taskName = 'skills-manager-release-update'", '-LogonType Interactive -RunLevel Limited', "-Description 'Checks skills-manager GitHub Releases")) {
        if (-not $approvedText.Contains($required, [StringComparison]::Ordinal)) { throw "Approved release update scheduler contract is missing: $required" }
    }
    if ($approvedText -match '(?i)-RunLevel\s+Highest') { throw 'Approved release update scheduler must not request RunLevel Highest.' }
    $patterns = @(
        [regex]::new('\b(?:Register|Set|Unregister)-ScheduledTask\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase),
        [regex]::new('\bschtasks(?:\.exe)?\b[^\r\n]*(?:/Create|/Change|/Delete)\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    )
    $findings = [Collections.Generic.List[string]]::new()

    foreach ($scanRoot in @((Join-Path $root 'src'), (Join-Path $root 'scripts'))) {
        foreach ($file in @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Filter '*.ps1')) {
            if ([IO.Path]::GetFullPath($file.FullName) -eq $gatePath) { continue }
            if ([IO.Path]::GetFullPath($file.FullName) -eq $approvedSchedulerPath) { continue }
            $lines = [IO.File]::ReadAllLines($file.FullName)
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if (@($patterns | Where-Object { $_.IsMatch($lines[$index]) }).Count -gt 0) {
                    $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
                    $findings.Add(('{0}:{1}' -f $relative, ($index + 1))) | Out-Null
                }
            }
        }
    }

    if ($findings.Count -gt 0) {
        throw ('Host scheduler lifecycle belongs to host/operator; mutating production entrypoints found: {0}' -f ($findings -join ', '))
    }
}

Push-Location $root
try {
    if ($Profile -eq 'auto') {
        $resolverPath = Join-Path $root 'scripts\quality\resolve-gate-profile.ps1'
        $resolverArgs = @{ Mode = 'local'; Json = $true }
        if (-not [string]::IsNullOrWhiteSpace($DiffBase)) { $resolverArgs['BaseSha'] = $DiffBase }
        $resolved = (& $resolverPath @resolverArgs) | ConvertFrom-Json
        Write-Host ("Gate profile auto -> {0} (reason={1}, base={2})" -f $resolved.profile, $resolved.reason, $resolved.base_sha)
        if ($ResolveOnly) { return }
        $Profile = [string]$resolved.profile
        if ($Profile -eq 'focused') { $TestPath = @($resolved.focused_test_paths) }
        # The docs gate must check the current worktree; a resolver-derived base
        # would narrow `git diff --check` to the committed range only.
        if ($Profile -eq 'docs') { $DiffBase = '' }
    }

    if ($Profile -eq 'docs') {
        if ([string]::IsNullOrWhiteSpace($DiffBase)) {
            Invoke-QualityGate 'diff-check' { & git diff --check }
        }
        else {
            Invoke-QualityGate 'diff-check' { & git diff --check $DiffBase HEAD -- }
        }
        Write-Host 'Local quality gates passed (docs).'
        return
    }

    Invoke-QualityGate 'build' { & .\build.ps1 }
    if ($Profile -eq 'focused') {
        if ($TestPath.Count -eq 0 -and $TestName.Count -eq 0) { throw 'Focused profile requires -TestPath or -TestName.' }
        if ($TestPath.Count -gt 0 -and $TestName.Count -gt 0) {
            Invoke-QualityGate 'focused-tests' { & .\tests\run.ps1 -TestPath $TestPath -TestName $TestName }
        }
        elseif ($TestPath.Count -gt 0) {
            Invoke-QualityGate 'focused-tests' { & .\tests\run.ps1 -TestPath $TestPath }
        }
        else {
            Invoke-QualityGate 'focused-tests' { & .\tests\run.ps1 -TestName $TestName }
        }
    }
    elseif ($Profile -eq 'full') {
        Invoke-QualityGate 'tests' { & .\tests\run.ps1 }
    }
    if (-not $AllowDirtyWorktree) {
        Invoke-QualityGate 'generated-bundle-committed' { & git diff --quiet HEAD -- skills.ps1 }
    }
    $selectedVerifiers = if ($Verifier.Count -gt 0) {
        @($Verifier)
    }
    elseif ($Profile -eq 'focused') {
        @()
    }
    else {
        # 'mor' stays explicit-only via -Verifier: design-only MOR (MOR-000)
        # carries no automatic gate until implementation is admitted.
        @('lock', 'integrity', 'config', 'scheduler')
    }
    foreach ($verifier in $selectedVerifiers) {
        switch ($verifier) {
            'lock' { Invoke-QualityGate 'workspace-lock-parity' { & .\skills.ps1 verify-lock } }
            'integrity' { Invoke-QualityGate 'skill-integrity' { & .\scripts\verify-skill-integrity.ps1 } }
            'config' { Invoke-QualityGate 'skills-config-contract' { & .\scripts\verify-skills-config.ps1 -Mode enforce } }
            'scheduler' { Invoke-QualityGate 'host-scheduler-ownership' { Assert-HostSchedulerOwnershipContract } }
            'mor' { Invoke-QualityGate 'model-orchestration-contract' { & .\scripts\quality\validate-mor-tuple-matrix.ps1 } }
        }
    }
    Write-Host ("Local quality gates passed ({0})." -f $Profile)
}
finally {
    Pop-Location
}
