#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding([string]$Code, [string]$Path, [string]$Message) {
    $findings.Add([pscustomobject][ordered]@{
        code = $Code
        severity = 'error'
        path = $Path
        message = $Message
    }) | Out-Null
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Finding 'required_file_missing' $RelativePath 'Required PowerShell runtime policy file is missing.'
        return ''
    }
    return Get-Content -LiteralPath $path -Raw
}

function Require-Literal([string]$Text, [string]$Literal, [string]$Path, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.IndexOf($Literal, [System.StringComparison]::Ordinal) -lt 0) {
        Add-Finding $Code $Path ("Required literal is missing: {0}" -f $Literal)
    }
}

function Require-Pattern([string]$Text, [string]$Pattern, [string]$Path, [string]$Code, [string]$Message) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch $Pattern) {
        Add-Finding $Code $Path $Message
    }
}

function Reject-Pattern([string]$Text, [string]$Pattern, [string]$Path, [string]$Code, [string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Text) -and $Text -match $Pattern) {
        Add-Finding $Code $Path $Message
    }
}

function Get-ActivePowerShellFiles {
    $excludedPrefixes = @(
        '.git/',
        '.txn/',
        'agent/',
        'imports/',
        'reports/',
        'tests/fixtures/',
        'vendor/'
    )
    $separatelyValidatedFiles = @('skills.ps1')
    $relativePaths = @()

    if ((Test-Path -LiteralPath (Join-Path $root '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $relativePaths = @(& git -C $root ls-files --cached --others --exclude-standard -- '*.ps1' 2>$null)
        if ($LASTEXITCODE -ne 0) { $relativePaths = @() }
    }
    if ($relativePaths.Count -eq 0) {
        $relativePaths = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse -Force -ErrorAction Stop |
            ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') })
    }

    foreach ($relativePath in @($relativePaths | ForEach-Object { ([string]$_).Trim().Replace('\', '/') } | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($relativePath) -or $relativePath -in $separatelyValidatedFiles) { continue }
        $excluded = $false
        foreach ($prefix in $excludedPrefixes) {
            if ($relativePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) {
            $fullPath = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
            [pscustomobject]@{
                path = $relativePath
                full_path = $fullPath
            }
        }
    }
}

function Test-IsWindowsPowerShellName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim().Trim('"', "'")
    try {
        $leaf = [System.IO.Path]::GetFileName($candidate)
    }
    catch {
        $leaf = $candidate
    }
    return $leaf -in @('powershell', 'powershell.exe')
}

function Test-ActivePowerShellEstate {
    $scanned = 0
    foreach ($entry in @(Get-ActivePowerShellFiles)) {
        $scanned++
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $entry.full_path,
            [ref]$tokens,
            [ref]$parseErrors
        )

        foreach ($parseError in @($parseErrors)) {
            Add-Finding 'powershell_script_parse_failed' $entry.path (
                'Active PowerShell script does not parse under PS7 at line {0}, column {1}: {2}' -f
                    $parseError.Extent.StartLineNumber,
                    $parseError.Extent.StartColumnNumber,
                    $parseError.Message
            )
        }

        $legacyInvocation = $null
        foreach ($command in @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true))) {
            $commandName = [string]$command.GetCommandName()
            if (Test-IsWindowsPowerShellName $commandName) {
                $legacyInvocation = $command.Extent
                break
            }

            if ($commandName -in @('Get-Command', 'Start-Process')) {
                foreach ($element in @($command.CommandElements | Select-Object -Skip 1)) {
                    if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        (Test-IsWindowsPowerShellName ([string]$element.Value))) {
                        $legacyInvocation = $element.Extent
                        break
                    }
                }
            }
            if ($null -ne $legacyInvocation) { break }
        }

        if ($null -eq $legacyInvocation) {
            $legacyVariable = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    [string]$node.VariablePath.UserPath -ieq 'env:CODEX_ALLOW_WINDOWS_POWERSHELL'
            }, $true)
            if ($null -ne $legacyVariable) {
                $legacyInvocation = $legacyVariable.Extent
            }
        }

        if ($null -ne $legacyInvocation) {
            Add-Finding 'legacy_runtime_invocation_detected' $entry.path (
                'Active PowerShell estate contains a Windows PowerShell execution path at line {0}, column {1}.' -f
                    $legacyInvocation.StartLineNumber,
                    $legacyInvocation.StartColumnNumber
            )
        }
    }
    return $scanned
}

