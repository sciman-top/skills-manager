# Install 命令的展示层 helper：vendor/mapping/skill 预览格式化、构建摘要
# 与 DRYUN 镜像收集的启动/停止/汇总。从 Core.ps1 纯迁移（函数名与实现
# 逐字不变）；dry-run 门卫 Skip-IfDryRun 与 RoboMirror 镜像写入留在 Core。

function Start-DryRunMirrorCollect {
    if (-not $DryRun) { return }
    $script:CollectDryRunMirror = $true
    $script:DryRunMirrorCommands = New-Object System.Collections.Generic.List[string]
}
function Stop-DryRunMirrorCollect {
    $script:CollectDryRunMirror = $false
}
function Write-DryRunMirrorSummary([string]$title = "DRYRUN Robocopy 预览", [int]$maxShow = 20) {
    if (-not $DryRun) { return }
    if (-not (Get-Variable -Name DryRunMirrorCommands -Scope Script -ErrorAction SilentlyContinue)) { return }
    if ($null -eq $script:DryRunMirrorCommands) { return }
    $count = $script:DryRunMirrorCommands.Count
    if ($count -eq 0) { return }
    Write-Host ("{0}：共 {1} 条" -f $title, $count)
    $shown = 0
    foreach ($cmd in $script:DryRunMirrorCommands) {
        Write-Host $cmd
        $shown++
        if ($shown -ge $maxShow) { break }
    }
    if ($count -gt $maxShow) {
        Write-Host ("... 另有 {0} 条未显示" -f ($count - $maxShow))
    }
}
function Get-BuildSummary($cfg) {
    $manualCount = @(收集ManualSkills $cfg).Count
    $overrideCount = @(Get-OverridesDirs).Count
    return ("构建摘要：mappings={0}，imports(manual)={1}，overrides={2}，targets={3}，sync_mode={4}" -f $cfg.mappings.Count, $manualCount, $overrideCount, $cfg.targets.Count, $cfg.sync_mode)
}
function Write-BuildSummary($cfg = $null) {
    try {
        if ($null -eq $cfg) { $cfg = LoadCfg }
        Write-Host (Get-BuildSummary $cfg)
    }
    catch {}
}
function Format-VendorPreview($vendors) {
    return ($vendors | ForEach-Object { "$($_.name) :: $($_.repo)" })
}
function Get-DisplayVendor($item) {
    if ($null -eq $item) { return "" }
    if ($item.PSObject.Properties.Match("display_vendor").Count -gt 0) {
        $display = [string]$item.display_vendor
        if (-not [string]::IsNullOrWhiteSpace($display)) { return $display }
    }
    return [string]$item.vendor
}
function Format-MappingPreview($items, [string]$targetPrefix = "") {
    $prefix = if ([string]::IsNullOrWhiteSpace($targetPrefix)) { "" } else { ($targetPrefix + " ") }
    return ($items | ForEach-Object { "$prefix$(Get-DisplayVendor $_) :: $($_.from) -> $($_.to)" })
}
function Format-SkillPreview($items) {
    return ($items | ForEach-Object { "$(Get-DisplayVendor $_) :: $($_.from)" })
}
