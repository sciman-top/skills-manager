. $PSScriptRoot\..\..\skills.ps1

Describe "Workflow command" {
    Context "Resolve-WorkflowProfileKey" {
        It "Resolves Chinese and English aliases" {
            Resolve-WorkflowProfileKey "新手" | Should Be "quickstart"
            Resolve-WorkflowProfileKey "maintenance" | Should Be "maintenance"
            Resolve-WorkflowProfileKey "审查" | Should Be "audit"
            Resolve-WorkflowProfileKey "full" | Should Be "all"
        }

        It "Returns null for unknown profile" {
            Resolve-WorkflowProfileKey "unknown-profile" | Should Be $null
        }
    }

    Context "Parse-WorkflowArgs" {
        It "Parses positional profile and flags" {
            $opts = Parse-WorkflowArgs @("维护", "--continue-on-error", "--no-prompt")
            $opts.profile | Should Be "maintenance"
            $opts.continue_on_error | Should Be $true
            $opts.no_prompt | Should Be $true
            $opts.list | Should Be $false
        }

        It "Parses --profile form" {
            $opts = Parse-WorkflowArgs @("--profile", "审查")
            $opts.profile | Should Be "audit"
        }

        It "Throws for unknown option" {
            $thrown = $false
            try {
                Parse-WorkflowArgs @("--bad-flag") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }
    }

    Context "Invoke-Workflow" {
        It "Runs maintenance workflow in order under no-prompt mode" {
            $script:callOrder = New-Object System.Collections.Generic.List[string]
            Mock 更新 { $script:callOrder.Add("更新") | Out-Null }
            Mock 构建生效 { $script:callOrder.Add("构建生效") | Out-Null }
            Mock 同步MCP { $script:callOrder.Add("同步MCP") | Out-Null }
            Mock Invoke-Doctor {
                $script:callOrder.Add("doctor") | Out-Null
                return [pscustomobject]@{ pass = $true }
            }

            $report = Invoke-Workflow @("维护", "--no-prompt")
            $report.pass | Should Be $true
            (@($script:callOrder) -join ",") | Should Be "更新,构建生效,同步MCP,doctor"
        }

        It "Throws when strict doctor fails and continue-on-error is not enabled" {
            Mock 更新 {}
            Mock 构建生效 {}
            Mock 同步MCP {}
            Mock Invoke-Doctor { [pscustomobject]@{ pass = $false } }

            $thrown = $false
            try {
                Invoke-Workflow @("维护", "--no-prompt") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }
    }
}
