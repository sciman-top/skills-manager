. $PSScriptRoot\..\..\skills.ps1

Describe "Set-ContentUtf8" {
    It "Overwrites read-only files" {
        $path = Join-Path $TestDrive "readonly.txt"
        Set-Content -Path $path -Value "old"
        (Get-Item $path).IsReadOnly = $true

        Set-ContentUtf8 $path "new"

        (Get-Content -Raw $path) | Should Be "new"
        (Get-Item $path).IsReadOnly | Should Be $false
    }

    It "Overwrites hidden files" {
        $path = Join-Path $TestDrive "hidden.txt"
        Set-Content -Path $path -Value "old"
        $item = Get-Item $path
        $item.Attributes = ($item.Attributes -bor [System.IO.FileAttributes]::Hidden)

        Set-ContentUtf8 $path "new"

        (Get-Content -Raw $path) | Should Be "new"
        ((Get-Item $path).Attributes -band [System.IO.FileAttributes]::Hidden) | Should Be 0
    }
}
