#requires -Version 5.1
[CmdletBinding()]
param([switch]$NoElevation,[string]$ResumeStatePath='')
$ErrorActionPreference = 'Stop'
$launcherMutex = $null
$launcherHeld = $false
$resumeState = $null; $resumeValidated = $false; $keepResume = $false; $deploymentCompleted = $false; $bootstrapLog = $null
try {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not [Environment]::Is64BitProcess) {
        $powershell = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    }
    if (-not $admin -or -not [Environment]::Is64BitProcess) {
        if ($NoElevation) { throw 'Administrator and a 64-bit PowerShell process are required.' }
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -NoElevation' -f $PSCommandPath
        if ($ResumeStatePath) { $arguments += ' -ResumeStatePath "{0}"' -f $ResumeStatePath }
        $options = @{ FilePath = $powershell; ArgumentList = $arguments; Wait = $true; PassThru = $true }
        if (-not $admin) { $options.Verb = 'RunAs' }
        $process = Start-Process @options
        exit $process.ExitCode
    }
    $launcherMutex = New-Object Threading.Mutex($false, 'Global\SchoolLab-Launcher')
    try { $launcherHeld = $launcherMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $launcherHeld = $true }
    if (-not $launcherHeld) { Write-Host 'Another SchoolLab installation is still running.'; exit 69002 }
    $installRoot = Join-Path $env:ProgramFiles 'SchoolLab'
    $bootstrapLog = Join-Path $env:ProgramData ('SchoolLab\Logs\' + $env:COMPUTERNAME + '\Bootstrap')
    New-Item -ItemType Directory -Path $bootstrapLog -Force | Out-Null
    $sourceConfig = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'LabConfig.psd1')
    $totalStages = if ($sourceConfig.EnableChromeExtension) { 5 } else { 4 }
    if ($ResumeStatePath) {
        # Resume only this protected local stage, never the USB/share or another
        # state-supplied executable. Verify hashes before running child scripts.
        Import-Module (Join-Path $PSScriptRoot 'Reboot.Core.psm1') -Force
        $resumeState = Get-Content -LiteralPath $ResumeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Assert-LabResumeState $resumeState $ResumeStatePath $installRoot $sid $env:COMPUTERNAME
        if ($resumeState.StageRoot -ine $PSScriptRoot) { throw 'Resume was invoked from a different staging directory.' }
        $resumeValidated = $true
        $stage = $PSScriptRoot
    } else {
        if ($sourceConfig.EnableChromeExtension) {
            & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Update-SfitSchedule.ps1') -PackageRoot $PSScriptRoot
            if ($LASTEXITCODE -ne 0) { throw 'SFIT schedule preparation failed. No installer was started.' }
        }
        $payloadBytes = (Get-ChildItem -LiteralPath $PSScriptRoot -File -Recurse | Measure-Object Length -Sum).Sum
        $stageDisk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f ([IO.Path]::GetPathRoot($env:ProgramFiles).TrimEnd('\')))
        if ($stageDisk.FreeSpace -lt ($payloadBytes + $sourceConfig.MinimumFreeGB * 1GB)) { throw 'Not enough free disk space to stage and install the package.' }
        $stage = Join-Path $installRoot ('Staging\' + [guid]::NewGuid().ToString('N'))
        Write-Host "[1/$totalStages] Copying the offline package to this computer. Please wait..."
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Get-ChildItem -LiteralPath $PSScriptRoot -Force | Copy-Item -Destination $stage -Recurse -Force
    }
    Import-Module (Join-Path $stage 'Lab.Core.psm1') -Force
    Import-Module (Join-Path $stage 'Reboot.Core.psm1') -Force
    $lock = Get-Content -LiteralPath (Join-Path $stage 'package-lock.json') -Raw | ConvertFrom-Json
    Write-Host "[2/$totalStages] Verifying package files..."
    Test-LabPackage -Root $stage -Lock $lock
    $bootUtc = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime()
    if ($resumeState) {
        if ($resumeState.PackageId -cne $lock.PackageId) { throw 'Resume PackageId does not match the staged payload.' }
        $decision = Get-LabResumeDecision $resumeState $bootUtc
        if ($decision -eq 'AwaitReboot') {
            $keepResume = $true
            Write-Host 'SchoolLab is waiting for an actual restart; signing out/in alone does not complete verification.' -ForegroundColor Yellow
            exit 3010
        }
        if ($decision -ne 'Resume') { throw "Automatic resume stopped: $decision. See $ResumeStatePath" }
        $context = Wait-LabClassroomContext -TimeoutSeconds 120
        Write-LabJson (Join-Path $bootstrapLog ('desktop-context-'+$resumeState.Id+'.json')) $context
        if (-not $context.Ready) { throw $context.Message }
        # The entire installation already passed BEFORE requesting the restart.
        # After sign-in only verify readiness; never replay Chrome UI/installers
        # or request another restart from this branch.
        Write-Host 'SchoolLab: checking readiness after the final restart.' -ForegroundColor Cyan
        $verificationLog = Join-Path $bootstrapLog ('after-restart-' + $resumeState.Id + '.log')
        $verifyUntil = [datetime]::UtcNow.AddSeconds(180)
        do {
            & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Check-LabReady.ps1') -PackageRoot $stage *> $verificationLog
            $verifyExit = $LASTEXITCODE
            if ($verifyExit -ne 2 -or [datetime]::UtcNow -ge $verifyUntil) { break }
            Start-Sleep -Seconds 5
        } while ($true)
        Get-Content -LiteralPath $verificationLog | Write-Host
        $resumeState | Add-Member NoteProperty VerificationExitCode $verifyExit -Force
        $resumeState | Add-Member NoteProperty VerificationLog $verificationLog -Force
        $deploymentCompleted = $verifyExit -eq 0
        if (-not $deploymentCompleted) { Write-Host "Check the logs: $verificationLog. No additional automatic restart will be requested." -ForegroundColor Yellow }
        exit $verifyExit
    }
    Write-Host "[3/$totalStages] Running preflight checks and silent installers. Logs: C:\ProgramData\SchoolLab\Logs"
    $resultPath = Join-Path $stage 'machine-result.json'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-AppDeployToolkit.ps1') -DeployMode Silent -ResultPath $resultPath
    $machineExit = $LASTEXITCODE
    $report = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($machineExit -notin @(0,3010)) { exit $machineExit }
    if ($report.PackageId -cne $lock.PackageId -or $report.ExitCode -ne $machineExit) { throw 'Machine report does not match this package or process exit code.' }
    # 3010 means restart required, not installation failed. Continue account
    # setup and SFIT first; a deferred/failed preflight must never reach them.
    if ($report.Status -ne 'MachinePassed_UserLogonRequired') {
        if ($machineExit -eq 3010 -and $report.Status -eq 'DeferredReboot') { exit 3010 }
        throw "Machine phase did not pass: $($report.Status). No automatic restart was requested."
    }
    Import-Module (Join-Path $stage 'Desktop.Setup.psm1') -Force
    Write-Host '[4/5] Configuring VS Code and SFIT in the actual desktop account...'
    $desktopResult=Invoke-LabDesktopSetup -PackageRoot $stage
    $report | Add-Member NoteProperty DesktopSetup $desktopResult -Force
    $report | Add-Member NoteProperty LauncherExitCode $desktopResult.ExitCode -Force
    $userRow=$report.Components|Where-Object Name -eq 'UserProvisioning'
    $chromeRow=$report.Components|Where-Object Name -eq 'ChromeExtension'
    $userRow.ExitCode=$desktopResult.UserExitCode
    $userRow.Status=if($desktopResult.UserExitCode -eq 0){'Passed'}else{'Failed'}
    $chromeRow.ExitCode=$desktopResult.ChromeExitCode
    $chromeRow.Status=if(-not $sourceConfig.EnableChromeExtension){'Disabled'}elseif($desktopResult.ChromeExitCode -eq 0){'Passed'}else{'Failed'}
    $report.Status=if($desktopResult.ExitCode -eq 0){'MachinePassed_UserReady'}else{'MachinePassed_ChromeSetupFailed'}
    Write-LabJson $resultPath $report
    Write-LabJson (Join-Path $report.LogDirectory 'result.json') $report
    $report.Components|Export-Csv -LiteralPath (Join-Path $report.LogDirectory 'components.csv') -NoTypeInformation -Encoding UTF8
    if($desktopResult.ExitCode -ne 0){Write-Host $desktopResult.Error -ForegroundColor Red;exit $desktopResult.ExitCode}
    Write-Host 'DESKTOP SETUP PASSED: VS Code and SFIT verified in the desktop account.' -ForegroundColor Green
    Write-Host "Machine log: $($report.LogDirectory)"
    # This is the ONLY automatic-restart site. All machine, account and Chrome
    # steps have completed; genuine failures above exit without restarting.
    $finalAction = Get-LabFinalRestartDecision $report $sourceConfig.AutomaticRestart ($desktopResult.ExitCode -eq 0)
    if ($finalAction -eq 'Restart') {
        $sid = $desktopResult.UserSid
        $resumeState = New-LabResumeState $stage $lock.PackageId $sid $env:COMPUTERNAME $bootUtc
        $ResumeStatePath = Join-Path $installRoot ('Resume\'+$resumeState.Id+'.json')
        Assert-LabResumeState $resumeState $ResumeStatePath $installRoot $sid $env:COMPUTERNAME
        $resumeValidated = $true
        Remove-LabOlderResumeTasks $installRoot $sid $env:COMPUTERNAME $resumeState.Id
        $keepResume = $true
        $requested = Invoke-LabAutomaticRestart $resumeState $ResumeStatePath 'All installation and account steps passed; final restart required.' $bootUtc $sourceConfig.RestartCountdownSeconds
        if (-not $requested) { $keepResume = $false; throw 'Automatic restart already requested; no restart loop will be started.' }
    } elseif ($finalAction -eq 'ManualRestart') {
        Write-Host 'Restart required. After signing in, run Check-LabReady.cmd. Automatic restart is disabled or no classroom desktop is available.' -ForegroundColor Yellow
    } elseif ($finalAction -eq 'Stop') {
        throw 'Final installation report is incomplete or failed. No automatic restart was requested.'
    }
    $deploymentCompleted = $true
    exit $machineExit
} catch {
    if ($bootstrapLog) {
        @{ Computer = $env:COMPUTERNAME; At = (Get-Date -Format o); Status = 'Failed'; Error = "$_"; ExitCode = 69001 } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bootstrapLog ('failure-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Encoding UTF8
    }
    Write-Error -Message $_ -ErrorAction Continue
    exit 69001
} finally {
    # A failed task registration must not leave an armed recovery entry. A
    # canceled countdown or rejected OS restart retains verification for a
    # later manual restart, with its bounded journal already written.
    if ($resumeState -and $resumeState.Status -notin @('WaitingForReboot','RestartFailed')) { $keepResume = $false }
    if ($resumeValidated -and $resumeState -and -not $keepResume) {
        try {
            if ($resumeState.Status -ne 'RestartLimitReached') { $resumeState.Status = if ($deploymentCompleted) {'Completed'} else {'Failed'} }
            Write-LabResumeState $ResumeStatePath $resumeState
            Remove-LabResumeTask $resumeState $ResumeStatePath
        } catch { Write-Warning "Resume task cleanup: $_" }
    }
    if ($launcherHeld) { $launcherMutex.ReleaseMutex() }
    if ($launcherMutex) { $launcherMutex.Dispose() }
}
