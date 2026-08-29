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
        offline_contract = $false
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
            "--offline-contract" { $opts.offline_contract = $true; continue }
            default { throw ("未知 doctor 参数：{0}" -f $t) }
        }
    }
    if ($opts.offline_contract) {
        Need $opts.json "--offline-contract 仅用于 doctor --json 结构契约"
        Need (-not $opts.strict) "--offline-contract 不能与 --strict 组合"
        Need (-not $opts.fix -and -not $opts.dry_run_fix) "--offline-contract 不能与配置修复参数组合"
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

function Test-DoctorGitHubConnection {
    try {
        $tcpOk = Test-NetConnection "github.com" -Port 443 -InformationLevel Quiet
        if ($tcpOk) {
            return [pscustomobject]@{ ok = $true; method = "tcp"; detail = "" }
        }
    }
    catch {}

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        try {
            $ghOutput = @(& gh api user --jq .login 2>$null)
            if ($LASTEXITCODE -eq 0 -and $ghOutput.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ghOutput[0])) {
                return [pscustomobject]@{ ok = $true; method = "gh_api"; detail = [string]$ghOutput[0] }
            }
        }
        catch {}
    }

    try {
        $probe = Invoke-GitCapture @("ls-remote", "--exit-code", "https://github.com/github/gitignore.git", "HEAD")
        if (-not [string]::IsNullOrWhiteSpace([string]$probe)) {
            return [pscustomobject]@{ ok = $true; method = "git_ls_remote"; detail = "" }
        }
    }
    catch {}

    return [pscustomobject]@{ ok = $false; method = "none"; detail = "github.com tcp, gh api, and git ls-remote probes failed" }
}

