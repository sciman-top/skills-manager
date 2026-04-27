function Get-PerfSummaryFromLogLines([string[]]$lines, [int]$RecentPerMetric = 3) {
    $events = New-Object System.Collections.Generic.List[object]
    if ($null -eq $lines) { return @() }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json
        }
        catch { continue }
        if ($null -eq $record -or $null -eq $record.data) { continue }
        if (-not $record.data.PSObject.Properties.Match("metric").Count) { continue }
        if (-not $record.data.PSObject.Properties.Match("duration_ms").Count) { continue }
        $metric = [string]$record.data.metric
        if ([string]::IsNullOrWhiteSpace($metric)) { continue }
        $duration = 0
        try { $duration = [int]$record.data.duration_ms } catch { continue }
        if ($duration -lt 0) { continue }
        $events.Add([pscustomobject]@{
            metric = $metric
            duration_ms = $duration
            ts = [string]$record.ts
        }) | Out-Null
    }
    if ($events.Count -eq 0) { return @() }

    $summary = New-Object System.Collections.Generic.List[object]
    $groups = $events | Group-Object metric
    foreach ($g in $groups) {
        $recent = $g.Group | Select-Object -Last $RecentPerMetric
        if ($recent.Count -eq 0) { continue }
        $avg = [math]::Round((($recent | Measure-Object -Property duration_ms -Average).Average), 0)
        $last = ($recent | Select-Object -Last 1)
        $summary.Add([pscustomobject]@{
            metric = $g.Name
            samples = @($recent).Count
            avg_ms = [int]$avg
            last_ms = [int]$last.duration_ms
            last_ts = [string]$last.ts
        }) | Out-Null
    }
    return ($summary | Sort-Object metric)
}

function Get-DoctorGitVersion([switch]$NoHostLog) {
    if ($DryRun -or $NoHostLog) {
        $gitOut = & git version 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $gitOut) { throw "git version failed" }
        return (($gitOut | Select-Object -First 1).ToString().Trim())
    }
    return (Invoke-GitCapture @("version"))
}

function Get-DoctorOsDescription {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os -and -not [string]::IsNullOrWhiteSpace([string]$os.Caption)) {
            return ("{0} {1}" -f [string]$os.Caption, [string]$os.OSArchitecture).Trim()
        }
    }
    catch {}

    try {
        $description = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        if (-not [string]::IsNullOrWhiteSpace([string]$description)) {
            return ("{0} {1}" -f [string]$description, [string]$architecture).Trim()
        }
    }
    catch {}

    return $null
}

function Parse-DoctorArgs([string[]]$tokens) {
    $opts = [ordered]@{
        json = $false
        fix = $false
        dry_run_fix = $false
        strict = $false
        strict_perf = $false
        threshold_ms = 5000
    }
    if ($null -eq $tokens) { return [pscustomobject]$opts }

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = [string]$tokens[$i]
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $k = $t.Trim().ToLowerInvariant()
        switch ($k) {
            "--json" { $opts.json = $true; continue }
            "-j" { $opts.json = $true; continue }
            "--fix" { $opts.fix = $true; continue }
            "--dry-run-fix" { $opts.dry_run_fix = $true; continue }
            "--strict" { $opts.strict = $true; continue }
            "--strict-perf" { $opts.strict_perf = $true; continue }
            "--threshold-ms" {
                Need ($i + 1 -lt $tokens.Count) "参数缺少值：--threshold-ms"
                $raw = [string]$tokens[++$i]
                $n = 0
                Need ([int]::TryParse($raw, [ref]$n)) ("--threshold-ms 必须是整数：{0}" -f $raw)
                Need ($n -gt 0) "--threshold-ms 必须大于 0"
                $opts.threshold_ms = $n
                continue
            }
            default { throw ("未知 doctor 参数：{0}" -f $t) }
        }
    }
    return [pscustomobject]$opts
}

