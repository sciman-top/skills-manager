$nativeSkillProjectionRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . (Join-Path $nativeSkillProjectionRepoRoot 'src\Domain\OperationPlan.ps1') }
if ($null -eq (Get-Command New-NativeSkillProjectionPlan -ErrorAction SilentlyContinue)) { . (Join-Path $nativeSkillProjectionRepoRoot 'src\Application\SkillProjection.ps1') }

function Get-NativeSkillProjectionFileHash {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return ([string](Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}

function Get-NativeSkillProjectionLinkTarget {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return '' }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return '' }
        $targetProperty = $item.PSObject.Properties['Target']
        if ($null -eq $targetProperty) { return '' }
        $target = $targetProperty.Value
        if ($target -is [array]) { $target = @($target)[0] }
        if ([string]::IsNullOrWhiteSpace([string]$target)) { return '' }
        return [IO.Path]::GetFullPath([string]$target).TrimEnd('\', '/')
    }
    catch { return '' }
}

function Get-NativeSkillProjectionTargetState {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    $directory = [IO.Path]::GetFullPath($DirectoryPath).TrimEnd('\', '/')
    $skillPath = Join-Path $directory 'SKILL.md'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return [pscustomobject][ordered]@{
            exists = $false
            kind = 'missing'
            directory_path = $directory
            skill_path = $skillPath
            link_target = ''
            content_hash = ''
        }
    }
    $item = Get-Item -LiteralPath $directory -Force
    $isReparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    return [pscustomobject][ordered]@{
        exists = $true
        kind = if ($isReparse) { 'junction' } else { 'directory' }
        directory_path = $directory
        skill_path = $skillPath
        link_target = if ($isReparse) { Get-NativeSkillProjectionLinkTarget $directory } else { '' }
        content_hash = Get-NativeSkillProjectionFileHash $skillPath
    }
}

function Ensure-NativeSkillProjectionDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Remove-NativeSkillProjectionPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $item.PSIsContainer) { Remove-Item -LiteralPath $Path -Force }
    else { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Test-NativeSkillProjectionStateEqual {
    param($Expected, $Actual)

    if ([bool]$Expected.exists -ne [bool]$Actual.exists) { return $false }
    if (-not [bool]$Expected.exists) { return $true }
    if ([string]$Expected.kind -ne [string]$Actual.kind) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Expected.link_target) -and -not [string]::Equals([string]$Expected.link_target, [string]$Actual.link_target, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Expected.content_hash) -and -not [string]::Equals([string]$Expected.content_hash, [string]$Actual.content_hash, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return $true
}

function Write-NativeSkillProjectionJsonAtomic {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)

    Ensure-NativeSkillProjectionDirectory (Split-Path -Parent $Path)
    $temporaryPath = '{0}.tmp.{1}' -f $Path, ([guid]::NewGuid().ToString('N'))
    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $encoding)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function New-NativeSkillProjectionJunction {
    param([Parameter(Mandatory = $true)][string]$LinkPath, [Parameter(Mandatory = $true)][string]$TargetPath)

    Ensure-NativeSkillProjectionDirectory (Split-Path -Parent $LinkPath)
    if (Get-Command New-Junction -ErrorAction SilentlyContinue) {
        New-Junction $LinkPath $TargetPath -QuietIfUnchanged
        return
    }
    New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
}

function Restore-NativeSkillProjectionBeforeState {
    param([object[]]$Before, [string]$TargetRoot)

    foreach ($state in @($Before | Sort-Object directory_path)) {
        $directory = [IO.Path]::GetFullPath([string]$state.directory_path)
        if (-not (Test-OperationPathWithinRoot $directory $TargetRoot)) { throw 'Projection rollback target escaped the owned root.' }
        if (-not [bool]$state.exists) {
            Remove-NativeSkillProjectionPath $directory
            continue
        }
        if ([string]$state.kind -ne 'junction' -or [string]::IsNullOrWhiteSpace([string]$state.link_target)) { throw ('Unsupported pre-transaction target state: {0}' -f $directory) }
        Remove-NativeSkillProjectionPath $directory
        New-NativeSkillProjectionJunction $directory ([string]$state.link_target)
    }
}

function Get-NativeSkillProjectionReceiptPath {
    param($Plan, [string]$ReceiptPath)

    $path = if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { [string]$Plan.receipt_path } else { $ReceiptPath }
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'Projection receipt path is required.' }
    return [IO.Path]::GetFullPath($path)
}

