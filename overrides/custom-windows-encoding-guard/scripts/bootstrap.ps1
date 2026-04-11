param(
    [switch]$CheckOnly,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Get-EncodingName {
    param([object]$EncodingValue)
    if ($null -eq $EncodingValue) { return $null }
    try {
        return $EncodingValue.WebName
    }
    catch {
        return $null
    }
}

function Test-IsUtf8 {
    param([string]$EncodingName)
    return -not [string]::IsNullOrWhiteSpace($EncodingName) -and $EncodingName.Equals("utf-8", [System.StringComparison]::OrdinalIgnoreCase)
}

$psDefaultEncoding = $null
if ($null -ne $PSDefaultParameterValues -and $PSDefaultParameterValues.ContainsKey("*:Encoding")) {
    $psDefaultEncoding = [string]$PSDefaultParameterValues["*:Encoding"]
}

$before = [ordered]@{
    output_encoding = Get-EncodingName $OutputEncoding
    console_input_encoding = Get-EncodingName ([Console]::InputEncoding)
    console_output_encoding = Get-EncodingName ([Console]::OutputEncoding)
    ps_default_encoding = $psDefaultEncoding
}

$changes = New-Object System.Collections.Generic.List[string]

if (-not $CheckOnly) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (-not (Test-IsUtf8 (Get-EncodingName $OutputEncoding))) {
        $global:OutputEncoding = $utf8NoBom
        $changes.Add("OutputEncoding=utf-8") | Out-Null
    }

    try {
        if (-not (Test-IsUtf8 (Get-EncodingName ([Console]::InputEncoding)))) {
            [Console]::InputEncoding = $utf8NoBom
            $changes.Add("Console.InputEncoding=utf-8") | Out-Null
        }
    }
    catch {}

    try {
        if (-not (Test-IsUtf8 (Get-EncodingName ([Console]::OutputEncoding)))) {
            [Console]::OutputEncoding = $utf8NoBom
            $changes.Add("Console.OutputEncoding=utf-8") | Out-Null
        }
    }
    catch {}

    if ($null -eq $PSDefaultParameterValues) {
        $global:PSDefaultParameterValues = @{}
    }
    $existingDefaultEncoding = $null
    if ($PSDefaultParameterValues.ContainsKey("*:Encoding")) {
        $existingDefaultEncoding = [string]$PSDefaultParameterValues["*:Encoding"]
    }
    if ([string]::IsNullOrWhiteSpace($existingDefaultEncoding) -or -not $existingDefaultEncoding.Equals("utf8", [System.StringComparison]::OrdinalIgnoreCase)) {
        $PSDefaultParameterValues["*:Encoding"] = "utf8"
        $changes.Add("PSDefaultParameterValues['*:Encoding']=utf8") | Out-Null
    }
}

$afterDefaultEncoding = $null
if ($null -ne $PSDefaultParameterValues -and $PSDefaultParameterValues.ContainsKey("*:Encoding")) {
    $afterDefaultEncoding = [string]$PSDefaultParameterValues["*:Encoding"]
}

$after = [ordered]@{
    output_encoding = Get-EncodingName $OutputEncoding
    console_input_encoding = Get-EncodingName ([Console]::InputEncoding)
    console_output_encoding = Get-EncodingName ([Console]::OutputEncoding)
    ps_default_encoding = $afterDefaultEncoding
}

$isCompliant = (
    (Test-IsUtf8 $after.output_encoding) -and
    (Test-IsUtf8 $after.console_input_encoding) -and
    (Test-IsUtf8 $after.console_output_encoding) -and
    (-not [string]::IsNullOrWhiteSpace($after.ps_default_encoding)) -and
    $after.ps_default_encoding.Equals("utf8", [System.StringComparison]::OrdinalIgnoreCase)
)

$result = [ordered]@{
    check_only = [bool]$CheckOnly
    compliant_before = (
        (Test-IsUtf8 $before.output_encoding) -and
        (Test-IsUtf8 $before.console_input_encoding) -and
        (Test-IsUtf8 $before.console_output_encoding) -and
        (-not [string]::IsNullOrWhiteSpace($before.ps_default_encoding)) -and
        $before.ps_default_encoding.Equals("utf8", [System.StringComparison]::OrdinalIgnoreCase)
    )
    compliant_after = $isCompliant
    changed = ($changes.Count -gt 0)
    changes = @($changes)
    powershell_edition = [string]$PSVersionTable.PSEdition
    powershell_version = [string]$PSVersionTable.PSVersion
    before = $before
    after = $after
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6 | Write-Output
}
else {
    if ($result.compliant_after) {
        Write-Host "[PASS] UTF-8 encoding guard is compliant."
    }
    else {
        Write-Host "[WARN] UTF-8 encoding guard is not fully compliant."
    }
    if ($changes.Count -gt 0) {
        Write-Host ("[INFO] Applied changes: " + ($changes -join "; "))
    }
}

if ($result.compliant_after) {
    exit 0
}

exit 2
