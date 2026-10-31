#requires -Version 5.1
$ErrorActionPreference='Stop'
function Get-LabDesktopTarget($s){
    if(-not $s -or $s.SessionId -le 0 -or $s.InputDesktop -ine 'Default' -or $s.SessionState -ne 0 -or
        $s.ShellSessionId -ne $s.SessionId -or $s.ShellSid -notmatch '^S-1-5-21-(\d+-){3}\d+$' -or
        ($s.SessionSid -and $s.SessionSid -ne $s.ShellSid)){throw 'Cannot identify the active desktop SID/session reliably.'}
    [pscustomobject]@{Sid=$s.ShellSid;Session=$s.SessionId}
}
function Test-LabDesktopResult($Result,[string]$Nonce,[string]$PackageId,$Target){
    $Result.Nonce -ceq $Nonce -and $Result.PackageId -ceq $PackageId -and $Result.UserSid -ceq $Target.Sid -and $Result.SessionId -eq $Target.Session
}
function Invoke-LabDesktopSetup {
    param([string]$PackageRoot,[switch]$ChromeOnly)
    Import-Module (Join-Path $PackageRoot 'Lab.Core.psm1') -Force
    $c=Get-LabClassroomContext;$s=$c.Snapshot
    $target=Get-LabDesktopTarget $s
    $root=Join-Path $env:ProgramFiles 'SchoolLab\Staging'
    if([IO.Path]::GetDirectoryName($PackageRoot) -ine $root){
        $stage=Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force|Out-Null
        Get-ChildItem -LiteralPath $PackageRoot -Force|Copy-Item -Destination $stage -Recurse -Force
        $PackageRoot=$stage
    }
    $lock=Get-Content -LiteralPath (Join-Path $PackageRoot 'package-lock.json') -Raw|ConvertFrom-Json
    Test-LabPackage $PackageRoot $lock
    $id=[guid]::NewGuid().ToString('N');$nonce=[guid]::NewGuid().ToString('N')
    $folder=Join-Path $env:ProgramData ('SchoolLab\DesktopSetup\'+$id)
    $parent=Split-Path -Parent $folder
    New-Item -ItemType Directory -Path $parent -Force|Out-Null
    $path=$parent
    while($path){if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked desktop result path refused'};$path=Split-Path -Parent $path}
    New-Item -ItemType Directory -Path $folder -ErrorAction Stop|Out-Null
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]$sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]$s.ShellSid,'Modify','ContainerInherit,ObjectInherit','None','Allow'))
    Set-Acl -LiteralPath $folder -AclObject $acl
    $resultPath=Join-Path $folder 'result.json';$taskName='SchoolLab-Desktop-'+$id
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedSid "{1}" -ExpectedSession {2} -ResultPath "{3}" -Nonce "{4}"' -f (Join-Path $PackageRoot 'Invoke-DesktopSetup.ps1'),$s.ShellSid,$s.SessionId,$resultPath,$nonce
    if($ChromeOnly){$arguments+=' -ChromeOnly'}
    $registered=$false
    try{
        Import-Module ScheduledTasks
        $action=New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $PackageRoot
        $principal=New-ScheduledTaskPrincipal -UserId $s.ShellSid -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([timespan]::FromMinutes(20))
        Register-ScheduledTask -TaskPath '\' -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Description ('SchoolLab desktop setup '+$id)|Out-Null
        $registered=$true
        $scheduler=New-Object -ComObject Schedule.Service;$scheduler.Connect()
        $nativeTask=$scheduler.GetFolder('\').GetTask($taskName)
        $running=$nativeTask.RunEx($null,4,$s.SessionId,$null)
        $deadline=[datetime]::UtcNow.AddMinutes(18)
        while(-not (Test-Path -LiteralPath $resultPath)){
            if([datetime]::UtcNow -ge $deadline){throw 'Desktop setup timed out; see the desktop account SchoolLab logs.'}
            Start-Sleep -Seconds 2
            if(Test-Path -LiteralPath $resultPath){break}
            $running.Refresh()
            if($running.State -eq 0 -and -not (Test-Path -LiteralPath $resultPath)){throw 'Desktop task ended without a verified result.'}
        }
        $result=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not (Test-LabDesktopResult $result $nonce $lock.PackageId $target)){throw 'Desktop setup result identity mismatch.'}
        $result
    }finally{
        if($registered){
            $task=Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue
            if($task -and $task.Description -ceq ('SchoolLab desktop setup '+$id) -and $task.Actions[0].Arguments -ceq $arguments -and $task.Actions[0].Execute -ieq $exe){
                if($task.State -eq 'Running'){Stop-ScheduledTask -InputObject $task}
                Unregister-ScheduledTask -InputObject $task -Confirm:$false
            }
        }
    }
}
Export-ModuleMember -Function Invoke-LabDesktopSetup,Get-LabDesktopTarget,Test-LabDesktopResult