function Apply-NativeSkillProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$ApplyToken,
        [string]$ReceiptPath = ''
    )

    $contract = Test-NativeSkillProjectionPlanContract $Plan
    if (-not [bool]$contract.pass) { throw ('Projection plan contract failed: {0}' -f (@($contract.findings | ForEach-Object code) -join ', ')) }
    if ([string]$Plan.status -ne 'ready' -or -not [bool]$Plan.pass) { throw 'Only a ready native projection plan can be applied.' }
    if ([bool]$Plan.apply_requires_token -and -not [string]::Equals($ApplyToken, [string]$Plan.apply_token, [StringComparison]::Ordinal)) { throw 'Native projection apply token is invalid.' }

    $targetRoot = [IO.Path]::GetFullPath([string]$Plan.target_root)
    Ensure-NativeSkillProjectionDirectory $targetRoot
    $receiptFile = Get-NativeSkillProjectionReceiptPath $Plan $ReceiptPath
    $before = @($Plan.skills | Sort-Object target_directory | ForEach-Object { Get-NativeSkillProjectionTargetState ([string]$_.target_directory) })
    $changedNames = New-Object System.Collections.Generic.List[string]
    $createdDirectories = New-Object System.Collections.Generic.List[string]
    $temporaryPaths = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($skill in @($Plan.skills | Sort-Object name)) {
            $sourcePath = [IO.Path]::GetFullPath([string]$skill.source_path)
            $sourceDirectory = [IO.Path]::GetFullPath([string]$skill.source_directory)
            $targetDirectory = [IO.Path]::GetFullPath([string]$skill.target_directory)
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ('Projection source drifted: {0}' -f $sourcePath) }
            if (-not [string]::Equals((Get-NativeSkillProjectionFileHash $sourcePath), [string]$skill.content_hash, [StringComparison]::OrdinalIgnoreCase)) { throw ('Projection source hash drifted: {0}' -f $sourcePath) }
            if (-not (Test-OperationPathWithinRoot $targetDirectory $targetRoot)) { throw ('Projection target escaped the owned root: {0}' -f $targetDirectory) }
            $current = Get-NativeSkillProjectionTargetState $targetDirectory
            if ([bool]$current.exists) {
                if ([string]$current.kind -eq 'junction' -and [string]::Equals([string]$current.link_target, $sourceDirectory, [StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$current.content_hash, [string]$skill.content_hash, [StringComparison]::OrdinalIgnoreCase)) { continue }
                throw ('Projection target conflict or drift: {0}' -f $targetDirectory)
            }
            $temporaryPath = Join-Path $targetRoot ('.skills-manager-native-projection-{0}' -f ([guid]::NewGuid().ToString('N')))
            $temporaryPaths.Add($temporaryPath) | Out-Null
            New-NativeSkillProjectionJunction $temporaryPath $sourceDirectory
            Move-Item -LiteralPath $temporaryPath -Destination $targetDirectory
            $temporaryPaths.Remove($temporaryPath) | Out-Null
            $createdDirectories.Add($targetDirectory) | Out-Null
            $changedNames.Add([string]$skill.name) | Out-Null
        }

        $after = @($Plan.skills | Sort-Object target_directory | ForEach-Object { Get-NativeSkillProjectionTargetState ([string]$_.target_directory) })
        foreach ($index in 0..([Math]::Max(0, $after.Count - 1))) {
            if ($after.Count -eq 0) { break }
            $skill = @($Plan.skills | Sort-Object target_directory)[$index]
            if (-not [string]::Equals([string]$after[$index].content_hash, [string]$skill.content_hash, [StringComparison]::OrdinalIgnoreCase)) { throw ('Projection target hash verification failed: {0}' -f $skill.name) }
        }
        $receiptIdentity = [ordered]@{ plan_id = [string]$Plan.plan_id; target_root = $targetRoot; changed_names = @($changedNames.ToArray()) }
        $receiptId = 'nsr-{0}' -f (Get-OperationSha256 ($receiptIdentity | ConvertTo-Json -Depth 20 -Compress)).Substring(0, 16)
        $receipt = [pscustomobject][ordered]@{
            schema_version = 1
            receipt_id = $receiptId
            status = 'applied'
            owner = [string]$Plan.owner
            plan_id = [string]$Plan.plan_id
            target_root = $targetRoot
            receipt_path = $receiptFile
            applied_at = [DateTimeOffset]::UtcNow.ToString('o')
            before = [object[]]$before
            after = [object[]]$after
            changed_names = [object[]]@($changedNames.ToArray() | Sort-Object)
            notification = [ordered]@{
                method = [string]$Plan.notification.method
                mode = [string]$Plan.notification.mode
                status = 'not_sent'
                plan_status = [string]$Plan.notification.status
                changed_names = [object[]]@($changedNames.ToArray() | Sort-Object)
                host_mutation = $false
            }
            rollback = [ordered]@{ status = 'available'; guard = 'target_state_must_match_after'; drift_safe = $true }
            provider_calls = 0
            native_mutations = $createdDirectories.Count
            writes = $createdDirectories.Count
        }
        if (Test-NativeSkillProjectionReceiptContract $receipt | Select-Object -ExpandProperty pass) { Write-NativeSkillProjectionJsonAtomic $receiptFile $receipt } else { throw 'Generated native projection receipt failed its contract.' }
        return [pscustomobject][ordered]@{
            status = 'applied'
            receipt_id = $receiptId
            plan_id = [string]$Plan.plan_id
            receipt_path = $receiptFile
            changed_names = [object[]]@($changedNames.ToArray() | Sort-Object)
            notification = $receipt.notification
            receipt = $receipt
        }
    }
    catch {
        foreach ($temporaryPath in @($temporaryPaths.ToArray())) { Remove-NativeSkillProjectionPath $temporaryPath }
        foreach ($directory in @($createdDirectories.ToArray() | Sort-Object -Descending)) { Remove-NativeSkillProjectionPath $directory }
        throw
    }
}

