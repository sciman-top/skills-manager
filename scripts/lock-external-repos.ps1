[CmdletBinding()]
param(
    [switch]$Unlock,
    [switch]$Status,
    [switch]$Deep,
    [string]$ExternalRoot = 'D:\CODE\external'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$baselinesPath = Join-Path $repoRoot 'references\external-readonly-baselines.json'

if (-not (Test-Path -LiteralPath $ExternalRoot -PathType Container)) {
    throw "external root not found: $ExternalRoot"
}

if ($Unlock -and $Status) {
    throw 'Use either -Unlock or -Status, not both.'
}

if ($Deep -and -not $Status) {
    throw '-Deep only applies to -Status.'
}

function Get-ExternalRootAccount {
    # deny ACE 的标识符写自 $env:USERNAME;这里取当前 token 的完整账户名做同一口径的匹配。
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Test-ExternalRootLockAce {
    param([Parameter(Mandatory)][string]$Path)
    $aces = @(Get-Acl -LiteralPath $Path | Select-Object -ExpandProperty Access | Where-Object {
            $_.AccessControlType -eq 'Deny' -and -not $_.IsInherited -and
            ((([string]$_.IdentityReference.Value) -eq $env:USERNAME) -or (([string]$_.IdentityReference.Value) -like "*\$env:USERNAME"))
        })
    $aces.Count -gt 0
}

function Remove-ExternalRootLockAce {
    param([Parameter(Mandatory)][string]$Path)
    $acl = Get-Acl -LiteralPath $Path
    $removed = 0
    foreach ($ace in @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and -not $_.IsInherited })) {
        $id = [string]$ace.IdentityReference.Value
        if (($id -eq $env:USERNAME) -or ($id -like "*\$env:USERNAME")) {
            [void]$acl.RemoveAccessRuleSpecific($ace)
            $removed++
        }
    }
    if ($removed -gt 0) { Set-Acl -LiteralPath $Path -AclObject $acl }
    $removed
}

function Invoke-ExternalRootDenyPurge {
    # Set-Acl 只重写目标对象自己的 DACL:根 ACE 移除后,子路径上已物化的 deny 副本不会
    # 一起消失,残留会让 git fetch 写对象、merge --ff-only 删旧文件报 Access denied。
    # icacls 单次原生遍历同时覆盖目录与文件,比逐对象 .NET ACL 调用快一个量级。
    # 受控复现(2026-10-15):对带 INHERITED_ACE 标记的 ACE,icacls /remove:d 返回
    # "Successfully processed" 且 exit 0,但 ACL 完全不变,所以它只是快速通路,
    # 真正决定解锁结果的是残留复扫、逐对象重写与顶层写探针。
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Account)
    $output = @(& icacls $Path /remove:d $Account /T /C /Q 2>&1)
    [pscustomobject][ordered]@{
        ExitCode = $LASTEXITCODE
        DeniedLines = @($output | Where-Object { $_ -match ': Access is denied\.$' })
    }
}

function Test-ExternalResidualDenyPath {
    # 残留判定必须同时覆盖显式与继承 ACE:失败传播留下的孤儿副本仍带 INHERITED_ACE 标记,
    # 只看非继承 ACE(如 Test-ExternalRootLockAce)会漏掉本机实测的全部残留。
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Account)
    try { $acl = Get-Acl -LiteralPath $Path }
    catch { return $true }
    @($acl.Access | Where-Object {
            $_.AccessControlType -eq 'Deny' -and [string]$_.IdentityReference.Value -eq $Account
        }).Count -gt 0
}

