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
# Selection must be read-only, including when upgrading from an old reset journal.
New-Item -ItemType Directory -Path (Join-Path $data 'Default'),(Join-Path $data 'Profile 1'),(Join-Path $data 'Profile 2') -Force | Out-Null
$idA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $idB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
WriteJson (Join-Path $data 'Default\Preferences') @{profile=@{name='My Default'};extensions=@{pinned_extensions=@($idA)};session=@{restore_on_startup=1}}
WriteJson (Join-Path $data 'Profile 1\Preferences') @{profile=@{name='Student One'};extensions=@{pinned_extensions=@($idB)}}
WriteJson (Join-Path $data 'Profile 2\Preferences') @{profile=@{name='Teacher'};extensions=@{pinned_extensions=@($idA,$idB)};custom=@{keep='ALL DATA'}}
WriteJson (Join-Path $data 'Local State') @{profile=@{last_used='Profile 1';info_cache=@{Default=@{};'Profile 1'=@{};'Profile 2'=@{}}}}
WriteJson $statePath @{Schema=2;Status='ResetPending';UserDataDirectory=$data;ProfileDirectory='Default'}
foreach($name in @('Default','Profile 1','Profile 2')) {
    Set-Content -LiteralPath (Join-Path $data ($name+'\History')) -Value ('KEEP HISTORY '+$name)
    Set-Content -LiteralPath (Join-Path $data ($name+'\Bookmarks')) -Value ('KEEP BOOKMARKS '+$name)
}
$before = @{}; foreach($f in Get-ChildItem -LiteralPath $local -File -Recurse){$before[$f.FullName]=(Get-FileHash -LiteralPath $f.FullName).Hash}
$last = Get-SfitChromeProfileSelection $local
Assert ($last.ProfileDirectory -eq 'Profile 1') 'Closed browser did not choose last_used'
$selected = Get-SfitChromeProfileSelection $local (Join-Path $data 'Profile 2')
Assert ($selected.ProfileDirectory -eq 'Profile 2') 'Actual open-window path did not override a different last_used profile'
Assert ((@(Get-SfitPinnedExtensions $selected.ProfilePath) -join ',') -eq ($idA+','+$idB)) 'Pinned extension IDs not read from selected profile'
Assert ((@(Get-SfitPinnedExtensions (Join-Path $data 'Default')) -join ',') -eq $idA) 'Other profile pins read incorrectly'
Assert (@(Get-SfitChromeProfiles $data).Count -eq 3) 'Profiles were removed'
foreach($path in $before.Keys){Assert ((Get-FileHash -LiteralPath $path).Hash -eq $before[$path]) ('Existing data changed: '+$path)}
Assert (@(Get-ChildItem -LiteralPath $local -File -Recurse).Count -eq $before.Count) 'Selection wrote extra Chrome/journal files'
Throws { Get-SfitChromeProfileSelection $local (Join-Path $scratch 'outside\Profile 2') }
Throws { Get-SfitChromeProfileSelection $local (Join-Path $data '..\outside') }
Throws { Get-SfitChromeProfileSelection $local (Join-Path $data 'Guest Profile') }
Throws { Get-SfitChromeProfileSelection $local (Join-Path $data 'System Profile') }
Throws { Get-SfitChromeDataPath 'relative-path' }
Throws { Get-SfitChromeDataPath 'C:\' }
$blankLocal = Join-Path $scratch 'Empty\Local'
$empty = Get-SfitChromeProfileSelection $blankLocal
Assert ($empty.ProfileDirectory -eq 'Default' -and -not (Test-Path -LiteralPath $blankLocal)) 'First-run selection created/deleted Chrome data'
WriteJson (Join-Path $data 'Local State') @{profile=@{info_cache=@{Default=@{};'Profile 1'=@{};'Profile 2'=@{}}}}
Throws { Get-SfitChromeProfileSelection $local }
# Missing/null/malformed preferences must not be rewritten to an empty profile.
WriteJson (Join-Path $data 'Profile 2\Preferences') @{custom=@{keep='NO EXTENSIONS'}}
Assert (@(Get-SfitPinnedExtensions (Join-Path $data 'Profile 2')).Count -eq 0) 'Missing pin list is not empty'
WriteJson (Join-Path $data 'Profile 2\Preferences') @{extensions=@{pinned_extensions=@('bad-id')}}
Throws { Get-SfitPinnedExtensions (Join-Path $data 'Profile 2') }
$external = Join-Path $scratch 'external'; New-Item -ItemType Directory -Path $external | Out-Null
$link = Join-Path $data 'Linked Profile'; New-Item -ItemType Junction -Path $link -Target $external | Out-Null
Throws { Get-SfitChromeProfileSelection $local $link }
# Delete just the disposable junction, never its target; no user data touched.
if(-not ([IO.Path]::GetFullPath($link).StartsWith([IO.Path]::GetFullPath($scratch)+'\'))){throw 'Fixture path mismatch'}
[IO.Directory]::Delete($link)
$source = [IO.File]::ReadAllText((Join-Path $root 'package\Chrome.Profile.psm1'))
Assert ($source -notmatch 'Remove-Item -LiteralPath \$data|function Initialize-SfitChromeProfile|function Update-SfitChromeShortcuts') 'Destructive profile reset/shortcut rewrite remains exposed'
# Provision OLBDB beside existing profiles; do not adopt by display name.
WriteJson (Join-Path $data 'Profile 5\Preferences') @{profile=@{name='OLBDB'};custom=@{keep='PREEXISTING OLBDB'}}
$originalFiles=@{}; foreach($f in Get-ChildItem -LiteralPath $local -File -Recurse){$originalFiles[$f.FullName]=(Get-FileHash -LiteralPath $f.FullName).Hash}
$examJournal=Join-Path $local 'SchoolLab\Chrome\olbdb-profile.json'
$exam = Initialize-SfitExamProfile $local $examJournal 'OLBDB'
Assert ($exam.ProfileName -eq 'OLBDB' -and -not $exam.Reused) 'Fresh exam profile not created'
Assert ($exam.ProfileDirectory -match '^SchoolLab-OLBDB-[0-9a-f]{12}$') 'Exam directory is not distinct/owned'
Assert ($exam.ProfilePath -ne (Join-Path $data 'Profile 5')) 'Adopted unrelated OLBDB profile'
$examPreferences=Get-Content -LiteralPath (Join-Path $exam.ProfilePath 'Preferences') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($examPreferences.profile.name -eq 'OLBDB' -and -not $examPreferences.profile.using_default_name) 'Exam profile name not seeded'
Assert (@(Get-SfitPinnedExtensions $exam.ProfilePath).Count -eq 0) 'New exam profile starts pinned'
foreach($path in $originalFiles.Keys){Assert ((Get-FileHash -LiteralPath $path).Hash -eq $originalFiles[$path]) ('Old data changed: '+$path)}
Set-Content -LiteralPath (Join-Path $exam.ProfilePath 'History') -Value 'KEEP EXAM PROFILE ON RETRY'
$examHash=(Get-FileHash -LiteralPath (Join-Path $exam.ProfilePath 'Preferences')).Hash
$again=Initialize-SfitExamProfile $local $examJournal 'OLBDB'
Assert ($again.Reused -and $again.ProfilePath -eq $exam.ProfilePath) 'Retry created another OLBDB profile'
Assert ((Get-FileHash -LiteralPath (Join-Path $exam.ProfilePath 'Preferences')).Hash -eq $examHash) 'Retry rewrote exam preferences'
Assert ((Get-Content -LiteralPath (Join-Path $exam.ProfilePath 'History')) -eq 'KEEP EXAM PROFILE ON RETRY') 'Retry lost exam data'
Assert (@(Get-SfitChromeProfiles $data | Where-Object {$_ -like 'SchoolLab-OLBDB-*'}).Count -eq 1) 'Duplicate exam profiles'
Throws { Initialize-SfitExamProfile $local (Join-Path $data 'unsafe-journal.json') 'OLBDB' }
Throws { Initialize-SfitExamProfile $local (Join-Path $scratch 'bad-name.json') '..\Default' }
$markerPath=Join-Path $exam.ProfilePath 'SchoolLab.Profile.json'
$markerText=[IO.File]::ReadAllText($markerPath)
$badMarker=$markerText | ConvertFrom-Json; $badMarker.ProfileToken='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
WriteJson $markerPath $badMarker
Throws { Initialize-SfitExamProfile $local $examJournal 'OLBDB' }
[IO.File]::WriteAllText($markerPath,$markerText,[Text.UTF8Encoding]::new($false))
# Actual .lnk operations are confined to a fake desktop/executable.
$desktop=Join-Path $scratch 'Desktop'; $fakeChrome=Join-Path $scratch 'Application\chrome.exe'
New-Item -ItemType Directory -Path (Split-Path -Parent $fakeChrome) -Force | Out-Null
Set-Content -LiteralPath $fakeChrome -Value 'NOT EXECUTED'
$shortcut=New-SfitExamShortcut $fakeChrome $exam.ProfileDirectory $desktop 'https://utcoj.info/' 'OLBDB'
$wsh=New-Object -ComObject WScript.Shell; $link=$wsh.CreateShortcut($shortcut)
Assert ((Split-Path -Leaf $shortcut) -eq 'OLBDB.lnk') 'Wrong shortcut name'
Assert ($link.TargetPath -ieq $fakeChrome) 'Shortcut targets wrong Chrome'
Assert ($link.Arguments -ceq ('--profile-directory="{0}" --new-window "https://utcoj.info/"' -f $exam.ProfileDirectory)) 'Shortcut opens wrong profile/site'
Assert ((New-SfitExamShortcut $fakeChrome $exam.ProfileDirectory $desktop 'https://utcoj.info/' 'OLBDB') -eq $shortcut) 'Shortcut retry not idempotent'
Throws { New-SfitExamShortcut $fakeChrome 'Default' $desktop 'https://utcoj.info/' 'OLBDB' }
Throws { New-SfitExamShortcut $fakeChrome $exam.ProfileDirectory $desktop 'https://password@utcoj.info/' 'OLBDB' }
$conflictDesktop=Join-Path $scratch 'UnrelatedDesktop';New-Item -ItemType Directory -Path $conflictDesktop | Out-Null
$conflict=Join-Path $conflictDesktop 'OLBDB.lnk';$other=$wsh.CreateShortcut($conflict);$other.TargetPath="$env:SystemRoot\System32\notepad.exe";$other.Save()
$conflictHash=(Get-FileHash -LiteralPath $conflict).Hash
Throws { New-SfitExamShortcut $fakeChrome $exam.ProfileDirectory $conflictDesktop 'https://utcoj.info/' 'OLBDB' }
Assert ((Get-FileHash -LiteralPath $conflict).Hash -eq $conflictHash) 'Unrelated shortcut overwritten'
# Resume a journal written before first directory creation, without Local State.
$recoveryLocal=Join-Path $scratch 'Recovery\Local'; $recoveryData=Get-SfitChromeDataPath $recoveryLocal
$recoveryJournal=Join-Path $recoveryLocal 'SchoolLab\Chrome\olbdb-profile.json'
WriteJson $recoveryJournal @{Schema=1;Status='Creating';UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;UserDataDirectory=$recoveryData;ProfileName='OLBDB';ProfileDirectory='SchoolLab-OLBDB-abcdef123456';ProfileToken='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}
$recovered=Initialize-SfitExamProfile $recoveryLocal $recoveryJournal 'OLBDB'
Assert ($recovered.ProfileDirectory -eq 'SchoolLab-OLBDB-abcdef123456' -and (Test-Path -LiteralPath (Join-Path $recovered.ProfilePath 'Preferences'))) 'Interrupted initial creation not resumed'
Assert (-not (Test-Path -LiteralPath (Join-Path $recoveryData 'Local State'))) 'SchoolLab rewrote Chrome Local State'

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
    # Force-pinning must fail explicitly without weakening administrator policy.
    $pinKey = Join-Path $testKey 'pin-policy'
    New-Item -Path $pinKey | Out-Null
    New-ItemProperty -LiteralPath $pinKey -Name ExtensionSettings -Value '{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":{"toolbar_pin":"force_pinned"}}' -PropertyType String | Out-Null
    Throws { Assert-SfitToolbarPolicies @($idA) @($pinKey) }
    Assert-SfitToolbarPolicies @($idB) @($pinKey); $script:passed++
    Assert (((Get-Item $pinKey).GetValue('ExtensionSettings') | ConvertFrom-Json).$idA.toolbar_pin -eq 'force_pinned') 'Force-pin policy was silently changed'
} finally {
    if ($testKey -notmatch '^HKCU:\\Software\\SchoolLabTests\\[0-9a-f]{32}$') { throw 'Invalid test registry cleanup target' }
    if (Test-Path -LiteralPath $testKey) {
        $absolute = (Get-Item -LiteralPath $testKey).Name
        if ($absolute -notmatch '^HKEY_CURRENT_USER\\Software\\SchoolLabTests\\[0-9a-f]{32}$') { throw 'Resolved registry target mismatch' }
        Remove-Item -LiteralPath $testKey -Recurse -Force
    }
}
@{Passed=$script:passed;PowerShell=$PSVersionTable.PSVersion.ToString();Scope='Read-only selection of synthetic profiles, byte-level preservation checks; isolated HKCU policy migration; no real Chrome data/policy changed';At=(Get-Date -Format o)} |
    ConvertTo-Json | Set-Content (Join-Path $scratch 'result.json') -Encoding UTF8
Write-Host "PASS: $script:passed preserved Chrome profile/migration checks. $scratch"
