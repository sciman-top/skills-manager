# Intentionally defective acceptance input. Repair only in a disposable copy.
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
