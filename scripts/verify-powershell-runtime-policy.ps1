#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepoRoot)
$findings = [Collections.Generic.List[object]]::new()

function Add-Finding([string]$Code, [string]$Path, [string]$Message) {
    $findings.Add([pscustomobject]@{ code = $Code; severity = 'error'; path = $Path; message = $Message }) | Out-Null
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Finding 'required_file_missing' $RelativePath 'Required PowerShell runtime policy file is missing.'
        return ''
    }
    return Get-Content -LiteralPath $path -Raw
}

function Require-Pattern([string]$Text, [string]$Pattern, [string]$Path, [string]$Code, [string]$Message) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch $Pattern) { Add-Finding $Code $Path $Message }
}

function Reject-Pattern([string]$Text, [string]$Pattern, [string]$Path, [string]$Code, [string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Text) -and $Text -match $Pattern) { Add-Finding $Code $Path $Message }
}

function Test-IsWindowsPowerShellName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    try { $leaf = [IO.Path]::GetFileName($Value.Trim().Trim('"', "'")) }
    catch { $leaf = $Value }
    return $leaf -in @('powershell', 'powershell.exe')
}

function Get-ActivePowerShellFiles {
    $excluded = @('.git/', '.txn/', 'agent/', 'imports/', 'reports/', 'tests/fixtures/', 'vendor/')
    $paths = @()
    if ((Test-Path -LiteralPath (Join-Path $root '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $paths = @(& git -C $root ls-files --cached --others --exclude-standard -- '*.ps1' 2>$null)
        if ($LASTEXITCODE -ne 0) { $paths = @() }
    }
    if ($paths.Count -eq 0) {
        $paths = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse -Force |
            ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') })
    }
    foreach ($relative in @($paths | ForEach-Object { ([string]$_).Trim().Replace('\', '/') } | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -eq 'skills.ps1') { continue }
        if (@($excluded | Where-Object { $relative.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { continue }
        $full = Join-Path $root $relative
        if (Test-Path -LiteralPath $full -PathType Leaf) { [pscustomobject]@{ path = $relative; full_path = $full } }
    }
}

function Test-ActivePowerShellEstate {
    $count = 0
    foreach ($entry in @(Get-ActivePowerShellFiles)) {
        $count++
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($entry.full_path, [ref]$tokens, [ref]$parseErrors)
        foreach ($error in @($parseErrors)) {
            Add-Finding 'powershell_script_parse_failed' $entry.path ('Parse failed at line {0}, column {1}: {2}' -f $error.Extent.StartLineNumber, $error.Extent.StartColumnNumber, $error.Message)
        }
        $legacy = $ast.Find({
                param($node)
                if ($node -is [Management.Automation.Language.CommandAst]) {
                    if (Test-IsWindowsPowerShellName ([string]$node.GetCommandName())) { return $true }
                    if ([string]$node.GetCommandName() -in @('Get-Command', 'Start-Process')) {
                        return @($node.CommandElements | Select-Object -Skip 1 | Where-Object {
                                $_ -is [Management.Automation.Language.StringConstantExpressionAst] -and (Test-IsWindowsPowerShellName ([string]$_.Value))
                            }).Count -gt 0
                    }
                }
                return ($node -is [Management.Automation.Language.VariableExpressionAst] -and [string]$node.VariablePath.UserPath -ieq 'env:CODEX_ALLOW_WINDOWS_POWERSHELL')
            }, $true)
        if ($null -ne $legacy) {
            Add-Finding 'legacy_runtime_invocation_detected' $entry.path ('Windows PowerShell path at line {0}, column {1}.' -f $legacy.Extent.StartLineNumber, $legacy.Extent.StartColumnNumber)
        }
    }
    return $count
}

$paths = [ordered]@{
    agents = 'AGENTS.md'; release = 'RELEASE_TEMPLATE.md'; version = 'src/Version.ps1'; build = 'build.ps1'
    installer = 'install.ps1'; cmd = 'skills.cmd'; core = 'src/Core.ps1'; mcp = 'src/Commands/Mcp.ps1'
    generated = 'skills.ps1'; github = '.github/workflows/ci.yml'
}
$content = @{}
foreach ($key in $paths.Keys) { $content[$key] = Read-Required $paths[$key] }

$versionPattern = '(?m)^#requires\s+-Version\s+7\.0\s*$'
foreach ($key in @('version', 'build', 'installer', 'generated')) {
    Require-Pattern $content[$key] $versionPattern $paths[$key] 'powershell_version_floor_invalid' ("{0} must require PowerShell 7.0." -f $paths[$key])
}
if (-not [string]::IsNullOrWhiteSpace($content.generated)) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root $paths.generated))
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
        Add-Finding 'generated_encoding_invalid' $paths.generated 'Generated bundle must keep deterministic UTF-8 BOM encoding.'
    }
}
Reject-Pattern $content.core '(?i)CODEX_ALLOW_WINDOWS_POWERSHELL|Get-Command\s+powershell(?:\.exe)?' $paths.core 'legacy_fallback_detected' 'Core must not resolve Windows PowerShell.'
Reject-Pattern $content.installer '(?i)Get-Command\s+powershell(?:\.exe)?|&\s*[''"]?powershell(?:\.exe)?' $paths.installer 'legacy_fallback_detected' 'Installer must not invoke Windows PowerShell.'
Reject-Pattern $content.cmd '(?i)POWERSHELL_EXE=powershell\.exe|where\s+powershell(?:\.exe)?|\bpause\b' $paths.cmd 'legacy_fallback_detected' 'CMD wrapper must resolve only pwsh.'
Reject-Pattern $content.mcp '(?i)["'']powershell\.exe["'']' $paths.mcp 'legacy_fallback_detected' 'MCP wrapper must invoke pwsh.exe only.'
Reject-Pattern $content.generated '(?i)CODEX_ALLOW_WINDOWS_POWERSHELL|(?:Get-Command|Start-Process)\s+(?:-FilePath\s+)?["'']?powershell(?:\.exe)?["'']?|&\s*["'']?powershell(?:\.exe)?["'']?|["'']powershell\.exe["'']' $paths.generated 'legacy_fallback_detected' 'Generated bundle contains a legacy runtime path.'
Reject-Pattern $content.github '(?i)Windows PowerShell 5\.1|shell:\s*powershell(?:\s|$)' $paths.github 'legacy_ci_detected' 'CI must not use Windows PowerShell.'

$scanned = Test-ActivePowerShellEstate
$result = [pscustomobject][ordered]@{
    schema_version = 1
    status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    track = 'powershell_runtime_policy'
    scope = 'active_runtime'
    runtime_policy = 'ps7_only'
    powershell_files_scanned = $scanned
    writes_performed = 0
    findings = $findings.ToArray()
}

if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    foreach ($finding in $findings) { Write-Host ("[{0}] {1}: {2}" -f $finding.code, $finding.path, $finding.message) }
    Write-Host ("PowerShell runtime policy: status={0}; scanned={1}; findings={2}" -f $result.status, $scanned, $findings.Count)
}
if ($findings.Count -gt 0) { exit 1 }
