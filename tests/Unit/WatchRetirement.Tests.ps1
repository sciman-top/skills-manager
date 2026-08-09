Describe 'watch-interrupted-task retirement contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:skillPath = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\SKILL.md'
        $script:metadataPath = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\agents\openai.yaml'
        $script:config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
        $script:skillRoot = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task'
    }

    It 'removes the legacy watch from resident and native projected skill sets' {
        @($script:config.skill_projection.resident_names) | Should Not Contain 'watch-interrupted-task'
        @($script:config.skill_projection.managed_link_excludes) | Should Contain 'watch-interrupted-task'
    }

    It 'retains only a read-only cleanup compatibility entrypoint' {
        $skill = Get-Content -Raw -LiteralPath $script:skillPath
        $metadata = Get-Content -Raw -LiteralPath $script:metadataPath

        $skill | Should Match 'runtime_status=retired_fail_closed'
        $skill | Should Match 'Never create, arm, enable, resume, reactivate, update, clone, or schedule'
        $skill | Should Match 'Never emit heartbeat XML'
        $metadata | Should Match 'never create, arm, resume, or update a watch'
        $metadata | Should Not Match 'recover this task'
    }

    It 'has no executable prompt, runtime generation, arming, disposition, or fleet state scripts' {
        $scripts = @(Get-ChildItem -LiteralPath (Join-Path $script:skillRoot 'scripts') -File -ErrorAction SilentlyContinue)

        $scripts.Count | Should Be 0
        foreach ($name in @(
            'New-WatchHeartbeatPrompt.ps1',
            'New-WatchFleetSupervisorPrompt.ps1',
            'New-WatchRuntimeGeneration.ps1',
            'Test-WatchRuntimeArming.ps1',
            'Get-WatchHeartbeatDisposition.ps1',
            'Get-WatchFleetShutdownDisposition.ps1',
            'Get-WatchPeerBusyDisposition.ps1'
        )) {
            Test-Path -LiteralPath (Join-Path $script:skillRoot ('scripts\' + $name)) | Should Be $false
        }
    }

    It 'has no active recovery-design reference that can be consumed as runtime instructions' {
        Test-Path -LiteralPath (Join-Path $script:skillRoot 'references\recovery-design.md') | Should Be $false
    }
}
