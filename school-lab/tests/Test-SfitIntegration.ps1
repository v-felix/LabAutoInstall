#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path (Split-Path -Parent $root) '1-sfit-tracker'
$scratch = Join-Path $root ('test-results\sfit-integration-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$script:passed = 0
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message }; $script:passed++ }
function Throws([scriptblock]$Action) { try { & $Action } catch { $script:passed++; return }; throw 'Expected failure' }
function Json($Value) { ConvertTo-Json -InputObject $Value -Depth 20 -Compress }
function WriteUtf8($Path,$Text) { [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
Import-Module (Join-Path $root 'package\Lab.Core.psm1') -Force

# Compile the production host, then invoke the production validator/writer in an
# isolated directory. Do not register the host or write the real LocalAppData.
$exe = Join-Path $scratch 'Sfit.NativeHost.exe'
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /reference:System.Web.Extensions.dll ("/out:" + $exe) (Join-Path $root 'package\Sfit.NativeHost.cs')
Assert ($LASTEXITCODE -eq 0) 'Native host compilation failed'
$null = [Reflection.Assembly]::LoadFile($exe)
$plan = @{extensionId='abcdefghijklmnopabcdefghijklmnop';version='2.0.0';configSha256='abc';packageId='test';token='nonce'}
$report = @{version='2.0.0';configSha256='abc';packageId='test';token='nonce';phase='WAITING';error=''}
$state = Join-Path $scratch 'state'
$origin = 'chrome-extension://' + $plan.extensionId + '/'
[SfitNativeHost]::SaveReport((Json $report),(Json $plan),$origin,$state,'test-sid')
$saved = Get-Content (Join-Path $state 'heartbeat.json') -Raw | ConvertFrom-Json
Assert ($saved.phase -eq 'WAITING' -and $saved.userSid -eq 'test-sid') 'Valid native status not saved'
$report.phase = 'ENDED'
[SfitNativeHost]::SaveReport((Json $report),(Json $plan),$origin,$state,'test-sid')
Assert ((Get-Content (Join-Path $state 'heartbeat.json') -Raw | ConvertFrom-Json).phase -eq 'ENDED') 'Atomic native report replace failed'
Throws { [SfitNativeHost]::SaveReport((Json $report),(Json $plan),'chrome-extension://other/',$state,'test-sid') }
foreach ($field in @('token','packageId','configSha256','version')) {
    $bad = $report.Clone(); $bad[$field] = 'wrong'
    Throws { [SfitNativeHost]::SaveReport((Json $bad),(Json $plan),$origin,$state,'test-sid') }
}
$bad = $report.Clone(); $bad.phase = 'FAKE'
Throws { [SfitNativeHost]::SaveReport((Json $bad),(Json $plan),$origin,$state,'test-sid') }
Assert ((Get-Content (Join-Path $state 'heartbeat.json') -Raw | ConvertFrom-Json).phase -eq 'ENDED') 'Rejected report overwrote good report'

# Exercise binary Chrome framing through the actual EXE, using a bad token to
# force rejection before any real account path is written.
WriteUtf8 (Join-Path $scratch 'native-plan.json') (Json $plan)
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $exe; $info.Arguments = ConvertTo-LabArgument $origin
$info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true
$process = [Diagnostics.Process]::Start($info)
$bad = $report.Clone(); $bad.token = 'rejected-test-token'
$bytes = [Text.Encoding]::UTF8.GetBytes((Json $bad)); $stream = $process.StandardInput.BaseStream
$prefix = [BitConverter]::GetBytes([int]$bytes.Length); $stream.Write($prefix,0,4); $stream.Write($bytes,0,$bytes.Length); $stream.Flush(); $stream.Close()
$reader = [IO.BinaryReader]::new($process.StandardOutput.BaseStream)
$length = $reader.ReadInt32(); $response = [Text.Encoding]::UTF8.GetString($reader.ReadBytes($length)) | ConvertFrom-Json
Assert (-not $response.ok -and $response.error -like '*token*') 'Native binary framing / rejection failed'
Assert ($process.WaitForExit(5000)) 'Native process did not terminate'; $process.Dispose()

# Compile the exact accessibility driver without invoking any UI actions.
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
Add-Type -Path @((Join-Path $root 'package\Sfit.UiAutomation.cs'),(Join-Path $PSScriptRoot 'Sfit.NavigationProbe.cs')) -ReferencedAssemblies @([Windows.Automation.AutomationElement].Assembly.Location,[Windows.Automation.ToggleState].Assembly.Location,[Windows.DependencyObject].Assembly.Location,'System.dll')
$script:passed++

# Regression from the user's Chrome diagnostic: an existing extension opened
# its Adblock Plus welcome page, so the old installer searched the WRONG page
# for Developer mode until the deadline. Exercise the exact production planner
# without clicking Chrome or changing the developer's browser profile.
Assert ([SfitChromePage]::Plan('https://welcome.adblockplus.org/installed', $false, $false) -eq 'NavigateAddress') 'Welcome page with no Extensions tab must navigate the omnibox'
Assert ([SfitChromePage]::Plan('https://welcome.adblockplus.org/installed', $true, $false) -eq 'SelectTab') 'Welcome page must select the existing Extensions tab'
Assert ([SfitChromePage]::Plan('chrome://extensions/', $false, $true) -eq 'Ready') 'Extensions page must be ready even if tab labels are unavailable'
Assert ([SfitChromePage]::Plan('', $true, $false) -eq 'SelectTab') 'Selected/loading tab is not proof the extensions page is ready'
foreach ($address in @('chrome://extensions','chrome://extensions/','CHROME://EXTENSIONS/')) {
    Assert ([SfitChromePage]::IsExtensionsAddress($address)) "Rejected extensions address $address"
}
foreach ($address in @('https://extensions/','chrome://extensions.evil/','chrome://extensions-internals/','chrome://extensions/other','https://example.test/?url=chrome://extensions/')) {
    Assert (-not [SfitChromePage]::IsExtensionsAddress($address)) "Accepted unrelated page $address"
}
Assert ([SfitChromePage]::IsExtensionsTab('  Extensions  ')) 'Extensions tab matching failed'
Assert (-not [SfitChromePage]::IsExtensionsTab('Adblock Plus has been installed!')) 'Welcome tab mistaken for Extensions'
$viTab = '"Ti\u1ec7n \u00edch"' | ConvertFrom-Json
$viMode = '"Ch\u1ebf \u0111\u1ed9 d\u00e0nh cho nh\u00e0 ph\u00e1t tri\u1ec3n"' | ConvertFrom-Json
$viLoad = '"T\u1ea3i ti\u1ec7n \u00edch \u0111\u00e3 gi\u1ea3i n\u00e9n"' | ConvertFrom-Json
Assert ([SfitChromePage]::IsExtensionsTab($viTab)) 'Vietnamese Extensions tab label failed'
Assert ([SfitChromePage]::IsDeveloperLabel($viMode)) 'Vietnamese Developer mode label failed'
Assert ([SfitChromePage]::IsLoadLabel($viLoad)) 'Vietnamese Load unpacked label failed'
Assert (-not [SfitChromePage]::IsDeveloperLabel('Learn about Developer mode')) 'Unrelated text mistaken for developer switch'

# Regression from the second VM log: Chrome starts on New Tab and ignores
# both launch/recovery URL requests until the tester navigates manually.
Assert ([SfitChromePage]::Plan('chrome://newtab/', $false, $false) -eq 'NavigateAddress') 'New Tab must request real navigation'
Assert ([SfitChromePage]::Plan('chrome://extensions/', $false, $false) -ne 'Ready') 'Typed omnibox text mistaken for loaded page'
Assert ([SfitChromePage]::Plan('https://example.test/', $true, $true) -ne 'Ready') 'Document title alone mistaken for internal page'
Assert ([SfitChromePage]::IsOmniboxLabel('Address and search bar')) 'Native omnibox label not recognized'
Assert (-not [SfitChromePage]::IsOmniboxLabel('Search Google or type a URL')) 'New Tab web search input mistaken for browser omnibox'
$box = [SfitFakeOmnibox]::new()
Assert ([SfitChromeNavigation]::Navigate($box) -eq 'NavigationRequested') 'Production navigation did not request Enter'
Assert ($box.Text -eq 'chrome://extensions/' -and $box.Enters -eq 1 -and $box.Sets -eq 1) 'Wrong navigation target or repeated Enter'
Assert (($box.Events -join '|') -eq 'Activate|Focus|Set:chrome://extensions/|Enter') 'Incorrect production navigation sequence'
$box = [SfitFakeOmnibox]::new(); $box.ChromeTarget = $false
Throws { [SfitChromeNavigation]::Navigate($box) }
Assert ($box.Events.Count -eq 0 -and $box.Enters -eq 0) 'Non-Chrome target received actions'
$box = [SfitFakeOmnibox]::new(); $box.ActivationSucceeds = $false
Assert ([SfitChromeNavigation]::Navigate($box) -eq 'AwaitForeground' -and $box.Enters -eq 0 -and $box.Sets -eq 0) 'Input sent when Chrome was not foreground'
$box = [SfitFakeOmnibox]::new(); $box.FocusSucceeds = $false
Assert ([SfitChromeNavigation]::Navigate($box) -eq 'AwaitOmniboxFocus' -and $box.Enters -eq 0 -and $box.Sets -eq 0) 'Input sent to an unfocused field'
$box = [SfitFakeOmnibox]::new(); $box.ClearKeys = $false
Assert ([SfitChromeNavigation]::Navigate($box) -eq 'AwaitReleasedKeys' -and $box.Enters -eq 0 -and $box.Sets -eq 0) 'Modified Enter could be sent'
foreach ($fault in @('LoseFocusOnSet','LoseForegroundOnSet','HoldKeysOnSet')) {
    $box = [SfitFakeOmnibox]::new(); $box.$fault = $true
    $null = [SfitChromeNavigation]::Navigate($box)
    Assert ($box.Sets -eq 1 -and $box.Enters -eq 0) "Enter sent after context changed: $fault"
}
$box = [SfitFakeOmnibox]::new(); $box.RejectText = $true
Throws { [SfitChromeNavigation]::Navigate($box) }
Assert ($box.Enters -eq 0) 'Enter sent despite rejected URL'
Assert ([SfitFakeOmnibox]::NativeInputSize() -eq $(if ([Environment]::Is64BitProcess) { 40 } else { 28 })) 'Incorrect Win32 INPUT union layout'

# Profile-preserving setup uses only version/details pages in the locked window.
foreach ($url in @('chrome://version/','chrome://extensions/?id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','chrome://settings/manageProfile')) {
    $box = [SfitFakeOmnibox]::new()
    Assert ([SfitChromeNavigation]::NavigateTo($box,$url) -eq 'NavigationRequested') 'Internal setup navigation failed'
    Assert ($box.Text -eq $url -and $box.Enters -eq 1) 'Setup URL was not committed exactly once'
}
foreach ($url in @('https://example.test','chrome://settings/','chrome://version/?bad=1','chrome://extensions/?id=invalid','chrome://extensions/?id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&bad=1')) {
    $box = [SfitFakeOmnibox]::new()
    Throws { [SfitChromeNavigation]::NavigateTo($box,$url) }
    Assert ($box.Events.Count -eq 0) 'Unsafe setup URL received native actions'
}
Assert ([SfitChromePage]::IsPinLabel('Pin to toolbar')) 'Pin toggle label not recognized'
$viPin = '"Ghim l\u00ean thanh c\u00f4ng c\u1ee5"' | ConvertFrom-Json
Assert ([SfitChromePage]::IsPinLabel($viPin)) 'Vietnamese pin label not recognized'
Assert (-not [SfitChromePage]::IsPinLabel('Remove extension')) 'Remove mistaken for pin control'
Assert ([SfitChromePage]::IsProfileNameLabel('Profile name')) 'Profile name label not recognized'
Assert (-not [SfitChromePage]::IsProfileNameLabel('Search settings')) 'Search box mistaken for profile name'

# A small locked fixture exercises the schedule updater with real child PS5.1.
$package = Join-Path $scratch 'package'; $files = Join-Path $package 'Files\ChromeExtension'
New-Item -ItemType Directory -Path $files -Force | Out-Null
$configPath = Join-Path $files 'config.js'
$original = [IO.File]::ReadAllText((Join-Path $source 'config.js'))
WriteUtf8 $configPath $original
WriteUtf8 (Join-Path $files 'background.js') '// immutable code'
$entries = @(Get-ChildItem $files -File | ForEach-Object { @{Path='Files\ChromeExtension\' + $_.Name;SHA256=(Get-FileHash $_.FullName).Hash} })
$meta = @{configSha256=(Get-FileHash $configPath).Hash.ToLowerInvariant();startAt='2026-11-01T13:00:00+07:00';endAt='2026-11-01T17:00:00+07:00';enabled=$true;phase='WAITING'}
$lock = @{PackageId='fixture';ChromeExtension=$meta;Files=$entries}
$lockPath = Join-Path $package 'package-lock.json'; WriteUtf8 $lockPath (Json $lock)
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'package\Update-SfitSchedule.ps1'),'-PackageRoot',$package)
WriteUtf8 $configPath ($original.Replace('2026-11-01','2026-11-02'))
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -eq 0) "Schedule update failed: $($r.StdErr)"
$updated = Get-Content $lockPath -Raw | ConvertFrom-Json
Assert ($updated.PackageId -like 'fixture-sfit-*' -and $updated.ChromeExtension.startAt -like '2026-11-02*') 'Schedule metadata / PackageId not updated'
Assert ($updated.ChromeExtension.configSha256 -eq (Get-FileHash $configPath).Hash.ToLowerInvariant()) 'Schedule hash mismatch'
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -eq 0 -and (Get-Content $lockPath -Raw | ConvertFrom-Json).PackageId -eq $updated.PackageId) 'Updater rerun not idempotent'
WriteUtf8 (Join-Path $files 'background.js') '// TAMPERED'
WriteUtf8 $configPath ($original.Replace('2026-11-01','2026-11-03'))
$before = (Get-FileHash $lockPath).Hash
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -ne 0 -and (Get-FileHash $lockPath).Hash -eq $before) 'Updater accepted modified code or rewrote failed lock'
WriteUtf8 (Join-Path $files 'background.js') '// immutable code'
WriteUtf8 $configPath ($original + "`nthrow 'injected';")
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -ne 0) 'Updater accepted executable code outside JSON config'
WriteUtf8 $configPath ($original.Replace('globalThis.SFIT_CONFIG','/* closed */ throw 1; /* re-open */ globalThis.SFIT_CONFIG'))
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -ne 0) 'Updater accepted executable code between header comments'
WriteUtf8 $configPath ($original.Replace('2026-11-01T17:00:00+07:00','2026-10-31T17:00:00+07:00'))
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -ne 0) 'Updater accepted reversed interval'
WriteUtf8 $configPath ($original.Replace('utcoj.info','exam.utcoj.info'))
$r = Invoke-LabCommand $ps $argsList
Assert ($r.ExitCode -eq 0) 'Updater rejected a valid exam site/allowlist change'
$updated = Get-Content $lockPath -Raw | ConvertFrom-Json
Assert ($updated.ChromeExtension.examUrl -eq 'https://exam.utcoj.info/' -and $updated.ChromeExtension.allowedHosts[0] -eq 'exam.utcoj.info') 'Exam URL/allowlist metadata stayed stale after config change'
@{Passed=$script:passed;PowerShell=$PSVersionTable.PSVersion.ToString();Scope='No UI actions, no Chrome profile/registry/Program Files changes';At=(Get-Date -Format o)} |
    ConvertTo-Json | Set-Content (Join-Path $scratch 'result.json') -Encoding UTF8
Write-Host "PASS: $script:passed SFIT integration checks. $scratch"
