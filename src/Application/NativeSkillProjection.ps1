$nativeSkillProjectionRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . (Join-Path $nativeSkillProjectionRepoRoot 'src\Domain\OperationPlan.ps1') }
if ($null -eq (Get-Command New-NativeSkillProjectionPlan -ErrorAction SilentlyContinue)) { . (Join-Path $nativeSkillProjectionRepoRoot 'src\Application\SkillProjection.ps1') }
if ($null -eq (Get-Command Get-ExistingFileSystemItem -ErrorAction SilentlyContinue)) { . (Join-Path $nativeSkillProjectionRepoRoot 'src\Core.ps1') }

function Get-NativeSkillProjectionFileHash {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return ([string](Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}

function Get-NativeSkillProjectionLinkTarget {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
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
    $item = Get-ExistingFileSystemItem $directory
    if ($null -eq $item) {
        return [pscustomobject][ordered]@{
            exists = $false
            kind = 'missing'
            directory_path = $directory
            skill_path = $skillPath
            link_target = ''
            content_hash = ''
            package_hash = ''
        }
    }
    $isReparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    $skillExists = Test-Path -LiteralPath $skillPath -PathType Leaf
    return [pscustomobject][ordered]@{
        exists = $true
        kind = if ($isReparse) { 'junction' } else { 'directory' }
        directory_path = $directory
        skill_path = $skillPath
        link_target = if ($isReparse) { Get-NativeSkillProjectionLinkTarget $directory } else { '' }
        content_hash = if ($skillExists) { Get-NativeSkillProjectionFileHash $skillPath } else { '' }
        package_hash = if ($skillExists) { Get-NativeSkillProjectionPackageHash $directory } else { '' }
    }
}

function Ensure-NativeSkillProjectionDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Remove-NativeSkillProjectionPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-ExistingFileSystemItem $Path
    if ($null -eq $item) { return }
    if ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $item.PSIsContainer) { Remove-Item -LiteralPath $Path -Force }
    else { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Test-NativeSkillProjectionStateEquivalent($Expected, $Actual) {
    if ($null -eq $Expected -or $null -eq $Actual) { return $false }
    foreach ($field in @('exists', 'kind', 'directory_path', 'link_target', 'content_hash', 'package_hash')) {
        if (-not [string]::Equals([string](Get-OperationObjectProperty $Expected $field), [string](Get-OperationObjectProperty $Actual $field), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
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

    $linkParent = Split-Path -Parent ([IO.Path]::GetFullPath($LinkPath))
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $linkParent ([IO.Path]::GetPathRoot($linkParent))
    Assert-NativeSkillProjectionPathHasNoReparseAncestor ([IO.Path]::GetFullPath($TargetPath)) ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($TargetPath)))
    Ensure-NativeSkillProjectionDirectory (Split-Path -Parent $LinkPath)
    if (Get-Command New-Junction -ErrorAction SilentlyContinue) {
        New-Junction $LinkPath $TargetPath -QuietIfUnchanged
        return
    }
    New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
}

function Get-NativeSkillProjectionReceiptPath {
    param($Plan, [string]$ReceiptPath)

    $path = if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { [string]$Plan.receipt_path } else { $ReceiptPath }
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'Projection receipt path is required.' }
    $path = [IO.Path]::GetFullPath($path)
    if (-not [string]::Equals($path, [IO.Path]::GetFullPath([string]$Plan.receipt_path), [StringComparison]::OrdinalIgnoreCase)) { throw 'Native projection receipt override must equal the path authorized by the plan.' }
    $receiptRoot = [IO.Path]::GetFullPath((Join-Path $nativeSkillProjectionRepoRoot 'reports\skill-projection'))
    if (-not (Test-NativeSkillProjectionPathWithinRoot $path $receiptRoot) -or [string]::Equals($path.TrimEnd('\', '/'), $receiptRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Native projection receipt must be a file under reports/skill-projection.' }
    Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path $path -Parent) $receiptRoot
    $receiptItem = Get-ExistingFileSystemItem $path
    if ($null -ne $receiptItem) {
        if ($receiptItem.PSIsContainer -or ($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Native projection receipt must be a regular file.' }
    }
    return $path
}

function Apply-NativeSkillProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [string]$ReceiptPath = '',
        [switch]$SkipLock
    )

    if (-not $SkipLock) {
        return (Invoke-WithSkillManagerProjectionLock -ScriptBlock {
            Apply-NativeSkillProjection -Plan $Plan -ReceiptPath $ReceiptPath -SkipLock
        })
    }

    $contract = Test-NativeSkillProjectionPlanContract $Plan
    if (-not [bool]$contract.pass) { throw ('Projection plan contract failed: {0}' -f (@($contract.findings | ForEach-Object code) -join ', ')) }
    if ([string]$Plan.status -ne 'ready' -or -not [bool]$Plan.pass) { throw 'Only a ready native projection plan can be applied.' }

    # Validate every write boundary before the first directory creation.  In
    # particular, a caller-supplied receipt override must not leave an empty
    # target root behind when it is rejected.
    $receiptFile = Get-NativeSkillProjectionReceiptPath $Plan $ReceiptPath
    $targetRoot = [IO.Path]::GetFullPath([string]$Plan.target_root)
    $targetRootItem = Get-ExistingFileSystemItem $targetRoot
    $targetRootExisted = $null -ne $targetRootItem
    if ($targetRootExisted) {
        if (-not $targetRootItem.PSIsContainer) { throw ('Projection target root is not a directory: {0}' -f $targetRoot) }
        if (($targetRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('Projection target root must not be a reparse point: {0}' -f $targetRoot) }
    }
    Assert-NativeSkillProjectionPathHasNoReparseAncestor $targetRoot ([IO.Path]::GetPathRoot($targetRoot))
    $affectedDirectories = @(@($Plan.skills | ForEach-Object { [string]$_.target_directory }) + @($Plan.removals | ForEach-Object { [string]$_.target_directory }) | Sort-Object -Unique)
    $before = @($affectedDirectories | ForEach-Object { Get-NativeSkillProjectionTargetState $_ })
    $changedNames = New-Object System.Collections.Generic.List[string]
    $createdDirectories = New-Object System.Collections.Generic.List[string]
    $removedDirectories = New-Object System.Collections.Generic.List[object]
    $mutations = New-Object System.Collections.Generic.List[object]
    $temporaryPaths = New-Object System.Collections.Generic.List[object]
    $targetRootCreationClaimed = -not $targetRootExisted
    try {
        if ($targetRootCreationClaimed) {
            try {
                # Do not use -Force here.  A no-force create gives us an
                # ownership boundary: if another writer created the root
                # after the preflight observation, the path is treated as
                # external and must not be removed during rollback.
                New-Item -ItemType Directory -Path $targetRoot -ErrorAction Stop | Out-Null
            }
            catch {
                # Clear the claim before inspecting the raced path.  If the
                # inspection itself fails, the outer rollback must preserve
                # the root rather than risk deleting an unowned path.
                $targetRootCreationClaimed = $false
                $racedRoot = Get-ExistingFileSystemItem $targetRoot
                if ($null -eq $racedRoot) { throw }
            }
            $rootItem = Get-ExistingFileSystemItem $targetRoot
            if ($null -eq $rootItem -or -not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'projection target root is not a regular directory after creation'
            }
            Assert-NativeSkillProjectionPathHasNoReparseAncestor $targetRoot ([IO.Path]::GetPathRoot($targetRoot))
        }

        foreach ($skill in @($Plan.skills | Sort-Object name)) {
            $sourcePath = [IO.Path]::GetFullPath([string]$skill.source_path)
            $sourceDirectory = [IO.Path]::GetFullPath([string]$skill.source_directory)
            $targetDirectory = [IO.Path]::GetFullPath([string]$skill.target_directory)
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ('Projection source drifted: {0}' -f $sourcePath) }
            if (-not [string]::Equals((Get-NativeSkillProjectionFileHash $sourcePath), [string]$skill.content_hash, [StringComparison]::OrdinalIgnoreCase)) { throw ('Projection source hash drifted: {0}' -f $sourcePath) }
            Assert-NativeSkillProjectionPackageTreeHasNoReparse $sourceDirectory ([IO.Path]::GetPathRoot($sourceDirectory))
            if (-not [string]::Equals((Get-NativeSkillProjectionPackageHash $sourceDirectory), [string]$skill.package_hash, [StringComparison]::OrdinalIgnoreCase)) { throw ('Projection package hash drifted: {0}' -f $sourceDirectory) }
            if (-not (Test-OperationPathWithinRoot $targetDirectory $targetRoot)) { throw ('Projection target escaped the owned root: {0}' -f $targetDirectory) }
            Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $targetDirectory) $targetRoot
            $current = Get-NativeSkillProjectionTargetState $targetDirectory
            if ([bool]$current.exists) {
                if ([string]$current.kind -eq 'junction' -and [string]::Equals([string]$current.link_target, $sourceDirectory, [StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$current.content_hash, [string]$skill.content_hash, [StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$current.package_hash, [string]$skill.package_hash, [StringComparison]::OrdinalIgnoreCase)) { continue }
                throw ('Projection target conflict or drift: {0}' -f $targetDirectory)
            }
            $temporaryPath = Join-Path $targetRoot ('.skills-manager-native-projection-{0}' -f ([guid]::NewGuid().ToString('N')))
            $temporaryRecord = [pscustomobject]@{ path = $temporaryPath; target = $sourceDirectory }
            $temporaryPaths.Add($temporaryRecord) | Out-Null
            New-NativeSkillProjectionJunction $temporaryPath $sourceDirectory
            Move-Item -LiteralPath $temporaryPath -Destination $targetDirectory
            $temporaryPaths.Remove($temporaryRecord) | Out-Null
            $expectedAfter = [pscustomobject][ordered]@{
                exists = $true
                kind = 'junction'
                directory_path = $targetDirectory.TrimEnd('\', '/')
                skill_path = Join-Path $targetDirectory 'SKILL.md'
                link_target = $sourceDirectory.TrimEnd('\', '/')
                content_hash = [string]$skill.content_hash
                package_hash = [string]$skill.package_hash
            }
            $mutations.Add([pscustomobject][ordered]@{ operation = 'create'; path = $targetDirectory; target_root = $targetRoot; before = $current; after = $expectedAfter }) | Out-Null
            if (-not (Test-NativeSkillProjectionStateEquivalent $expectedAfter (Get-NativeSkillProjectionTargetState $targetDirectory))) { throw ('Projection target creation verification failed: {0}' -f $targetDirectory) }
            $createdDirectories.Add($targetDirectory) | Out-Null
            $changedNames.Add([string]$skill.name) | Out-Null
        }

        foreach ($removal in @($Plan.removals | Sort-Object name)) {
            $targetDirectory = [IO.Path]::GetFullPath([string]$removal.target_directory)
            if (-not (Test-OperationPathWithinRoot $targetDirectory $targetRoot)) { throw ('Projection removal escaped the owned root: {0}' -f $targetDirectory) }
            Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $targetDirectory) $targetRoot
            $current = Get-NativeSkillProjectionTargetState $targetDirectory
            if (-not [bool]$current.exists) { continue }
            if ([string]$current.kind -ne 'junction' -or -not [string]::Equals([string]$current.link_target, [string]$removal.previous_link_target, [StringComparison]::OrdinalIgnoreCase)) { throw ('Projection stale target drifted: {0}' -f $targetDirectory) }
            $expectedAfter = [pscustomobject][ordered]@{
                exists = $false
                kind = 'missing'
                directory_path = $targetDirectory.TrimEnd('\', '/')
                skill_path = Join-Path $targetDirectory 'SKILL.md'
                link_target = ''
                content_hash = ''
                package_hash = ''
            }
            $mutations.Add([pscustomobject][ordered]@{ operation = 'remove'; path = $targetDirectory; target_root = $targetRoot; before = $current; after = $expectedAfter }) | Out-Null
            $removedDirectories.Add($current) | Out-Null
            Remove-NativeSkillProjectionPath $targetDirectory
            $changedNames.Add([string]$removal.name) | Out-Null
        }

        $after = @($affectedDirectories | ForEach-Object { Get-NativeSkillProjectionTargetState $_ })
        foreach ($skill in @($Plan.skills)) {
            $state = @($after | Where-Object directory_path -eq ([IO.Path]::GetFullPath([string]$skill.target_directory).TrimEnd('\', '/')))[0]
            if ($null -eq $state -or -not [string]::Equals([string]$state.content_hash, [string]$skill.content_hash, [StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$state.package_hash, [string]$skill.package_hash, [StringComparison]::OrdinalIgnoreCase)) { throw ('Projection target hash verification failed: {0}' -f $skill.name) }
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
            added_names = [object[]]@($createdDirectories | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
            removed_names = [object[]]@($removedDirectories | ForEach-Object { Split-Path ([string]$_.directory_path) -Leaf } | Sort-Object)
            provider_calls = 0
            native_mutations = $createdDirectories.Count + $removedDirectories.Count
            writes = $createdDirectories.Count + $removedDirectories.Count
        }
        if (Test-NativeSkillProjectionReceiptContract $receipt | Select-Object -ExpandProperty pass) { Write-NativeSkillProjectionJsonAtomic $receiptFile $receipt } else { throw 'Generated native projection receipt failed its contract.' }
        return [pscustomobject][ordered]@{
            status = 'applied'
            receipt_id = $receiptId
            plan_id = [string]$Plan.plan_id
            receipt_path = $receiptFile
            changed_names = [object[]]@($changedNames.ToArray() | Sort-Object)
            receipt = $receipt
        }
    }
    catch {
        $failure = $_
        $rollbackErrors = New-Object System.Collections.Generic.List[string]
        foreach ($temporaryRecord in @($temporaryPaths.ToArray())) {
            try {
                $temporaryPath = [string]$temporaryRecord.path
                $temporaryState = Get-NativeSkillProjectionTargetState $temporaryPath
                if (-not $temporaryState.exists) { continue }
                if ([string]$temporaryState.kind -ne 'junction' -or -not [string]::Equals([string]$temporaryState.link_target, [string]$temporaryRecord.target, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'temporary projection path was changed by another writer'
                }
                Remove-NativeSkillProjectionPath $temporaryPath
                if ((Get-NativeSkillProjectionTargetState $temporaryPath).exists) { throw 'temporary projection path remains after cleanup' }
            }
            catch { $rollbackErrors.Add(('temporary:{0} => {1}' -f [string]$temporaryRecord.path, $_.Exception.Message)) | Out-Null }
        }
        for ($mutationIndex = $mutations.Count - 1; $mutationIndex -ge 0; $mutationIndex--) {
            try {
                $mutation = $mutations[$mutationIndex]
                $path = [string]$mutation.path
                $current = Get-NativeSkillProjectionTargetState $path
                if (Test-NativeSkillProjectionStateEquivalent $mutation.before $current) { continue }
                if (-not (Test-NativeSkillProjectionStateEquivalent $mutation.after $current)) { throw ('projection rollback conflict: current state is neither before nor after: {0}' -f $path) }
                Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path -Parent $path) ([string]$mutation.target_root)
                if ([bool]$mutation.after.exists) {
                    if ([string]$mutation.after.kind -ne 'junction') { throw ('projection rollback refuses to remove a non-junction after-state: {0}' -f $path) }
                    Remove-NativeSkillProjectionPath $path
                }
                if ([bool]$mutation.before.exists) {
                    if ([string]$mutation.before.kind -ne 'junction') { throw ('projection rollback refuses to recreate a non-junction before-state: {0}' -f $path) }
                    New-NativeSkillProjectionJunction $path ([string]$mutation.before.link_target)
                }
                if (-not (Test-NativeSkillProjectionStateEquivalent $mutation.before (Get-NativeSkillProjectionTargetState $path))) { throw ('projection rollback verification failed: {0}' -f $path) }
            }
            catch { $rollbackErrors.Add(('mutation:{0} => {1}' -f [string]$mutation.path, $_.Exception.Message)) | Out-Null }
        }

        if ($targetRootCreationClaimed) {
            try {
                $rootItem = Get-ExistingFileSystemItem $targetRoot
                if ($null -ne $rootItem) {
                    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'created target root is no longer a regular directory' }
                    if (@(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction Stop).Count -gt 0) { throw 'created target root is not empty after rollback' }
                    Remove-Item -LiteralPath $targetRoot -Force -ErrorAction Stop
                    if ((Get-NativeSkillProjectionTargetState $targetRoot).exists) { throw 'created target root remains after cleanup' }
                }
            }
            catch { $rollbackErrors.Add(('target-root:{0} => {1}' -f $targetRoot, $_.Exception.Message)) | Out-Null }
        }

        foreach ($expected in @($before)) {
            try {
                $actual = Get-NativeSkillProjectionTargetState ([string]$expected.directory_path)
                if (-not (Test-NativeSkillProjectionStateEquivalent $expected $actual)) { throw 'projection target differs from its pre-apply state' }
            }
            catch { $rollbackErrors.Add(('verify:{0} => {1}' -f [string]$expected.directory_path, $_.Exception.Message)) | Out-Null }
        }

        $afterRollback = @($affectedDirectories | ForEach-Object { Get-NativeSkillProjectionTargetState $_ })
        $rollbackStatus = if ($rollbackErrors.Count -eq 0) { 'rolled_back' } else { 'rollback_failed' }
        $receiptIdentity = [ordered]@{ plan_id = [string]$Plan.plan_id; target_root = $targetRoot; changed_names = @($changedNames.ToArray()); status = $rollbackStatus }
        $receiptId = 'nsr-{0}' -f (Get-OperationSha256 ($receiptIdentity | ConvertTo-Json -Depth 20 -Compress)).Substring(0, 16)
        $recoveryReceipt = [pscustomobject][ordered]@{
            schema_version = 1
            receipt_id = $receiptId
            status = $rollbackStatus
            owner = [string]$Plan.owner
            plan_id = [string]$Plan.plan_id
            target_root = $targetRoot
            receipt_path = $receiptFile
            applied_at = [DateTimeOffset]::UtcNow.ToString('o')
            before = [object[]]$before
            after = [object[]]$afterRollback
            changed_names = [object[]]@($changedNames.ToArray() | Sort-Object)
            added_names = [object[]]@($createdDirectories | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
            removed_names = [object[]]@($removedDirectories | ForEach-Object { Split-Path ([string]$_.directory_path) -Leaf } | Sort-Object)
            provider_calls = 0
            native_mutations = $createdDirectories.Count + $removedDirectories.Count
            writes = $createdDirectories.Count + $removedDirectories.Count
            failure_message = $failure.Exception.Message
            rollback_errors = @($rollbackErrors.ToArray())
            recovery_required = ($rollbackErrors.Count -gt 0)
        }
        try {
            $validatedReceiptFile = Get-NativeSkillProjectionReceiptPath $Plan $receiptFile
            if (-not [string]::Equals($validatedReceiptFile, $receiptFile, [StringComparison]::OrdinalIgnoreCase)) { throw 'recovery receipt path changed during rollback' }
            Write-NativeSkillProjectionJsonAtomic $receiptFile $recoveryReceipt
        }
        catch { $rollbackErrors.Add(('receipt:{0} => {1}' -f $receiptFile, $_.Exception.Message)) | Out-Null }

        if ($rollbackErrors.Count -gt 0) {
            throw ('Native skill projection failed: {0}; rollback/recovery required: {1}; receipt: {2}' -f $failure.Exception.Message, ($rollbackErrors -join ' | '), $receiptFile)
        }
        throw $failure
    }
}

function Test-NativeSkillProjectionReceiptContract {
    param($Receipt)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Receipt) { return New-OperationValidationResult @((New-OperationFinding 'receipt_missing' 'error' '$' 'Projection receipt is required.')) }
    if ((Get-OperationObjectProperty $Receipt 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only receipt schema version 1 is supported.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Receipt 'receipt_id') -notmatch '^nsr-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'receipt_id_invalid' 'error' '$.receipt_id' 'Receipt id is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Receipt 'status') -notin @('applied', 'rolled_back', 'rollback_failed')) { $findings.Add((New-OperationFinding 'status_invalid' 'error' '$.status' 'Receipt status is invalid.')) | Out-Null }
    foreach ($field in @('owner', 'plan_id', 'target_root', 'receipt_path')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Receipt field is required.')) | Out-Null } }
    foreach ($field in @('before', 'after', 'changed_names', 'added_names', 'removed_names')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding 'array_field_invalid' 'error' ('$.{0}' -f $field) 'Receipt field must be an array.')) | Out-Null } }
    if ([long](Get-OperationObjectProperty $Receipt 'provider_calls') -ne 0) { $findings.Add((New-OperationFinding 'provider_calls_forbidden' 'error' '$.provider_calls' 'Projection cannot call a provider.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
