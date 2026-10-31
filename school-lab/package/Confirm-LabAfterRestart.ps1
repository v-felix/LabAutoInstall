#requires -Version 5.1
param([string]$ResumeStatePath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Reboot.Core.psm1') -Force
try{
    $s=Get-Content -LiteralPath $ResumeStatePath -Raw|ConvertFrom-Json
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Assert-LabResumeState $s $ResumeStatePath (Join-Path $env:ProgramFiles 'SchoolLab') $sid $env:COMPUTERNAME
    if($s.StageRoot -ine $PSScriptRoot){throw 'Unexpected stage'}
    $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package-lock.json') -Raw|ConvertFrom-Json
    Test-LabPackage $PSScriptRoot $lock
    if($lock.PackageId -cne $s.PackageId){throw 'Package mismatch'}
    if((Get-LabResumeDecision $s (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime()) -ne 'Resume'){exit 3010}
    if(-not (Wait-LabClassroomContext -TimeoutSeconds 120).Ready){throw 'Desktop not ready'}
    $folder=Join-Path $env:LOCALAPPDATA 'SchoolLab\Reboot'
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $resultPath=Join-Path $folder ($s.Id+'.json')
    if(-not (Test-Path -LiteralPath $resultPath)){
        $until=[datetime]::UtcNow.AddSeconds(180)
        do {
            & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Check-LabReady.ps1') -PackageRoot $PSScriptRoot *> (Join-Path $folder ($s.Id+'.log'))
            $code=$LASTEXITCODE
            if($code -ne 2 -or [datetime]::UtcNow -ge $until){break}
            Start-Sleep -Seconds 5
        }while($true)
        Write-LabJson $resultPath @{PackageId=$s.PackageId;UserSid=$sid;ExitCode=$code;At=(Get-Date -Format o)}
    }
    Remove-LabResumeTask $s $ResumeStatePath
}catch{Write-Error $_;exit 1}
