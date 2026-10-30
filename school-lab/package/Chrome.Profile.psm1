#requires -Version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
$script:json = [Web.Script.Serialization.JavaScriptSerializer]::new()
$script:json.MaxJsonLength = 16777216

function Write-SfitProfileJson([string]$Path,$Value) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temp,$Path) }
}

function Assert-SfitPlainPath([string]$Path) {
    $item = [IO.Path]::GetFullPath($Path)
    while ($item) {
        if ((Test-Path -LiteralPath $item) -and ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refuse reparse point: $item" }
        $item = Split-Path -Parent $item
    }
}

function Get-SfitChromeDataPath([string]$LocalAppDataDirectory) {
    if (-not [IO.Path]::IsPathRooted($LocalAppDataDirectory) -or $LocalAppDataDirectory.StartsWith('\\')) { throw 'LOCALAPPDATA must be an absolute local path.' }
    $local = [IO.Path]::GetFullPath($LocalAppDataDirectory).TrimEnd('\')
    if ($local.TrimEnd('\') -eq [IO.Path]::GetPathRoot($local).TrimEnd('\')) { throw 'Refuse a drive root as LOCALAPPDATA.' }
    $data = [IO.Path]::GetFullPath((Join-Path $local 'Google\Chrome\User Data'))
    if (-not $data.StartsWith($local+'\Google\Chrome\',[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $data) -ne 'User Data') { throw 'Chrome data path escaped its expected location.' }
    Assert-SfitPlainPath $data
    $data
}

function Get-SfitChromeProfiles([string]$UserDataDirectory) {
    $names = @()
    if (Test-Path -LiteralPath $UserDataDirectory) {
        $names += @(Get-ChildItem -LiteralPath $UserDataDirectory -Directory -Force | Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile [0-9]+$' } | ForEach-Object Name)
        $localState = Join-Path $UserDataDirectory 'Local State'
        if (Test-Path -LiteralPath $localState) {
            $state = $script:json.DeserializeObject([IO.File]::ReadAllText($localState))
            if ($state -is [Collections.IDictionary] -and $state.ContainsKey('profile') -and $state['profile'].ContainsKey('info_cache')) {
                $names += @($state['profile']['info_cache'].Keys)
            }
        }
    }
    @($names | Sort-Object -Unique)
}

# Read-only selection: never edit Preferences, Local State, shortcuts or profiles.
function Get-SfitChromeProfileSelection {
    param([string]$LocalAppDataDirectory,[string]$ProfilePath='')
    $data = Get-SfitChromeDataPath $LocalAppDataDirectory
    if (-not $ProfilePath) {
        $stateFile = Join-Path $data 'Local State'
        if (Test-Path -LiteralPath $stateFile) {
            $state = $script:json.DeserializeObject([IO.File]::ReadAllText($stateFile))
            if ($state.ContainsKey('profile') -and $state['profile'].ContainsKey('last_used')) {
                $name = [string]$state['profile']['last_used']
                if ($name) { $ProfilePath = Join-Path $data $name }
            }
        }
        if (-not $ProfilePath) {
            $names = @(Get-SfitChromeProfiles $data)
            if ($names.Count -gt 1) { throw 'Multiple Chrome profiles with no last-used profile. Open the intended Chrome profile, then rerun.' }
            if ($names.Count -eq 1) { $ProfilePath = Join-Path $data $names[0] }
            else { $ProfilePath = Join-Path $data 'Default' }
        }
    }
    $full = [IO.Path]::GetFullPath($ProfilePath).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ine $data -or [IO.Path]::GetFileName($full) -in @('Guest Profile','System Profile','.','..')) {
        throw 'Unsupported Chrome profile path. Use a normal profile under the standard Chrome User Data directory.'
    }
    Assert-SfitPlainPath $full
    [pscustomobject]@{UserDataDirectory=$data;ProfileDirectory=[IO.Path]::GetFileName($full);ProfilePath=$full}
}

function Get-SfitPinnedExtensions([string]$ProfilePath) {
    Assert-SfitPlainPath $ProfilePath
    $path = Join-Path $ProfilePath 'Preferences'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $prefs = $script:json.DeserializeObject([IO.File]::ReadAllText($path))
    if ($prefs.ContainsKey('extensions') -and $prefs['extensions'].ContainsKey('pinned_extensions')) {
        foreach ($id in @($prefs['extensions']['pinned_extensions'])) {
            if ([string]$id -notmatch '^[a-p]{32}$') { throw 'Invalid pinned extension ID in Chrome Preferences; no preferences were modified.' }
            [string]$id
        }
    }
}

function Undo-SfitOwnedMapChanges([Collections.IDictionary]$Current,[Collections.IDictionary]$Applied,[Collections.IDictionary]$Original) {
    foreach ($name in @($Applied.Keys)) {
        $hadOriginal = $Original.ContainsKey($name)
        if ($hadOriginal -and $script:json.Serialize($Applied[$name]) -ceq $script:json.Serialize($Original[$name])) { continue }
        if (-not $Current.ContainsKey($name)) { continue }
        if ($Applied[$name] -is [Collections.IDictionary] -and $Current[$name] -is [Collections.IDictionary]) {
            $oldMap = if ($hadOriginal -and $Original[$name] -is [Collections.IDictionary]) { $Original[$name] } else { @{} }
            Undo-SfitOwnedMapChanges $Current[$name] $Applied[$name] $oldMap
            if (-not $hadOriginal -and $Current[$name].Count -eq 0) { $null = $Current.Remove($name) }
        } elseif ($script:json.Serialize($Current[$name]) -ceq $script:json.Serialize($Applied[$name])) {
            if ($hadOriginal) { $Current[$name] = $Original[$name] } else { $null = $Current.Remove($name) }
        }
    }
}

function Remove-SfitLegacyPolicies {
    param([string]$StatePath,[string]$RegistryPath='HKLM:\SOFTWARE\Policies\Google\Chrome')
    if (-not (Test-Path -LiteralPath $StatePath)) { return [pscustomobject]@{Status='NotPresent';ChangedNames=@()} }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.Schema -ne 1 -or $state.RegistryPath -ine $RegistryPath) { throw 'Legacy policy journal does not match the expected Chrome registry path.' }
    if ($state.Status -in @('Restored','Removed')) { return [pscustomobject]@{Status='AlreadyRemoved';ChangedNames=@()} }
    $known = @('BrowserAddPersonEnabled','BrowserGuestModeEnabled','IncognitoModeAvailability','BrowserSignin','SyncDisabled','ExtensionSettings')
    $changed = @()
    if (Test-Path -LiteralPath $RegistryPath) {
        $key = Get-Item -LiteralPath $RegistryPath
        foreach ($old in $state.Original) {
            if ($old.Name -notin $known) { throw 'Unexpected policy name in legacy journal.' }
            $applied = @($state.Applied | Where-Object Name -eq $old.Name)
            if ($applied.Count -ne 1) { throw 'Incomplete legacy policy journal.' }
            if ($old.Name -notin $key.GetValueNames()) { continue }
            $now = $key.GetValue($old.Name,$null,'DoNotExpandEnvironmentNames')
            if ($old.Name -eq 'ExtensionSettings') {
                $currentMap = $script:json.DeserializeObject([string]$now)
                $appliedMap = $script:json.DeserializeObject([string]$applied[0].Value)
                $originalMap = if ($old.Exists) { $script:json.DeserializeObject([string]$old.Value) } else { @{} }
                if ($currentMap -isnot [Collections.IDictionary] -or $appliedMap -isnot [Collections.IDictionary] -or $originalMap -isnot [Collections.IDictionary]) { throw 'Invalid legacy ExtensionSettings object.' }
                $before = $script:json.Serialize($currentMap)
                Undo-SfitOwnedMapChanges $currentMap $appliedMap $originalMap
                $after = $script:json.Serialize($currentMap)
                if ($before -cne $after) {
                    if ($currentMap.Count -eq 0 -and -not $old.Exists) { Remove-ItemProperty -LiteralPath $RegistryPath -Name $old.Name }
                    else { Set-ItemProperty -LiteralPath $RegistryPath -Name $old.Name -Value $after }
                    $changed += $old.Name
                }
            } elseif ([string]$now -ceq [string]$applied[0].Value -and $key.GetValueKind($old.Name).ToString() -eq $applied[0].Kind) {
                if ($old.Exists) { New-ItemProperty -LiteralPath $RegistryPath -Name $old.Name -Value $old.Value -PropertyType $old.Kind -Force | Out-Null }
                else { Remove-ItemProperty -LiteralPath $RegistryPath -Name $old.Name }
                $changed += $old.Name
            }
        }
    }
    $state.Status = 'Removed'
    $state | Add-Member NoteProperty CleanupAt (Get-Date -Format o) -Force
    Write-SfitProfileJson $StatePath $state
    [pscustomobject]@{Status='Removed';ChangedNames=@($changed)}
}

function Assert-SfitUnpackedPolicies {
    param([string]$ExtensionId,[string[]]$RegistryRoots=@('HKLM:\SOFTWARE\Policies\Google\Chrome','HKCU:\SOFTWARE\Policies\Google\Chrome'))
    foreach ($root in $RegistryRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $key = Get-Item -LiteralPath $root
        if ($key.GetValue('UserDataDir',$null)) { throw "External UserDataDir policy: $root. No profile data was deleted." }
        $mode = $key.GetValue('ExtensionDeveloperModeSettings',$null)
        if ($mode -eq 1 -or ($null -eq $mode -and $key.GetValue('DeveloperToolsAvailability',$null) -eq 2)) { throw "External policy disables Developer mode: $root. No profile data was deleted." }
        $raw = $key.GetValue('ExtensionSettings',$null)
        if ($raw) {
            $settings = $script:json.DeserializeObject([string]$raw)
            foreach ($id in @('*',$ExtensionId)) {
                if ($settings.ContainsKey($id) -and $settings[$id].ContainsKey('installation_mode') -and $settings[$id]['installation_mode'] -in @('blocked','removed')) {
                    throw "External ExtensionSettings blocks unpacked/SFIT: $root ($id). No profile data was deleted."
                }
            }
        }
        foreach ($list in @('ExtensionInstallBlocklist','ExtensionInstallTypeBlocklist')) {
            $path = Join-Path $root $list
            if (Test-Path -LiteralPath $path) {
                $listKey = Get-Item -LiteralPath $path
                foreach ($name in $listKey.GetValueNames()) {
                    if ($listKey.GetValue($name) -in @('*',$ExtensionId,'unpacked')) { throw "External $list blocks SFIT: $root. No profile data was deleted." }
                }
            }
        }
    }
}

function Assert-SfitToolbarPolicies {
    param([string[]]$ExtensionIds,[string[]]$RegistryRoots=@('HKLM:\SOFTWARE\Policies\Google\Chrome','HKCU:\SOFTWARE\Policies\Google\Chrome'))
    foreach ($root in $RegistryRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $raw = (Get-Item -LiteralPath $root).GetValue('ExtensionSettings',$null)
        if (-not $raw) { continue }
        $settings = $script:json.DeserializeObject([string]$raw)
        foreach ($id in $ExtensionIds) {
            $pin = ''
            if ($settings.ContainsKey('*') -and $settings['*'].ContainsKey('toolbar_pin')) { $pin = [string]$settings['*']['toolbar_pin'] }
            if ($settings.ContainsKey($id) -and $settings[$id].ContainsKey('toolbar_pin')) { $pin = [string]$settings[$id]['toolbar_pin'] }
            if ($pin -eq 'force_pinned') { throw "External policy force-pins extension $id at $root. Cannot unpin without changing that administrator policy." }
        }
    }
}

Export-ModuleMember -Function Get-SfitChromeProfileSelection,Get-SfitPinnedExtensions,Get-SfitChromeDataPath,Get-SfitChromeProfiles,Remove-SfitLegacyPolicies,Assert-SfitUnpackedPolicies,Assert-SfitToolbarPolicies
