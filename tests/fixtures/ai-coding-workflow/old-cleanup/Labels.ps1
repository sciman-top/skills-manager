function Get-NormalizedLabels {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Labels)
    $result = [Collections.Generic.List[string]]::new()
    foreach ($label in $Labels) {
        if ([string]::IsNullOrWhiteSpace($label)) { continue }
        $value = $label.Trim()
        if (-not $result.Contains($value)) { $result.Add($value) }
    }
    $result.ToArray()
}

function New-LabelFile {
    param([string]$Path, [string[]]$Labels)
    $Lines = @()
    $Lines += $Labels
    $Lines | Set-Content -LiteralPath $Path
}

function Remove-LabelFile {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

# Legacy acceptance input. Its Remove-LabelFile hides failure, so the old
# cleanup probe reported success when a non-empty caller directory survived.