function Test-McpLoopbackHost([string]$HostName) {
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    if ([string]::Equals($HostName, 'localhost', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $address = $null
    if (-not [Net.IPAddress]::TryParse($HostName, [ref]$address)) { return $false }
    return [Net.IPAddress]::IsLoopback($address)
}

function Get-McpTransportDiagnostics($cfg) {
    $diagnostics = [Collections.Generic.List[object]]::new()
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match('mcp_servers').Count -eq 0) { return @() }
    foreach ($server in @($cfg.mcp_servers)) {
        if ($null -eq $server -or -not [string]::Equals([string]$server.transport, 'http', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $name = ([string]$server.name).Trim()
        $url = ([string]$server.url).Trim()
        $parsed = $null
        $valid = [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsed) -and $parsed.Scheme -in @([Uri]::UriSchemeHttp, [Uri]::UriSchemeHttps)
        $loopback = $valid -and (Test-McpLoopbackHost $parsed.Host)
        $security = if (-not $valid) { 'invalid_url' } elseif ($parsed.Scheme -eq [Uri]::UriSchemeHttps) { 'encrypted' } elseif ($loopback) { 'loopback_plaintext' } else { 'remote_plaintext' }
        $authConfigured = $server.PSObject.Properties.Match('bearer_token_env_var').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.bearer_token_env_var)
        if (-not $authConfigured -and $server.PSObject.Properties.Match('headers').Count -gt 0 -and $null -ne $server.headers) {
            $authConfigured = @($server.headers.PSObject.Properties | Where-Object { $_.Name -match '^(?i:authorization|proxy-authorization)$' }).Count -gt 0
        }
        $diagnostics.Add([pscustomobject][ordered]@{
                name = $name
                configured_transport = 'http'
                protocol = 'streamable_http'
                url = $url
                security = $security
                loopback = $loopback
                auth_configured = $authConfigured
                warning_code = if ($security -eq 'remote_plaintext') { 'remote_plaintext_http' } else { '' }
            }) | Out-Null
    }
    return @($diagnostics.ToArray())
}

function Get-DoctorSkillProjectionConsistency {
    # Configuration/profile declaration drift silently changes what the host
    # actually projects; surface it before audit reasoning inherits it.
    $result = [ordered]@{ ok = $true; warnings = @(); detail = "" }
    try {
        $cfg = LoadCfg
        $projection = if ($cfg.PSObject.Properties.Match('skill_projection').Count -gt 0) { $cfg.skill_projection } else { $null }
        if ($null -eq $projection) {
            $result.detail = "skill_projection not configured"
            return $result
        }
        try {
            $selection = Resolve-SkillProjectionSelection -ProjectionConfig $projection -HostName 'codex'
        }
        catch {
            $result.ok = $false
            $result.warnings += ("projection_selection_invalid: {0}" -f $_.Exception.Message)
            return $result
        }
        if ([bool]$selection.uses_profiles) {
            $legacyIncludes = @()
            if (Test-OperationObjectProperty $projection 'managed_link_includes') {
                $legacyIncludes = @((Get-OperationObjectProperty $projection 'managed_link_includes') | ForEach-Object { [string]$_ })
            }
            $profileIncludes = @($selection.included_names | ForEach-Object { [string]$_ })
            $profileOnly = @($profileIncludes | Where-Object { $legacyIncludes -notcontains $_ } | Sort-Object)
            $legacyOnly = @($legacyIncludes | Where-Object { $profileIncludes -notcontains $_ } | Sort-Object)
            if ($profileOnly.Count -gt 0 -or $legacyOnly.Count -gt 0) {
                $result.warnings += ("managed_link_includes 与 profiles.{0}.include 漂移：profiles 独有=[{1}] legacy 独有=[{2}]（profiles 优先生效，建议同步 legacy 字段）" -f [string]$selection.profile, ($profileOnly -join ','), ($legacyOnly -join ','))
            }
        }
        $userRoot = Resolve-SkillProjectionPath ([string]$projection.user_skill_root) $Root
        $expectedNames = @()
        if ([bool]$selection.include_all) {
            $managedSource = Resolve-SkillProjectionPath ([string]$projection.managed_source_path) $Root
            if (Test-Path -LiteralPath $managedSource -PathType Container) {
                $expectedNames = @(Get-ChildItem -LiteralPath $managedSource -Directory -Force | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } | ForEach-Object { [string]$_.Name })
            }
        }
        else {
            $expectedNames = @($selection.included_names | Where-Object { @($selection.excluded_names) -notcontains $_ } | ForEach-Object { [string]$_ })
        }
        $actualNames = @()
        if (Test-Path -LiteralPath $userRoot -PathType Container) {
            $actualNames = @(Get-ChildItem -LiteralPath $userRoot -Directory -Force | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } | ForEach-Object { [string]$_.Name })
        }
        else {
            $result.warnings += ("user_skill_root 缺失: {0}" -f $userRoot)
        }
        $missing = @($expectedNames | Where-Object { $actualNames -notcontains $_ } | Sort-Object)
        $extra = @($actualNames | Where-Object { $expectedNames -notcontains $_ } | Sort-Object)
        if ($missing.Count -gt 0) { $result.warnings += ("声明未投影: [{0}]" -f ($missing -join ',')) }
        if ($extra.Count -gt 0) { $result.warnings += ("投影未声明: [{0}]" -f ($extra -join ',')) }
        $result.detail = ("profile={0} declared={1} projected={2}" -f [string]$selection.profile, @($expectedNames).Count, @($actualNames).Count)
        if ($result.warnings.Count -gt 0) { $result.ok = $false }
    }
    catch {
        $result.ok = $false
        $result.warnings += ("skill_projection_check_failed: {0}" -f $_.Exception.Message)
    }
    return $result
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

    foreach ($diagnostic in @(Get-McpTransportDiagnostics $cfg)) {
        if ([string]$diagnostic.warning_code -eq 'remote_plaintext_http') {
            $risks += ("MCP {0} 使用非 loopback 明文 HTTP；Streamable HTTP 远端端点应使用 HTTPS：{1}" -f [string]$diagnostic.name, [string]$diagnostic.url)
        }
    }

    return @($risks)
}

function Get-DoctorAutoUpdateTaskClassification([object]$Task, [string]$ExpectedRunner) {
    $arguments = (@($Task.Actions) | ForEach-Object { [string]$_.Arguments }) -join "`n"
    $runnerExists = [IO.File]::Exists($ExpectedRunner)
    $knownExternal = $runnerExists -and $arguments.Contains($ExpectedRunner, [StringComparison]::OrdinalIgnoreCase)
    $legacy = $arguments -match '(?i)weekly-auto-update\.ps1'
    $state = if ($knownExternal) { 'external_current' } elseif ($legacy) { 'stale_legacy' } else { 'unknown_existing' }
    $action = if ($knownExternal) { 'none' } else { 'manual_repair_or_cleanup' }
    return [pscustomobject][ordered]@{ state = $state; runner_exists = $runnerExists; action = $action }
}

