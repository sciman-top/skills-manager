function Remove-RulePatchTransactionFile([string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path) -and [System.IO.File]::Exists($Path)) { [System.IO.File]::Delete($Path) }
}

function Invoke-RulePatchApply {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$BoundaryRoot,
        [Parameter(Mandatory = $true)][string]$Token,
        [ValidateSet('none', 'before_stage', 'after_stage', 'before_replace', 'after_replace', 'before_receipt', 'after_replace_rollback_failure')][string]$TestFaultPoint = 'none'
    )
    $guard = Test-RulePatchApplyGuard $Plan $BoundaryRoot $Token
    if (-not $guard.pass) { return [pscustomobject][ordered]@{ pass = $false; status = 'blocked'; findings = @($guard.findings); receipt = $null; writes = 0; rollback = 'not_required' } }
    $targetPath = [string]$guard.target_path
    $targetDir = [System.IO.Path]::GetDirectoryName($targetPath)
    $suffix = [string](Get-OperationObjectProperty $Plan 'patch_id')
    $stagePath = Join-Path $targetDir ('.{0}.stage' -f $suffix)
    $backupPath = Join-Path $targetDir ('.{0}.backup' -f $suffix)
    $operation = [string](Get-OperationObjectProperty (Get-OperationObjectProperty $Plan 'target') 'operation')
    $beforeBytes = if ($operation -eq 'update') { [System.IO.File]::ReadAllBytes($targetPath) } else { [byte[]]@() }
    $started = [datetimeoffset]::UtcNow.ToString('o')
    $replaced = $false; $rollbackState = 'not_required'; $failure = $null
    try {
        if ($TestFaultPoint -eq 'before_stage') { throw 'test_fault:before_stage' }
        $desiredBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes([string](Get-OperationObjectProperty $Plan 'desired_text'))
        [System.IO.File]::WriteAllBytes($stagePath, $desiredBytes)
        if ($TestFaultPoint -eq 'after_stage') { throw 'test_fault:after_stage' }
        if ($operation -eq 'update') {
            $freshText = [System.IO.File]::ReadAllText($targetPath)
            if ((Get-RulePatchTextHash $freshText) -ne [string](Get-OperationObjectProperty (Get-OperationObjectProperty $Plan 'target') 'before_hash')) { throw 'target_hash_stale_before_replace' }
        }
        elseif ([System.IO.File]::Exists($targetPath)) { throw 'create_target_appeared_before_replace' }
        if ($TestFaultPoint -eq 'before_replace') { throw 'test_fault:before_replace' }
        if ($operation -eq 'update') { [System.IO.File]::Replace($stagePath, $targetPath, $backupPath, $true) }
        else { [System.IO.File]::Move($stagePath, $targetPath) }
        $replaced = $true
        if ($TestFaultPoint -in @('after_replace', 'after_replace_rollback_failure')) { throw ('test_fault:{0}' -f $TestFaultPoint) }
        $appliedHash = Get-RulePatchTextHash ([System.IO.File]::ReadAllText($targetPath))
        if ($appliedHash -ne [string](Get-OperationObjectProperty (Get-OperationObjectProperty $Plan 'target') 'desired_hash')) { throw 'desired_hash_not_applied' }
        if ($TestFaultPoint -eq 'before_receipt') { throw 'test_fault:before_receipt' }
        Remove-RulePatchTransactionFile $backupPath
        $receipt = New-OperationReceipt -OperationId ([string](Get-OperationObjectProperty $Plan 'operation_id')) -Status applied -StartedAt $started -CompletedAt ([datetimeoffset]::UtcNow.ToString('o')) -Actions @([pscustomobject]@{ action_id = [string](Get-OperationObjectProperty $Plan 'patch_id'); status = 'applied'; target_ref = 'rule-target' }) -Verification ([pscustomobject]@{ static_validated = 'pass'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }) -Rollback @($(if ($operation -eq 'create') { 'delete_created_file' } else { 'restore_before_bytes' }))
        return [pscustomobject][ordered]@{ pass = $true; status = 'applied'; findings = @(); receipt = $receipt; writes = 1; rollback = 'not_required' }
    }
    catch {
        $failure = $_.Exception.Message
        if ($replaced) {
            if ($TestFaultPoint -eq 'after_replace_rollback_failure') { $rollbackState = 'rollback_failed' }
            else {
                try {
                    if ($operation -eq 'create') { [System.IO.File]::Delete($targetPath) }
                    else { Write-BytesAtomic -Path $targetPath -Bytes $beforeBytes }
                    $rollbackState = 'restored'
                }
                catch { $rollbackState = 'rollback_failed'; $failure = '{0}; rollback: {1}' -f $failure, $_.Exception.Message }
            }
        }
        $receiptStatus = if ($rollbackState -eq 'restored') { 'rolled_back' } else { 'failed' }
        $receipt = New-OperationReceipt -OperationId ([string](Get-OperationObjectProperty $Plan 'operation_id')) -Status $receiptStatus -StartedAt $started -CompletedAt ([datetimeoffset]::UtcNow.ToString('o')) -Actions @([pscustomobject]@{ action_id = [string](Get-OperationObjectProperty $Plan 'patch_id'); status = 'failed'; target_ref = 'rule-target'; error = $failure }) -Verification ([pscustomobject]@{ static_validated = 'fail'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }) -Rollback @([pscustomobject]@{ state = $rollbackState })
        return [pscustomobject][ordered]@{ pass = $false; status = $receiptStatus; findings = @([pscustomobject]@{ code = $failure; severity = 'error'; path = $targetPath; message = $failure }); receipt = $receipt; writes = $(if ($replaced) { 1 } else { 0 }); rollback = $rollbackState }
    }
    finally {
        Remove-RulePatchTransactionFile $stagePath
        if ($rollbackState -ne 'rollback_failed') { Remove-RulePatchTransactionFile $backupPath }
    }
}