function Apply-DoctorFixes($cfg, [switch]$Preview) {
    $result = [ordered]@{
        changed = $false
        applied = @()
    }
    if ($null -eq $cfg) { return [pscustomobject]$result }

    # low-risk fix #1: dedupe duplicate targets.path (keep first)
    if ($cfg.PSObject.Properties.Match("targets").Count -gt 0 -and $cfg.targets -ne $null) {
        $seenTarget = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $newTargets = @()
        foreach ($t in @($cfg.targets)) {
            if ($null -eq $t) { continue }
            $path = if ($t.PSObject.Properties.Match("path").Count -gt 0) { [string]$t.path } else { "" }
            if ([string]::IsNullOrWhiteSpace($path)) {
                $newTargets += $t
                continue
            }
            $norm = $path.Trim()
            if ($seenTarget.Add($norm)) {
                $newTargets += $t
            }
            else {
                $result.applied += ("删除重复 targets.path：{0}" -f $norm)
                $result.changed = $true
            }
        }
        if ($result.changed -and -not $Preview) { $cfg.targets = @($newTargets) }
    }

    # low-risk fix #2: remove mappings referencing missing vendor
    if ($cfg.PSObject.Properties.Match("mappings").Count -gt 0 -and $cfg.mappings -ne $null) {
        $vendors = if ($cfg.PSObject.Properties.Match("vendors").Count -gt 0 -and $cfg.vendors -ne $null) { @($cfg.vendors) } else { @() }
        $vendorSet = New-CfgVendorNameSet $vendors

        $newMappings = @()
        foreach ($m in @($cfg.mappings)) {
            if ($null -eq $m) { continue }
            $vendor = if ($m.PSObject.Properties.Match("vendor").Count -gt 0) { [string]$m.vendor } else { "" }
            if ([string]::IsNullOrWhiteSpace($vendor) -or $vendorSet.Contains($vendor)) {
                $newMappings += $m
                continue
            }
            $from = if ($m.PSObject.Properties.Match("from").Count -gt 0) { [string]$m.from } else { "" }
            $to = if ($m.PSObject.Properties.Match("to").Count -gt 0) { [string]$m.to } else { "" }
            $result.applied += ("删除无效 mapping：vendor={0}, from={1}, to={2}" -f $vendor, $from, $to)
            $result.changed = $true
        }
        if ($result.changed -and -not $Preview) { $cfg.mappings = @($newMappings) }
    }

    $result.applied = @($result.applied)
    return [pscustomobject]$result
}

function Get-PerfThresholdMs([string]$Metric, [int]$DefaultThresholdMs = 5000) {
    if ([string]::IsNullOrWhiteSpace($Metric)) { return $DefaultThresholdMs }

    $metricKey = $Metric.Trim().ToLowerInvariant()
    switch ($metricKey) {
        "discover" { return 5000 }
        "build_agent" { return 8000 }
        "apply_targets" { return 5000 }
        # Includes prebuild checks + full build/apply flow; realistic baseline in this repo is ~180s.
        "build_apply_total" { return 240000 }
        "sync_mcp" { return 10000 }
        # Update flow is network-heavy but should still surface regressions in doctor warnings.
        "update_vendor" { return 60000 }
        "update_imports" { return 180000 }
        "update_total" { return 240000 }
        # One-click workflows may include target-repo audit scans; keep this stricter than update_total but above normal audit smoke time.
        "workflow_run" { return 30000 }
        default { return $DefaultThresholdMs }
    }
}

function Add-PerfThresholdMetadata($summary, [int]$DefaultThresholdMs = 5000) {
    $annotated = @()
    if ($null -eq $summary) { return @() }

    foreach ($p in @($summary)) {
        if ($null -eq $p) { continue }
        $metricName = ""
        try { $metricName = [string]$p.metric } catch { $metricName = "" }
        $metricThreshold = Get-PerfThresholdMs $metricName $DefaultThresholdMs

        $item = [ordered]@{}
        foreach ($prop in $p.PSObject.Properties) {
            $item[$prop.Name] = $prop.Value
        }
        $item.effective_threshold_ms = $metricThreshold
        $item.anomaly_check_enabled = ($null -ne $metricThreshold)
        $annotated += [pscustomobject]$item
    }

    return @($annotated)
}

