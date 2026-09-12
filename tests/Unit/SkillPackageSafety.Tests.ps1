BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1
}

Describe 'Skill package safety' {
    Context 'Staged directory replacement' {
        BeforeEach {
            $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $source = Join-Path $fixture 'source'
            $target = Join-Path $fixture 'target'
            New-Item -ItemType Directory -Path $source, $target -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $source 'value.txt') -Value 'new'
            Set-Content -LiteralPath (Join-Path $target 'value.txt') -Value 'old'
            Mock Log {}
        }

        It 'preserves the original directory when its backup move fails' {
            Mock Invoke-MoveItem { throw 'backup move blocked' }
            { Install-StagedDirectoryAtomic $source $target } | Should -Throw '*backup move blocked*'
            Get-Content -LiteralPath (Join-Path $target 'value.txt') | Should -Be 'old'
            Get-Content -LiteralPath (Join-Path $source 'value.txt') | Should -Be 'new'
        }

        It 'restores the original directory when publishing the new one fails' {
            Mock Invoke-MoveItem {
                if ($src -eq $source) { throw 'publish blocked' }
                Move-Item -LiteralPath $src -Destination $dst
            }
            { Install-StagedDirectoryAtomic $source $target } | Should -Throw '*publish blocked*'
            Get-Content -LiteralPath (Join-Path $target 'value.txt') | Should -Be 'old'
        }

        It 'keeps the published directory when backup cleanup partially fails' {
            Mock Invoke-RemoveItemWithRetry {
                Remove-Item -LiteralPath $path -Recurse
                return $true
            }
            Mock Invoke-RemoveItemWithRetry {
                Remove-Item -LiteralPath (Join-Path $path 'value.txt')
                if ($IgnoreFailure) { return $false }
                throw 'backup cleanup blocked'
            } -ParameterFilter { $path -like '*.previous-*' }
            Install-StagedDirectoryAtomic $source $target
            Get-Content -LiteralPath (Join-Path $target 'value.txt') | Should -Be 'new'
        }
    }

    It 'accepts an ordinary package contained by its source root' {
        $root = Join-Path $TestDrive 'ordinary'
        $skill = Join-Path $root 'skills\demo'
        New-Item -ItemType Directory -Path $skill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skill 'SKILL.md') -Value "---`nname: demo`ndescription: fixture`n---" -Encoding utf8

        $result = Assert-SkillPackageSafe -Path $skill -ContainmentRoot $root -Label 'ordinary'

        $result.safe | Should -BeTrue
        $result.entry_count | Should -Be 1
    }

    It 'rejects a reparse point inside a package' {
        $root = Join-Path $TestDrive 'reparse'
        $skill = Join-Path $root 'skill'
        $outside = Join-Path $TestDrive 'outside'
        $junction = Join-Path $skill 'linked'
        New-Item -ItemType Directory -Path $skill, $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skill 'SKILL.md') -Value "---`nname: demo`ndescription: fixture`n---" -Encoding utf8
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            { Assert-SkillPackageSafe -Path $skill -ContainmentRoot $root -Label 'reparse' } |
                Should -Throw '*skill_package_unsafe:reparse_point:reparse*'
        }
        finally {
            if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
        }
    }

    It 'rejects a Git symlink mode even when checkout materializes it as a regular file' {
        $root = Join-Path $TestDrive 'git-mode'
        $skill = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path $skill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skill 'SKILL.md') -Value "---`nname: demo`ndescription: fixture`n---" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $skill 'target.txt') -Value 'target' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $skill 'link.txt') -Value 'target.txt' -NoNewline -Encoding utf8
        & git -C $root init --quiet
        & git -C $root add skill/SKILL.md skill/target.txt
        $blob = (& git -C $root hash-object -w skill/link.txt).Trim()
        & git -C $root update-index --add --cacheinfo ("120000,{0},skill/link.txt" -f $blob)
        $LASTEXITCODE | Should -Be 0

        { Assert-SkillPackageSafe -Path $skill -ContainmentRoot $root -Label 'git-mode' } |
            Should -Throw '*skill_package_unsafe:git_special_mode:git-mode:120000*'
    }

    It 'rejects a selected package whose path traverses a junction' {
        $root = Join-Path $TestDrive 'ancestor'
        $outside = Join-Path $TestDrive 'ancestor-outside'
        $skill = Join-Path $outside 'demo'
        $junction = Join-Path $root 'linked'
        New-Item -ItemType Directory -Path $root, $skill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skill 'SKILL.md') -Value "---`nname: demo`ndescription: fixture`n---" -Encoding utf8
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            { Assert-SkillPackageSafe -Path (Join-Path $junction 'demo') -ContainmentRoot $root -Label 'ancestor' } |
                Should -Throw '*skill_package_unsafe:reparse_point:ancestor*'
        }
        finally {
            if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
        }
    }
}
