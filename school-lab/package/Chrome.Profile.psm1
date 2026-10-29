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

function Assert-SfitDeletableTree([string]$Data) {
    # Enumerate one level at a time: do not traverse junctions while checking.
    # Complete the check before deleting ANY part of the explicitly named tree.
    $pending = [Collections.Generic.Stack[string]]::new(); $pending.Push($Data)
    while ($pending.Count) {
        $directory = $pending.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            $resolved = [IO.Path]::GetFullPath($item.FullName)
            if (-not $resolved.StartsWith($Data+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Deletion target escaped Chrome User Data.' }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refuse linked Chrome data: $resolved" }
            if ($item.PSIsContainer) { $pending.Push($resolved) }
        }
    }
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

function Initialize-SfitChromeProfile {
    param([string]$LocalAppDataDirectory,[string]$StatePath)
    $data = Get-SfitChromeDataPath $LocalAppDataDirectory
    $statePathFull = [IO.Path]::GetFullPath($StatePath)
    if ($statePathFull.StartsWith($data+'\',[StringComparison]::OrdinalIgnoreCase) -or $statePathFull -ieq $data) { throw 'Profile journal must be outside Chrome data.' }
    Assert-SfitPlainPath $statePathFull
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $existing = $null
    if (Test-Path -LiteralPath $statePathFull) {
        $existing = Get-Content -LiteralPath $statePathFull -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.UserDataDirectory -ine $data -or $existing.UserSid -ne $sid) { throw 'Profile journal belongs to another path/account.' }
        if ($existing.Schema -eq 2 -and $existing.Status -eq 'Ready' -and (Test-Path -LiteralPath (Join-Path $data 'Default') -PathType Container)) {
            $profiles = @(Get-SfitChromeProfiles $data)
            if ($profiles.Count -eq 1 -and $profiles[0] -eq 'Default') { return $existing }
        }
    }
    $state = [pscustomobject]@{Schema=2;Status='ResetPending';UserDataDirectory=$data;UserSid=$sid;
        ProfileDirectory='Default';ProfileName='SchoolLab';BackupEnabled=$false;At=(Get-Date -Format o)}
    # New explicit classroom requirement: discard old Chrome data, no backup.
    # A retry after an interrupted deletion can repeat the same scoped reset.
    Write-SfitProfileJson $statePathFull $state
    if (Test-Path -LiteralPath $data) {
        Assert-SfitDeletableTree $data
        # Native PowerShell only; absolute target was derived from LOCALAPPDATA
        # and checked above, including all ancestors and descendant links.
        Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $data) { throw 'Chrome data removal did not finish.' }
    }
    New-Item -ItemType Directory -Path (Join-Path $data 'Default') -Force | Out-Null
    Write-SfitProfileJson (Join-Path $data 'Default\Preferences') @{profile=@{name='SchoolLab';using_default_name=$false};extensions=@{pinned_extensions=@()}}
    Write-SfitProfileJson (Join-Path $data 'Local State') @{profile=@{last_used='Default';last_active_profiles=@('Default');info_cache=@{Default=@{name='SchoolLab';is_using_default_name=$false}}}}
    [IO.File]::WriteAllText((Join-Path $data 'First Run'),'',[Text.UTF8Encoding]::new($false))
    $state.Status = 'Ready'; Write-SfitProfileJson $statePathFull $state
    $state
}

function ConvertTo-SfitDefaultProfileArguments([string]$Arguments) {
    $pattern = '(?i)(?<!\S)(?:"--profile-directory=[^"]*"|--profile-directory=(?:"[^"]*"|\S+)|--profile-directory\s+(?:"[^"]*"|\S+))(?=\s|$)'
    if ([regex]::IsMatch($Arguments,$pattern)) { return [regex]::Replace($Arguments,$pattern,'--profile-directory="Default"') }
    ($Arguments.Trim() + ' --profile-directory="Default"').Trim()
}

function Update-SfitChromeShortcuts {
    param([string]$ChromeExecutable,[string[]]$ShortcutRoots,[string]$DesktopDirectory)
    $chrome = [IO.Path]::GetFullPath($ChromeExecutable)
    $proxy = Join-Path (Split-Path -Parent $chrome) 'chrome_proxy.exe'
    $shell = New-Object -ComObject WScript.Shell
    $changed = @(); $skipped = @()
    foreach ($root in @($ShortcutRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Sort-Object -Unique)) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -Force) {
            $link = $shell.CreateShortcut($file.FullName)
            if (-not $link.TargetPath) { continue }
            $target = [IO.Path]::GetFullPath($link.TargetPath)
            if ($target -ine $chrome -and $target -ine $proxy) { continue }
            if ($link.Arguments -match '(?i)--user-data-dir(?:=|\s)') { $skipped += $file.FullName; continue }
            $arguments = ConvertTo-SfitDefaultProfileArguments $link.Arguments
            if ($arguments -cne $link.Arguments) { $link.Arguments = $arguments; $link.Save(); $changed += $file.FullName }
        }
    }
    New-Item -ItemType Directory -Path $DesktopDirectory -Force | Out-Null
    $labPath = Join-Path $DesktopDirectory 'SchoolLab Chrome.lnk'
    $lab = $shell.CreateShortcut($labPath)
    $lab.TargetPath = $chrome; $lab.Arguments = '--profile-directory="Default"'
    $lab.WorkingDirectory = Split-Path -Parent $chrome; $lab.IconLocation = $chrome + ',0'; $lab.Save()
    [pscustomobject]@{Changed=@($changed);SkippedCustomData=@($skipped);SchoolLabShortcut=$labPath}
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

Export-ModuleMember -Function Initialize-SfitChromeProfile,Get-SfitChromeDataPath,Get-SfitChromeProfiles,Remove-SfitLegacyPolicies,Assert-SfitUnpackedPolicies,Update-SfitChromeShortcuts,ConvertTo-SfitDefaultProfileArguments
