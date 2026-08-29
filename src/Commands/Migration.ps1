function Get-MigrationTokens([string[]]$Tokens) {
    $result = [ordered]@{ mode = 'private-all'; out_path = ''; force = $false; json = $false; version = '' }
    $items = @($Tokens)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $token = [string]$items[$i]
        switch -Regex ($token.ToLowerInvariant()) {
            '^(--mode|-m)$' {
                Need ($i + 1 -lt $items.Count) '迁移 --mode 需要 private-all 或 rescan'
                $result.mode = [string]$items[++$i]
                continue
            }
            '^--mode=' {
                $result.mode = $token.Substring(7)
                continue
            }
            '^(--out|-o)$' {
                Need ($i + 1 -lt $items.Count) '迁移 --out 需要输出 ZIP 路径'
                $result.out_path = [string]$items[++$i]
                continue
            }
            '^--out=' {
                $result.out_path = $token.Substring(6)
                continue
            }
            '^--version$' {
                Need ($i + 1 -lt $items.Count) '迁移 --version 需要交付版本号'
                $result.version = [string]$items[++$i]
                continue
            }
            '^--version=' {
                $result.version = $token.Substring(10)
                continue
            }
            '^--force$' { $result.force = $true; continue }
            '^--json$' { $result.json = $true; continue }
            default { throw ("迁移不支持参数：{0}" -f $token) }
        }
    }
    $result.mode = ([string]$result.mode).Trim().ToLowerInvariant()
    Need (@('private-all','rescan') -contains $result.mode) '迁移模式必须是 private-all 或 rescan'
    if (-not [string]::IsNullOrWhiteSpace($result.version)) { Need ($result.version -match '^[0-9A-Za-z][0-9A-Za-z._-]*$') '迁移 --version 格式非法' }
    return [pscustomobject]$result
}

