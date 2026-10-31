#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Silent','Interactive')][string]$DeployMode = 'Silent', [string]$ResultPath = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'Lab.Core.psm1') -Force
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$logDirectory = Join-Path $env:ProgramData "SchoolLab\Logs\$env:COMPUTERNAME\$runId"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$report = [ordered]@{ Computer = $env:COMPUTERNAME; RunId = $runId; StartedAt = (Get-Date -Format o);
    Status = 'Running'; ExitCode = 69001; RebootRequired = $false; Components = @(); Error = '' }
$rows = @{}
foreach ($name in @('Preflight','DevCpp','Jdk','Python','VSCode','Environment','UserProvisioning','ChromeExtension','SmokeTests')) {
    $rows[$name] = [pscustomobject]@{ Name = $name; Status = 'NotRun'; InstalledVersion = ''; RequiredVersion = '';
        ExitCode = $null; Details = '' }
    $report.Components += $rows[$name]
}
$exitCode = 69001
$sessionOpen = $false
$current = 'Preflight'
$mutex = New-Object Threading.Mutex($false, 'Global\SchoolLab-Deployment')
$held = $false
Start-Transcript -Path (Join-Path $logDirectory 'deployment.log') -Force | Out-Null

function Save-LabReport {
    $report.LogDirectory = $logDirectory
    Write-LabJson (Join-Path $logDirectory 'result.json') $report
    if ($ResultPath) { Write-LabJson $ResultPath $report }
    $report.Components | Export-Csv -LiteralPath (Join-Path $logDirectory 'components.csv') -NoTypeInformation -Encoding UTF8
}