$paths = [ordered]@{
    manifest = 'tasks/skills-manager-vnext-powershell7-migration.tasks.json'
    spec = 'docs/superpowers/specs/2026-08-05-powershell-7-only-runtime-migration.md'
    evidence = 'docs/change-evidence/20260805-powershell-7-only-runtime-migration.md'
    runbook = 'docs/runbooks/powershell-runtime-compatibility.md'
    prd = 'docs/product/skills-manager-vnext-prd.md'
    architecture = 'docs/product/skills-manager-vnext-architecture.md'
    roadmap = 'docs/product/skills-manager-vnext-roadmap.md'
    lean = 'docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md'
    agents = 'AGENTS.md'
    release = 'RELEASE_TEMPLATE.md'
    version = 'src/Version.ps1'
    build = 'build.ps1'
    installer = 'install.ps1'
    cmd = 'skills.cmd'
    core = 'src/Core.ps1'
    mcp = 'src/Commands/Mcp.ps1'
    generated = 'skills.ps1'
    github = '.github/workflows/ci.yml'
    azure = 'azure-pipelines.yml'
    gitlab = '.gitlab-ci.yml'
    quality = 'scripts/quality/run-local-quality-gates.ps1'
    typedManifest = 'tasks/skills-manager-vnext-typed-core-pilot.tasks.json'
    historicalManifest = 'tasks/skills-manager-vnext-phase0.tasks.json'
}

$content = @{}
foreach ($key in @($paths.Keys)) {
    $content[$key] = Read-Required $paths[$key]
}

$manifest = $null
if (-not [string]::IsNullOrWhiteSpace($content.manifest)) {
    try { $manifest = $content.manifest | ConvertFrom-Json }
    catch { Add-Finding 'manifest_parse_failed' $paths.manifest $_.Exception.Message }
}

$expectedTaskIds = @('SMV-PS7-001', 'SMV-PS7-002', 'SMV-PS7-003', 'SMV-PS7-004', 'SMV-PS7-005')
$doneCount = 0
if ($null -ne $manifest) {
    if ([int]$manifest.schema_version -ne 1 -or [string]$manifest.program_id -ne 'skills-manager-vnext' -or [string]$manifest.track -ne 'powershell7_runtime_migration' -or [string]$manifest.base_phase -ne 'P5') {
        Add-Finding 'manifest_identity_invalid' $paths.manifest 'Manifest identity must remain schema 1 / skills-manager-vnext / powershell7_runtime_migration / P5.'
    }
    foreach ($check in @(
        @{ property='track_status'; value='repo_verified'; code='track_status_invalid' },
        @{ property='runtime_policy'; value='ps7_only'; code='runtime_policy_invalid' },
        @{ property='minimum_version'; value='7.0'; code='minimum_version_invalid' },
        @{ property='recommended_baseline'; value='7.6_lts'; code='recommended_baseline_invalid' },
        @{ property='legacy_runtime_status'; value='unsupported'; code='legacy_runtime_status_invalid' },
        @{ property='historical_evidence_policy'; value='preserve'; code='historical_policy_invalid' },
        @{ property='typed_core_production_status'; value='not_started'; code='typed_core_boundary_invalid' },
        @{ property='p6_admission_status'; value='hold'; code='p6_status_invalid' },
        @{ property='live_acceptance_status'; value='not_run'; code='live_status_invalid' }
    )) {
        if ([string]$manifest.($check.property) -ne $check.value) {
            Add-Finding $check.code $paths.manifest ("{0} must be {1}." -f $check.property, $check.value)
        }
    }

    $tasks = @($manifest.tasks)
    $actualTaskSet = (@($tasks | ForEach-Object { [string]$_.id } | Sort-Object) -join ',')
    $expectedTaskSet = (@($expectedTaskIds | Sort-Object) -join ',')
    if ($actualTaskSet -ne $expectedTaskSet) {
        Add-Finding 'task_set_invalid' $paths.manifest 'Manifest must contain exactly SMV-PS7-001 through SMV-PS7-005.'
    }
    foreach ($task in $tasks) {
        if ([string]$task.status -eq 'done') { $doneCount++ }
        else { Add-Finding 'task_not_done' $paths.manifest ("Task is not done: {0}" -f [string]$task.id) }
        if ([string]$task.evidence_group -ne 'powershell7_runtime_migration') {
            Add-Finding 'evidence_group_invalid' $paths.manifest ("Task evidence group drifted: {0}" -f [string]$task.id)
        }
    }
}