function ConvertFrom-MigrationSecureString([System.Security.SecureString]$Value) {
    Need ($null -ne $Value) '迁移加密口令不能为空'
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Read-MigrationPassphrase([string]$Prompt, [switch]$Confirm) {
    $firstSecure = Read-Host -Prompt $Prompt -AsSecureString
    $first = ConvertFrom-MigrationSecureString $firstSecure
    Need (-not [string]::IsNullOrWhiteSpace($first)) '迁移加密口令不能为空'
    if ($Confirm) {
        $secondSecure = Read-Host -Prompt '请再次输入迁移加密口令（不会保存）' -AsSecureString
        $second = ConvertFrom-MigrationSecureString $secondSecure
        $a = [Text.Encoding]::UTF8.GetBytes($first)
        $b = [Text.Encoding]::UTF8.GetBytes($second)
        try {
            Need ($a.Length -eq $b.Length -and [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)) '两次输入的迁移加密口令不一致'
        }
        finally { [Array]::Clear($a, 0, $a.Length); [Array]::Clear($b, 0, $b.Length) }
    }
    return $firstSecure
}

function Unprotect-MigrationCredentialPayload($Encrypted, [System.Security.SecureString]$Passphrase) {
    Need ([int]$Encrypted.schema_version -eq 1) '迁移凭据文件 schema_version 不支持'
    Need ([string]$Encrypted.algorithm -eq 'AES-256-GCM' -and [string]$Encrypted.kdf -eq 'PBKDF2-SHA256') '迁移凭据文件加密算法不支持'
    $iterations = [int]$Encrypted.iterations
    Need ($iterations -ge 100000 -and $iterations -le 5000000) '迁移凭据文件 KDF iterations 非法'
    try {
        $salt = [Convert]::FromBase64String([string]$Encrypted.salt); $nonce = [Convert]::FromBase64String([string]$Encrypted.nonce)
        $tag = [Convert]::FromBase64String([string]$Encrypted.tag); $cipherBytes = [Convert]::FromBase64String([string]$Encrypted.ciphertext)
    }
    catch { throw '迁移凭据文件 Base64 字段非法' }
    Need ($salt.Length -eq 16 -and $nonce.Length -eq 12 -and $tag.Length -eq 16 -and $cipherBytes.Length -gt 0) '迁移凭据文件字段长度非法'
    $pass = ConvertFrom-MigrationSecureString $Passphrase
    $key = New-Object byte[] 32; $plainBytes = New-Object byte[] $cipherBytes.Length
    $aad = [Text.Encoding]::UTF8.GetBytes('skills-manager:migration:mcp:v1')
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($pass, $salt, $iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        [Array]::Copy($kdf.GetBytes($key.Length), $key, $key.Length)
        $aes = [Security.Cryptography.AesGcm]::new($key, $tag.Length)
        try { $aes.Decrypt($nonce, $cipherBytes, $tag, $plainBytes, $aad) }
        catch { throw '迁移加密口令错误或凭据文件已损坏' }
        finally { $aes.Dispose() }
        return [Text.Encoding]::UTF8.GetString($plainBytes)
    }
    finally { [Array]::Clear($key, 0, $key.Length); [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
}

function Copy-MigrationTree([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return $false }
    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    foreach ($entry in @(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse -ErrorAction Stop)) {
        # Migration contains package payload only: never follow links and never copy Git history.
        if ($entry.Name -eq '.git' -or ($entry.FullName -match '[\\/]\.git(?:[\\/]|$)') -or (Is-ReparsePoint $entry.FullName)) { continue }
        $relative = [IO.Path]::GetRelativePath($sourceRoot, $entry.FullName)
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -eq '.') { continue }
        $target = Join-Path $Destination $relative
        if ($entry.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
            continue
        }
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $entry.FullName -Destination $target -Force
    }
    return $true
}

function Assert-MigrationContentIntegrity([string]$PackageRoot, $Manifest) {
    $contentPath = Join-Path $PackageRoot 'MIGRATION-CONTENT.json'
    Need (Test-Path -LiteralPath $contentPath -PathType Leaf) '迁移包缺少 MIGRATION-CONTENT.json'
    $content = Get-ContentUtf8 $contentPath | ConvertFrom-Json
    Need ([int]$content.schema_version -eq 1 -and $null -ne $content.files) 'MIGRATION-CONTENT.json schema 无效'
    $expected = @($content.files)
    $actual = @(Get-PackageFileEntries $PackageRoot | Where-Object { $_.path -ne 'MIGRATION-CONTENT.json' })
    # One-to-one closure: reject duplicate paths on either side and any actual
    # file the content manifest does not claim (count equality alone lets an
    # attacker swap in an extra file and pad the expected list).
    $expectedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $expected) {
        $path = [string]$entry.path
        Need (-not [string]::IsNullOrWhiteSpace($path)) 'MIGRATION-CONTENT.json 包含空路径'
        Need ($expectedPaths.Add($path)) ("MIGRATION-CONTENT.json 包含重复路径：{0}" -f $path)
    }
    $actualPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $actual) {
        $path = [string]$entry.path
        Need ($actualPaths.Add($path)) ("迁移包存在重复路径：{0}" -f $path)
        Need ($expectedPaths.Contains($path)) ("迁移包包含 MIGRATION-CONTENT.json 未声明的文件：{0}" -f $path)
    }
    Need ($expectedPaths.Count -eq $actualPaths.Count) '迁移包内容文件数量不匹配'
    $byPath = @{}; foreach ($entry in $actual) { $byPath[[string]$entry.path] = $entry }
    foreach ($entry in $expected) {
        $path = [string]$entry.path
        Need ($byPath.ContainsKey($path)) ("迁移包缺少内容文件：{0}" -f $path)
        Need ([long]$byPath[$path].size -eq [long]$entry.size -and [string]$byPath[$path].sha256 -eq ([string]$entry.sha256).ToLowerInvariant()) ("迁移包内容校验失败：{0}" -f $path)
    }
    return $true
}

function Get-MigrationMcpIntent($Server) {
    $item = [ordered]@{}
    foreach ($name in @('name','enabled','transport','command','args','url','startup_timeout_sec','enabled_tools','bearer_token_env_var')) {
        $property = $Server.PSObject.Properties[$name]
        if ($null -ne $property) { $item[$name] = $property.Value }
    }
    $credentialNames = @()
    foreach ($field in @('env','headers')) {
        $property = $Server.PSObject.Properties[$field]
        if ($null -eq $property -or $null -eq $property.Value) { continue }
        foreach ($entry in $property.Value.PSObject.Properties) { $credentialNames += [string]$entry.Name }
    }
    if ($credentialNames.Count -gt 0) { $item.credential_reference_names = @($credentialNames | Sort-Object -Unique) }
    return [pscustomobject]$item
}

