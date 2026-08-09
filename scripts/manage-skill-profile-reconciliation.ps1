[CmdletBinding()]
param(
    [ValidateSet("Plan", "Migrate", "RollbackMigration", "Apply", "Accept", "Rollback")][string]$Mode = "Plan",
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ProposalPath = "",
    [string]$ReceiptPath = "",
    [string]$ReplayReportPath = "",
    [string]$CorpusPath = "",
    [string]$Token = "",
    [ValidateRange(1, 20)][int]$MaxSkillChanges = 5,
    [ValidateRange(1, 50)][int]$MaxActions = 10,
    [ValidateRange(0, 2000)][int]$MinBudgetHeadroomChars = 256,
    [switch]$RollbackOnFailure,
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$entry = Join-Path $root "skills.ps1"
$configPath = Join-Path $root "skills.json"

function Resolve-ReceiptFile([string]$Path, [bool]$MustExist) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($MustExist) { throw "ReceiptPath is required." }
        return (Join-Path $root ("reports\skill-profile-reconciliation\{0}-receipt.json" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff")))
    }
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) } else { [System.IO.Path]::GetFullPath((Join-Path $root $Path)) }
    if ($MustExist -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Receipt file does not exist: $full" }
    return $full
}

function New-RetiredProfileReconciliationResult([string]$ModeName, [string]$Message) {
    return [pscustomobject][ordered]@{
        schema_version = 1
        command = "manage-skill-profile-reconciliation"
        mode = $ModeName.ToLowerInvariant()
        status = "deprecated"
        pass = $false
        writes_performed = 0
        findings = @([pscustomobject]@{
                code = "profile_reconciliation_retired"
                message = $Message
                blocking = $true
            })
    }
}

try {
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "skills.ps1 is missing: $entry" }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "skills.json is missing: $configPath" }
    Push-Location $root
    try {
        . $entry
    }
    finally { Pop-Location }
    $cfg = Get-ContentUtf8 $configPath | ConvertFrom-Json
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0) { throw "skills.json does not define skill_projection." }
    switch ($Mode) {
        "Plan" {
            if ([string]::IsNullOrWhiteSpace($ProposalPath)) {
                $result = New-SkillProfileMigrationPlan -Config $cfg -ConfigPath $configPath
            }
            else {
                $result = New-RetiredProfileReconciliationResult "Plan" "Profile canary proposal planning is retired; use the read-only migration plan without ProposalPath."
            }
        }
        "Migrate" {
            $receipt = Resolve-ReceiptFile $ReceiptPath $false
            $result = Invoke-SkillProfileMigration -ConfigPath $configPath -ReceiptPath $receipt -Token $Token
            if ([bool]$result.pass -and $null -ne $result.receipt) { $result | Add-Member -NotePropertyName receipt_path -NotePropertyValue $receipt -Force }
        }
        "RollbackMigration" {
            $receipt = Resolve-ReceiptFile $ReceiptPath $true
            $result = Invoke-SkillProfileMigrationRollback -ConfigPath $configPath -ReceiptPath $receipt -Token $Token
        }
        "Apply" {
            $result = New-RetiredProfileReconciliationResult "Apply" "Profile canary apply is retired; use explicit config migration with a versioned receipt."
        }
        "Accept" {
            $result = New-RetiredProfileReconciliationResult "Accept" "Profile canary acceptance is retired; use the read-only migration report and receipt."
        }
        "Rollback" {
            $receipt = Resolve-ReceiptFile $ReceiptPath $true
            $result = Invoke-SkillProfileReconciliationRollback -ConfigPath $configPath -ReceiptPath $receipt -Token $Token
        }
    }
}
catch {
    $result = [pscustomobject]@{
        schema_version = 1
        command = "manage-skill-profile-reconciliation"
        mode = $Mode.ToLowerInvariant()
        pass = $false
        status = "failed"
        writes_performed = 0
        findings = @([pscustomobject]@{ code = "manager_error"; message = $_.Exception.Message; blocking = $true })
    }
}

if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 50) }
elseif ([bool]$result.pass) { Write-Host ("Profile reconciliation {0} passed: status={1}" -f $Mode.ToLowerInvariant(), [string]$result.status) -ForegroundColor Green }
else { foreach ($finding in @($result.findings)) { Write-Host ("[{0}] {1}" -f [string]$finding.code, [string]$finding.message) -ForegroundColor Red } }

if (-not [bool]$result.pass -and -not $NoExit) { exit 2 }
