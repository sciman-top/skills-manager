. $PSScriptRoot\..\..\skills.ps1

Describe "Junction optimization" {
    Context "New-Junction" {
        It "Skips recreation when existing junction already points to the same target" {
            $linkPath = "C:\mock\link"
            $targetPath = "C:\mock\target"

            Mock EnsureDir {}
            Mock Test-PathEntry { $true }
            Mock Is-ReparsePoint { $true }
            Mock Get-ReparsePointTargetFullPath { "C:\mock\target" }
            Mock Invoke-RemoveItem {}
            Mock Invoke-MklinkJunction {}

            New-Junction $linkPath $targetPath

            Assert-MockCalled Invoke-RemoveItem -Times 0 -Exactly -Scope It -ParameterFilter { $path -eq $linkPath }
            Assert-MockCalled Invoke-MklinkJunction -Times 0 -Exactly -Scope It
        }

        It "Recreates junction when target path differs" {
            $linkPath = "C:\mock\link"
            $targetPath = "C:\mock\target"

            Mock EnsureDir {}
            Mock Test-PathEntry { $true }
            Mock Is-ReparsePoint { $true }
            Mock Get-ReparsePointTargetFullPath { "C:\mock\other-target" }
            Mock Invoke-RemoveItem {}
            Mock Invoke-MklinkJunction {}

            New-Junction $linkPath $targetPath

            Assert-MockCalled Invoke-RemoveItem -Times 1 -Exactly -Scope It -ParameterFilter { $path -eq $linkPath -and $Recurse }
            Assert-MockCalled Invoke-MklinkJunction -Times 1 -Exactly -Scope It -ParameterFilter { $linkPath -eq "C:\mock\link" -and $targetPath -eq "C:\mock\target" }
        }
    }
}