function Get-MigrationCredentialPayload($Config, [string[]]$McpNames) {
    $servers = New-Object Collections.Generic.List[object]
    foreach ($server in @($Config.mcp_servers | Where-Object { $McpNames -contains [string]$_.name })) {
        $item = [ordered]@{ name = [string]$server.name }
        foreach ($field in @('env','headers')) {
            $property = $server.PSObject.Properties[$field]
            if ($null -eq $property -or $null -eq $property.Value) { continue }
            $map = [ordered]@{}
            foreach ($entry in $property.Value.PSObject.Properties) { $map[[string]$entry.Name] = [string]$entry.Value }
            if ($map.Count -gt 0) { $item[$field] = $map }
        }
        if ($item.Keys.Count -gt 1) { $servers.Add([pscustomobject]$item) | Out-Null }
    }
    return [pscustomobject][ordered]@{ schema_version = 1; mcp_servers = @($servers.ToArray()) }
}

function Get-MigrationUnlockTokens([string[]]$Tokens) {
    $result = [ordered]@{ credentials_path = ''; yes = $false; json = $false }
    $items = @($Tokens)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $token = [string]$items[$i]
        switch -Regex ($token.ToLowerInvariant()) {
            '^(--credentials|-c)$' { Need ($i + 1 -lt $items.Count) 'migration-unlock --credentials 需要文件路径'; $result.credentials_path = [string]$items[++$i]; continue }
            '^--credentials=' { $result.credentials_path = $token.Substring(14); continue }
            '^--yes$' { $result.yes = $true; continue }
            '^--json$' { $result.json = $true; continue }
            default { throw ("migration-unlock 不支持参数：{0}" -f $token) }
        }
    }
    return [pscustomobject]$result
}

function Get-MigrationApplyTokens([string[]]$Tokens) {
    $result = [ordered]@{ skip_mcp = $false; json = $false }
    foreach ($token in @($Tokens)) {
        switch ([string]$token) {
            '--skip-mcp' { $result.skip_mcp = $true; continue }
            '--json' { $result.json = $true; continue }
            default { throw ("migration-apply 不支持参数：{0}" -f $token) }
        }
    }
    return [pscustomobject]$result
}

function Invoke-MigrationUnlockCommand([string[]]$Tokens) {
    $options = Get-MigrationUnlockTokens $Tokens
    $manifestPath = Join-Path $Root 'MIGRATION-MANIFEST.json'
    Need (Test-Path -LiteralPath $manifestPath -PathType Leaf) '当前目录缺少 MIGRATION-MANIFEST.json'
    $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
    Assert-MigrationContentIntegrity $Root $manifest | Out-Null
    Need ([string]$manifest.kind -eq 'migration' -and [string]$manifest.mode -in @('private-general','private-all')) '当前迁移包不是私用迁移包'
    $manifestCredentialFile = [string]$manifest.credential_file
    $credentialsEncrypted = if ($manifest.PSObject.Properties['credentials_encrypted']) {
        [bool]$manifest.credentials_encrypted
    } else {
        # Compatibility with manifests produced before credentials_encrypted existed.
        $manifestCredentialFile -like '*.enc.json'
    }
    $defaultCredentialFile = if ($credentialsEncrypted) { 'MIGRATION-MCP-CREDENTIALS.enc.json' } else { 'MIGRATION-MCP-CREDENTIALS.json' }
    $credentialFile = if ([string]::IsNullOrWhiteSpace($manifestCredentialFile)) { $defaultCredentialFile } else { $manifestCredentialFile }
    $credentialPath = if ([string]::IsNullOrWhiteSpace($options.credentials_path)) {
        Join-Path $Root $credentialFile
    } else { [IO.Path]::GetFullPath($options.credentials_path) }
    Need (Is-PathInsideOrEqual $credentialPath $Root) '凭据文件必须位于当前迁移包目录内'
    Need (Test-Path -LiteralPath $credentialPath -PathType Leaf) ("缺少迁移凭据文件：{0}" -f $credentialPath)
    $credentialDocument = Get-ContentUtf8 $credentialPath | ConvertFrom-Json
    $payload = if ($credentialsEncrypted) {
        $passphrase = Read-MigrationPassphrase '请输入迁移加密口令（不会保存）'
        Unprotect-MigrationCredentialPayload $credentialDocument $passphrase | ConvertFrom-Json
    } else {
        $credentialDocument
    }
    Need ([int]$payload.schema_version -eq 1 -and $null -ne $payload.mcp_servers) '迁移凭据明文载荷 schema 无效'
    $cfg = LoadCfg
    $changed = 0
    foreach ($payloadServer in @($payload.mcp_servers)) {
        $name = [string]$payloadServer.name
        Need (@($manifest.mcp_servers) -contains $name) ("迁移凭据服务不在 manifest 中：{0}" -f $name)
        $server = @($cfg.mcp_servers | Where-Object { [string]$_.name -eq $name }) | Select-Object -First 1
        Need ($null -ne $server) ("迁移凭据服务不在当前 skills.json 中：{0}" -f $name)
        foreach ($field in @('env','headers')) {
            $property = $payloadServer.PSObject.Properties[$field]
            if ($null -eq $property) { continue }
            $map = [ordered]@{}
            foreach ($entry in $property.Value.PSObject.Properties) { $map[[string]$entry.Name] = [string]$entry.Value }
            $server | Add-Member -NotePropertyName $field -NotePropertyValue ([pscustomobject]$map) -Force
            $changed++
        }
    }
    Need ($options.yes -or (Confirm-Action ("将恢复 {0} 个 MCP 凭据字段到当前 skills.json" -f $changed) 'RESTORE' -DefaultNo)) '已取消恢复 MCP 凭据'
    Assert-Cfg $cfg
    $raw = Get-ContentUtf8 $CfgPath
    SaveCfgSafe $cfg $raw
    $result = [pscustomobject]@{ command = 'migration-unlock'; mode = [string]$manifest.mode; restored_fields = $changed; path = $CfgPath; passphrase_exposed = $false }
    if ($options.json) { return ($result | ConvertTo-Json -Depth 8) }
    Write-Host ("已恢复 {0} 个 MCP 凭据字段到 skills.json。" -f $changed) -ForegroundColor Green
    return $result
}