function Get-DoctorLegacyAutoUpdateTaskStatus {
    $taskName = "skills-manager-weekly-update-friday-2000"
    $expectedRunner = [IO.Path]::GetFullPath((Join-Path $Root 'scripts\weekly-skills-update.ps1'))
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return [pscustomobject][ordered]@{ observed = $false; platform_na = $true; exists = $null; task_name = $taskName; state = 'not_observed'; runner_exists = $null; action = "none" }
    }
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $classification = Get-DoctorAutoUpdateTaskClassification -Task $task -ExpectedRunner $expectedRunner
        return [pscustomobject][ordered]@{ observed = $true; platform_na = $false; exists = ($null -ne $task); task_name = $taskName; state = $classification.state; runner_exists = $classification.runner_exists; action = $classification.action }
    }
    catch {
        return [pscustomobject][ordered]@{ observed = $true; platform_na = $false; exists = $false; task_name = $taskName; state = 'absent'; runner_exists = (Test-Path -LiteralPath $expectedRunner -PathType Leaf); action = "none" }
    }
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
        offline_contract = [bool]$opts.offline_contract
        checks = [ordered]@{}
        risks = @()
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
    $report.checks.legacy_auto_update_task = Get-DoctorLegacyAutoUpdateTaskStatus

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

    # 2.5 Skill Projection Consistency
    try {
        $projectionCheck = Get-DoctorSkillProjectionConsistency
        $report.checks.skill_projection = $projectionCheck
        if (-not $projectionCheck.ok) {
            if (-not $opts.json) {
                Write-Host "❌ Skill projection: 投影与声明不一致" -ForegroundColor Red
                foreach ($warning in @($projectionCheck.warnings)) { Write-Host ("   - {0}" -f $warning) -ForegroundColor Yellow }
            }
            $pass = $false
        }
        elseif (-not $opts.json) {
            Write-Host ("✅ Skill projection: {0}" -f $projectionCheck.detail) -ForegroundColor Green
        }
    }
    catch {
        $report.checks.skill_projection = [ordered]@{ ok = $false; warnings = @([string]$_.Exception.Message); detail = "" }
        if (-not $opts.json) { Write-Host "❌ Skill projection: 检查失败" -ForegroundColor Red }
        $pass = $false
    }

    # 2.6 Working tree snapshot (report-vs-reality anchor for delegated runs)
    try {
        $dirtyLines = @(& git -C $Root status --porcelain 2>$null | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $report.checks.working_tree = [ordered]@{ dirty_count = @($dirtyLines).Count; files = @($dirtyLines | Select-Object -First 10) }
        if (-not $opts.json) {
            if (@($dirtyLines).Count -gt 0) { Write-Host ("⚠️ Working tree: {0} 个未提交改动" -f @($dirtyLines).Count) -ForegroundColor Yellow }
            else { Write-Host "✅ Working tree: clean" -ForegroundColor Green }
        }
    }
    catch {
        $report.checks.working_tree = [ordered]@{ dirty_count = -1 }
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
            $report.checks.mcp_transport = @(Get-McpTransportDiagnostics $cfgObj)
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

    # 7. Network Check. JSON structure contracts are deterministic and must not
    # pay for or depend on a live GitHub probe; strict health checks always probe.
    if ($opts.offline_contract) {
        $report.checks.network = [ordered]@{ ok = $true; skipped = $true; reason = "offline_contract" }
    }
    else {
        try {
            $githubConnection = Test-DoctorGitHubConnection
            if ($githubConnection.ok) {
                $report.checks.network = [ordered]@{ ok = $true; method = [string]$githubConnection.method }
                if (-not $opts.json) { Write-Host ("✅ GitHub Connection: OK ({0})" -f [string]$githubConnection.method) -ForegroundColor Green }
            }
            else {
                $report.checks.network = [ordered]@{ ok = $false; method = [string]$githubConnection.method; reason = [string]$githubConnection.detail }
                if (-not $opts.json) { Write-Host ("❌ GitHub Connection: Failed - {0}" -f [string]$githubConnection.detail) -ForegroundColor Red }
                $pass = $false
            }
        }
        catch {
            $report.checks.network = [ordered]@{ ok = $false; reason = $_.Exception.Message }
            if (-not $opts.json) { Write-Host ("❌ GitHub Connection: Failed - {0}" -f $_.Exception.Message) -ForegroundColor Red }
            $pass = $false
        }
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
    if ($report.checks.network -and -not $report.checks.network.ok) { $report.summary.errors += "network_unavailable" }
    if ($report.checks.long_paths.value -eq 0) { $report.summary.warnings += "long_paths_off" }
    if ($report.checks.legacy_auto_update_task.action -ne 'none') { $report.summary.warnings += "auto_update_task_manual_repair" }
    if (@($report.risks).Count -gt 0) { $report.summary.warnings += "config_risks_present" }
    if ($opts.strict -and @($report.risks).Count -gt 0) {
        $report.pass = $false
    }
    $report.summary.error_count = @($report.summary.errors).Count
    $report.summary.warn_count = @($report.summary.warnings).Count
    if ($opts.json) {
        Write-Host ($report | ConvertTo-Json -Depth 30)
        return [pscustomobject]$report
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
