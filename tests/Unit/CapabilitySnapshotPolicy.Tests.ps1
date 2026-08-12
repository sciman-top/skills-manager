Describe 'Capability snapshot tool policy' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\..\scripts\get-codex-app-server-capability-snapshot.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
        $functionAst = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Convert-ToolDescriptor'
        }, $true)
        $null -ne $functionAst | Should Be $true
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }

    It 'Treats an explicit non-read-only non-destructive protocol tool as a controlled write' {
        $tool = [pscustomobject]@{
            name = 'gmail.apply_labels_to_emails'
            title = 'Apply labels'
            description = 'Apply labels to matching email messages.'
            annotations = [pscustomobject]@{ readOnlyHint = $false; destructiveHint = $false; openWorldHint = $false }
        }

        $descriptor = Convert-ToolDescriptor $tool $tool.name $true $true

        $descriptor.side_effect | Should Be 'controlled_write'
        $descriptor.approval | Should Be 'required'
        $descriptor.evidence.classification | Should Be 'protocol_annotation'
        $descriptor.evidence.read_only_hint | Should Be $false
    }

    It 'Applies MCP fail-closed defaults when protocol annotations are absent' {
        $tool = [pscustomobject]@{
            name = 'ambiguous_action'
            title = 'Ambiguous action'
            description = 'Perform an operation.'
        }

        $descriptor = Convert-ToolDescriptor $tool $tool.name $true $true

        $descriptor.side_effect | Should Be 'destructive'
        $descriptor.approval | Should Be 'required'
        $descriptor.evidence.classification | Should Be 'protocol_default'
        $descriptor.evidence.read_only_hint | Should Be $false
        $descriptor.evidence.destructive_hint | Should Be $true
        $descriptor.evidence.open_world_hint | Should Be $true
    }

    It 'Preserves an annotated open-world read as an external read' {
        $tool = [pscustomobject]@{
            name = 'search_public_docs'
            title = 'Search public docs'
            description = 'Search public documentation.'
            annotations = [pscustomobject]@{ readOnlyHint = $true; destructiveHint = $false; openWorldHint = $true }
        }

        $descriptor = Convert-ToolDescriptor $tool $tool.name $true $true

        $descriptor.side_effect | Should Be 'external_read'
        $descriptor.approval | Should Be 'none'
        $descriptor.evidence.open_world_hint | Should Be $true
    }
}