$versionPattern = '(?m)^#requires\s+-Version\s+7\.0\s*$'
foreach ($key in @('version', 'build', 'installer', 'generated')) {
    Require-Pattern $content[$key] $versionPattern $paths[$key] 'powershell_version_floor_invalid' ("{0} must require PowerShell 7.0." -f $paths[$key])
}

if (-not [string]::IsNullOrWhiteSpace($content.generated)) {
    $generatedPath = Join-Path $root $paths.generated
    $bytes = [System.IO.File]::ReadAllBytes($generatedPath)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
        Add-Finding 'generated_encoding_invalid' $paths.generated 'Generated bundle must keep deterministic UTF-8 BOM encoding.'
    }
}

Reject-Pattern $content.core '(?i)CODEX_ALLOW_WINDOWS_POWERSHELL|Get-Command\s+powershell(?:\.exe)?' $paths.core 'legacy_fallback_detected' 'Core must not resolve or authorize Windows PowerShell.'
Reject-Pattern $content.installer '(?i)Get-Command\s+powershell(?:\.exe)?|&\s*[''\"]?powershell(?:\.exe)?' $paths.installer 'legacy_fallback_detected' 'Installer must not resolve or invoke Windows PowerShell.'
Reject-Pattern $content.cmd '(?i)POWERSHELL_EXE=powershell\.exe|where\s+powershell(?:\.exe)?|\bpause\b' $paths.cmd 'legacy_fallback_detected' 'CMD wrapper must resolve only pwsh and must not pause.'
Reject-Pattern $content.mcp '(?i)["'']powershell\.exe["'']' $paths.mcp 'legacy_fallback_detected' 'MCP environment wrapper must invoke pwsh.exe only.'
Reject-Pattern $content.generated '(?i)CODEX_ALLOW_WINDOWS_POWERSHELL|(?:Get-Command|Start-Process)\s+(?:-FilePath\s+)?["'']?powershell(?:\.exe)?["'']?|&\s*["'']?powershell(?:\.exe)?["'']?|["'']powershell\.exe["'']' $paths.generated 'legacy_fallback_detected' 'Generated bundle contains a legacy runtime execution path.'

$powershellFilesScanned = Test-ActivePowerShellEstate

Require-Literal $content.cmd 'PowerShell 7+ (pwsh) is required' $paths.cmd 'cmd_diagnostic_missing'
Require-Literal $content.mcp '"pwsh.exe"' $paths.mcp 'mcp_pwsh_wrapper_missing'
Require-Literal $content.build 'deterministic UTF-8 BOM' $paths.build 'build_encoding_contract_missing'

Reject-Pattern $content.github '(?i)Windows PowerShell 5\.1|shell:\s*powershell(?:\s|$)' $paths.github 'legacy_ci_detected' 'GitHub Actions must not contain a Windows PowerShell job or shell.'
Reject-Pattern $content.azure '(?im)Windows PowerShell 5\.1|^-\s*powershell:' $paths.azure 'legacy_ci_detected' 'Azure Pipelines must not contain a Windows PowerShell task.'
Reject-Pattern $content.gitlab '(?i)powershell\.exe' $paths.gitlab 'legacy_ci_detected' 'GitLab CI must not invoke powershell.exe.'
Require-Literal $content.github 'Verify PowerShell 7 runtime' $paths.github 'ps7_ci_missing'
Require-Literal $content.azure 'Verify PowerShell 7 runtime' $paths.azure 'ps7_ci_missing'
Require-Literal $content.gitlab 'pwsh -NoProfile' $paths.gitlab 'ps7_ci_missing'

