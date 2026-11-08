# GitLISP managed deployment v2
# Copyright (c) 2026 Denon Deterding. MIT License.
# Run in the target user's Windows context. Dot-source to import helpers without installing.
[CmdletBinding()]
param(
    [string]$Ref = 'main',
    [ValidateSet('Stable', 'Development')][string]$Channel = 'Stable',
    [string]$Token = $env:GITLISP_TOKEN,
    [string]$ContextFile,
    [string]$RequestedRef
)

Set-StrictMode -Version Latest

function Get-GitLISPPaths {
    $bundle = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins\3DingGitHub.bundle'))
    $data = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA '3Ding\GitHub'))
    @{ Bundle = $bundle; Data = $data; Work = (Join-Path $data 'installer') }
}

function Get-PathKey([string]$Path) {
    $Path.Trim(' ', '"').Replace('/', '\').TrimEnd('\').ToUpperInvariant()
}

function Assert-OrdinaryPath([string]$Path) {
    $item = [IO.Path]::GetFullPath($Path)
    while ($item) {
        if ([IO.File]::Exists($item) -or [IO.Directory]::Exists($item)) {
            if (([IO.File]::GetAttributes($item) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'A deployment path contains a reparse point.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($item)
        if ($parent -eq $item) { break }
        $item = $parent
    }
}

function Assert-OrdinaryTree([string]$Path) {
    Assert-OrdinaryPath $Path
    if ([IO.Directory]::Exists($Path)) {
        foreach ($item in Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) {
            Assert-OrdinaryPath $item.FullName
            if ($item.PSIsContainer) { Assert-OrdinaryTree $item.FullName }
        }
    }
}

# A small data reader for the existing AutoLISP ownership journal; never evaluates code.
function Read-LispData([string]$Text) {
    $state = @{ Text = $Text; Pos = 0 }
    function Read-Node($s) {
        while ($s.Pos -lt $s.Text.Length -and [char]::IsWhiteSpace($s.Text[$s.Pos])) { $s.Pos++ }
        if ($s.Pos -ge $s.Text.Length) { throw 'Incomplete setup data.' }
        $c = $s.Text[$s.Pos]; $s.Pos++
        if ($c -eq '(') {
            $items = [Collections.Generic.List[object]]::new()
            while ($true) {
                while ($s.Pos -lt $s.Text.Length -and [char]::IsWhiteSpace($s.Text[$s.Pos])) { $s.Pos++ }
                if ($s.Pos -ge $s.Text.Length) { throw 'Incomplete setup list.' }
                if ($s.Text[$s.Pos] -eq ')') {
                    $s.Pos++
                    return [pscustomobject]@{ Kind = 'List'; Items = $items.ToArray() }
                }
                if ($s.Text[$s.Pos] -eq '.') {
                    $s.Pos++
                    if ($items.Count -ne 1) { throw 'Invalid setup pair.' }
                    $tail = Read-Node $s
                    while ($s.Pos -lt $s.Text.Length -and [char]::IsWhiteSpace($s.Text[$s.Pos])) { $s.Pos++ }
                    if ($s.Pos -ge $s.Text.Length -or $s.Text[$s.Pos] -ne ')') { throw 'Invalid setup pair ending.' }
                    $s.Pos++
                    return [pscustomobject]@{ Kind = 'Pair'; Key = $items[0]; Value = $tail }
                }
                $items.Add((Read-Node $s))
            }
        }
        if ($c -eq '"') {
            $out = [Text.StringBuilder]::new()
            while ($s.Pos -lt $s.Text.Length) {
                $c = $s.Text[$s.Pos]; $s.Pos++
                if ($c -eq '"') { return $out.ToString() }
                if ($c -eq '\') {
                    if ($s.Pos -ge $s.Text.Length) { throw 'Incomplete setup escape.' }
                    $c = $s.Text[$s.Pos]; $s.Pos++
                    switch ($c) {
                        '\' { [void]$out.Append('\') }
                        '"' { [void]$out.Append('"') }
                        'n' { [void]$out.Append("`n") }
                        'r' { [void]$out.Append("`r") }
                        't' { [void]$out.Append("`t") }
                        default { throw 'Unsupported setup escape.' }
                    }
                } else { [void]$out.Append($c) }
            }
            throw 'Unterminated setup string.'
        }
        $start = $s.Pos - 1
        while ($s.Pos -lt $s.Text.Length -and -not [char]::IsWhiteSpace($s.Text[$s.Pos]) -and $s.Text[$s.Pos] -ne ')') { $s.Pos++ }
        $atom = $s.Text.Substring($start, $s.Pos - $start)
        if ($atom -eq 'nil') { return $null }
        if ($atom -match '^\d+$') { return [long]::Parse($atom) }
        throw 'Unexpected setup-data token.'
    }
    $root = Read-Node $state
    while ($state.Pos -lt $Text.Length -and [char]::IsWhiteSpace($Text[$state.Pos])) { $state.Pos++ }
    if ($state.Pos -ne $Text.Length) { throw 'Extra expressions in setup data.' }
    $root
}

function Quote-Lisp([string]$Value) {
    if ($Value -match '[\x00-\x1F]') { throw 'Control characters in setup metadata.' }
    '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-SetupRecords([string]$File, $Paths) {
    Assert-OrdinaryPath $File
    if (-not [IO.File]::Exists($File)) { throw 'An existing bundle has no valid ownership journal.' }
    $root = Read-LispData ([IO.File]::ReadAllText($File))
    if ($root.Kind -ne 'List' -or $root.Items.Count -ne 3) { throw 'Unrecognized setup journal.' }
    $product = @($root.Items | Where-Object { $_.Kind -eq 'Pair' -and $_.Key -eq 'product' })
    $version = @($root.Items | Where-Object { $_.Kind -eq 'Pair' -and $_.Key -eq 'version' })
    $profiles = @($root.Items | Where-Object { $_.Kind -eq 'List' -and $_.Items.Count -gt 0 -and $_.Items[0] -eq 'profiles' })
    if ($product.Count -ne 1 -or $product[0].Value -ne '3Ding.GitHub' -or $version.Count -ne 1 -or $version[0].Value -ne 1 -or $profiles.Count -ne 1) {
        throw 'Unrecognized setup owner/version.'
    }
    $allowed = @((Get-PathKey (Join-Path $Paths.Bundle 'Contents')), (Get-PathKey (Join-Path $Paths.Data 'sources\...')))
    foreach ($entry in @($profiles[0].Items | Select-Object -Skip 1)) {
        if ($entry.Kind -ne 'List' -or $entry.Items.Count -lt 1 -or $entry.Items[0] -isnot [string]) { throw 'Invalid recorded profile.' }
        $key = $entry.Items[0]
        if ($key -notmatch '^HKEY_CURRENT_USER\\Software\\Autodesk\\AutoCAD[^\\]*\\.+\\Profiles\\.+\\Variables$') { throw 'Unexpected profile registry location.' }
        $added = @($entry.Items | Select-Object -Skip 1)
        foreach ($path in $added) {
            if ($path -isnot [string] -or (Get-PathKey $path) -notin $allowed) { throw 'Unexpected recorded trust path.' }
        }
        [pscustomobject]@{ Key = $key; Added = $added }
    }
}

function Write-SetupJournal([string]$File, $Records) {
    $entries = foreach ($record in $Records) {
        '(' + (Quote-Lisp $record.Key) + $(if ($record.Added.Count) { ' ' + (($record.Added | ForEach-Object { Quote-Lisp $_ }) -join ' ') }) + ')'
    }
    $text = '(("product" . "3Ding.GitHub") ("version" . 1) ("profiles"' + $(if ($entries) { ' ' + ($entries -join ' ') }) + '))'
    [IO.File]::WriteAllText($File, $text + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Get-AutoCADProfiles {
    foreach ($family in @('Software\Autodesk\AutoCAD', 'Software\Autodesk\AutoCAD LT')) {
        $base = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($family)
        if (-not $base) { continue }
        try {
            foreach ($release in $base.GetSubKeyNames()) {
                $r = $base.OpenSubKey($release)
                try {
                    foreach ($product in $r.GetSubKeyNames()) {
                        $profiles = $r.OpenSubKey($product + '\Profiles')
                        if (-not $profiles) { continue }
                        try {
                            foreach ($name in $profiles.GetSubKeyNames()) {
                                $variables = $profiles.OpenSubKey($name + '\Variables')
                                if (-not $variables) { continue }
                                try {
                                    $exists = $variables.GetValueNames() -contains 'TRUSTEDPATHS'
                                    $value = if ($exists) { [string]$variables.GetValue('TRUSTEDPATHS', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { '' }
                                    [pscustomobject]@{ Key = 'HKEY_CURRENT_USER\' + $family + '\' + $release + '\' + $product + '\Profiles\' + $name + '\Variables'; Old = $value; Existed = $exists }
                                } finally { $variables.Dispose() }
                            }
                        } finally { $profiles.Dispose() }
                    }
                } finally { $r.Dispose() }
            }
        } finally { $base.Dispose() }
    }
}

function Set-ProfileTrust([string]$Key, [string]$Value, [bool]$Remove = $false) {
    if ($Key -notmatch '^HKEY_CURRENT_USER\\Software\\Autodesk\\AutoCAD[^\\]*\\.+\\Profiles\\.+\\Variables$') { throw 'Unexpected profile registry location.' }
    $relative = $Key.Substring('HKEY_CURRENT_USER\'.Length)
    $registry = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($relative, $true)
    if (-not $registry) { throw 'A recorded profile is unavailable or locked.' }
    try {
        if ($Remove) { $registry.DeleteValue('TRUSTEDPATHS', $false) }
        else { $registry.SetValue('TRUSTEDPATHS', $Value, [Microsoft.Win32.RegistryValueKind]::String) }
    } finally { $registry.Dispose() }
}

function Get-ProfileTrustValue([string]$Key) {
    $relative = $Key.Substring('HKEY_CURRENT_USER\'.Length)
    $registry = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($relative)
    if (-not $registry) { throw 'A recorded profile is unavailable.' }
    try { [string]$registry.GetValue('TRUSTEDPATHS', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $registry.Dispose() }
}

function Get-GitBytes($Client, [string]$Url, [string]$Accept = 'application/vnd.github+json') {
    $uri = [uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('api.github.com', 'raw.githubusercontent.com') -or $uri.Port -ne 443 -or $uri.UserInfo) {
        throw 'Blocked an unexpected download destination.'
    }
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $uri)
    [void]$request.Headers.TryAddWithoutValidation('Accept', $Accept)
    try {
        $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -ne 200) { throw ('GitHub download failed with HTTP ' + [int]$response.StatusCode + '.') }
            $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            if ($bytes.Length -gt 5242880) { throw 'An installer download exceeded the size limit.' }
            return ,$bytes
        } finally { $response.Dispose() }
    } finally { $request.Dispose() }
}

function Get-GitBlobHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $header = [Text.Encoding]::ASCII.GetBytes('blob ' + $Bytes.Length + [char]0)
        $all = [byte[]]::new($header.Length + $Bytes.Length)
        [Buffer]::BlockCopy($header, 0, $all, 0, $header.Length)
        [Buffer]::BlockCopy($Bytes, 0, $all, $header.Length, $Bytes.Length)
        ([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Write-BundleManifest([string]$File) {
    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" AppVersion="1.1.0" Name="GitLISP" Description="GitHub-backed AutoLISP loading" Author="Denon Deterding" ProductCode="{885A15C9-1E61-4EAA-80D5-F5F2EC3159A0}" UpgradeCode="{BA3E6C93-9B2B-47A2-A853-85AE629BE249}" Helpfile="./README.md">
  <CompanyDetails Name="3Ding" />
  <Components>
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R24.0" />
    <ComponentEntry AppName="3DingGitHub" ModuleName="./Contents/GitHub.lsp" PerDocument="True" />
    <ComponentEntry AppName="3DingGitHubSetup" ModuleName="./Contents/Install.lsp" PerDocument="True" />
  </Components>
</ApplicationPackage>
'@
    [IO.File]::WriteAllText($File, $xml, [Text.UTF8Encoding]::new($false))
}

function Remove-DeploymentStage([string]$Stage, [string]$Bundle) {
    $root = [IO.Path]::GetFullPath($Bundle).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Stage)
    if ([IO.Path]::GetDirectoryName($target) -ne $root -or [IO.Path]::GetFileName($target) -notmatch '^\.deploy-[0-9a-f]{32}$') {
        throw 'Refusing an unexpected deployment cleanup path.'
    }
    Assert-OrdinaryTree $target
    if ([IO.Directory]::Exists($target)) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop }
}

function Invoke-GitLISPDeployment {
    [CmdletBinding()]
    param([string]$Ref = 'main', [string]$Channel = 'Stable', [string]$Token, [string]$ContextFile, [string]$RequestedRef)
    $ErrorActionPreference = 'Stop'
    $paths = $null; $lock = $null; $client = $null; $stage = $null
    $created = $false; $committed = $false; $recovery = $false; $ownsLock = $false
    $changes = [Collections.Generic.List[object]]::new()
    $moves = [Collections.Generic.List[object]]::new()
    $code = 1; $sha = $null; $message = 'Installation did not complete.'
    try {
        if ($env:OS -ne 'Windows_NT') { throw 'This installer requires Windows.' }
        if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
            throw 'Deploy in the target user context, not SYSTEM or a service account.'
        }
        if ($Ref -notmatch '^[A-Za-z0-9._/@+-]{1,200}$' -or $Ref.Contains('..') -or $Channel -notin @('Stable','Development')) { throw 'Invalid source ref or channel.' }
        $Channel = if ($Channel -ieq 'Development') { 'Development' } else { 'Stable' }
        if (-not $RequestedRef) { $RequestedRef=$Ref }
        if ($RequestedRef -notmatch '^[A-Za-z0-9._/@+-]{1,200}$' -or $RequestedRef.Contains('..')) { throw 'Invalid requested source ref.' }
        if ($Token -and $Token -match '[^\x21-\x7E]') { throw 'Invalid token format.' }
        $paths = Get-GitLISPPaths
        Assert-OrdinaryTree $paths.Bundle
        Assert-OrdinaryPath $paths.Work
        $context = $null
        if ($ContextFile) {
            $fullContext = [IO.Path]::GetFullPath($ContextFile)
            if ([IO.Path]::GetDirectoryName($fullContext) -ne $paths.Work) { throw 'Invalid AutoCAD deployment context location.' }
            Assert-OrdinaryPath $fullContext
            $node = Read-LispData ([IO.File]::ReadAllText($fullContext))
            if ($node.Kind -ne 'List' -or $node.Items.Count -ne 3) { throw 'Invalid AutoCAD deployment context.' }
            $context = @{}
            foreach ($pair in $node.Items) {
                if ($pair.Kind -ne 'Pair' -or $pair.Key -notin @('profile','trusted','hwnd') -or $context.ContainsKey($pair.Key)) { throw 'Invalid AutoCAD context field.' }
                $context[$pair.Key] = $pair.Value
            }
            if ($context.profile -isnot [string] -or $context.trusted -isnot [string] -or $context.hwnd -isnot [long]) { throw 'Invalid AutoCAD context values.' }
        }
        $running = @(Get-Process -Name acad,acadlt,accoreconsole -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId })
        if ($running.Count -gt 0 -and (-not $context -or $running.Count -ne 1 -or (($running[0].MainWindowHandle.ToInt64() -band 4294967295) -ne ($context.hwnd -band 4294967295)))) {
            $code = 1618; throw 'Close other AutoCAD sessions before deploying.'
        }
        $records = @()
        if ([IO.Directory]::Exists($paths.Bundle)) {
            if ([IO.File]::Exists((Join-Path $paths.Bundle 'pending-deploy.json'))) { $code = 1003; throw 'A previous deployment needs recovery; its backups were preserved.' }
            if ([IO.File]::Exists((Join-Path $paths.Bundle 'install.dat.bak')) -or [IO.File]::Exists((Join-Path $paths.Bundle 'install.dat.new'))) { $code=1003; throw 'Setup ownership metadata needs recovery before deployment.' }
            $records = @(Get-SetupRecords (Join-Path $paths.Bundle 'install.dat') $paths)
        } else {
            [void][IO.Directory]::CreateDirectory($paths.Bundle); $created = $true
        }
        if ([IO.File]::Exists((Join-Path $paths.Bundle '.deploy.lock')) -or [IO.Directory]::Exists((Join-Path $paths.Bundle '.deploy.lock'))) { $code=1618; throw 'Another installation or a stale deployment lock exists.' }
        $lock = [IO.File]::Open((Join-Path $paths.Bundle '.deploy.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $ownsLock=$true
        $stage = Join-Path $paths.Bundle ('.deploy-' + [guid]::NewGuid().ToString('N'))
        $fresh = Join-Path $stage 'new'; $backup = Join-Path $stage 'backup'
        [void][IO.Directory]::CreateDirectory((Join-Path $fresh 'Contents'))
        [void][IO.Directory]::CreateDirectory($backup)
        Add-Type -AssemblyName System.Net.Http
        $handler = [Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect = $false
        $client = [Net.Http.HttpClient]::new($handler); $client.Timeout = [TimeSpan]::FromSeconds(30)
        $client.MaxResponseContentBufferSize = 5242880
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent','GitLISP-Installer')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('X-GitHub-Api-Version','2026-03-10')
        if ($Token) { [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Authorization','Bearer ' + $Token) }
        Write-Output ('GitLISP: resolving ' + $Ref + ' (' + $Channel + ').')
        $sha = if ($Ref -match '^[0-9a-fA-F]{40}$') { $Ref.ToLowerInvariant() } else {
            [Text.Encoding]::UTF8.GetString((Get-GitBytes $client ('https://api.github.com/repos/CODED1NG/GitLISP/commits/' + [uri]::EscapeDataString($Ref)) 'application/vnd.github.sha')).Trim()
        }
        if ($sha -notmatch '^[0-9a-fA-F]{40}$') { throw 'GitHub did not return a full commit SHA.' }
        $tree = [Text.Encoding]::UTF8.GetString((Get-GitBytes $client ('https://api.github.com/repos/CODED1NG/GitLISP/git/trees/' + $sha + '?recursive=1'))) | ConvertFrom-Json
        if ($tree.truncated -or -not $tree.tree) { throw 'The installer source tree is incomplete.' }
        $payload = [ordered]@{'GitHub.lsp'='Contents\GitHub.lsp';'Install.lsp'='Contents\Install.lsp';'Deploy.ps1'='Contents\Deploy.ps1';'README.md'='README.md';'LICENSE'='LICENSE'}
        foreach ($name in $payload.Keys) {
            $entry = @($tree.tree | Where-Object { $_.path -ceq $name -and $_.type -eq 'blob' -and $_.mode -in @('100644','100755') })
            if ($entry.Count -ne 1 -or $entry[0].size -le 0 -or $entry[0].size -gt 5242880) { throw ('Missing or invalid installer file: ' + $name) }
            Write-Output ('GitLISP: downloading ' + $name + '.')
            $bytes = Get-GitBytes $client ('https://raw.githubusercontent.com/CODED1NG/GitLISP/' + $sha + '/' + $name) 'application/octet-stream'
            if ($bytes.Length -ne $entry[0].size -or (Get-GitBlobHash $bytes) -ne $entry[0].sha) { throw ('Verification failed: ' + $name) }
            [IO.File]::WriteAllBytes((Join-Path $fresh $payload[$name]),$bytes)
        }
        $profiles = @(Get-AutoCADProfiles)
        if ($context -and @($profiles | Where-Object { $_.Key -eq $context.profile }).Count -ne 1) { throw 'The originating AutoCAD profile is unavailable.' }
        $wanted = @((Join-Path $paths.Bundle 'Contents'), (Join-Path $paths.Data 'sources\...'))
        foreach ($profile in $profiles) {
            $old = if ($context -and $profile.Key -eq $context.profile) { $context.trusted } else { $profile.Old }
            $entries = @($old.Split(';') | Where-Object { $_ -ne '' })
            $keys = @($entries | ForEach-Object { Get-PathKey $_ })
            $added = @($wanted | Where-Object { (Get-PathKey $_) -notin $keys })
            if ($added.Count) {
                $records += [pscustomobject]@{ Key = $profile.Key; Added = $added }
                if (-not $context -or $profile.Key -ne $context.profile) {
                    $changes.Add([pscustomobject]@{ Key=$profile.Key; Old=$profile.Old; Existed=$profile.Existed; New=(($entries + $added) -join ';'); Applied=$false })
                }
            }
        }
        Write-SetupJournal (Join-Path $fresh 'install.dat') $records
        [void](Get-SetupRecords (Join-Path $fresh 'install.dat') $paths)
        $release = '(("repository" . "CODED1NG/GitLISP") ("ref" . ' + (Quote-Lisp $RequestedRef) + ') ("commit" . ' + (Quote-Lisp $sha) + ') ("channel" . ' + (Quote-Lisp $Channel) + '))'
        [IO.File]::WriteAllText((Join-Path $fresh 'release.dat'),$release,[Text.UTF8Encoding]::new($false))
        Write-BundleManifest (Join-Path $fresh 'PackageContents.xml')
        $pending = Join-Path $paths.Bundle 'pending-deploy.json'
        [IO.File]::WriteAllText($pending,(@{ Stage=$stage; Commit=$sha; Profiles=@($changes) } | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        # Disable discovery while files change. Every target has a backup or a recorded new-file hash.
        $targets = @('PackageContents.xml','install.dat') + @($payload.Values) + @('release.dat')
        foreach ($relative in $targets) {
            $target = Join-Path $paths.Bundle $relative; $saved = Join-Path $backup $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved))
            $move = [pscustomobject]@{ Target=$target; Backup=$saved; Original=[IO.File]::Exists($target); Installed=$false; Hash=$null }
            $moves.Add($move)
            if ($move.Original) { Move-Item -LiteralPath $target -Destination $saved -ErrorAction Stop }
            if ($relative -ne 'PackageContents.xml') {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
                Move-Item -LiteralPath (Join-Path $fresh $relative) -Destination $target -ErrorAction Stop
                $move.Installed=$true; $move.Hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            }
        }
        foreach ($change in $changes) {
            $change.Applied=$true
            Set-ProfileTrust $change.Key $change.New
        }
        $activation = $moves[0]
        Move-Item -LiteralPath (Join-Path $fresh 'PackageContents.xml') -Destination $activation.Target -ErrorAction Stop
        $activation.Installed=$true; $activation.Hash=(Get-FileHash -LiteralPath $activation.Target -Algorithm SHA256).Hash
        $committed=$true; $code=0
        $message='Installed commit ' + $sha.Substring(0,12) + ' (' + $Channel + '). Restart AutoCAD.'
    } catch {
        $message=$_.Exception.Message
        if ($lock -and -not $committed) {
            foreach ($change in @($changes | Where-Object Applied)) {
                try {
                    $current = Get-ProfileTrustValue $change.Key
                    if ($current -eq $change.New) { Set-ProfileTrust $change.Key $change.Old (-not $change.Existed) }
                    elseif ($current -ne $change.Old) { throw 'A profile changed during deployment.' }
                } catch { $recovery=$true }
            }
            for ($index=$moves.Count-1; $index -ge 0; $index--) {
                $move=$moves[$index]
                try {
                    if ($move.Installed -and [IO.File]::Exists($move.Target)) {
                        if ((Get-FileHash -LiteralPath $move.Target -Algorithm SHA256).Hash -ne $move.Hash) { throw 'An installed file changed during rollback.' }
                        Remove-Item -LiteralPath $move.Target -ErrorAction Stop
                    }
                    if ($move.Original -and [IO.File]::Exists($move.Backup)) {
                        if ([IO.File]::Exists($move.Target)) { throw 'A rollback destination changed.' }
                        Move-Item -LiteralPath $move.Backup -Destination $move.Target -ErrorAction Stop
                    }
                } catch { $recovery=$true }
            }
            if ($recovery) { $code=1003; $message += ' Recovery data was preserved inside the bundle.' }
        }
    } finally {
        if ($client) { $client.Dispose() }
        $Token=$null
        if ($stage -and -not $recovery) {
            try { Remove-DeploymentStage $stage $paths.Bundle } catch { $recovery=$true; $code=1003; $message += ' Deployment cleanup needs recovery.' }
        }
        if ($lock) {
            $lock.Dispose()
            $lockPath=Join-Path $paths.Bundle '.deploy.lock'
            if ([IO.File]::Exists($lockPath)) { Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue }
        }
        if ($ownsLock -and $paths -and -not $recovery -and [IO.Directory]::Exists($paths.Bundle)) {
            $pending=Join-Path $paths.Bundle 'pending-deploy.json'
            if ([IO.File]::Exists($pending)) { Remove-Item -LiteralPath $pending -ErrorAction SilentlyContinue }
            if ($created -and -not $committed) {
                $contents=Join-Path $paths.Bundle 'Contents'
                if ([IO.Directory]::Exists($contents) -and @(Get-ChildItem -LiteralPath $contents -Force).Count -eq 0) { [IO.Directory]::Delete($contents) }
                if (@(Get-ChildItem -LiteralPath $paths.Bundle -Force).Count -eq 0) { [IO.Directory]::Delete($paths.Bundle) }
            }
        }
        if ($paths) {
            try {
                Assert-OrdinaryPath $paths.Work
                [void][IO.Directory]::CreateDirectory($paths.Work)
                $report=Join-Path $paths.Work 'last-result.json'
                Assert-OrdinaryPath $report
                [IO.File]::WriteAllText($report,(@{ ExitCode=$code; Message=$message; Commit=$sha; Channel=$Channel } | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            } catch { Write-Warning 'GitLISP: could not write the local deployment report.' }
        }
    }
    Write-Output ('GitLISP: ' + $message)
    return $code
}

if ($MyInvocation.InvocationName -ne '.') {
    $output = @(Invoke-GitLISPDeployment -Ref $Ref -Channel $Channel -Token $Token -ContextFile $ContextFile -RequestedRef $RequestedRef)
    $exitCode = [int]$output[-1]
    $output | Select-Object -SkipLast 1 | Write-Output
    exit $exitCode
}