function Repair-ExternalResidualDenyPath {
    # 逐对象重写 DACL:把当前账号的 deny ACE 从 ACL 对象里移除后写回,OS 会按父链重新
    # 推导继承 ACE,因此父链已无源 ACE 的孤儿副本就此消失;若写回后仍在,再退一步用
    # icacls /reset 让该对象回到纯继承状态。返回实际生效的机制名,失败返回空串。
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Account)
    $matched = @(Get-Acl -LiteralPath $Path | Select-Object -ExpandProperty Access | Where-Object {
            $_.AccessControlType -eq 'Deny' -and [string]$_.IdentityReference.Value -eq $Account
        })
    if ($matched.Count -eq 0) { return '' }
    try {
        $acl = Get-Acl -LiteralPath $Path
        foreach ($rule in $matched) { [void]$acl.RemoveAccessRuleAll($rule) }
        Set-Acl -LiteralPath $Path -AclObject $acl
        if (-not (Test-ExternalResidualDenyPath -Path $Path -Account $Account)) { return 'dacl-rewrite' }
    }
    catch { }
    try {
        $null = & icacls $Path /reset /C /Q 2>&1
        if (-not (Test-ExternalResidualDenyPath -Path $Path -Account $Account)) { return 'icacls-reset' }
    }
    catch { }
    ''
}

function Get-ExternalResidualDenyPath {
    # 目录与文件都要扫:实测(2026-10-15)单货架 12122 个目录里有 137 个带孤儿 deny,
    # 53804 个文件里另有 319 个,含 .git\objects 松散对象与 packed-refs——只扫目录会漏掉
    # fetch 写对象库、merge 替换旧文件这两条真实故障链。
    # 联接点(ReparsePoint)整棵跳过:货架里的 junction 都指向 _shared\repos,规范位置会被
    # 扫到一次,跟进去只会重复计数并成倍放大耗时。
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Account)
    $options = [IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $true
    $options.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
    $options.IgnoreInaccessible = $true
    $residual = [Collections.Generic.List[string]]::new()
    foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($Path, '*', $options)) {
        if (Test-ExternalResidualDenyPath -Path $entry -Account $Account) { $residual.Add($entry) }
    }
    return @($residual)
}

function Test-ExternalWriteProbe {
    # 有效权限探针:真实创建并删除临时文件,不依赖 ACL 解析结果。
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $probe = Join-Path $Path ('.external-acl-probe-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($probe, 'probe')
        Remove-Item -LiteralPath $probe -Force
        $true
    }
    catch {
        if (Test-Path -LiteralPath $probe) {
            try { Remove-Item -LiteralPath $probe -Force -ErrorAction Stop } catch { }
        }
        $false
    }
}

function Get-ExternalTopLevelDirectory {
    param([Parameter(Mandatory)][string]$Path)
    @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue)
}