function Get-PerfAnomalyItems($summary, [int]$WarnThresholdMs = 5000, [int]$MinSamples = 3) {
    $items = @()
    if ($null -eq $summary) { return @() }
    foreach ($p in $summary) {
        if ($null -eq $p) { continue }
        $last = 0
        $avg = 0
        $samples = 0
        try { $last = [int]$p.last_ms } catch { continue }
        try { $avg = [int]$p.avg_ms } catch { continue }
        try { $samples = [int]$p.samples } catch { $samples = 0 }
        if ($samples -lt $MinSamples) { continue }
        $metricThreshold = Get-PerfThresholdMs ([string]$p.metric) $WarnThresholdMs
        if ($null -eq $metricThreshold) { continue }
        if ($last -gt $metricThreshold -or $avg -gt $metricThreshold) {
            $items += ("{0}: last={1}ms avg={2}ms threshold={3}ms" -f [string]$p.metric, $last, $avg, $metricThreshold)
        }
    }
    return ,@($items)
}

function Get-DoctorConfigRisks($cfg) {
    $risks = @()
    if ($null -eq $cfg) { return @() }

    $targetPaths = @()
    if ($cfg.PSObject.Properties.Match("targets").Count -gt 0 -and $cfg.targets -ne $null) {
        foreach ($t in $cfg.targets) {
            if ($null -eq $t) { continue }
            $path = if ($t.PSObject.Properties.Match("path").Count -gt 0) { [string]$t.path } else { "" }
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            $targetPaths += $path.Trim()
        }
    }
    $dupTargets = @($targetPaths | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupTargets.Count -gt 0) {
        $risks += ("检测到重复 targets.path：{0}" -f ($dupTargets -join ", "))
    }

    $mappingTo = @()
    if ($cfg.PSObject.Properties.Match("mappings").Count -gt 0 -and $cfg.mappings -ne $null) {
        foreach ($m in $cfg.mappings) {
            if ($null -eq $m) { continue }
            $to = if ($m.PSObject.Properties.Match("to").Count -gt 0) { [string]$m.to } else { "" }
            if ([string]::IsNullOrWhiteSpace($to)) { continue }
            $mappingTo += $to.Trim()
        }
    }
    $dupTo = @($mappingTo | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupTo.Count -gt 0) {
        $risks += ("检测到重复 mappings.to（可能互相覆盖）：{0}" -f ($dupTo -join ", "))
    }

    $vendors = if ($cfg.PSObject.Properties.Match("vendors").Count -gt 0 -and $cfg.vendors -ne $null) { @($cfg.vendors) } else { @() }
    $vendorSet = New-CfgVendorNameSet $vendors
    if ($cfg.PSObject.Properties.Match("mappings").Count -gt 0 -and $cfg.mappings -ne $null) {
        foreach ($m in $cfg.mappings) {
            if ($null -eq $m) { continue }
            $vendor = if ($m.PSObject.Properties.Match("vendor").Count -gt 0) { [string]$m.vendor } else { "" }
            if ([string]::IsNullOrWhiteSpace($vendor)) { continue }
            if (-not $vendorSet.Contains($vendor)) {
                $from = if ($m.PSObject.Properties.Match("from").Count -gt 0) { [string]$m.from } else { "" }
                $to = if ($m.PSObject.Properties.Match("to").Count -gt 0) { [string]$m.to } else { "" }
                $risks += ("mapping 引用了不存在的 vendor：{0} (from={1}, to={2})" -f $vendor, $from, $to)
            }
        }
    }

    return @($risks)
}