function Invoke-MigrationApplyCommand([string[]]$Tokens) {
    $options = Get-MigrationApplyTokens $Tokens
    $manifestPath = Join-Path $Root 'MIGRATION-MANIFEST.json'
    Need (Test-Path -LiteralPath $manifestPath -PathType Leaf) '当前目录缺少 MIGRATION-MANIFEST.json'
    $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
    Assert-MigrationContentIntegrity $Root $manifest | Out-Null
    Need ([string]$manifest.kind -eq 'migration' -and [string]$manifest.mode -in @('all','general','private-general','private-all')) 'migration-apply 只接受 all、general 或私用迁移包'
    if ([string]$manifest.mode -in @('private-general','private-all') -and [bool]$manifest.includes_credentials) { Invoke-MigrationUnlockCommand @('--yes') | Out-Null }
    $installPath = Join-Path $Root 'install.ps1'
    Need (Test-Path -LiteralPath $installPath -PathType Leaf) '迁移包缺少 install.ps1'
    $pwsh = Get-Command pwsh -ErrorAction Stop | Select-Object -First 1
    $installArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installPath,'-Mode','CurrentUser','-SkipRebuildLocked')
    if (-not $options.skip_mcp) { $installArgs += '-SyncMcp' }
    & $pwsh.Source @installArgs
    $exitCode = $LASTEXITCODE
    Need ($exitCode -eq 0) ("迁移安装失败，exit={0}" -f $exitCode)
    $result = [pscustomobject]@{ command = 'migration-apply'; mode = [string]$manifest.mode; sync_mcp = (-not $options.skip_mcp); exit_code = $exitCode; host_loaded = $false; live_accepted = $false }
    if ($options.json) { return ($result | ConvertTo-Json -Depth 8) }
    Write-Host ("迁移安装完成：mode={0}，MCP同步={1}" -f $manifest.mode, (-not $options.skip_mcp)) -ForegroundColor Green
    return $result
}

function New-MigrationConfig($Config, [string]$Mode, [string[]]$SkillNames, [string[]]$McpNames) {
    $json = $Config | ConvertTo-Json -Depth 100
    $copy = $json | ConvertFrom-Json
    if ($Mode -notin @('all','private-all')) {
        $copy.mappings = @($copy.mappings | Where-Object { $SkillNames -contains [string]$_.to })
        $usedVendors = @($copy.mappings | ForEach-Object { [string]$_.vendor } | Sort-Object -Unique)
        $manualImportNames = @($copy.mappings | Where-Object { [string]$_.vendor -eq 'manual' } | ForEach-Object { [string]$_.from } | Sort-Object -Unique)
        $copy.vendors = @($copy.vendors | Where-Object { $usedVendors -contains [string]$_.name })
        $copy.imports = @($copy.imports | Where-Object { $manualImportNames -contains [string]$_.name })
        $copy.mcp_servers = @($copy.mcp_servers | Where-Object { $McpNames -contains [string]$_.name } | ForEach-Object { Get-MigrationMcpIntent $_ })
        if ($copy.PSObject.Properties['mcp_profiles']) {
            $default = $copy.mcp_profiles.profiles.default
            $copy.mcp_profiles = [pscustomobject]@{ active = 'default'; profiles = [pscustomobject]@{ default = $default } }
        }
    }
    else {
        $copy.mcp_servers = @($copy.mcp_servers | ForEach-Object { Get-MigrationMcpIntent $_ })
    }
    return $copy
}