$resolvedRoot = [IO.Path]::GetFullPath($ExternalRoot).TrimEnd('\')

# 解锁窗口只服务显式 refresh/手动维护;AI 会话不属于合法调用方。
if ($Unlock) {
    $account = Get-ExternalRootAccount
    $elevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $rootAcesRemoved = Remove-ExternalRootLockAce -Path $ExternalRoot
    $purge = Invoke-ExternalRootDenyPurge -Path $ExternalRoot -Account $account

    $scanWatch = [Diagnostics.Stopwatch]::StartNew()
    $residual = @(Get-ExternalResidualDenyPath -Path $ExternalRoot -Account $account)
    $scanWatch.Stop()

    $repairedByMechanism = @{}
    $unrepaired = [Collections.Generic.List[string]]::new()
    foreach ($entry in $residual) {
        if (-not $entry.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $mechanism = ''
        try { $mechanism = Repair-ExternalResidualDenyPath -Path $entry -Account $account }
        catch { $mechanism = '' }
        if ($mechanism) {
            if (-not $repairedByMechanism.ContainsKey($mechanism)) { $repairedByMechanism[$mechanism] = 0 }
            $repairedByMechanism[$mechanism]++
        }
        else { $unrepaired.Add($entry) }
    }
    $repairedCount = if ($repairedByMechanism.Count) { @($repairedByMechanism.Values | Measure-Object -Sum).Sum } else { 0 }
    $remaining = @($unrepaired)
    $samples = @($remaining | Select-Object -First 3 | ForEach-Object {
            $sampleAcl = Get-Acl -LiteralPath $_ -ErrorAction SilentlyContinue
            "$_ ($(@($sampleAcl.Access | Where-Object { $_.AccessControlType -eq 'Deny' }).Count) deny ACEs, owner=$($sampleAcl.Owner))"
        })
    $probeTargets = @(Get-ExternalTopLevelDirectory -Path $ExternalRoot)
    $probeFailures = @($probeTargets | Where-Object { -not (Test-ExternalWriteProbe -Path $_.FullName) })
    if ($remaining.Count -gt 0 -or $probeFailures.Count -gt 0) {
        # 残留对象通常由其他 token 创建并持有(本机实测 owner=sciman-home\CodexSandboxOffline),
        # 当前用户在其上只有 Modify、没有 WRITE_DAC,非提权 token 改不了它们的 DACL;
        # 管理员 token 通过 Administrators 的继承 FullControl 才能重写,所以必须提权重跑。
        throw ("unlock incomplete: rootAcesRemoved=$rootAcesRemoved residualDenyPaths=$($residual.Count) " +
            "repaired=$repairedCount stillDenied=$($remaining.Count) icaclsExit=$($purge.ExitCode) " +
            "icaclsDeniedLines=$($purge.DeniedLines.Count) probeFailures=$($probeFailures.Count) elevated=$elevated " +
            "scanSeconds=$([int]$scanWatch.Elapsed.TotalSeconds); " +
            "re-run this command from an elevated PowerShell if elevated=False, otherwise take ownership of the sampled paths. " +
            "samples: $($samples -join ' ; ')")
    }
    $repairSummary = if ($repairedByMechanism.Count) {
        (@($repairedByMechanism.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ',')
    }
    else { 'none' }
    Write-Host ("UNLOCKED: $ExternalRoot (deny ACE removed for $env:USERNAME; rootAcesRemoved=$rootAcesRemoved; " +
        "residualDenyPaths(before repair)=$($residual.Count); repairs=$repairSummary; residual deny paths=0; " +
        "top-level write probes=$($probeTargets.Count) passed; icaclsExit=$($purge.ExitCode); " +
        "scanSeconds=$([int]$scanWatch.Elapsed.TotalSeconds); elevated=$elevated)")
    Write-Host "Finish your work, then re-lock: pwsh scripts/lock-external-repos.ps1"
    exit 0
}

if ($Status) {
    $account = Get-ExternalRootAccount
    $locked = Test-ExternalRootLockAce -Path $ExternalRoot
    $probeTargets = @(Get-ExternalTopLevelDirectory -Path $ExternalRoot)
    $probeFailures = @($probeTargets | Where-Object { -not (Test-ExternalWriteProbe -Path $_.FullName) })
    $scope = if ($Deep) { 'tree' } else { 'top-level' }
    Write-Host "external-root=$ExternalRoot locked=$locked scope=$scope topLevelWriteProbes=$($probeTargets.Count) probeFailures=$($probeFailures.Count)"
    if (-not $Deep) {
        if ($locked) {
            Write-Host 'shallow status: the root deny ACE is active; descendant denials are expected while locked.'
            exit 0
        }
        if ($probeFailures.Count -eq 0) {
            Write-Host 'shallow status: unlocked root permits writes at every top-level directory; run -Status -Deep to scan all objects for residual deny ACEs.'
            exit 0
        }
        Write-Host 'shallow status: unlocked root still denies top-level writes; run -Unlock from an elevated PowerShell.' -ForegroundColor Red
        exit 1
    }
    $scanWatch = [Diagnostics.Stopwatch]::StartNew()
    $residual = @(Get-ExternalResidualDenyPath -Path $ExternalRoot -Account $account)
    $scanWatch.Stop()
    $fileResidual = @($residual | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) }).Count
    Write-Host ("deep status: residualDenyPaths=$($residual.Count) (files=$fileResidual) scanSeconds=$([int]$scanWatch.Elapsed.TotalSeconds)")
    foreach ($sample in @($residual | Select-Object -First 5)) { Write-Host "  residual: $sample" }
    if ($locked) {
        Write-Host 'status self-consistent: locked root owns the deny ACE; residual descendant ACEs are expected while locked.'
        exit 0
    }
    if ($residual.Count -eq 0 -and $probeFailures.Count -eq 0) {
        Write-Host 'status self-consistent: unlocked root carries no deny ACE anywhere and writes are permitted.'
        exit 0
    }
    Write-Host ('status inconsistent: unlocked root still denies writes. The residual ACEs are inherited-flag copies left by' +
        ' failed propagation and icacls cannot delete them; run -Unlock from an elevated PowerShell to rewrite those DACLs.') -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $baselinesPath)) {
    throw "baseline file missing: $baselinesPath"
}