function Invoke-Doctor([string[]]$tokens = @()) {
    $opts = Parse-DoctorArgs $tokens
    if (-not $opts.json) {
        Write-Host "=== Skills Manager Doctor ===" -ForegroundColor Cyan
    }
    $pass = $true
    $cfgObj = $null
    $report = [ordered]@{
        pass = $true
        strict = [bool]$opts.strict
        strict_perf = [bool]$opts.strict_perf
        checks = [ordered]@{}
        risks = @()
        performance = [ordered]@{
            threshold_ms = [int]$opts.threshold_ms
            summary = @()
            anomalies = @()
        }
        summary = [ordered]@{
            errors = @()
            warnings = @()
            error_count = 0
            warn_count = 0
        }
        fix = [ordered]@{
            requested = [bool]$opts.fix
            changed = $false
            applied = @()
        }
    }

    # 1. System Checks
    try {
        $osText = Get-DoctorOsDescription
        if ([string]::IsNullOrWhiteSpace([string]$osText)) { throw "OS detection returned empty" }
        $report.checks.os = $osText
        if (-not $opts.json) { Write-Host ("OS: {0}" -f $osText) }
    }
    catch {
        $report.checks.os = "unknown"
        if (-not $opts.json) { Write-Host "OS: unknown（读取失败）" -ForegroundColor Yellow }
    }

    # 2. Git Check
    try {
        $gitVer = Get-DoctorGitVersion -NoHostLog:$opts.json
        if ([string]::IsNullOrWhiteSpace($gitVer)) { throw "git version is empty" }
        $report.checks.git = [ordered]@{ ok = $true; value = $gitVer }
        if (-not $opts.json) { Write-Host "✅ Git: $gitVer" -ForegroundColor Green }
    }
    catch {
        $report.checks.git = [ordered]@{ ok = $false; value = "" }
        if (-not $opts.json) { Write-Host "❌ Git: Not found or error" -ForegroundColor Red }
        $pass = $false
    }

    # 3. Robocopy Check
    if (Get-Command robocopy -ErrorAction SilentlyContinue) {
        $report.checks.robocopy = [ordered]@{ ok = $true }
        if (-not $opts.json) { Write-Host "✅ Robocopy: Available" -ForegroundColor Green }
    }
    else {
        $report.checks.robocopy = [ordered]@{ ok = $false }
        if (-not $opts.json) { Write-Host "❌ Robocopy: Not found" -ForegroundColor Red }
        $pass = $false
    }

    # 4. Long Paths
    try {
        $lp = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
        if ($lp -and $lp.LongPathsEnabled -eq 1) {
            $report.checks.long_paths = [ordered]@{ ok = $true; value = 1 }
            if (-not $opts.json) { Write-Host "✅ LongPathsEnabled: 1 (On)" -ForegroundColor Green }
        }
        else {
            $report.checks.long_paths = [ordered]@{ ok = $false; value = 0 }
            if (-not $opts.json) { Write-Host "⚠️ LongPathsEnabled: 0 (Off) - Deep paths may fail." -ForegroundColor Yellow }
        }
    }
    catch {
        $report.checks.long_paths = [ordered]@{ ok = $false; value = "unknown" }
        if (-not $opts.json) { Write-Host "⚠️ LongPathsEnabled: Check failed" -ForegroundColor Yellow }
    }

    # 5. Config Check
    if (Test-Path $CfgPath) {
        try {
            # Keep parser behavior aligned with LoadCfg:
            # support whole-line comments in skills.json.
            $rawCfg = Get-Content $CfgPath -Raw
            $cleanCfg = $rawCfg -replace "(?m)^\s*//.*", ""
            $cfg = $cleanCfg | ConvertFrom-Json
            if ($cfg) {
                $contractErrors = @(Get-CfgContractErrors $cfg)
                if ($contractErrors.Count -gt 0) {
                    $report.checks.config = [ordered]@{
                        ok = $false
                        reason = ("contract_error: {0}" -f ($contractErrors -join " | "))
                        errors = @($contractErrors)
                    }
                    if (-not $opts.json) {
                        Write-Host "❌ skills.json: Contract Error" -ForegroundColor Red
                        foreach ($err in $contractErrors) {
                            Write-Host ("   - {0}" -f $err) -ForegroundColor Red
                        }
                    }
                    $pass = $false
                }
                else {
                    $cfgObj = $cfg
                    $report.checks.config = [ordered]@{ ok = $true; vendors = @($cfg.vendors).Count; mappings = @($cfg.mappings).Count }
                    if (-not $opts.json) {
                        Write-Host "✅ skills.json: Valid JSON + contract" -ForegroundColor Green
                        Write-Host ("   - Vendors: {0}" -f @($cfg.vendors).Count)
                        Write-Host ("   - Mappings: {0}" -f @($cfg.mappings).Count)
                    }
                }
            }
            else {
                $report.checks.config = [ordered]@{ ok = $false; reason = "invalid_or_empty" }
                if (-not $opts.json) { Write-Host "❌ skills.json: Invalid/Empty" -ForegroundColor Red }
                $pass = $false
            }
        }
        catch {
            $report.checks.config = [ordered]@{ ok = $false; reason = ("parse_error: {0}" -f $_.Exception.Message) }
            if (-not $opts.json) { Write-Host ("❌ skills.json: Parse Error - {0}" -f $_.Exception.Message) -ForegroundColor Red }
            $pass = $false
        }
    }
    else {
        $report.checks.config = [ordered]@{ ok = $false; reason = "not_found" }
        if (-not $opts.json) { Write-Host "⚠️ skills.json: Not found (Run init or add first)" -ForegroundColor Yellow }
    }

    # 6. Config Risk Scan
    try {
        if ($null -ne $cfgObj) {
            $risks = Get-DoctorConfigRisks $cfgObj
            $report.risks = @($risks)
            if ($risks.Count -gt 0) {
                if (-not $opts.json) {
                    Write-Host ("⚠️ 配置风险（{0} 项）：" -f $risks.Count) -ForegroundColor Yellow
                    foreach ($risk in $risks) {
                        Write-Host ("   - {0}" -f $risk) -ForegroundColor Yellow
                    }
                }
            }
        }
    }
    catch {
        if (-not $opts.json) { Write-Host "⚠️ 配置风险扫描失败（已忽略）" -ForegroundColor Yellow }
    }

    # 6.5 Optional auto-fix for low-risk config issues
    if (($opts.fix -or $opts.dry_run_fix) -and $null -ne $cfgObj) {
        try {
            $fixResult = Apply-DoctorFixes $cfgObj -Preview:$opts.dry_run_fix
            $report.fix.changed = [bool]$fixResult.changed
            $report.fix.applied = @($fixResult.applied)
            $report.fix.preview = [bool]$opts.dry_run_fix
            if ($fixResult.changed) {
                if (-not $DryRun -and -not $opts.dry_run_fix) {
                    $json = $cfgObj | ConvertTo-Json -Depth 50
                    Set-ContentUtf8 $CfgPath $json
                }
                if (-not $opts.json) {
                    if ($opts.dry_run_fix) {
                        Write-Host ("doctor --dry-run-fix 预览 {0} 项可修复内容。" -f @($fixResult.applied).Count) -ForegroundColor Yellow
                    }
                    else {
                        Write-Host ("✅ doctor --fix 已应用 {0} 项修复。" -f @($fixResult.applied).Count) -ForegroundColor Green
                    }
                    foreach ($line in @($fixResult.applied)) {
                        if ($opts.dry_run_fix) {
                            Write-Host ("   - {0}" -f $line) -ForegroundColor Yellow
                        }
                        else {
                            Write-Host ("   - {0}" -f $line) -ForegroundColor Green
                        }
                    }
                }
            }
            elseif (-not $opts.json) {
                if ($opts.dry_run_fix) { Write-Host "doctor --dry-run-fix：未发现可自动修复项。" }
                else { Write-Host "doctor --fix：未发现可自动修复项。" }
            }
        }
        catch {
            if (-not $opts.json) { Write-Host ("⚠️ doctor --fix 执行失败：{0}" -f $_.Exception.Message) -ForegroundColor Yellow }
        }
    }

    # 7. Network Check (Optional)
    try {
        $ping = Test-NetConnection "github.com" -Port 443 -InformationLevel Quiet
        if ($ping) {
            $report.checks.network = [ordered]@{ ok = $true }
            if (-not $opts.json) { Write-Host "✅ GitHub Connection: OK" -ForegroundColor Green }
        }
        else {
            $report.checks.network = [ordered]@{ ok = $false }
            if (-not $opts.json) { Write-Host "❌ GitHub Connection: Failed" -ForegroundColor Red }
            $pass = $false
        }
    }
    catch {
        $report.checks.network = [ordered]@{ ok = $false; skipped = $true }
        if (-not $opts.json) { Write-Host "⚠️ Network Check: Skipped" -ForegroundColor Yellow }
    }

    # 8. Performance Summary
    try {
        if (Test-Path $LogPath) {
            $lines = Get-Content $LogPath -Tail 5000 -ErrorAction SilentlyContinue
            $perf = Get-PerfSummaryFromLogLines $lines 3
            $report.performance.summary = @(Add-PerfThresholdMetadata $perf $opts.threshold_ms)
            if ($perf.Count -gt 0) {
                if (-not $opts.json) {
                    Write-Host "最近性能摘要（最近 3 次）："
                    foreach ($p in $report.performance.summary) {
                        Write-Host ("   - {0}: last={1}ms avg={2}ms samples={3}" -f $p.metric, $p.last_ms, $p.avg_ms, $p.samples)
                    }
                }
                $anomalies = Get-PerfAnomalyItems $report.performance.summary $opts.threshold_ms
                $report.performance.anomalies = @($anomalies)
                if ($anomalies.Count -gt 0) {
                    if (-not $opts.json) {
                        Write-Host ("⚠️ 性能异常（阈值 {0}ms，{1} 项）：" -f $opts.threshold_ms, $anomalies.Count) -ForegroundColor Yellow
                        foreach ($a in $anomalies) {
                            Write-Host ("   - {0}" -f $a) -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    }
    catch {
        if (-not $opts.json) { Write-Host "⚠️ 性能摘要读取失败（已忽略）" -ForegroundColor Yellow }
    }

    $report.pass = $pass
    if (-not $report.checks.git.ok) { $report.summary.errors += "git_unavailable" }
    if (-not $report.checks.robocopy.ok) { $report.summary.errors += "robocopy_unavailable" }
    if (-not $report.checks.config.ok) {
        $reason = if ($report.checks.config.reason) { [string]$report.checks.config.reason } else { "config_invalid" }
        if ($reason -like "parse_error*") { $report.summary.errors += "config_parse_error" }
        elseif ($reason -like "contract_error*") { $report.summary.errors += "config_contract_error" }
        else { $report.summary.warnings += "config_not_ready" }
    }
    if ($report.checks.long_paths.value -eq 0) { $report.summary.warnings += "long_paths_off" }
    if (@($report.risks).Count -gt 0) { $report.summary.warnings += "config_risks_present" }
    if (@($report.performance.anomalies).Count -gt 0) { $report.summary.warnings += "perf_anomalies_present" }

    if ($opts.strict -and (@($report.risks).Count -gt 0 -or ([bool]$opts.strict_perf -and @($report.performance.anomalies).Count -gt 0))) {
        $report.pass = $false
    }
    $report.summary.error_count = @($report.summary.errors).Count
    $report.summary.warn_count = @($report.summary.warnings).Count
    if ($opts.json) {
        Write-Host ($report | ConvertTo-Json -Depth 30)
        return [pscustomobject]$report
    }
    if ($opts.strict -and -not $opts.strict_perf -and @($report.performance.anomalies).Count -gt 0) {
        Write-Host "提示：性能异常仅告警，不影响 --strict 结果。使用 --strict-perf 可将其纳入阻断。" -ForegroundColor Yellow
    }

    Write-Host ""
    if ($report.pass) {
        Write-Host "Your system is ready for skills-manager." -ForegroundColor Green
    }
    else {
        Write-Host "Some checks failed. Please review issues above." -ForegroundColor Red
    }
    return [pscustomobject]$report
}
