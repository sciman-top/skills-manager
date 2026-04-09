. $PSScriptRoot\..\..\skills.ps1

Describe "Vendor root display filtering" {
    It "Hides vendor root when child skills exist in same list" {
        $items = @(
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "." },
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "skills\\accessibility" },
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "skills\\seo" }
        )

        $filtered = Hide-VendorRootSkills $items

        @($filtered).Count | Should Be 2
        (@($filtered) | Where-Object { $_.from -eq "." }).Count | Should Be 0
    }

    It "Keeps vendor root when no child skill exists for that vendor" {
        $items = @(
            [pscustomobject]@{ vendor = "web-quality-skills"; from = "." }
        )

        $filtered = Hide-VendorRootSkills $items

        @($filtered).Count | Should Be 1
        @($filtered)[0].from | Should Be "."
    }

    It "Does not hide root of other vendor" {
        $items = @(
            [pscustomobject]@{ vendor = "a"; from = "." },
            [pscustomobject]@{ vendor = "b"; from = "." },
            [pscustomobject]@{ vendor = "b"; from = "skills\\child" }
        )

        $filtered = Hide-VendorRootSkills $items

        (@($filtered) | Where-Object { $_.vendor -eq "a" -and $_.from -eq "." }).Count | Should Be 1
        (@($filtered) | Where-Object { $_.vendor -eq "b" -and $_.from -eq "." }).Count | Should Be 0
    }
}