function Test-NativeSkillProjectionReceiptContract {
    param($Receipt)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Receipt) { return New-OperationValidationResult @((New-OperationFinding 'receipt_missing' 'error' '$' 'Projection receipt is required.')) }
    if ((Get-OperationObjectProperty $Receipt 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only receipt schema version 1 is supported.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Receipt 'receipt_id') -notmatch '^nsr-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'receipt_id_invalid' 'error' '$.receipt_id' 'Receipt id is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Receipt 'status') -notin @('applied', 'rolled_back')) { $findings.Add((New-OperationFinding 'status_invalid' 'error' '$.status' 'Receipt status is invalid.')) | Out-Null }
    foreach ($field in @('owner', 'plan_id', 'target_root', 'receipt_path')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Receipt field is required.')) | Out-Null } }
    foreach ($field in @('before', 'after', 'changed_names')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding 'array_field_invalid' 'error' ('$.{0}' -f $field) 'Receipt field must be an array.')) | Out-Null } }
    if ([long](Get-OperationObjectProperty $Receipt 'provider_calls') -ne 0) { $findings.Add((New-OperationFinding 'provider_calls_forbidden' 'error' '$.provider_calls' 'Projection cannot call a provider.')) | Out-Null }
    $notification = Get-OperationObjectProperty $Receipt 'notification'
    if ([string](Get-OperationObjectProperty $notification 'method') -ne 'skills/changed') { $findings.Add((New-OperationFinding 'notification_method_invalid' 'error' '$.notification.method' 'Receipt notification method is invalid.')) | Out-Null }
    $rollback = Get-OperationObjectProperty $Receipt 'rollback'
    if ((Get-OperationObjectProperty $rollback 'drift_safe') -ne $true) { $findings.Add((New-OperationFinding 'rollback_guard_invalid' 'error' '$.rollback.drift_safe' 'Receipt rollback must be drift-safe.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}

function Rollback-NativeSkillProjection {
    [CmdletBinding()]
    param(
        $Receipt = $null,
        [string]$ReceiptPath = ''
    )

    if ($null -eq $Receipt) {
        if ([string]::IsNullOrWhiteSpace($ReceiptPath) -or -not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { throw 'Projection receipt was not found.' }
        $Receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
    }
    $contract = Test-NativeSkillProjectionReceiptContract $Receipt
    if (-not [bool]$contract.pass) { throw ('Projection receipt contract failed: {0}' -f (@($contract.findings | ForEach-Object code) -join ', ')) }
    if ([string]$Receipt.status -eq 'rolled_back') { return $Receipt }
    $targetRoot = [IO.Path]::GetFullPath([string]$Receipt.target_root)
    foreach ($expected in @($Receipt.after)) {
        $actual = Get-NativeSkillProjectionTargetState ([string]$expected.directory_path)
        if (-not (Test-NativeSkillProjectionStateEqual $expected $actual)) { throw ('rollback_drift_detected: {0}' -f [string]$expected.directory_path) }
    }
    try {
        Restore-NativeSkillProjectionBeforeState -Before @($Receipt.before) -TargetRoot $targetRoot
    }
    catch { throw }
    $Receipt.status = 'rolled_back'
    $rolledBackAt = [DateTimeOffset]::UtcNow.ToString('o')
    if ($null -ne $Receipt.PSObject.Properties['rolled_back_at']) { $Receipt.rolled_back_at = $rolledBackAt }
    else { $Receipt | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue $rolledBackAt }
    $Receipt.rollback.status = 'rolled_back'
    if (-not [string]::IsNullOrWhiteSpace($ReceiptPath)) { Write-NativeSkillProjectionJsonAtomic ([IO.Path]::GetFullPath($ReceiptPath)) $Receipt }
    return $Receipt
}