function Invoke-LabInstaller {
    param([string]$FilePath, [string[]]$Arguments)
    # IgnoreExitCodes allows OUR journal to retain the exact failure code. This is
    # intentional and supported by PSADT 4.1.8; never infer success from no exception.
    $result = Start-ADTProcess -FilePath $FilePath -ArgumentList $Arguments -PassThru -IgnoreExitCodes '*' `
        -Timeout ([timespan]::FromMinutes($config.InstallerTimeoutMinutes)) -ErrorAction Stop
    $rows[$current].ExitCode = $result.ExitCode
    Save-LabReport
    if ($result.ExitCode -in @(3010,1641)) { $report.RebootRequired = $true }
    if ($result.ExitCode -eq 1641) { throw 'Installer initiated a reboot despite /norestart; stop and rerun after restart.' }
    if ($result.ExitCode -notin @(0,3010)) { throw "Installer failed with exit code $($result.ExitCode): $FilePath" }
}

try {
    try { $held = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { $exitCode = 69002; throw 'Another SchoolLab deployment is running.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run Install-Lab.cmd as Administrator.'
    }
    if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'Only Windows x64 with 64-bit Windows PowerShell is supported.'
    }
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 10240) { throw 'Windows 10/11 workstation is required.' }
    $report.OS = $os.Caption + ' build ' + $os.BuildNumber
    $config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'LabConfig.psd1')
    $dotNet = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release
    if ($dotNet -lt 461808) { throw '.NET Framework 4.7.2 or later is required by PSADT.' }
    $lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package-lock.json') -Raw | ConvertFrom-Json
    Test-LabPackage $PSScriptRoot $lock
    $report.PackageId = $lock.PackageId
    $pending = @(Get-LabPendingReboot)
    $report.PendingRebootAtStart = $pending
    if ($pending.Count) {
        $report.RebootRequired = $true
        Write-Warning ('Windows has a pending restart: ' + ($pending -join ', ') + '. The launcher will restart only after ALL setup steps pass.')
    }
    if ($pending.Count -and $config.BlockOnPendingReboot) {
        $report.RebootRequired = $true
        $exitCode = 3010
        throw 'Reboot is pending before installation. Restart, then run the package again.'
    }
    $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive)
    if ($disk.FreeSpace -lt ($config.MinimumFreeGB * 1GB)) { throw "Need at least $($config.MinimumFreeGB) GB free after staging." }
    $applications = @(Get-LabApplications)
    $applications | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logDirectory 'inventory.json') -Encoding UTF8
    $paths = @{
        Jdk = Expand-LabPath $config.JdkDirectory
        Python = Expand-LabPath $config.PythonDirectory
        VSCode = Expand-LabPath $config.VSCodeDirectory
    }
    $support = Expand-LabPath $config.SupportDirectory
    foreach ($target in @($paths.Values) + @($support)) {
        if (-not ([IO.Path]::GetFullPath($target)).StartsWith($env:ProgramFiles + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Machine installation paths must be inside Program Files: $target"
        }
    }
    $relativeExe = @{ Jdk = 'bin\java.exe'; Python = 'python.exe'; VSCode = 'Code.exe' }
    # Reuse exact-version machine installs, including those not installed by us.
    foreach ($name in @('Jdk','Python','VSCode')) {
        $required = $lock.Components.$name.Version
        $rows[$name].RequiredVersion = $required
        $candidates = @($paths[$name])
        if ($name -eq 'Jdk') { $candidates += [Environment]::GetEnvironmentVariable('JAVA_HOME','Machine') }
        $candidates += @($applications | Where-Object { $_.RegistryKey -like 'HKEY_LOCAL_MACHINE*' -and $_.InstallLocation } |
            ForEach-Object InstallLocation)
        if ($name -eq 'Python' -and (Test-Path 'HKLM:\SOFTWARE\Python\PythonCore')) {
            foreach ($key in Get-ChildItem 'HKLM:\SOFTWARE\Python\PythonCore') {
                $installKey = Join-Path $key.PSPath 'InstallPath'
                if (Test-Path $installKey) { $candidates += (Get-Item $installKey).GetValue('') }
            }
        }
        foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
            $candidate = Expand-LabPath ([string]$candidate).Trim().Trim('"')
            try { $candidate = [IO.Path]::GetFullPath($candidate) } catch { continue }
            # A per-user install must never satisfy the all-users requirement.
            if (-not ([IO.Path]::GetFullPath($candidate)).StartsWith($env:ProgramFiles + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $exe = Join-Path $candidate $relativeExe[$name]
            if ((Test-Path -LiteralPath $exe) -and (Test-LabX64Executable $exe)) {
                if ((Get-LabExecutableVersion $exe $name) -ceq $required) {
                    if ($name -eq 'Jdk' -and -not (Test-Path (Join-Path $candidate 'bin\javac.exe'))) { continue }
                    $paths[$name] = $candidate
                    break
                }
            }
        }
        $rows[$name].InstalledVersion = Get-LabExecutableVersion (Join-Path $paths[$name] $relativeExe[$name]) $name
        $rows[$name].Details = $paths[$name]
        # Detect downgrades before the first installer makes a change.
        $null = Get-LabVersionAction $rows[$name].InstalledVersion $required
    }
    if (Get-Process -Name Code -ErrorAction SilentlyContinue) { throw 'Close all VS Code windows before installing applications and extensions.' }
    $rows.Preflight.Status = 'Passed'
    Save-LabReport

    $module = Join-Path $PSScriptRoot 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
    $moduleInfo = Import-PowerShellDataFile $module
    if ($moduleInfo.ModuleVersion -ne '4.1.8') { throw 'PSADT must be exactly 4.1.8.' }
    # Match the official 4.1.8 template: ZIP extraction can propagate Mark of
    # the Web to DLLs. ExecutionPolicy Bypass does not unblock .NET assemblies.
    # All package hashes were verified above, before removing zone metadata.
    Get-ChildItem -LiteralPath (Split-Path -Parent $module) -Recurse -File |
        Unblock-File -ErrorAction Stop
    Import-Module -Name $module -Force
    # RequireAdmin is a SWITCH in 4.1.8. Splat its boolean value so it cannot
    # become a positional SessionState argument (as '-RequireAdmin $true' did).
    $sessionOptions = @{
        SessionState = $ExecutionContext.SessionState
        ScriptDirectory = $PSScriptRoot
        AppVendor = 'SchoolLab'
        AppName = 'School Programming Lab'
        AppVersion = $config.PackageRevision
        AppArch = 'x64'
        AppLang = 'EN'
        AppRevision = '01'
        RequireAdmin = $true
        DeploymentType = 'Install'
        DeployMode = $DeployMode
        AppScriptVersion = $config.PackageRevision
        AppScriptDate = '2026-10-24'
        AppScriptAuthor = 'School IT'
    }
    $adtSession = Open-ADTSession @sessionOptions -PassThru
    $sessionOpen = $true
    $current = 'DevCpp'
    $rows.DevCpp.RequiredVersion = $lock.Components.DevCpp.Version + ' (only if missing)'
    $devcpp = Get-LabDevCpp $config $applications
    if (-not $devcpp) {
        $devDirectory = Expand-LabPath $config.DevCppDirectory
        $devBase = [IO.Path]::GetFullPath((Expand-LabPath '%ProgramFiles(x86)%')).TrimEnd('\') + '\'
        if (-not ([IO.Path]::GetFullPath($devDirectory)).StartsWith($devBase,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'DevCppDirectory must be inside Program Files (x86).'
        }
        Write-Host 'Installing Dev-C++ with its MinGW compiler...'
        $rows.DevCpp.Status = 'Running'
        Save-LabReport
        Invoke-LabInstaller (Resolve-LabPackagePath $PSScriptRoot $lock.Components.DevCpp.File) @("/S /D=$devDirectory")
        $applications = @(Get-LabApplications)
        $devcpp = Get-LabDevCpp $config $applications
        if (-not $devcpp) { throw 'Dev-C++ installer finished but devcpp.exe was not found.' }
        $rows.DevCpp.Status = 'Installed'
    } else { $rows.DevCpp.Status = 'Skipped' }
    $rows.DevCpp.InstalledVersion = $devcpp.Version
    $rows.DevCpp.Details = $devcpp.Directory
    Save-LabReport
    $current = 'Preflight'
    $mingwConfig = $config.Clone()
    # Prefer the compiler paired with the detected Dev-C++ IDE when unambiguous.
    if (-not $config.MinGWBin) {
        $paired = @(Get-ChildItem -LiteralPath $devcpp.Directory -Directory | ForEach-Object { Join-Path $_.FullName 'bin' } |
            Where-Object { (Test-Path (Join-Path $_ 'g++.exe')) -and (Test-Path (Join-Path $_ 'gdb.exe')) })
        if ($paired.Count -eq 1) { $mingwConfig.MinGWBin = $paired[0] }
    }
    $mingw = Get-LabMinGW -Config $mingwConfig -Applications $applications
    $report.MinGW = $mingw
    $originalPath = $env:Path
    try {
        $env:Path = $mingw.Bin + ';' + $env:Path
        $cppStandard = Resolve-LabCppStandard $mingw $config.CppStandard (Join-Path $logDirectory 'cpp-preflight')
        $report.CppStandard = $cppStandard
        $null = Test-LabCppToolchain $mingw (Join-Path $logDirectory 'cpp-preflight') $cppStandard
    } finally { $env:Path = $originalPath }
    Save-LabReport
    foreach ($current in @('Jdk','Python','VSCode')) {
        Write-Host "Processing $current (required $($lock.Components.$current.Version))..."
        $rows[$current].Status = 'Running'
        $component = $lock.Components.$current
        $exe = Join-Path $paths[$current] $relativeExe[$current]
        $action = Get-LabVersionAction $rows[$current].InstalledVersion $component.Version
        # An incomplete same-version installation needs repair, not an empty skip.
        if ($action -eq 'Skip' -and $current -eq 'Python') {
            try { $null = Assert-LabCommand $exe @('-I','-m','pip','--version') } catch { $action = 'Repair' }
        }
        if ($action -eq 'Skip' -and $current -eq 'Jdk' -and -not (Test-Path (Join-Path $paths.Jdk 'bin\javac.exe'))) { $action = 'Repair' }
        if ($action -eq 'Skip') { $rows[$current].Status = 'Skipped' } else {
            $file = Resolve-LabPackagePath $PSScriptRoot $component.File
            switch ($current) {
                Jdk {
                    $arguments = '/i "{0}" /qn /norestart REBOOT=ReallySuppress ALLUSERS=1 ADDLOCAL=FeatureMain INSTALLDIR="{1}" /L*v "{2}"' -f
                        $file, $paths.Jdk, (Join-Path $logDirectory 'jdk-msi.log')
                    if ($action -eq 'Repair') { $arguments += ' REINSTALL=ALL REINSTALLMODE=amus' }
                    Invoke-LabInstaller "$env:SystemRoot\System32\msiexec.exe" @($arguments)
                }
                Python {
                    $mode = if ($action -eq 'Repair') { '/repair' } else { '' }
                    $arguments = '{0} /quiet /norestart InstallAllUsers=1 TargetDir="{1}" Include_pip=1 Include_test=0 Include_doc=0 Include_launcher=0 Include_debug=0 Include_symbols=0 Include_freethreaded=0 PrependPath=0 /log "{2}"' -f
                        $mode, $paths.Python, (Join-Path $logDirectory 'python.log')
                    Invoke-LabInstaller $file @($arguments)
                }
                VSCode {
                    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /MERGETASKS="!runcode,!addtopath" /DIR="{0}" /LOG="{1}"' -f
                        $paths.VSCode, (Join-Path $logDirectory 'vscode.log')
                    Invoke-LabInstaller $file @($arguments)
                }
            }
            $actual = Get-LabExecutableVersion $exe $current
            if ($actual -cne $component.Version) { throw "Version mismatch after install: $current expected $($component.Version), actual '$actual'." }
            if (-not (Test-LabX64Executable $exe)) { throw "Not x64: $exe" }
            $rows[$current].InstalledVersion = $actual
            $rows[$current].Status = 'Installed'
        }
        Save-LabReport
    }
    $current = 'Environment'
    Set-LabMachineEnvironment -JavaHome $paths.Jdk -PathEntries @((Join-Path $paths.Jdk 'bin'), $paths.Python,
        (Join-Path $paths.Python 'Scripts'), $mingw.Bin, (Join-Path $paths.VSCode 'bin'))
    $rows.Environment.Status = 'Passed'
    if ($config.PinVSCodeUpdates) {
        $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\VSCode'
        New-Item -Path $policy -Force | Out-Null
        # Domain policy may override these; validate with Policy Diagnostics in pilot.
        New-ItemProperty -LiteralPath $policy -Name UpdateMode -Value 'none' -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $policy -Name ExtensionsAutoUpdate -Value 'off' -PropertyType String -Force | Out-Null
    }
    Save-LabReport

    $current = 'UserProvisioning'
    $support = Expand-LabPath $config.SupportDirectory
    # Program Files inherits read/execute for students, write for admins/SYSTEM.
    if (-not $support.StartsWith($env:ProgramFiles + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'SupportDirectory must be inside Program Files.'
    }
    New-Item -ItemType Directory -Path (Join-Path $support 'Extensions') -Force | Out-Null
    foreach ($file in @('Lab.Core.psm1','Initialize-LabUser.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $support -Force }
    $extensions = @()
    foreach ($extension in $lock.Extensions) {
        $file = Resolve-LabPackagePath $PSScriptRoot $extension.File
        $destination = 'Extensions\' + [IO.Path]::GetFileName($file)
        Copy-Item -LiteralPath $file -Destination (Join-Path $support $destination) -Force
        $extensions += [pscustomobject]@{ Id = $extension.Id; Version = $extension.Version; File = $destination; SHA256 = $extension.SHA256 }
        if ($config.EnableExtensionBootstrap) {
            $bootstrap = Join-Path $paths.VSCode 'bootstrap\extensions'
            New-Item -ItemType Directory -Path $bootstrap -Force | Out-Null
            Copy-Item -LiteralPath $file -Destination $bootstrap -Force
        }
    }
    @{ PackageId = $lock.PackageId; JavaHome = $paths.Jdk; PythonHome = $paths.Python; CodeDirectory = $paths.VSCode;
        JavaVersion=$lock.Components.Jdk.Version; MinGW = $mingw; CppStandard = $cppStandard; Extensions = $extensions;
        AdditionalProfiles = @($config.AdditionalVSCodeProfiles) } | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath (Join-Path $support 'user-settings.json') -Encoding UTF8
    $run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $run -Force | Out-Null
    $command = '"{0}" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}"' -f
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe", (Join-Path $support 'Initialize-LabUser.ps1')
    New-ItemProperty -LiteralPath $run -Name 'SchoolLabUserInit' -Value $command -PropertyType String -Force | Out-Null
    $rows.UserProvisioning.Status = 'PendingUserLogon'
    $rows.ChromeExtension.Status = if ($config.EnableChromeExtension) { 'PendingInteractiveInstall' } else { 'Disabled' }
    $rows.ChromeExtension.Details = 'Launcher runs Chrome extension setup after classroom account initialization; profile scoped.'
    $rows.UserProvisioning.Details = 'Teacher must restart/sign into the classroom account and run Check-LabReady.cmd before handover; see %LOCALAPPDATA%\SchoolLab\result.json.'
    Save-LabReport

    $current = 'SmokeTests'
    $test = Test-LabToolchain -JavaHome $paths.Jdk -PythonHome $paths.Python -MinGW $mingw `
        -Directory (Join-Path $logDirectory 'smoke') -Standard $cppStandard
    $test | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logDirectory 'smoke-tests.json') -Encoding UTF8
    foreach ($pair in @(@('java.exe', (Join-Path $paths.Jdk 'bin\java.exe')), @('javac.exe', (Join-Path $paths.Jdk 'bin\javac.exe')),
        @('python.exe', (Join-Path $paths.Python 'python.exe')), @('pip.exe', (Join-Path $paths.Python 'Scripts\pip.exe')),
        @('g++.exe', $mingw.Gpp), @('gdb.exe', $mingw.Gdb))) {
        $resolved = Get-Command $pair[0] -CommandType Application | Select-Object -First 1
        if ($resolved.Source -ine $pair[1]) { throw "PATH conflict: $($pair[0]) resolves to $($resolved.Source), expected $($pair[1])." }
    }
    $rows.SmokeTests.Status = 'Passed'
    if (@(Get-LabPendingReboot).Count) { $report.RebootRequired = $true }
    $report.Status = 'MachinePassed_UserLogonRequired'
    $exitCode = if ($report.RebootRequired) { 3010 } else { 0 }
} catch {
    $rows[$current].Status = if ($exitCode -eq 3010) { 'DeferredReboot' } else { 'Failed' }
    $rows[$current].Details = "$_"
    $report.Status = $rows[$current].Status
    $report.Error = "$_"
    $report.ErrorStack = $_.ScriptStackTrace
    $report.ErrorLine = $_.InvocationInfo.ScriptLineNumber
    Write-Error -Message $_ -ErrorAction Continue
} finally {
    $report.ExitCode = $exitCode
    $report.FinishedAt = Get-Date -Format o
    Save-LabReport
    Stop-Transcript | Out-Null
    if ($held) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
if ($sessionOpen) { Close-ADTSession -ExitCode $exitCode }
exit $exitCode
