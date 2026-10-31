#requires -Version 5.1
param([string]$ExpectedSid,[int]$ExpectedSession,[string]$ResultPath,[string]$Nonce,[switch]$ChromeOnly)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.Core.psm1') -Force
$lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package-lock.json') -Raw|ConvertFrom-Json
$result=[ordered]@{PackageId=$lock.PackageId;Nonce=$Nonce;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;SessionId=(Get-Process -Id $PID).SessionId;ExitCode=69031;UserExitCode=$null;ChromeExitCode=$null;Error=''}
try{
    Test-LabPackage $PSScriptRoot $lock
    $c=Wait-LabClassroomContext
    if(-not $c.Ready -or $result.UserSid -cne $ExpectedSid -or $result.SessionId -ne $ExpectedSession){throw 'Desktop actor identity/session verification failed.'}
    $config=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'LabConfig.psd1')
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if(-not $ChromeOnly){
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Expand-LabPath $config.SupportDirectory) 'Initialize-LabUser.ps1')
        $result.UserExitCode=$LASTEXITCODE
        if($LASTEXITCODE -ne 0){$result.ExitCode=69020;throw 'Desktop VS Code account setup failed.'}
        $user=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'SchoolLab\result.json') -Raw|ConvertFrom-Json
        if($user.Status -ne 'Passed' -or $user.PackageId -cne $lock.PackageId){$result.ExitCode=69020;throw 'Desktop account verification does not match this package.'}
    }
    if($config.EnableChromeExtension){
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-ChromeExtension.ps1') -PackageRoot $PSScriptRoot -CurrentDesktopUser
        $result.ChromeExitCode=$LASTEXITCODE
        if($LASTEXITCODE -ne 0){$result.ExitCode=69030;throw 'SFIT setup failed in the desktop account; see its SchoolLab\Chrome logs.'}
    }
    $result.ExitCode=0
}catch{$result.Error="$_"}finally{
    Write-LabJson $ResultPath $result
}
exit $result.ExitCode
