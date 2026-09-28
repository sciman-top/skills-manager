[CmdletBinding()]
param(
    [switch]$Unlock,
    [string]$ExternalRoot = 'D:\CODE\external'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$baselinesPath = Join-Path $repoRoot 'references\external-readonly-baselines.json'

if (-not (Test-Path -LiteralPath $ExternalRoot -PathType Container)) {
    throw "external root not found: $ExternalRoot"
}

# 解锁窗口只服务显式 refresh/手动维护;AI 会话不属于合法调用方。
if ($Unlock) {
    $acl = Get-Acl -LiteralPath $ExternalRoot
    $removed = $false
    foreach ($ace in @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and -not $_.IsInherited })) {
        $id = [string]$ace.IdentityReference.Value
        if (($id -eq $env:USERNAME) -or ($id -like "*\$env:USERNAME")) {
            [void]$acl.RemoveAccessRuleSpecific($ace)
            $removed = $true
        }
    }
    if ($removed) { Set-Acl -LiteralPath $ExternalRoot -AclObject $acl }
    Write-Host "UNLOCKED: $ExternalRoot (explicit deny ACE removed for $env:USERNAME)"
    Write-Host "Finish your work, then re-lock: pwsh scripts/lock-external-repos.ps1"
    exit 0
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