# 上锁即重钉基线:解锁窗口期产生的合法新 HEAD 从此成为漂移比对基点。
$baselinesText = Get-Content -Raw -LiteralPath $baselinesPath -Encoding UTF8
$baselines = $baselinesText | ConvertFrom-Json
foreach ($repo in @($baselines.repos)) {
    $repoPath = Join-Path $ExternalRoot ([string]$repo.relative_path)
    $head = (& git -C $repoPath rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') {
        throw "cannot resolve HEAD for baseline repo: $($repo.relative_path)"
    }
    if ([string]$repo.head -eq $head) { continue }
    $pattern = '(?s)("relative_path"\s*:\s*"' + [regex]::Escape([string]$repo.relative_path) + '".*?"head"\s*:\s*")[0-9a-f]{40}'
    $updated = [regex]::Replace($baselinesText, $pattern, ('${1}' + $head), 'IgnoreCase')
    if ($updated -eq $baselinesText) {
        throw "baseline head pattern not matched for repo: $($repo.relative_path)"
    }
    $baselinesText = $updated
    Write-Host "baseline re-pinned: $($repo.relative_path) -> $head"
}
[System.IO.File]::WriteAllText($baselinesPath, $baselinesText, [System.Text.UTF8Encoding]::new($false))

# 本机 icacls 对多数 specific rights 误报“无效参数”,改用 .NET ACL API 写 deny。
# Write 已含 WriteData/WriteAttributes/WriteExtendedAttributes;目录上 AppendData = 建子目录。
$denyRights = [System.Security.AccessControl.FileSystemRights]::Write -bor
    [System.Security.AccessControl.FileSystemRights]::AppendData -bor
    [System.Security.AccessControl.FileSystemRights]::Delete -bor
    [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
$denyRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $env:USERNAME, $denyRights,
    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
    [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Deny)
$acl = Get-Acl -LiteralPath $ExternalRoot
$acl.AddAccessRule($denyRule)
Set-Acl -LiteralPath $ExternalRoot -AclObject $acl
Write-Host "LOCKED: $ExternalRoot (deny write/append/delete for $env:USERNAME)"

# NTFS 自动继承对深树可能物化延迟(曾实测单文件删除逃逸);上锁后必须抽查确认。
$probeFiles = @(Get-ChildItem -LiteralPath $ExternalRoot -Directory | ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
            Select-Object -First 2
    })
if ($probeFiles.Count -eq 0) { throw "no probe files found under $ExternalRoot" }
$pending = @($probeFiles | Where-Object {
        $probeAcl = Get-Acl -LiteralPath $_.FullName
        @($probeAcl.Access | Where-Object {
                $_.AccessControlType -eq 'Deny' -and
                ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete)
            }).Count -eq 0
    })
if ($pending.Count -gt 0) {
    throw "deny propagation incomplete for $($pending.Count) file(s), e.g. $($pending[0].FullName); re-run lock-external-repos.ps1"
}
Write-Host "deny propagation confirmed on $($probeFiles.Count) probe file(s)"

& (Join-Path $PSScriptRoot 'verify-reference-governance.ps1')
