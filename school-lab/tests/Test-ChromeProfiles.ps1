#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'package\Chrome.Profile.psm1') -Force
$scratch = Join-Path $root ('test-results\chrome-simple-' + [guid]::NewGuid().ToString('N'))
$local = Join-Path $scratch 'AppData\Local'
$data = Join-Path $local 'Google\Chrome\User Data'
$statePath = Join-Path $local 'SchoolLab\Chrome\profile-state.json'
$script:passed = 0
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message }; $script:passed++ }
function Throws([scriptblock]$Action) { try { & $Action | Out-Null } catch { $script:passed++; return }; throw 'Expected failure' }
function Json($Value) { ConvertTo-Json -InputObject $Value -Depth 30 -Compress }
function WriteJson($Path,$Value) { New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null; [IO.File]::WriteAllText($Path,(Json $Value),[Text.UTF8Encoding]::new($false)) }
# Absolute fixture targets are confined to this explicitly named workspace tree.
Assert ([IO.Path]::GetFullPath($data).StartsWith([IO.Path]::GetFullPath($scratch)+'\')) 'Fixture escaped test directory'
New-Item -ItemType Directory -Path (Join-Path $data 'Default'),(Join-Path $data 'Profile 1'),(Join-Path $data 'Profile 2') -Force | Out-Null
Set-Content (Join-Path $data 'Default\old.txt') 'DISCARD OLD FIXTURE'
Set-Content (Join-Path $data 'Profile 1\old.txt') 'DISCARD OTHER PROFILE'
Set-Content (Join-Path $local 'outside.txt') 'KEEP OUTSIDE CHROME'
WriteJson (Join-Path $data 'Local State') @{profile=@{info_cache=@{Default=@{};'Profile 1'=@{};'Profile 2'=@{}}}}
$first = Initialize-SfitChromeProfile $local $statePath
Assert ($first.Schema -eq 2 -and $first.Status -eq 'Ready' -and -not $first.BackupEnabled) 'Fresh profile preparation failed'
Assert (-not (Test-Path (Join-Path $data 'Default\old.txt'))) 'Old default profile data was retained'
Assert (-not (Test-Path (Join-Path $data 'Profile 1'))) 'Extra profile not deleted'
Assert (-not (Test-Path (Join-Path $data 'Profile 2'))) 'Second extra profile not deleted'
Assert (Test-Path (Join-Path $local 'outside.txt')) 'Data outside Chrome was changed'
Assert (-not (Test-Path (Join-Path $scratch 'SchoolLabChromeBackups'))) 'Unexpected backup created'
Assert ((@(Get-SfitChromeProfiles $data) -join ',') -eq 'Default') 'More than one profile remains'
$prefs = Get-Content (Join-Path $data 'Default\Preferences') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($prefs.profile.name -eq 'SchoolLab' -and $prefs.extensions.pinned_extensions.Count -eq 0) 'SchoolLab profile name/pin defaults incorrect'
$chromeState = Get-Content (Join-Path $data 'Local State') -Raw | ConvertFrom-Json
Assert ($chromeState.profile.last_used -eq 'Default' -and $chromeState.profile.last_active_profiles[0] -eq 'Default') 'Default profile startup selection not set'
Assert (Test-Path (Join-Path $data 'First Run')) 'First-run sentinel not prepared'
Set-Content (Join-Path $data 'Default\new.txt') 'KEEP WHEN ONLY PROFILE'
$again = Initialize-SfitChromeProfile $local $statePath
Assert ((Get-Content (Join-Path $data 'Default\new.txt') -Raw) -like '*KEEP WHEN ONLY PROFILE*') 'Rerun unnecessarily erased the prepared profile'
Assert ($again.At -eq $first.At) 'Rerun reset an already-correct profile'
New-Item -ItemType Directory -Path (Join-Path $data 'Profile 3') | Out-Null
$null = Initialize-SfitChromeProfile $local $statePath
Assert (-not (Test-Path (Join-Path $data 'Profile 3')) -and -not (Test-Path (Join-Path $data 'Default\new.txt'))) 'Explicit cleanup did not reset extra profiles'
# Even an arbitrary cached profile name, without a matching directory, must go.
WriteJson (Join-Path $data 'Local State') @{profile=@{info_cache=@{Default=@{};CustomExamProfile=@{}}}}
$null = Initialize-SfitChromeProfile $local $statePath
Assert ((@(Get-SfitChromeProfiles $data) -join ',') -eq 'Default') 'Stale profile picker metadata was retained'
Throws { Get-SfitChromeDataPath 'C:\' }
Throws { Get-SfitChromeDataPath 'relative\path' }
Throws { Get-SfitChromeDataPath '\\server\share' }
Throws { Initialize-SfitChromeProfile $local (Join-Path $data 'state.json') }
# Old backup-era journal is migrated automatically; no manual restore/cleanup.
WriteJson $statePath @{Schema=1;Status='Ready';UserDataDirectory=$data;UserSid=$first.UserSid;BackupRoot='unused-old-path'}
Set-Content (Join-Path $data 'Default\legacy.txt') 'OLD VERSION DATA'
$migrated = Initialize-SfitChromeProfile $local $statePath
Assert ($migrated.Schema -eq 2 -and -not (Test-Path (Join-Path $data 'Default\legacy.txt'))) 'Old profile journal blocked migration'
# A stopped reset can repeat safely within the same explicit Chrome data root.
$migrated.Status = 'ResetPending'; WriteJson $statePath $migrated
Set-Content (Join-Path $data 'Default\partial.txt') 'PARTIAL RESET'
$null = Initialize-SfitChromeProfile $local $statePath
Assert (-not (Test-Path (Join-Path $data 'Default\partial.txt'))) 'Interrupted reset did not finish'
# Do not follow directory junctions out of the disposable Chrome fixture.
$external = Join-Path $scratch 'external'
New-Item -ItemType Directory -Path $external | Out-Null
Set-Content (Join-Path $external 'sentinel.txt') 'KEEP EXTERNAL'
$link = Join-Path $data 'linked-data'
New-Item -ItemType Junction -Path $link -Target $external | Out-Null
$pending = Get-Content $statePath -Raw | ConvertFrom-Json; $pending.Status = 'ResetPending'; WriteJson $statePath $pending
Throws { Initialize-SfitChromeProfile $local $statePath }
Assert (Test-Path (Join-Path $external 'sentinel.txt')) 'Linked external data was deleted'
Assert (Test-Path (Join-Path $data 'Default\Preferences')) 'Reset deleted data before link validation completed'
if (-not ([IO.Path]::GetFullPath($link).StartsWith([IO.Path]::GetFullPath($scratch)+'\')) -or
    -not ((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe link cleanup target' }
[IO.Directory]::Delete($link) # delete junction itself, never its target contents
$null = Initialize-SfitChromeProfile $local $statePath

# Actual .lnk file operations, confined to a synthetic desktop in the workspace.
Assert ((ConvertTo-SfitDefaultProfileArguments '--profile-directory="Profile 2" --new-window') -eq '--profile-directory="Default" --new-window') 'Quoted profile argument not normalized'
Assert ((ConvertTo-SfitDefaultProfileArguments '"--profile-directory=Profile 3" https://example.test') -eq '--profile-directory="Default" https://example.test') 'Entire quoted profile flag not normalized'
Assert ((ConvertTo-SfitDefaultProfileArguments '--profile-directory "Profile 4"') -eq '--profile-directory="Default"') 'Split profile flag not normalized'
$desktop = Join-Path $scratch 'Desktop'
New-Item -ItemType Directory -Path $desktop -Force | Out-Null
$fakeChrome = Join-Path $scratch 'Application\chrome.exe'
New-Item -ItemType Directory -Path (Split-Path -Parent $fakeChrome) -Force | Out-Null
Set-Content $fakeChrome 'NOT EXECUTED'
$wsh = New-Object -ComObject WScript.Shell
$oldLink = Join-Path $desktop 'Google Chrome.lnk'; $lnk = $wsh.CreateShortcut($oldLink)
$lnk.TargetPath = $fakeChrome; $lnk.Arguments = '--profile-directory="Profile 8" --new-window'; $lnk.Save()
$otherLink = Join-Path $desktop 'Other.lnk'; $lnk = $wsh.CreateShortcut($otherLink)
$lnk.TargetPath = "$env:SystemRoot\System32\notepad.exe"; $lnk.Arguments = 'unchanged'; $lnk.Save()
$customLink = Join-Path $desktop 'Custom Chrome.lnk'; $lnk = $wsh.CreateShortcut($customLink)
$lnk.TargetPath = $fakeChrome; $lnk.Arguments = '--user-data-dir="D:\Custom" --profile-directory="Profile 1"'; $lnk.Save()
$links = Update-SfitChromeShortcuts $fakeChrome @($desktop) $desktop
Assert ($wsh.CreateShortcut($oldLink).Arguments -eq '--profile-directory="Default" --new-window') 'Old Chrome shortcut can reopen a deleted profile'
Assert ($wsh.CreateShortcut($otherLink).Arguments -eq 'unchanged') 'Non-Chrome shortcut modified'
Assert ($links.SkippedCustomData.Count -eq 1 -and $wsh.CreateShortcut($customLink).Arguments -like '*D:\Custom*') 'Custom data shortcut silently changed'
Assert ($wsh.CreateShortcut($links.SchoolLabShortcut).Arguments -eq '--profile-directory="Default"') 'Dedicated SchoolLab Chrome shortcut missing'
$linksAgain = Update-SfitChromeShortcuts $fakeChrome @($desktop) $desktop
Assert ($linksAgain.Changed.Count -eq 0) 'Shortcut normalization not idempotent'

# All registry mutations below use our own disposable HKCU test key.
$testKey = 'HKCU:\Software\SchoolLabTests\' + [guid]::NewGuid().ToString('N')
$id = 'gojbmoppgoeccpfgiigckholndeagdcm'
function NewLegacy([string]$Name,[string]$OriginalSettings='') {
    $key = Join-Path $testKey $Name
    New-Item -Path $key -Force | Out-Null
    $settings = @{ '*'=@{installation_mode='blocked'} }; $settings[$id]=@{installation_mode='allowed';toolbar_pin='default_unpinned'}
    $values = [ordered]@{BrowserAddPersonEnabled=0;BrowserGuestModeEnabled=0;IncognitoModeAvailability=1;BrowserSignin=0;SyncDisabled=1;ExtensionSettings=(Json $settings)}
    $old = @(); $applied = @()
    foreach ($name in $values.Keys) {
        $kind = if ($name -eq 'ExtensionSettings') { 'String' } else { 'DWord' }
        New-ItemProperty -LiteralPath $key -Name $name -Value $values[$name] -PropertyType $kind | Out-Null
        $old += @{Name=$name;Exists=($name -eq 'ExtensionSettings' -and [bool]$OriginalSettings);Value=$(if ($name -eq 'ExtensionSettings' -and $OriginalSettings) {$OriginalSettings} else {$null});Kind=$kind}
        $applied += @{Name=$name;Value=$values[$name];Kind=$kind}
    }
    New-ItemProperty -LiteralPath $key -Name Unrelated -Value 'KEEP' -PropertyType String | Out-Null
    $journal = Join-Path $scratch ("policy-$Name.json")
    WriteJson $journal @{Schema=1;Status='Applied';RegistryPath=$key;Original=$old;Applied=$applied}
    @{Key=$key;Journal=$journal}
}
try {
    $absent = Remove-SfitLegacyPolicies (Join-Path $scratch 'none.json') $testKey
    Assert ($absent.Status -eq 'NotPresent') 'Missing legacy journal should be a no-op'
    $fixture = NewLegacy 'ordinary'
    Throws { Assert-SfitUnpackedPolicies $id @($fixture.Key) }
    $cleanup = Remove-SfitLegacyPolicies $fixture.Journal $fixture.Key
    Assert ($cleanup.ChangedNames.Count -eq 6) 'Did not automatically remove all six SchoolLab policy values'
    Assert (((Get-Item $fixture.Key).GetValueNames() -join ',') -eq 'Unrelated') 'Legacy policies remain or unrelated value was removed'
    Assert ((Get-Item $fixture.Key).GetValue('Unrelated') -eq 'KEEP') 'Unrelated policy changed'
    Assert-SfitUnpackedPolicies $id @($fixture.Key); $script:passed++
    Assert ((Remove-SfitLegacyPolicies $fixture.Journal $fixture.Key).Status -eq 'AlreadyRemoved') 'Migration not idempotent'
    Assert ((Get-Content $fixture.Journal -Raw | ConvertFrom-Json).Status -eq 'Removed') 'Cleanup journal not recorded'
    # Preserve administrator additions made after the old SchoolLab run.
    $fixture = NewLegacy 'mixed'
    $settings = (Get-Item $fixture.Key).GetValue('ExtensionSettings') | ConvertFrom-Json
    $settings.'*' | Add-Member NoteProperty blocked_permissions @('cookies')
    $settings.$id.toolbar_pin = 'force_pinned'
    $settings | Add-Member NoteProperty bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb @{installation_mode='allowed'}
    Set-ItemProperty -LiteralPath $fixture.Key -Name ExtensionSettings -Value (Json $settings)
    Set-ItemProperty -LiteralPath $fixture.Key -Name BrowserSignin -Value 1
    $null = Remove-SfitLegacyPolicies $fixture.Journal $fixture.Key
    $left = (Get-Item $fixture.Key).GetValue('ExtensionSettings') | ConvertFrom-Json
    Assert ('installation_mode' -notin $left.'*'.PSObject.Properties.Name) 'SchoolLab global block not removed from mixed settings'
    Assert ($left.'*'.blocked_permissions[0] -eq 'cookies') 'Administrator wildcard settings were deleted'
    Assert ($left.$id.toolbar_pin -eq 'force_pinned' -and 'installation_mode' -notin $left.$id.PSObject.Properties.Name) 'Changed SFIT settings not preserved correctly'
    Assert ($left.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.installation_mode -eq 'allowed') 'Other extension settings were deleted'
    Assert ((Get-Item $fixture.Key).GetValue('BrowserSignin') -eq 1) 'Administrator scalar change overwritten'
    Assert-SfitUnpackedPolicies $id @($fixture.Key); $script:passed++
    # An original policy was NOT set by SchoolLab: preserve and report it.
    $fixture = NewLegacy 'external' '{"*":{"installation_mode":"blocked"}}'
    $null = Remove-SfitLegacyPolicies $fixture.Journal $fixture.Key
    Assert (((Get-Item $fixture.Key).GetValue('ExtensionSettings') | ConvertFrom-Json).'*'.installation_mode -eq 'blocked') 'External block policy was weakened'
    Throws { Assert-SfitUnpackedPolicies $id @($fixture.Key) }
    # A policy without our journal is never silently removed.
    $unowned = Join-Path $testKey 'unowned'
    New-Item -Path $unowned | Out-Null
    New-ItemProperty -LiteralPath $unowned -Name ExtensionSettings -Value '{"*":{"installation_mode":"blocked"}}' -PropertyType String | Out-Null
    $null = Remove-SfitLegacyPolicies (Join-Path $scratch 'missing.json') $unowned
    Throws { Assert-SfitUnpackedPolicies $id @($unowned) }
    Assert ((Get-Item $unowned).GetValue('ExtensionSettings') -eq '{"*":{"installation_mode":"blocked"}}') 'Unowned settings were changed'
    $fixture = NewLegacy 'wrong-root'
    Throws { Remove-SfitLegacyPolicies $fixture.Journal $unowned }
    Assert ((Get-Item $fixture.Key).GetValue('BrowserAddPersonEnabled') -eq 0) 'Root mismatch mutated a policy'
    # Existing original values are restored instead of simply deleted.
    $fixture = NewLegacy 'original-value'
    $journal = Get-Content $fixture.Journal -Raw | ConvertFrom-Json
    ($journal.Original | Where-Object Name -eq 'BrowserAddPersonEnabled').Exists = $true
    ($journal.Original | Where-Object Name -eq 'BrowserAddPersonEnabled').Value = 1
    WriteJson $fixture.Journal $journal
    $null = Remove-SfitLegacyPolicies $fixture.Journal $fixture.Key
    Assert ((Get-Item $fixture.Key).GetValue('BrowserAddPersonEnabled') -eq 1) 'Original Add Profile value was not restored'
    # Developer-mode and alternate-data policies are diagnosed before data reset.
    $foreign = Join-Path $testKey 'foreign'
    New-Item -Path $foreign | Out-Null
    New-ItemProperty -LiteralPath $foreign -Name ExtensionDeveloperModeSettings -Value 1 -PropertyType DWord | Out-Null
    Throws { Assert-SfitUnpackedPolicies $id @($foreign) }
    Remove-ItemProperty -LiteralPath $foreign -Name ExtensionDeveloperModeSettings
    New-ItemProperty -LiteralPath $foreign -Name UserDataDir -Value 'C:\ExternalChromeData' -PropertyType String | Out-Null
    Throws { Assert-SfitUnpackedPolicies $id @($foreign) }
} finally {
    if ($testKey -notmatch '^HKCU:\\Software\\SchoolLabTests\\[0-9a-f]{32}$') { throw 'Invalid test registry cleanup target' }
    if (Test-Path -LiteralPath $testKey) {
        $absolute = (Get-Item -LiteralPath $testKey).Name
        if ($absolute -notmatch '^HKEY_CURRENT_USER\\Software\\SchoolLabTests\\[0-9a-f]{32}$') { throw 'Resolved registry target mismatch' }
        Remove-Item -LiteralPath $testKey -Recurse -Force
    }
}
@{Passed=$script:passed;PowerShell=$PSVersionTable.PSVersion.ToString();Scope='Deletion of synthetic Chrome data under the workspace only; isolated HKCU test key; no real Chrome data/policy changed';At=(Get-Date -Format o)} |
    ConvertTo-Json | Set-Content (Join-Path $scratch 'result.json') -Encoding UTF8
Write-Host "PASS: $script:passed simple Chrome profile/migration checks. $scratch"
