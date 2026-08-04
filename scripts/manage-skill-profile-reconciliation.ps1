[CmdletBinding()]
param(
    [ValidateSet("Plan", "Apply", "Accept", "Rollback")][string]$Mode = "Plan",
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

function Resolve-InputFile([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label path is required." }
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) } else { [System.IO.Path]::GetFullPath((Join-Path $root $Path)) }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Label file does not exist: $full" }
    return $full
}

function Resolve-ReceiptFile([string]$Path, [bool]$MustExist) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($MustExist) { throw "ReceiptPath is required." }
        return (Join-Path $root ("reports\skill-profile-reconciliation\{0}-receipt.json" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff")))
    }
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) } else { [System.IO.Path]::GetFullPath((Join-Path $root $Path)) }
    if ($MustExist -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Receipt file does not exist: $full" }
    return $full
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
            $proposal = Read-SkillProfileReconciliationProposal (Resolve-InputFile $ProposalPath "Proposal")
            $result = New-SkillProfileReconciliationApplyPlan -Config $cfg -ConfigPath $configPath -Proposal $proposal -MaxSkillChanges $MaxSkillChanges -MaxActions $MaxActions -MinBudgetHeadroomChars $MinBudgetHeadroomChars
        }
        "Apply" {
            $proposal = Read-SkillProfileReconciliationProposal (Resolve-InputFile $ProposalPath "Proposal")
            $receipt = Resolve-ReceiptFile $ReceiptPath $false
            $result = Invoke-SkillProfileReconciliationApply -Config $cfg -ConfigPath $configPath -Proposal $proposal -ReceiptPath $receipt -Token $Token -MaxSkillChanges $MaxSkillChanges -MaxActions $MaxActions -MinBudgetHeadroomChars $MinBudgetHeadroomChars
            if ([bool]$result.pass) { $result | Add-Member -NotePropertyName receipt_path -NotePropertyValue $receipt -Force }
        }
        "Accept" {
            $receipt = Resolve-ReceiptFile $ReceiptPath $true
            $report = Resolve-InputFile $ReplayReportPath "Replay report"
            $corpus = Resolve-InputFile $CorpusPath "Corpus"
            $result = Complete-SkillProfileReconciliationCanary -ConfigPath $configPath -ReceiptPath $receipt -ReplayReportPath $report -CorpusPath $corpus -Token $Token -RollbackOnFailure:$RollbackOnFailure
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
