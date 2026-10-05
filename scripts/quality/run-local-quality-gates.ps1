[CmdletBinding()]
param(
    [ValidateSet('docs', 'quick', 'focused', 'full', 'auto')]
    [string]$Profile = 'auto',
    [switch]$CheckGenerated,
    [switch]$ResolveOnly,
    [string[]]$TestPath = @(),
    [string[]]$TestName = @(),
    [ValidateSet('lock', 'integrity', 'config', 'scheduler', 'mor')]
    [string[]]$Verifier = @(),
    [string]$DiffBase = '',
    # Explicit escape hatch for the shimmed-sandbox full block below.
    [switch]$AllowShimmedFull
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$autoProfile = $Profile -eq 'auto'
$docsSupplemented = $false
# Cost signal: total wall clock is printed on success so a caller can see the
# price of the chosen profile. On this host a sandboxed full run is dominated
# by shim overhead, not code cost; CI is the intended full runner.
$suiteStopwatch = [Diagnostics.Stopwatch]::StartNew()

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
        try {
            $global:LASTEXITCODE = 0
            $resolved = & $resolverPath @resolverArgs
            $resolverExit = $LASTEXITCODE
            if ($resolverExit -ne 0) { throw "exit=$resolverExit" }
            $resolved = $resolved | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
        }
        catch { throw "Gate profile resolver failed: $($_.Exception.Message)" }
        if ($resolved -isnot [pscustomobject] -or
            $resolved.profile -isnot [string] -or $resolved.profile -notin @('docs', 'focused', 'full') -or
            $resolved.reason -isnot [string] -or [string]::IsNullOrWhiteSpace($resolved.reason) -or
            $resolved.docs_only -isnot [bool] -or $resolved.requires_locked_sources -isnot [bool] -or
            $resolved.focused_test_paths -isnot [array]) {
            throw 'Gate profile resolver returned an invalid result.'
        }
        foreach ($focusedPath in $resolved.focused_test_paths) {
            if ($focusedPath -isnot [string] -or [string]::IsNullOrWhiteSpace($focusedPath)) {
                throw 'Gate profile resolver returned an invalid focused test path.'
            }
        }
        if ($resolved.profile -eq 'focused' -and $resolved.focused_test_paths.Count -eq 0) {
            throw 'Gate profile resolver returned focused without test paths.'
        }
        Write-Host ("Gate profile auto -> {0} (reason={1}, base={2})" -f $resolved.profile, $resolved.reason, $resolved.base_sha)
        if ($ResolveOnly) { return }
        $Profile = [string]$resolved.profile
        if ($Profile -eq 'focused') { $TestPath = @(@($resolved.focused_test_paths) + $TestPath | Sort-Object -Unique) }
    }

    if ($Profile -eq 'full' -and -not $env:CI) {
        # Fingerprint-based block, per docs/runbooks/agent-sandbox-instrumentation.md:
        # the hour-scale full inflation (19303s recorded) was measured on hosts whose
        # sandbox sets these env markers or wraps Remove-Item as a Function. ZCode
        # sessions measured clean (Cmdlet, 0.01s/30-file delete), so absence of
        # markers genuinely means no known shim here, not a detection gap.
        $shimInstrumented = [bool]($env:CODEBUDDY_SAFE_DELETE_ENABLED -or $env:CODEBUDDY_SAFE_DELETE_SANDBOX `
                -or -not [string]::IsNullOrWhiteSpace($env:SANDBOX_CENTER_IPC_ADDRESS) `
                -or (([string]$env:NODE_OPTIONS) -match 'shim') `
                -or (([string]$env:PYTHONPATH) -match 'shim') `
                -or ((Get-Command Remove-Item).CommandType -eq 'Function'))
        if ($shimInstrumented -and -not $AllowShimmedFull) {
            throw "Profile full is blocked inside an instrumented sandbox (safe-delete shim fingerprints detected): the suite can inflate from ~3-5 minutes to hours of environment cost. Run docs/focused with -TestPath here and let CI run full, or pass -AllowShimmedFull to accept the cost explicitly."
        }
        Write-Host 'Cost note: -Profile full runs the entire suite. On a plain terminal or CI this is about 3-5 minutes (sharded, ~1267 cases); on a shim-instrumented sandbox host (see docs/runbooks/agent-sandbox-instrumentation.md) it can inflate to hours, which is environment cost, not code cost. Prefer docs/focused in such hosts and let CI run full.'
    }

    if ($Profile -eq 'docs') {
        if ($autoProfile -or [string]::IsNullOrWhiteSpace($DiffBase)) {
            Invoke-QualityGate 'diff-check' {
                $checkBase = if ([string]::IsNullOrWhiteSpace($DiffBase)) { 'HEAD' } else { $DiffBase }
                & git diff --check $checkBase --
                if ($LASTEXITCODE -ne 0) { throw 'Tracked whitespace check failed.' }
                $untrackedDocs = @(& git ls-files --others --exclude-standard)
                if ($LASTEXITCODE -ne 0) { throw 'Untracked file enumeration failed.' }
                foreach ($path in $untrackedDocs) {
                    & git diff --no-index --check -- /dev/null $path
                    # --no-index 用 1 表示“与 /dev/null 存在差异”（任何新文件皆是），
                    # 3 才是空白问题、128 是 git 错误：只有 >1 属于检查失败。
                    if ($LASTEXITCODE -gt 1) { throw "Untracked whitespace check failed: $path" }
                }
                # 干净新文件遗留的退出码 1 属于正常信号，不能泄漏给
                # Invoke-QualityGate 的整段 $LASTEXITCODE 检查。
                $global:LASTEXITCODE = 0
            }
        }
        else {
            Invoke-QualityGate 'diff-check' { & git diff --check $DiffBase HEAD -- }
        }
        if ($TestPath.Count -eq 0 -and $TestName.Count -eq 0 -and $Verifier.Count -eq 0) {
            Write-Host ("Local quality gates passed (docs). elapsed={0:n1}s" -f $suiteStopwatch.Elapsed.TotalSeconds)
            return
        }
        # Explicit proof supplements the classification, including an empty diff.
        $Profile = if ($TestPath.Count -gt 0 -or $TestName.Count -gt 0) { 'focused' } else { 'quick' }
        # docs 分支带显式补充验证时意图是“验证”：build 关必须只读核对提交的
        # 生成物，不允许静默重写漂移的 skills.ps1 掩盖本地漂移。
        $docsSupplemented = $true
    }

    if ($Profile -eq 'focused' -and $TestPath.Count -eq 0 -and $TestName.Count -eq 0) {
        throw 'Focused profile requires -TestPath or -TestName.'
    }
    # Local builds regenerate the bundle; CI checks the submitted bytes before tests.
    # The independent preset suite uses disposable host roots and never consumes
    # the main CLI bundle. Mixed selections and full still validate that bundle.
    $modelPresetOnly = $Profile -eq 'focused' -and $Verifier.Count -eq 0 -and $TestPath.Count -eq 1 -and
        $TestPath[0].Replace('\', '/') -eq 'tests/Unit/ModelPreset.Tests.ps1'
    if (-not $modelPresetOnly) {
        Invoke-QualityGate 'build' { & .\build.ps1 -Check:($CheckGenerated -or $docsSupplemented) }
    }
    if ($Profile -eq 'focused') {
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
    $selectedVerifiers = if ($Verifier.Count -gt 0) {
        @($Verifier)
    }
    elseif ($Profile -eq 'focused') {
        @()
    }
    elseif ($Profile -eq 'full') {
        @('lock', 'integrity', 'config', 'scheduler')
    }
    else {
        # 'mor' validates the optional design tuple matrix. Implemented preset
        # behavior is covered by ModelPreset.Tests.ps1 in focused/full tests.
        @('lock', 'integrity', 'config', 'scheduler')
    }
    foreach ($verifier in $selectedVerifiers) {
        switch ($verifier) {
            'lock' { Invoke-QualityGate 'workspace-lock-parity' { & .\skills.ps1 verify-lock } }
            'integrity' { Invoke-QualityGate 'skill-integrity' { & .\scripts\verify-skill-integrity.ps1 } }
            'config' { Invoke-QualityGate 'skills-config-contract' { & .\scripts\verify-skills-config.ps1 -Mode enforce } }
            'scheduler' { Invoke-QualityGate 'host-scheduler-ownership' { Assert-HostSchedulerOwnershipContract } }
            'mor' {
                Invoke-QualityGate 'model-orchestration-contract' {
                    & .\scripts\quality\validate-mor-tuple-matrix.ps1
                    & .\src\model-orchestration\Test-ModelPreset.ps1
                }
            }
        }
    }
    Write-Host ("Local quality gates passed ({0}). elapsed={1:n1}s" -f $Profile, $suiteStopwatch.Elapsed.TotalSeconds)
}
finally {
    Pop-Location
}
