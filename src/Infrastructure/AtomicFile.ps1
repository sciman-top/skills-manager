function Clear-AtomicFileWriteBlockAttributes([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $blocked = [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
        if (($item.Attributes -band $blocked) -ne 0) {
            $item.Attributes = $item.Attributes -band (-bnot $blocked)
        }
    }
    catch {}
}

function Write-BytesAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [ValidateRange(1, 100)][int]$MaxAttempts = 4,
        [ValidateRange(0, 60000)][int]$DelayMs = 200
    )

    $parent = Split-Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $tempPath = "{0}.tmp-{1}" -f $Path, ([System.Guid]::NewGuid().ToString('N'))
    $backupPath = "{0}.bak-{1}" -f $Path, ([System.Guid]::NewGuid().ToString('N'))

    for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt++) {
        try {
            Clear-AtomicFileWriteBlockAttributes $Path
            [System.IO.File]::WriteAllBytes($tempPath, $Bytes)
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                [System.IO.File]::Replace($tempPath, $Path, $backupPath, $true)
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
            else {
                [System.IO.File]::Move($tempPath, $Path)
            }
            Clear-AtomicFileWriteBlockAttributes $Path
            return
        }
        catch {
            $baseException = $_.Exception
            if ($baseException -is [System.Management.Automation.MethodInvocationException] -and $baseException.InnerException) {
                $baseException = $baseException.InnerException
            }

            foreach ($transactionPath in @($tempPath, $backupPath)) {
                if (Test-Path -LiteralPath $transactionPath -PathType Leaf) {
                    try { Remove-Item -LiteralPath $transactionPath -Force -ErrorAction Stop } catch {}
                }
            }
            Clear-AtomicFileWriteBlockAttributes $Path

            $retryable = $baseException -is [System.UnauthorizedAccessException] -or $baseException -is [System.IO.IOException]
            if (-not $retryable -or $attempt -ge ($MaxAttempts - 1)) { throw $baseException }
            if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
        }
    }
}

function Write-Utf8FileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [ValidateRange(1, 100)][int]$MaxAttempts = 4,
        [ValidateRange(0, 60000)][int]$DelayMs = 200
    )

    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Content)
    Write-BytesAtomic -Path $Path -Bytes $bytes -MaxAttempts $MaxAttempts -DelayMs $DelayMs
}
