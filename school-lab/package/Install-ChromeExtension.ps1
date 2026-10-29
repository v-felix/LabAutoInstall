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
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'")) {
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
        if ($owner.Sid -eq $sid) { throw 'Close Chrome completely (including background Chrome processes), then run Install-ChromeExtension.cmd again. No processes were killed.' }
    }
    $candidates = @($config.ChromeExecutable, "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    $chrome = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $chrome) { throw 'Chrome is not installed. Install Chrome Stable, then rerun this extension-only command.' }
    if ((Get-Item -LiteralPath $chrome).VersionInfo.FileMajorPart -lt 120) { throw 'Chrome 120 or newer is required.' }
    if ($config.ChromeProfileDirectory -ne 'Default') { throw 'This classroom package uses one Default/SchoolLab Chrome profile.' }
    Import-Module (Join-Path $PackageRoot 'Chrome.Profile.psm1') -Force
    $step = 'LegacyPolicyCleanup'
    $migration = Remove-SfitLegacyPolicies (Join-Path $logRoot 'policy-state.json')
    Write-SfitTrace "Old SchoolLab policies: $($migration.Status); changed=$($migration.ChangedNames -join ',')"
    # Check unrelated administrator policies BEFORE discarding profile data.
    Assert-SfitUnpackedPolicies $extension.id
    $step = 'ProfileReset'
    Write-Host 'SFIT: Don profile Chrome cu, khong sao luu; chuan bi mot profile SchoolLab.' -ForegroundColor Cyan
    $profileState = Initialize-SfitChromeProfile $env:LOCALAPPDATA (Join-Path $logRoot 'profile-state.json')
    Write-SfitTrace "One profile ready: Default/SchoolLab; path=$($profileState.UserDataDirectory); no backup or profile-blocking policies."
    $step = 'ChromeShortcuts'
    $shortcutRoots = @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))
    $shortcuts = Update-SfitChromeShortcuts $chrome $shortcutRoots ([Environment]::GetFolderPath('Desktop'))
    Write-SfitTrace "Chrome shortcuts normalized=$($shortcuts.Changed.Count); custom data shortcuts skipped=$($shortcuts.SkippedCustomData.Count); lab=$($shortcuts.SchoolLabShortcut)"
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
    Write-LabJson (Join-Path $logRoot 'expected.json') ($plan + @{profileDirectory=$config.ChromeProfileDirectory;extensionDirectory=$destination})
    Write-SfitTrace "Chrome=$chrome; version=$((Get-Item -LiteralPath $chrome).VersionInfo.FileVersion); profile=$($config.ChromeProfileDirectory); session=$((Get-Process -Id $PID).SessionId)"
    # Load runtime accessibility assemblies before compiling the shipped UI driver.
    Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
    $references = @([Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ToggleState].Assembly.Location,[Windows.DependencyObject].Assembly.Location,'System.dll')
    Add-Type -Path (Join-Path $support 'Sfit.UiAutomation.cs') -ReferencedAssemblies $references
    $started = [datetime]::UtcNow
    Write-Host 'SFIT: Mo Chrome va tu nap extension. Hay de may yen, khong chuyen cua so.' -ForegroundColor Cyan
    # Ask the existing Explorer desktop to launch Chrome with its normal token.
    $shell = New-Object -ComObject Shell.Application
    $hwnd = 0
    $desktop = $shell.Windows().FindWindowSW(0,0,8,[ref]$hwnd,1)
    if (-not $desktop) { throw 'Cannot obtain the interactive Explorer desktop to launch Chrome without elevation.' }
    $arguments = '--profile-directory="{0}" --new-window --no-first-run --no-default-browser-check --force-renderer-accessibility chrome://extensions/' -f $config.ChromeProfileDirectory
    $desktop.Document.Application.ShellExecute($chrome,$arguments,'','open',1)
    Write-SfitTrace 'Requested a Chrome window at chrome://extensions/ through Explorer.'
    $deadline = [datetime]::UtcNow.AddSeconds($config.ChromeAutomationTimeoutSeconds)
    $step = 'Navigate'; $loaded = $false; $ready = $null
    $lastNavigation = [datetime]::UtcNow; $recoveryWindows = 0; $lastObservation = ''; $lastProgress = [datetime]::MinValue
    while ([datetime]::UtcNow -lt $deadline) {
        $heartbeat = Join-Path $logRoot 'heartbeat.json'
        if (Test-Path -LiteralPath $heartbeat) {
            try {
                $candidate = Get-Content -LiteralPath $heartbeat -Raw | ConvertFrom-Json
                if ($candidate.token -eq $token -and $candidate.packageId -eq $lock.PackageId -and $candidate.configSha256 -eq $extension.configSha256 -and
                    $candidate.userSid -eq $sid -and ([datetimeoffset]::Parse($candidate.receivedAtUtc)).UtcDateTime -ge $started) {
                    if ($candidate.phase -in @('INVALID_CONFIG','ERROR')) { throw "Extension runtime error: $($candidate.error)" }
                    if ($candidate.phase -in @('WAITING','ACTIVE','ENDED','DISABLED')) { $ready = $candidate; break }
                }
            } catch { if ("$_" -like '*Extension runtime error:*') { throw }; Write-Verbose "Waiting for complete native report: $_" }
        }
        $window = [SfitUi]::ChromeWindow((Get-Process -Id $PID).SessionId)
        if ($window) {
            if ($step -in @('Navigate','DeveloperMode','Load')) {
                $page = [SfitUi]::EnsureExtensionsPage($window)
                if ($page -eq 'Ready') {
                    $lastNavigation = [datetime]::UtcNow
                    if ($step -eq 'Navigate') { $step = 'DeveloperMode'; Write-SfitTrace 'Confirmed chrome://extensions/ AND the loaded Extensions document.' }
                    if ($step -eq 'DeveloperMode' -and [SfitUi]::EnableDeveloperMode($window)) { $step = 'Load'; Write-SfitTrace 'Load unpacked is visible.' }
                    elseif ($step -eq 'Load' -and [SfitUi]::ClickLoad($window)) { $step = 'Folder'; Write-SfitTrace 'Load unpacked dispatched; waiting for native folder dialog.' }
                } else {
                    $step = 'Navigate'
                    $observation = "$page; window=$([SfitUi]::WindowTitle($window))"
                    if ($observation -ne $lastObservation) { Write-SfitTrace $observation; $lastObservation = $observation }
                    # The driver selects an existing Extensions tab, or directly
                    # sets the native omnibox and commits Enter after focus checks.
                    # A dedicated window is only a bounded secondary recovery.
                    if ($recoveryWindows -lt 2 -and ([datetime]::UtcNow-$lastNavigation).TotalSeconds -ge 10) {
                        $desktop.Document.Application.ShellExecute($chrome,$arguments,'','open',1)
                        $recoveryWindows++; $lastNavigation = [datetime]::UtcNow
                        Write-SfitTrace "Requested recovery window $recoveryWindows at chrome://extensions/."
                    }
                }
            } elseif ($step -eq 'Folder' -and [SfitUi]::SelectFolder($window,$destination)) {
                $step = 'Verify'; $loaded = $true; Write-SfitTrace 'Selected the local extension folder; waiting for a fresh native report.'
            }
        } elseif (([datetime]::UtcNow-$lastProgress).TotalSeconds -ge 5) {
            Write-SfitTrace 'Waiting for a visible Chrome browser window.'
        }
        if (([datetime]::UtcNow-$lastProgress).TotalSeconds -ge 5) { Write-SfitTrace 'Waiting; native handshake has not passed yet.'; $lastProgress = [datetime]::UtcNow }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        throw "Chrome UI automation timed out at $step. No fresh extension handshake was received. See $logRoot. Close Chrome and rerun."
    }
    Write-LabJson (Join-Path $logRoot 'result.json') @{Status='Passed';PackageId=$lock.PackageId;ExtensionId=$extension.id;Version=$extension.version;ConfigSha256=$extension.configSha256;
        Phase=$ready.phase;ProfileDirectory=$config.ChromeProfileDirectory;UserSid=$sid;At=(Get-Date -Format o);ElapsedSeconds=([datetime]::UtcNow-$started).TotalSeconds;Scope='Selected Chrome profile only';UiLoadPerformed=$loaded;
        ProfilePrepared=$true;ProfileLayout='OneDefault_NoBackup';LegacyPolicyCleanup=$migration.Status;ChromeShortcut=$shortcuts.SchoolLabShortcut;UninstallProtection='NotAvailable_OfflineUnpacked'}
    Write-Host "SFIT DA XAC NHAN: $($ready.phase), profile $($config.ChromeProfileDirectory), lich $($extension.startAt) -> $($extension.endAt)" -ForegroundColor Green
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
