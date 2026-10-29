#requires -Version 5.1
[CmdletBinding()]
param([switch]$NoElevation)
$ErrorActionPreference = 'Stop'
$launcherMutex = $null
$launcherHeld = $false
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
        $options = @{ FilePath = $powershell; ArgumentList = $arguments; Wait = $true; PassThru = $true }
        if (-not $admin) { $options.Verb = 'RunAs' }
        $process = Start-Process @options
        exit $process.ExitCode
    }
    $launcherMutex = New-Object Threading.Mutex($false, 'Global\SchoolLab-Launcher')
    try { $launcherHeld = $launcherMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $launcherHeld = $true }
    if (-not $launcherHeld) { Write-Host 'Another SchoolLab installation is still running.'; exit 69002 }
    # Stage locally before running any installer, so USB removal / LAN loss cannot
    # interrupt a later component. Each attempt has its own staging directory.
    $bootstrapLog = Join-Path $env:ProgramData ('SchoolLab\Logs\' + $env:COMPUTERNAME + '\Bootstrap')
    New-Item -ItemType Directory -Path $bootstrapLog -Force | Out-Null
    $sourceConfig = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'LabConfig.psd1')
    $totalStages = if ($sourceConfig.EnableChromeExtension) { 5 } else { 4 }
    if ($sourceConfig.EnableChromeExtension) {
        # A teacher may edit ONLY Files\ChromeExtension\config.js on the USB.
        # Verify all other hashes, validate its data, then update the schedule lock.
        & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Update-SfitSchedule.ps1') -PackageRoot $PSScriptRoot
        if ($LASTEXITCODE -ne 0) { throw 'SFIT schedule preparation failed. No installer was started.' }
    }
    $payloadBytes = (Get-ChildItem -LiteralPath $PSScriptRoot -File -Recurse | Measure-Object Length -Sum).Sum
    $stageDisk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f ([IO.Path]::GetPathRoot($env:ProgramFiles).TrimEnd('\')))
    if ($stageDisk.FreeSpace -lt ($payloadBytes + $sourceConfig.MinimumFreeGB * 1GB)) { throw 'Not enough free disk space to stage and install the package.' }
    $stage = Join-Path $env:ProgramFiles ('SchoolLab\Staging\' + [guid]::NewGuid().ToString('N'))
    Write-Host "[1/$totalStages] Copying the offline package to this computer. Please wait..."
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Get-ChildItem -LiteralPath $PSScriptRoot -Force | Copy-Item -Destination $stage -Recurse -Force
    # Verify before importing toolkit code from the staged copy.
    Import-Module (Join-Path $stage 'Lab.Core.psm1') -Force
    $lock = Get-Content -LiteralPath (Join-Path $stage 'package-lock.json') -Raw | ConvertFrom-Json
    Write-Host "[2/$totalStages] Verifying package files..."
    Test-LabPackage -Root $stage -Lock $lock
    Write-Host "[3/$totalStages] Running preflight checks and silent installers. Logs: C:\ProgramData\SchoolLab\Logs"
    $resultPath = Join-Path $stage 'machine-result.json'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-AppDeployToolkit.ps1') -DeployMode Silent -ResultPath $resultPath
    $machineExit = $LASTEXITCODE
    if ($machineExit -notin @(0,3010)) { exit $machineExit }
    $report = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($report.Status -ne 'MachinePassed_UserLogonRequired') { exit $machineExit }
    if (Test-LabClassroomContext) {
        Write-Host "[4/$totalStages] Configuring offline C++, Java and Python extensions for this classroom account..."
        $support = Expand-LabPath $sourceConfig.SupportDirectory
        & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $support 'Initialize-LabUser.ps1')
        $userExit = $LASTEXITCODE
        $row = $report.Components | Where-Object Name -eq 'UserProvisioning'
        if ($userExit -eq 0) {
            $userResult = Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'SchoolLab\result.json') -Raw | ConvertFrom-Json
            if ($userResult.Status -ne 'Passed' -or $userResult.PackageId -ne $lock.PackageId) { throw 'Classroom account verification did not complete.' }
            $row.Status = 'Passed'
            $row.Details = 'C++, Java and Python extensions, workspaces and account smoke tests passed.'
            $report.Status = 'MachinePassed_UserReady'
            if ($sourceConfig.EnableChromeExtension) {
                Write-Host '[5/5] Installing and verifying SFIT Tracker in the selected Chrome profile...'
                & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Install-ChromeExtension.ps1') -PackageRoot $stage
                $chromeExit = $LASTEXITCODE
                $chromeRow = $report.Components | Where-Object Name -eq 'ChromeExtension'
                $chromeRow.ExitCode = $chromeExit
                $chromeRow.Status = if ($chromeExit -eq 0) { 'Passed' } else { 'Failed' }
                $chromeRow.Details = 'See %LOCALAPPDATA%\SchoolLab\Chrome\result.json. Selected profile only.'
                if ($chromeExit -ne 0) {
                    $report.Status = 'MachinePassed_ChromeSetupFailed'; $report.ExitCode = 69030
                    $report.Error = $chromeRow.Details
                    Write-LabJson (Join-Path $report.LogDirectory 'result.json') $report
                    $report.Components | Export-Csv -LiteralPath (Join-Path $report.LogDirectory 'components.csv') -NoTypeInformation -Encoding UTF8
                    exit 69030
                }
            }
            Write-Host 'SAN SANG: This classroom account passed setup. Open samples and verify the exam schedule before handover.' -ForegroundColor Green
        } else {
            $row.Status = 'Failed'; $row.ExitCode = $userExit
            $row.Details = 'See %LOCALAPPDATA%\SchoolLab\initialize.log and result.json.'
            $report.Status = 'MachinePassed_UserSetupFailed'
            $report.Error = $row.Details
            $report.ExitCode = 69020
        }
        Write-LabJson (Join-Path $report.LogDirectory 'result.json') $report
        Write-LabJson $resultPath $report
        $report.Components | Export-Csv -LiteralPath (Join-Path $report.LogDirectory 'components.csv') -NoTypeInformation -Encoding UTF8
        if ($userExit -ne 0) { exit 69020 }
    } else {
        Write-Host 'APPLICATIONS INSTALLED. Classroom account setup is pending.' -ForegroundColor Yellow
        Write-Host 'Sign into the account used in class, wait for automatic initialization, then run Check-LabReady.cmd.'
    }
    Write-Host "Machine log: $($report.LogDirectory)"
    if ($machineExit -eq 3010) { Write-Host 'RESTART REQUIRED before using this computer.' -ForegroundColor Yellow }
    exit $machineExit
} catch {
    if ($bootstrapLog) {
        @{ Computer = $env:COMPUTERNAME; At = (Get-Date -Format o); Status = 'Failed'; Error = "$_"; ExitCode = 69001 } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bootstrapLog ('failure-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Encoding UTF8
    }
    Write-Error -Message $_ -ErrorAction Continue
    exit 69001
} finally {
    if ($launcherHeld) { $launcherMutex.ReleaseMutex() }
    if ($launcherMutex) { $launcherMutex.Dispose() }
}
