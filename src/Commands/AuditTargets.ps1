function Get-AuditTargetsConfigPath {
    return (Join-Path $script:Root "audit-targets.json")
}

function New-DefaultAuditTargetsConfig {
    return [pscustomobject]@{
        version = 1
        path_base = "skills_manager_root"
        targets = @()
    }
}

function Save-AuditTargetsConfig($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 20
    Set-ContentUtf8 (Get-AuditTargetsConfigPath) $json
}

function Initialize-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $false }
    Save-AuditTargetsConfig (New-DefaultAuditTargetsConfig)
    return $true
}

function Load-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    Need (Test-Path -LiteralPath $path -PathType Leaf) "缺少 audit-targets.json，请先运行：./skills.ps1 审查目标 初始化"
    try {
        $cfg = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        throw ("audit-targets.json 解析失败：{0}" -f $_.Exception.Message)
    }

    if (-not $cfg.PSObject.Properties.Match("version").Count) {
        $cfg | Add-Member -NotePropertyName version -NotePropertyValue 1
    }
    if (-not $cfg.PSObject.Properties.Match("path_base").Count) {
        $cfg | Add-Member -NotePropertyName path_base -NotePropertyValue "skills_manager_root"
    }
    if (-not $cfg.PSObject.Properties.Match("targets").Count -or $null -eq $cfg.targets) {
        $cfg | Add-Member -NotePropertyName targets -NotePropertyValue @() -Force
    }

    Need ([int]$cfg.version -eq 1) "audit-targets.json version 仅支持 1"
    Need ([string]$cfg.path_base -eq "skills_manager_root") "audit-targets.json path_base 仅支持 skills_manager_root"
    if (-not (Assert-IsArray $cfg.targets)) { $cfg.targets = @($cfg.targets) }
    return $cfg
}

function Resolve-AuditTargetPath([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "目标仓路径不能为空"
    $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
    if ($expanded -eq "~" -or $expanded.StartsWith("~\") -or $expanded.StartsWith("~/")) {
        $userHome = [Environment]::GetFolderPath("UserProfile")
        if ($expanded.Length -eq 1) {
            $expanded = $userHome
        }
        else {
            $expanded = Join-Path $userHome $expanded.Substring(2)
        }
    }
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $script:Root $expanded))
}

function Add-AuditTargetConfigEntry([string]$name, [string]$path, [string[]]$tags = @(), [string]$notes = "") {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    Need (-not [string]::IsNullOrWhiteSpace($path)) "target path 不能为空"

    $entry = [pscustomobject]@{
        name = $normName
        path = $path
        enabled = $true
        tags = @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        notes = $notes
    }

    $existing = @($cfg.targets | Where-Object { $_.name -eq $normName })
    if ($existing.Count -gt 0) {
        $existing[0].path = $entry.path
        $existing[0].enabled = $entry.enabled
        $existing[0].tags = $entry.tags
        $existing[0].notes = $entry.notes
    }
    else {
        $cfg.targets += $entry
    }
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Parse-AuditTargetsArgs([string[]]$tokens) {
    $result = [ordered]@{
        action = "list"
        name = $null
        path = $null
        target = $null
        out = $null
        recommendations = $null
        apply = $false
        yes = $false
        tags = @()
        notes = ""
    }

    $items = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -gt 0) {
        $head = ([string]$items[0]).ToLowerInvariant()
        switch ($head) {
            "初始化" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "init" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "添加" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "add" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "列表" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "list" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "扫描" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "scan" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "应用" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            "apply" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            default { throw ("未知审查目标子命令：{0}" -f $items[0]) }
        }
    }

    $positional = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        $t = [string]$items[$i]
        $key = $t.ToLowerInvariant()
        switch ($key) {
            "--target" {
                Need ($i + 1 -lt $items.Count) "--target 缺少值"
                $result.target = [string]$items[++$i]
                continue
            }
            "--out" {
                Need ($i + 1 -lt $items.Count) "--out 缺少值"
                $result.out = [string]$items[++$i]
                continue
            }
            "--recommendations" {
                Need ($i + 1 -lt $items.Count) "--recommendations 缺少值"
                $result.recommendations = [string]$items[++$i]
                continue
            }
            "--apply" {
                $result.apply = $true
                continue
            }
            "--yes" {
                $result.yes = $true
                continue
            }
            "--tag" {
                Need ($i + 1 -lt $items.Count) "--tag 缺少值"
                $result.tags += [string]$items[++$i]
                continue
            }
            "--notes" {
                Need ($i + 1 -lt $items.Count) "--notes 缺少值"
                $result.notes = [string]$items[++$i]
                continue
            }
            default {
                $positional += $t
            }
        }
    }

    if ($result.action -eq "add") {
        Need ($positional.Count -ge 2) "添加目标仓需要 name 和 path"
        $result.name = [string]$positional[0]
        $result.path = [string]$positional[1]
    }
    return [pscustomobject]$result
}

function Write-AuditTargetsList {
    $cfg = Load-AuditTargetsConfig
    $items = @($cfg.targets)
    if ($items.Count -eq 0) {
        Write-Host "未登记目标仓。"
        return
    }
    foreach ($t in $items) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $exists = Test-Path -LiteralPath $resolved
        $enabled = if ($t.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$t.enabled } else { $true }
        $enabledText = if ($enabled) { "enabled" } else { "disabled" }
        Write-Host ("- {0} [{1}] {2} -> {3} exists={4}" -f [string]$t.name, $enabledText, [string]$t.path, $resolved, $exists)
    }
}

function Invoke-AuditTargetsScan {
    param(
        [string]$Target,
        [string]$OutDir
    )
    throw "审查目标扫描尚未实现。"
}

function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [switch]$Apply,
        [switch]$Yes
    )
    throw "审查目标应用尚未实现。"
}

function Invoke-AuditTargetsCommand([string[]]$tokens = @()) {
    $opts = Parse-AuditTargetsArgs $tokens
    switch ($opts.action) {
        "init" {
            if (Initialize-AuditTargetsConfig) {
                Write-Host "已创建 audit-targets.json" -ForegroundColor Green
            }
            else {
                Write-Host "audit-targets.json 已存在，未覆盖。" -ForegroundColor Yellow
            }
        }
        "add" {
            Add-AuditTargetConfigEntry $opts.name $opts.path $opts.tags $opts.notes | Out-Null
            Write-Host ("已登记目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "list" { Write-AuditTargetsList }
        "scan" { Invoke-AuditTargetsScan -Target $opts.target -OutDir $opts.out | Out-Null }
        "apply" { Invoke-AuditRecommendationsApply -RecommendationsPath $opts.recommendations -Apply:$opts.apply -Yes:$opts.yes | Out-Null }
    }
}
