function New-RuleFinding {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('deterministic', 'semantic')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][ValidateSet('info', 'warning', 'error')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message,
        [Nullable[int]]$Line,
        [object[]]$Evidence = @(),
        [ValidateRange(0.0, 1.0)][double]$Confidence = 1.0,
        [ValidateSet('adopt', 'adapt', 'reject', 'defer')][string]$Disposition = 'defer',
        [switch]$Blocking
    )
    if ($Kind -eq 'semantic' -and $Blocking) { throw 'Semantic findings cannot block.' }
    $identity = '{0}|{1}|{2}|{3}|{4}' -f $Kind, $Code.ToLowerInvariant(), $Path.ToLowerInvariant(), $Line, $Message
    return [pscustomobject][ordered]@{
        finding_id = 'finding-{0}' -f (Get-OperationSha256 $identity).Substring(0, 16)
        kind = $Kind; code = $Code; severity = $Severity; path = $Path
        line = if ($null -eq $Line) { $null } else { [int]$Line }
        message = $Message; evidence = @($Evidence); confidence = $Confidence
        disposition = $Disposition; blocking = [bool]$Blocking
    }
}

function New-RuleDocument {
    param(
        [Parameter(Mandatory = $true)][Alias('Host')][string]$HostName,
        [Parameter(Mandatory = $true)][ValidateSet('global', 'repo', 'subtree', 'override')][string]$Scope,
        [Parameter(Mandatory = $true)][ValidateSet('common', 'platform_delta', 'project_action', 'deterministic_enforcement', 'task_local')][string]$Responsibility,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Owner = 'unknown', [string]$ContentHash, [int]$ByteSize = 0, [Nullable[int]]$Precedence,
        [ValidateSet('observed', 'inferred', 'unknown')][string]$DiscoveryState = 'unknown',
        [Parameter(Mandatory = $true)][string]$SourceOfTruth,
        [object[]]$Findings = @(), [object[]]$Evidence = @(),
        [ValidateSet('not_verified', 'static_validated', 'repo_verified', 'host_loaded', 'live_accepted')][string]$VerificationState = 'not_verified'
    )
    if (-not [string]::IsNullOrWhiteSpace($ContentHash) -and $ContentHash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Content hash must be SHA-256 or empty.' }
    $identity = '{0}|{1}|{2}' -f $HostName.ToLowerInvariant(), $Scope, $Path.ToLowerInvariant()
    return [pscustomobject][ordered]@{
        schema_version = 1; id = 'rule-{0}' -f (Get-OperationSha256 $identity).Substring(0, 16)
        host = $HostName.ToLowerInvariant(); scope = $Scope; responsibility = $Responsibility; path = $Path; owner = $Owner
        content_hash = if ([string]::IsNullOrWhiteSpace($ContentHash)) { $null } else { $ContentHash.ToLowerInvariant() }
        byte_size = $ByteSize; precedence = if ($null -eq $Precedence) { $null } else { [int]$Precedence }
        discovery_state = $DiscoveryState; source_of_truth = $SourceOfTruth
        findings = @($Findings | Sort-Object finding_id); evidence = @($Evidence | Sort-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
        verification_state = $VerificationState
    }
}