function Invoke-MigrationCommand([string[]]$Tokens) {
    $options = Get-MigrationTokens $Tokens
    $cfg = LoadCfg
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $outPath = if ([string]::IsNullOrWhiteSpace($options.out_path)) {
        Need (-not [string]::IsNullOrWhiteSpace($options.version)) '默认交付路径需要 --version <version>，以便四类交付物位于同一版本目录'
        $deliveryKind = if ($options.mode -eq 'private-all') { 'private-snapshot' } else { 'rescan' }
        $migrationRunRoot = Join-Path (Join-Path $Root 'artifacts') (Join-Path (Join-Path (Join-Path 'deliveries' $options.version) $deliveryKind) $stamp)
        Join-Path $migrationRunRoot ("skills-manager-{0}-{1}-{2}.zip" -f $options.version, $options.mode, $stamp)
    } else { [IO.Path]::GetFullPath($options.out_path) }
    $artifactsRoot = [IO.Path]::GetFullPath((Join-Path $Root 'artifacts')).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($outPath.Equals($artifactsRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $outPath.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $relativeArtifactPath = [IO.Path]::GetRelativePath($artifactsRoot, $outPath).Replace('\', '/')
        if ($relativeArtifactPath -notmatch '^deliveries/[^/]+/(private-snapshot|rescan)/[^/]+/[^/]+\.zip$') {
            throw 'Migration output under artifacts must be artifacts\deliveries\<version>\{private-snapshot,rescan}\<run-id>\<file>.zip; use an external temporary path only for isolated tests.'
        }
    }
    $outParent = Split-Path -Parent $outPath
    if (-not (Test-Path -LiteralPath $outParent)) { New-Item -ItemType Directory -Path $outParent -Force | Out-Null }
    Need ($options.force -or -not (Test-Path -LiteralPath $outPath)) ("迁移输出已存在：{0}；如需覆盖请使用 --force" -f $outPath)

    $skillNames = @()
    if ($options.mode -eq 'private-all') {
        $skillNames = @(Get-ChildItem -LiteralPath $AgentDir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object Name | Sort-Object)
    }
    $mcpNames = if ($options.mode -eq 'private-all') { @($cfg.mcp_servers | ForEach-Object Name) } else { @() }
    $credentialPayload = $null
    $credentialFileName = $null
    $privateMode = $options.mode -eq 'private-all'
    if ($privateMode) {
        $privatePayload = Get-MigrationCredentialPayload $cfg $mcpNames
        $credentialPayload = $privatePayload
        $credentialFileName = 'MIGRATION-MCP-CREDENTIALS.json'
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) ("skills-manager-migration-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $packageFolder = if ([string]::IsNullOrWhiteSpace($options.version)) { "skills-manager-migration-{0}" -f $options.mode } else { "skills-manager-{0}-{1}" -f $options.version, $options.mode }
        $packageRoot = Join-Path $work $packageFolder
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
        $manifest = [ordered]@{
            schema_version = 1
            product = 'skills-manager'
            kind = 'migration'
            delivery_version = if ([string]::IsNullOrWhiteSpace($options.version)) { $null } else { $options.version }
            mode = $options.mode
            created_at = (Get-Date).ToUniversalTime().ToString('o')
            skills = @($skillNames)
            mcp_servers = @($mcpNames)
            private_use_only = $privateMode
            includes_credentials = $privateMode
            credentials_encrypted = $false
            includes_materialized_sources = ($options.mode -ne 'rescan')
            development_ready = $false
            restore_ready = ($options.mode -ne 'rescan')
            git_history_included = $false
            license_file = if ($options.mode -ne 'rescan' -and (Test-Path -LiteralPath (Join-Path $Root 'LICENSE') -PathType Leaf)) { 'LICENSE' } else { $null }
            source_directories = if ($options.mode -ne 'rescan') { @('src','config','tests','scripts','docs','rules','overrides','vendor','imports','agent','references','.github') } else { @() }
            credential_file = $credentialFileName
            apply = if ($options.mode -eq 'rescan') {
                @('先在新电脑安装同版本的 skills-manager', '在新电脑运行 skills.ps1 发现', '按需运行 skills.ps1 安装 和 同步MCP')
            } elseif ($privateMode) {
                @('解压后运行 migration-apply（本包为明文私用快照，不需要口令）', '不要上传公共 GitHub、公共 Release 或公共网盘', '公共 Git clone/fork/tag 才是持续开发真值；本快照不含 Git 历史', '在新电脑开启全新宿主会话验证')
            } else {
                @('解压后运行 migration-apply', '公共 Git clone/fork/tag 才是持续开发真值；本快照不含 Git 历史', '在新电脑开启全新宿主会话验证')
            }
        }
        $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $packageRoot 'MIGRATION-MANIFEST.json') -Encoding utf8
        if ($null -ne $credentialPayload) {
            $credentialPayload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $packageRoot $credentialFileName) -Encoding utf8
        }
        if ($options.mode -ne 'rescan') {
            $migrationCfg = New-MigrationConfig $cfg $options.mode $skillNames $mcpNames
            $migrationCfg | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $packageRoot 'skills.json') -Encoding utf8
            foreach ($name in @('skills.lock.json','setup.cmd','install.ps1','build.ps1','skills.cmd','skills.ps1','LICENSE','README.md','README.en.md','AGENTS.md','CODE_OF_CONDUCT.md','CONTRIBUTING.md','SECURITY.md','.gitignore')) {
                $source = Join-Path $Root $name
                if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $name) -Force }
            }
            foreach ($directory in @('src','config','tests','scripts','docs','rules')) {
                $source = Join-Path $Root $directory
                if (Test-Path -LiteralPath $source -PathType Container) { Copy-MigrationTree $source (Join-Path $packageRoot $directory) | Out-Null }
            }
            foreach ($directory in @('references','.github')) {
                $source = Join-Path $Root $directory
                if (Test-Path -LiteralPath $source -PathType Container) { Copy-MigrationTree $source (Join-Path $packageRoot $directory) | Out-Null }
            }
            if (Test-Path -LiteralPath (Join-Path $Root 'overrides') -PathType Container) { Copy-MigrationTree (Join-Path $Root 'overrides') (Join-Path $packageRoot 'overrides') | Out-Null }
            $sourceRoots = @('vendor','imports')
            foreach ($relativeSource in @($sourceRoots | Sort-Object -Unique)) {
                $source = Join-Path $Root $relativeSource
                $destination = Join-Path $packageRoot $relativeSource
                if (Test-Path -LiteralPath $source -PathType Container) { Copy-MigrationTree $source $destination | Out-Null }
            }
            if ($options.mode -eq 'private-all') {
                if (Test-Path -LiteralPath $AgentDir -PathType Container) { Copy-MigrationTree $AgentDir (Join-Path $packageRoot 'agent') | Out-Null }
            }
            else {
                $agentTarget = Join-Path $packageRoot 'agent'; New-Item -ItemType Directory -Path $agentTarget -Force | Out-Null
                foreach ($name in $skillNames) {
                    $source = Join-Path $AgentDir $name
                    if (Test-Path -LiteralPath $source -PathType Container) { Copy-MigrationTree $source (Join-Path $agentTarget $name) | Out-Null }
                }
            }
        }
        $contentEntries = @(Get-PackageFileEntries $packageRoot)
        [ordered]@{ schema_version = 1; files = @($contentEntries) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'MIGRATION-CONTENT.json') -Encoding utf8
        Assert-MigrationContentIntegrity $packageRoot $manifest | Out-Null
        if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }
        $archive = New-VerifiedPackageArchive $packageRoot $outPath
        $result = [pscustomobject]@{ mode = $options.mode; path = $archive.path; size = $archive.size; sha256 = $archive.sha256; skills = @($skillNames); mcp_servers = @($mcpNames) }
        if ($options.json) { return ($result | ConvertTo-Json -Depth 8) }
        Write-Host ("迁移包已生成：{0}" -f $outPath) -ForegroundColor Green
        Write-Host ("模式={0}，技能={1}，MCP={2}，SHA-256={3}" -f $options.mode, $skillNames.Count, $mcpNames.Count, $result.sha256)
        return $result
    }
    finally { if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } }
}