foreach ($required in @(
    @{ key='spec'; literal='**RUNTIME_POLICY**: `ps7_only`'; code='current_policy_missing' },
    @{ key='manifest'; literal='"runtime_policy": "ps7_only"'; code='current_policy_missing' },
    @{ key='lean'; literal='POWERSHELL_COMPATIBILITY_STATUS: ps7_only'; code='current_policy_missing' },
    @{ key='roadmap'; literal='`powershell7_runtime_migration`'; code='current_policy_missing' },
    @{ key='agents'; literal='runtime 为 PS7-only'; code='current_policy_missing' },
    @{ key='release'; literal='PowerShell 7 (`pwsh`) only'; code='release_policy_missing' },
    @{ key='runbook'; literal='Migration guide'; code='migration_guide_missing' },
    @{ key='runbook'; literal='Rollback'; code='rollback_missing' },
    @{ key='runbook'; literal='powershell-support-lifecycle'; code='official_reference_missing' },
    @{ key='runbook'; literal='migrating-from-windows-powershell-51-to-powershell-7'; code='official_reference_missing' },
    @{ key='evidence'; literal='Typed-core TC2 / production integration: `not_started`'; code='evidence_boundary_missing' },
    @{ key='quality'; literal="Invoke-QualityGate 'powershell-runtime-policy'"; code='full_gate_integration_missing' }
)) {
    Require-Literal $content[$required.key] $required.literal $paths[$required.key] $required.code
}

foreach ($key in @('lean', 'agents', 'roadmap')) {
    Reject-Pattern $content[$key] 'ps7_primary_ps51_bounded_smoke' $paths[$key] 'stale_current_policy_detected' 'A current truth surface still claims the retired compatibility policy.'
}

Require-Pattern $content.historicalManifest 'PowerShell 5\.1|PS5\.1|5\.1 bounded smoke' $paths.historicalManifest 'historical_truth_missing' 'Historical Phase 0 compatibility evidence must remain traceable.'

try {
    $typed = $content.typedManifest | ConvertFrom-Json
    if ([string]$typed.tc2_status -ne 'not_started' -or [string]$typed.production_integration_status -ne 'not_started' -or [string]$typed.powershell_runtime_status -ne 'authoritative') {
        Add-Finding 'typed_core_boundary_invalid' $paths.typedManifest 'PS7-only shell support must not advance TC2 or typed-core production integration.'
    }
}
catch { Add-Finding 'typed_core_manifest_invalid' $paths.typedManifest $_.Exception.Message }

$currentP6AdmissionStatus = if ($content.roadmap.IndexOf('P6_ADMISSION_STATUS: admitted', [System.StringComparison]::Ordinal) -ge 0) {
    'admitted'
}
elseif ($content.roadmap.IndexOf('P6_ADMISSION_STATUS: hold', [System.StringComparison]::Ordinal) -ge 0) {
    'hold'
}
else {
    Add-Finding 'roadmap_p6_admission_missing' $paths.roadmap 'Roadmap must declare the current P6 admission status.'
    'unknown'
}
if ($currentP6AdmissionStatus -eq 'hold' -and (Test-Path -LiteralPath (Join-Path $root 'tasks/skills-manager-vnext-phase6.tasks.json'))) {
    Add-Finding 'p6_manifest_forbidden' 'tasks/skills-manager-vnext-phase6.tasks.json' 'P6 manifest is forbidden while admission remains hold.'
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    track = 'powershell7_runtime_migration'
    runtime_policy = if ($null -ne $manifest) { [string]$manifest.runtime_policy } else { 'unknown' }
    tasks = 5
    done = $doneCount
    historical_evidence = 'preserved'
    typed_core_production_status = 'not_started'
    current_p6_admission_status = $currentP6AdmissionStatus
    powershell_files_scanned = $powershellFilesScanned
    writes_performed = 0
    findings = $findings.ToArray()
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
}
else {
    foreach ($finding in $findings) {
        Write-Host ("[{0}] {1}: {2}" -f $finding.code, $finding.path, $finding.message)
    }
    Write-Host ("PowerShell runtime policy: status={0}; policy={1}; tasks={2}/{3}; findings={4}" -f $result.status, $result.runtime_policy, $result.done, $result.tasks, $findings.Count)
}

if ($findings.Count -gt 0) { exit 1 }
exit 0
