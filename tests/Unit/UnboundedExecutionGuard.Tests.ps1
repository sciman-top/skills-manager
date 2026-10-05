# Guards the "bounded external execution" contract.
#
# Eleven production hangs were fixed on 2026-10-05; every one of them was an
# external process or HTTP call that could block forever, and the most damaging
# one (an unbounded output read that silently bypassed a process timeout) was
# invisible to review. These checks make the mechanically detectable half of
# that class fail here instead of being re-diagnosed by hand in a later session.
#
# Scope: src/ and scripts/ (production and tooling). docs/handover/** are
# deployment assets with their own manifest, and unbounded waits inside test
# helpers are review-level rather than statically enforced.
BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

    function Get-GuardedSourceFile {
        $files = [Collections.Generic.List[object]]::new()
        foreach ($root in @('src', 'scripts')) {
            $base = Join-Path $repoRoot $root
            if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $base -Recurse -Filter '*.ps1' -File | Sort-Object FullName)) {
                $files.Add([pscustomobject]@{
                        path     = $file.FullName
                        relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
                        lines    = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
                    })
            }
        }
        return @($files)
    }
}

Describe 'Bounded external execution contract' {
    BeforeAll {
        $script:GuardedFiles = @(Get-GuardedSourceFile)
    }

    It 'scans the production sources' {
        @($script:GuardedFiles).Count | Should -BeGreaterThan 40
    }

    It 'never invokes an HTTP cmdlet without -TimeoutSec' {
        $violations = [Collections.Generic.List[string]]::new()
        foreach ($file in $script:GuardedFiles) {
            for ($index = 0; $index -lt $file.lines.Count; $index++) {
                # A real invocation, not the cmdlet name inside a quoted string.
                if ($file.lines[$index] -notmatch '(?<![A-Za-z"''])Invoke-(WebRequest|RestMethod)\s') { continue }
                $last = [Math]::Min($index + 3, $file.lines.Count - 1)
                if ((@($file.lines[$index..$last]) -join "`n") -notmatch '-TimeoutSec\b') {
                    $violations.Add(('{0}:{1}' -f $file.relative, $index + 1)) | Out-Null
                }
            }
        }
        @($violations).Count | Should -Be 0 -Because ('every HTTP call needs a wall-clock bound, offenders: ' + (@($violations) -join ', '))
    }

    It 'never waits on a process without a wall-clock bound' {
        $violations = [Collections.Generic.List[string]]::new()
        foreach ($file in $script:GuardedFiles) {
            for ($index = 0; $index -lt $file.lines.Count; $index++) {
                if ($file.lines[$index] -match '\.WaitForExit\(\)') {
                    $violations.Add(('{0}:{1}' -f $file.relative, $index + 1)) | Out-Null
                }
            }
        }
        @($violations).Count | Should -Be 0 -Because ('parameterless WaitForExit() waits forever, offenders: ' + (@($violations) -join ', '))
    }

    It 'never reads the hook stdin stream without a bound' {
        $violations = [Collections.Generic.List[string]]::new()
        foreach ($file in $script:GuardedFiles) {
            for ($index = 0; $index -lt $file.lines.Count; $index++) {
                if ($file.lines[$index] -match '\[Console\]::In\.ReadToEnd\(\)') {
                    $violations.Add(('{0}:{1}' -f $file.relative, $index + 1)) | Out-Null
                }
            }
        }
        @($violations).Count | Should -Be 0 -Because ('a host that never closes the pipe must not hang the hook, offenders: ' + (@($violations) -join ', '))
    }

    It 'pairs every process stream read with a bounded read' {
        $violations = [Collections.Generic.List[string]]::new()
        foreach ($file in $script:GuardedFiles) {
            $text = @($file.lines) -join "`n"
            if ($text -notmatch 'Standard(Output|Error)\.ReadToEndAsync\(') { continue }
            # A grandchild that inherited the pipe keeps ReadToEndAsync from
            # reaching EOF, so an unbounded GetResult()/Result bypasses the
            # process timeout. Every such file must bound the read explicitly.
            if ($text -match 'Read-ExternalCommandTaskText' -or $text -match '::WaitAll\(') { continue }
            $violations.Add($file.relative) | Out-Null
        }
        @($violations).Count | Should -Be 0 -Because ('unbounded output reads bypass process timeouts, offenders: ' + (@($violations) -join ', '))
    }
}
