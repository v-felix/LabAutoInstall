#requires -Version 5.1
[CmdletBinding()]
param([string]$PackageRoot = '', [switch]$NoElevation, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -Force
if (-not $PackageRoot) { $PackageRoot = $PSScriptRoot }
Import-Module (Join-Path $PackageRoot 'Lab.Core.psm1') -Force
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackageRoot 'Update-SfitSchedule.ps1') -PackageRoot $PackageRoot
if ($LASTEXITCODE -ne 0) { throw 'SFIT config validation failed; rebuild or fix the schedule.' }
$lock = Get-Content -LiteralPath (Join-Path $PackageRoot 'package-lock.json') -Raw | ConvertFrom-Json
$config = Import-PowerShellDataFile (Join-Path $PackageRoot 'LabConfig.psd1')
$logRoot = Join-Path $env:LOCALAPPDATA 'SchoolLab\Chrome'
$mutex = $null; $held = $false; $window = $null
$step = 'Preflight'; $started = [datetime]::UtcNow
$tracePath = Join-Path $logRoot 'install.log'
function Write-SfitJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
}
function Write-SfitTrace([string]$Message) {
    Add-Content -LiteralPath $tracePath -Value ('{0:o} [{1}] {2}' -f [datetime]::UtcNow,$step,$Message) -Encoding UTF8
}
try {
    Test-LabPackage $PackageRoot $lock
    if (-not $config.EnableChromeExtension) { Write-Host 'Chrome extension disabled in package config.'; exit 0 }
    if (-not $lock.ChromeExtension) { throw 'Missing ChromeExtension metadata in package lock.' }
    $extension = $lock.ChromeExtension
    if ($ValidateOnly) { Write-Host "PASS: Chrome payload hashes verified. ID=$($extension.id) config=$($extension.configSha256)"; exit 0 }
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not [Environment]::Is64BitProcess) { $ps = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin -or -not [Environment]::Is64BitProcess) {
        if ($NoElevation) { throw 'Administrator and x64 Windows PowerShell are required.' }
        $argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-PackageRoot',$PackageRoot,'-NoElevation')
        $options = @{FilePath=$ps;ArgumentList=(($argsList | ForEach-Object { ConvertTo-LabArgument $_ }) -join ' ');Wait=$true;PassThru=$true}
        if (-not $admin) { $options.Verb = 'RunAs' }
        exit (Start-Process @options).ExitCode
    }
    if (-not (Test-LabClassroomContext)) { throw 'Sign into the classroom account on an unlocked desktop. SYSTEM / a different administrator cannot initialize this Chrome profile.' }
    $mutex = [Threading.Mutex]::new($false,'Global\SchoolLab-Chrome-Installer')
    try { $held = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw 'Chrome extension setup is already running.' }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Set-Content -LiteralPath $tracePath -Value ('SFIT setup started {0:o}; package {1}' -f $started,$lock.PackageId) -Encoding UTF8
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $candidates = @($config.ChromeExecutable, "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    $chrome = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $chrome) { throw 'Chrome is not installed. Install Chrome Stable, then rerun this extension-only command.' }
    if ((Get-Item -LiteralPath $chrome).VersionInfo.FileMajorPart -lt 120) { throw 'Chrome 120 or newer is required.' }
    if ($config.ChromeProfileDirectory -ne 'Dedicated' -or $config.ChromeProfileKey -ne 'OLBDB') { throw 'This package uses its dedicated exam profile.' }
    Import-Module (Join-Path $PackageRoot 'Chrome.Profile.psm1') -Force
    $step = 'LegacyPolicyCleanup'
    $migration = Remove-SfitLegacyPolicies (Join-Path $logRoot 'policy-state.json')
    Write-SfitTrace "Old SchoolLab policies: $($migration.Status); changed=$($migration.ChangedNames -join ',')"
    Assert-SfitUnpackedPolicies $extension.id
    Assert-SfitToolbarPolicies @($extension.id)
    $step = 'PrepareOLBDB'
    $selection = Initialize-SfitExamProfile $env:LOCALAPPDATA (Join-Path $logRoot 'olbdb-profile.json') $config.ChromeProfileName $config.ChromeProfileKey
    $profileDirectory = $selection.ProfileDirectory
    $examUrl = [string]$lock.ChromeExtension.examUrl
    if (-not $examUrl) { throw 'Missing examUrl in the Chrome payload metadata.' }
    $shortcut = New-SfitExamShortcut $chrome $profileDirectory ([Environment]::GetFolderPath('Desktop')) $examUrl $selection.ProfileName $config.ChromeProfileKey $config.ChromeProfileKey
    Write-SfitTrace "New dedicated profile=$profileDirectory; name=$($selection.ProfileName); shortcut=$shortcut. Existing profiles are preserved; exam shortcut points to the new profile."
    $destination = [IO.Path]::GetFullPath((Expand-LabPath $config.ChromeExtensionDirectory))
    $support = Join-Path $env:ProgramFiles 'SchoolLab\ChromeSupport'
    if (-not $destination.StartsWith($env:ProgramFiles + '\SchoolLab\',[StringComparison]::OrdinalIgnoreCase)) { throw 'ChromeExtensionDirectory must remain inside Program Files\SchoolLab.' }
    New-Item -ItemType Directory -Path $destination,$support -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'Files\ChromeExtension') -File | Copy-Item -Destination $destination -Force
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'Files\Sfit.NativeHost.exe') -Destination $support -Force
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'Sfit.UiAutomation.cs') -Destination $support -Force
    $token = [guid]::NewGuid().ToString('N')
    $plan = @{extensionId=$extension.id;version=$extension.version;configSha256=$extension.configSha256;packageId=$lock.PackageId;token=$token}
    Write-SfitJson (Join-Path $support 'native-plan.json') $plan
    Write-SfitJson (Join-Path $destination 'deployment.json') @{token=$token;packageId=$lock.PackageId}
    $manifestPath = Join-Path $support 'vn.schoollab.sfit.json'
    Write-SfitJson $manifestPath @{name='vn.schoollab.sfit';description='SFIT installation status bridge';path=(Join-Path $support 'Sfit.NativeHost.exe');type='stdio';allowed_origins=@("chrome-extension://$($extension.id)/")}
    $registry = 'HKLM:\SOFTWARE\Google\Chrome\NativeMessagingHosts\vn.schoollab.sfit'
    New-Item -Path $registry -Force | Out-Null
    Set-Item -LiteralPath $registry -Value $manifestPath


    # Load runtime accessibility assemblies before compiling the shipped UI driver.
    Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
    $references = @([Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ToggleState].Assembly.Location,[Windows.DependencyObject].Assembly.Location,'System.dll')
    Add-Type -Path (Join-Path $support 'Sfit.UiAutomation.cs') -ReferencedAssemblies $references
    $step = 'OpenOLBDB'
    $sessionId = (Get-Process -Id $PID).SessionId
    $oldHandles = @([SfitUi]::ChromeWindows($sessionId) | ForEach-Object { [SfitUi]::WindowHandle($_) })
    $shell = New-Object -ComObject Shell.Application; $hwnd = 0
    $desktop = $shell.Windows().FindWindowSW(0,0,8,[ref]$hwnd,1)
    if (-not $desktop) { throw 'Cannot obtain the interactive Explorer desktop.' }
    $arguments = '--profile-directory="{0}" --new-window --no-first-run --no-default-browser-check --force-renderer-accessibility chrome://version/' -f $profileDirectory
    $desktop.Document.Application.ShellExecute($chrome,$arguments,'','open',1)
    $openUntil = [datetime]::UtcNow.AddSeconds(45); $window = $null; $lastOpenLog = [datetime]::MinValue
    while (-not $window -and [datetime]::UtcNow -lt $openUntil) {
        foreach ($candidateWindow in @([SfitUi]::ChromeWindows($sessionId))) {
            $handle = [SfitUi]::WindowHandle($candidateWindow)
            if ($handle -in $oldHandles) { continue } # Never navigate old profile windows.
            $null = [SfitUi]::EnsureSetupAddress($candidateWindow,'chrome://version/')
            $path = [SfitUi]::VersionProfilePath($candidateWindow,$selection.UserDataDirectory)
            if ($path -and [IO.Path]::GetFullPath($path).TrimEnd('\') -ieq $selection.ProfilePath) {
                $window = $candidateWindow; $windowHandle = $handle; break
            }
        }
        if (-not $window) {
            if (([datetime]::UtcNow-$lastOpenLog).TotalSeconds -ge 5) { Write-SfitTrace 'Waiting for the newly opened OLBDB window and its exact Profile Path.'; $lastOpenLog=[datetime]::UtcNow }
            Start-Sleep -Milliseconds 400
        }
    }
    if (-not $window) { throw 'Cannot verify the dedicated OLBDB Profile Path in a new Chrome window. No existing profile was selected or reset.' }
    Write-SfitTrace "Locked OLBDB window=$windowHandle; verified path=$($selection.ProfilePath)."
    $step = 'ProfileDisplayName'; $nameUntil = [datetime]::UtcNow.AddSeconds(35); $nameStage = 'Edit'; $nameVerified = $false
    while (-not $nameVerified -and [datetime]::UtcNow -lt $nameUntil) {
        $window = [SfitUi]::SelectedWindow($windowHandle,$sessionId)
        if ($nameStage -eq 'Version') {
            $null = [SfitUi]::EnsureSetupAddress($window,'chrome://version/')
            if ([SfitUi]::VersionProfilePath($window,$selection.UserDataDirectory) -ieq $selection.ProfilePath) { $nameStage = 'Confirm' }
        } else {
            $null = [SfitUi]::EnsureSetupAddress($window,'chrome://settings/manageProfile')
            $name = [SfitUi]::ProfileDisplayName($window)
            if ($name -ceq $selection.ProfileName) { $nameVerified = $true }
            elseif ($name -and $nameStage -eq 'Edit' -and [SfitUi]::SetProfileDisplayName($window,$selection.ProfileName)) { $nameStage = 'Version' }
        }
        if (-not $nameVerified) { Start-Sleep -Milliseconds 400 }
    }
    if (-not $nameVerified) { throw 'Chrome did not confirm the saved exam profile display name.' }
    Complete-SfitExamProfileName $env:LOCALAPPDATA (Join-Path $logRoot 'olbdb-profile.json') $selection.ProfileName $config.ChromeProfileKey $profileDirectory $selection.ProfileToken
    Write-SfitTrace "Profile display name verified=$($selection.ProfileName); shortcut=$shortcut."
    $pins = New-Object 'Collections.Generic.Queue[string]'
    foreach ($id in @(Get-SfitPinnedExtensions $selection.ProfilePath | Sort-Object -Unique)) { $pins.Enqueue($id) }
    $pinCount = $pins.Count; $unpinChanged = 0; $pinInventoryReady = $false
    Write-LabJson (Join-Path $logRoot 'expected.json') ($plan + @{profileDirectory=$profileDirectory;profilePath=$selection.ProfilePath;profileName=$selection.ProfileName;shortcut=$shortcut;chromeExecutable=$chrome;extensionDirectory=$destination})
    Write-SfitTrace "Verified dedicated profile=$profileDirectory; path=$($selection.ProfilePath); pinned extensions=$pinCount. Existing profiles are preserved."
    Write-Host "SFIT: Profile $($selection.ProfileName) [$profileDirectory]; shortcut tren Desktop; giu nguyen profile cu." -ForegroundColor Cyan
    $started = [datetime]::UtcNow
    $deadline = [datetime]::UtcNow.AddSeconds(([math]::Min(600,$config.ChromeAutomationTimeoutSeconds+10*$pinCount)))
    $step = 'Navigate'; $loaded = $false; $ready = $null
    $lastObservation = ''; $lastProgress = [datetime]::MinValue; $loadedAt = [datetime]::MaxValue
    $unpinId = ''; $unpinUntil = [datetime]::MinValue
    while ([datetime]::UtcNow -lt $deadline) {
        $heartbeat = Join-Path $logRoot 'heartbeat.json'
        if ($loaded -and (Test-Path -LiteralPath $heartbeat)) {
            try {
                $candidate = Get-Content -LiteralPath $heartbeat -Raw | ConvertFrom-Json
                if ($candidate.token -eq $token -and $candidate.packageId -eq $lock.PackageId -and $candidate.configSha256 -eq $extension.configSha256 -and
                    $candidate.userSid -eq $sid -and ([datetimeoffset]::Parse($candidate.receivedAtUtc)).UtcDateTime -ge $loadedAt) {
                    if ($candidate.phase -in @('INVALID_CONFIG','ERROR')) { throw "Extension runtime error: $($candidate.error)" }
                    if ($candidate.phase -in @('WAITING','ACTIVE','ENDED','DISABLED')) { $ready = $candidate; break }
                }
            } catch { if ("$_" -like '*Extension runtime error:*') { throw }; Write-Verbose "Waiting for complete native report: $_" }
        }
        $window = [SfitUi]::SelectedWindow($windowHandle,$sessionId)
        if ($window) {
            if ($step -in @('Navigate','DeveloperMode','Load')) {
                $page = [SfitUi]::EnsureExtensionsPage($window)
                if ($page -eq 'Ready') {
                    if ($step -eq 'Navigate') { $step = 'DeveloperMode'; Write-SfitTrace 'Confirmed chrome://extensions/ AND the loaded Extensions document.' }
                    if ($step -eq 'DeveloperMode' -and [SfitUi]::EnableDeveloperMode($window)) {
                        if (-not $pinInventoryReady) {
                            # Include live extension IDs as Chrome may not yet
                            # have flushed newly pinned icons to Preferences.
                            $ids = @(@($pins.ToArray()) + @([SfitUi]::ExtensionIds($window)) | Sort-Object -Unique)
                            Assert-SfitToolbarPolicies $ids
                            $pins.Clear(); foreach ($id in $ids) { $pins.Enqueue($id) }
                            $pinInventoryReady = $true
                            $deadline = [datetime]::UtcNow.AddSeconds([math]::Min(600,$config.ChromeAutomationTimeoutSeconds+10*$pins.Count))
                            Write-SfitTrace "Live extension/pin inventory=$($pins.Count)."
                        }
                        $step = if ($pins.Count) {'Unpin'} else {'Load'}
                        Write-SfitTrace 'Developer mode ready; preparing unpin/load.'
                    }
                    elseif ($step -eq 'Load' -and [SfitUi]::ClickLoad($window)) { $step = 'Folder'; Write-SfitTrace 'Load unpacked dispatched; waiting for native folder dialog.' }
                } else {
                    $step = 'Navigate'
                    $observation = "$page; window=$([SfitUi]::WindowTitle($window))"
                    if ($observation -ne $lastObservation) { Write-SfitTrace $observation; $lastObservation = $observation }
                }
            } elseif ($step -eq 'Unpin') {
                if (-not $pins.Count) { $step = 'Navigate'; continue }
                $id = $pins.Peek()
                if ($unpinId -ne $id) { $unpinId = $id; $unpinUntil = [datetime]::UtcNow.AddSeconds(25) }
                if ([datetime]::UtcNow -ge $unpinUntil) { throw "Cannot verify/unpin extension $id in the selected profile within 25 seconds." }
                $null = [SfitUi]::EnsureSetupAddress($window,('chrome://extensions/?id='+$id))
                $pinState = [SfitUi]::UnpinExtension($window,$id)
                if ($pinState -eq 'Changed') { $unpinChanged++; Write-SfitTrace "Unpinned extension=$id" }
                if ($pinState -in @('Unpinned','NotPinnable')) { $null = $pins.Dequeue(); $step = if ($pins.Count) {'Unpin'} else {'Navigate'} }
            } elseif ($step -eq 'Folder' -and [SfitUi]::SelectFolder($window,$destination)) {
                $step = 'Verify'; $loadedAt = [datetime]::UtcNow; $loaded = $true; Write-SfitTrace 'Selected the local extension folder; waiting for a fresh native report.'
            }
        } elseif (([datetime]::UtcNow-$lastProgress).TotalSeconds -ge 5) {
            Write-SfitTrace 'Waiting for a visible Chrome browser window.'
        }
        if (([datetime]::UtcNow-$lastProgress).TotalSeconds -ge 5) { Write-SfitTrace 'Waiting; native handshake has not passed yet.'; $lastProgress = [datetime]::UtcNow }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        throw "Chrome UI automation timed out at $step. No fresh extension handshake was received. See $logRoot. Rerunning creates a new exam profile; old profiles are preserved."
    }
    # Verify the target profile really contains SFIT, and leave SFIT unpinned.
    # This also prevents a heartbeat from another profile alone from succeeding.
    $step = 'UnpinSFIT'; $pinUntil = [datetime]::UtcNow.AddSeconds(30); $sfitUnpinned = $false
    while (-not $sfitUnpinned -and [datetime]::UtcNow -lt $pinUntil) {
        $window = [SfitUi]::SelectedWindow($windowHandle,$sessionId)
        $null = [SfitUi]::EnsureSetupAddress($window,('chrome://extensions/?id='+$extension.id))
        $state = [SfitUi]::UnpinExtension($window,$extension.id)
        if ($state -eq 'Changed') { $unpinChanged++ }
        if ($state -eq 'Unpinned') { $sfitUnpinned = $true } else { Start-Sleep -Milliseconds 400 }
    }
    if (-not $sfitUnpinned) { throw 'SFIT detail/pin state was not verified in the selected profile.' }
    Write-LabJson (Join-Path $logRoot 'profile-state.json') @{Schema=4;Status='Ready';UserSid=$sid;UserDataDirectory=$selection.UserDataDirectory;
        ProfileDirectory=$profileDirectory;ProfilePath=$selection.ProfilePath;ProfileName=$selection.ProfileName;Shortcut=$shortcut;ProfileLayout='DedicatedOLBDB';Unpinned=$true;At=(Get-Date -Format o)}
    Write-LabJson (Join-Path $logRoot 'result.json') @{Status='Passed';PackageId=$lock.PackageId;ExtensionId=$extension.id;Version=$extension.version;ConfigSha256=$extension.configSha256;
        Phase=$ready.phase;ProfileDirectory=$profileDirectory;UserSid=$sid;At=(Get-Date -Format o);ElapsedSeconds=([datetime]::UtcNow-$started).TotalSeconds;Scope='Dedicated OLBDB Chrome profile only';UiLoadPerformed=$loaded;
        ProfilePrepared=$true;ProfileLayout='DedicatedOLBDB';ProfilePath=$selection.ProfilePath;ProfileName=$selection.ProfileName;Shortcut=$shortcut;ExamUrl=$examUrl;ExtensionsUnpinned=$true;UnpinChanges=$unpinChanged;LegacyPolicyCleanup=$migration.Status;UninstallProtection='NotAvailable_OfflineUnpacked'}
    Write-Host "SFIT DA XAC NHAN: $($ready.phase), profile $($selection.ProfileName) [$profileDirectory], lich $($extension.startAt) -> $($extension.endAt)" -ForegroundColor Green
    Write-SfitTrace "Passed: fresh native report phase=$($ready.phase)."
    exit 0
} catch {
    $failure = $_
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    try {
        Write-SfitTrace "Failed: $failure"
        if ($window) { [SfitUi]::Describe($window) | Set-Content -LiteralPath (Join-Path $logRoot 'uia-diagnostic.txt') -Encoding UTF8 }
        else { 'No visible Chrome browser window was found for this attempt.' | Set-Content -LiteralPath (Join-Path $logRoot 'uia-diagnostic.txt') -Encoding UTF8 }
    } catch { Add-Content -LiteralPath $tracePath -Value "Diagnostic collection failed: $_" -Encoding UTF8 }
    Write-LabJson (Join-Path $logRoot 'result.json') @{Status='Failed';PackageId=$lock.PackageId;At=(Get-Date -Format o);Error="$failure";Stack=$failure.ScriptStackTrace;Step=$step;ElapsedSeconds=([datetime]::UtcNow-$started).TotalSeconds}
    Write-Host "CHUA CAI DUOC SFIT: $failure" -ForegroundColor Red
    exit 69030
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
