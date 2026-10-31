#requires -Version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Write-LabResumeState([string]$Path,$State) {
    $State.UpdatedAt=[datetime]::UtcNow.ToString('o')
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,($State|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}
    else{[IO.File]::Move($temporary,$Path)}
}

function Assert-LabResumePath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while($current){
        if((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Refuse linked resume path: $current"}
        $current=Split-Path -Parent $current
    }
}

function New-LabResumeState {
    param([string]$StageRoot,[string]$PackageId,[string]$UserSid,[string]$ComputerName,[datetime]$BootUtc)
    $id=[guid]::NewGuid().ToString('N')
    [pscustomobject]@{Schema=1;Id=$id;TaskName=('SchoolLab-Resume-'+$id);StageRoot=[IO.Path]::GetFullPath($StageRoot).TrimEnd('\');
        PackageId=$PackageId;UserSid=$UserSid;ComputerName=$ComputerName;BootUtc=$BootUtc.ToUniversalTime().ToString('o');
        RestartCount=0;MaximumRestarts=1;Phase='VerifyOnly';Status='Running';Reason='';UpdatedAt=[datetime]::UtcNow.ToString('o')}
}

function Assert-LabResumeState {
    param($State,[string]$StatePath,[string]$InstallRoot,[string]$UserSid,[string]$ComputerName)
    $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $stage=[IO.Path]::GetFullPath($State.StageRoot).TrimEnd('\')
    $path=[IO.Path]::GetFullPath($StatePath)
    if($State.Schema -ne 1 -or $State.Id -notmatch '^[0-9a-f]{32}$' -or $State.TaskName -cne ('SchoolLab-Resume-'+$State.Id) -or
        $State.UserSid -cne $UserSid -or $State.ComputerName -ine $ComputerName -or
        [IO.Path]::GetDirectoryName($stage) -ine (Join-Path $root 'Staging') -or (Split-Path -Leaf $stage) -notmatch '^[0-9a-f]{32}$' -or
        $path -ine (Join-Path $root ('Resume\'+$State.Id+'.json')) -or
        $State.MaximumRestarts -ne 1 -or $State.RestartCount -lt 0 -or $State.RestartCount -gt 1 -or $State.Phase -cne 'VerifyOnly' -or
        $State.Status -notin @('Running','WaitingForReboot','RestartLimitReached','RestartFailed','Completed','Failed','Superseded')){
        throw 'Resume state does not match this protected staging directory, computer or Windows account.'
    }
    $null=[datetimeoffset]::Parse($State.BootUtc)
    Assert-LabResumePath $stage;Assert-LabResumePath $path
}

function Get-LabResumeDecision {
    param($State,[datetime]$BootUtc)
    if($State.Status -notin @('WaitingForReboot','RestartFailed') -or $State.Phase -cne 'VerifyOnly' -or $State.RestartCount -ne 1){return 'Stop'}
    if($BootUtc.ToUniversalTime() -le ([datetimeoffset]::Parse($State.BootUtc)).UtcDateTime){return 'AwaitReboot'}
    'Resume'
}

function Get-LabFinalRestartDecision {
    param($Report,[bool]$AutomaticRestart,[bool]$InteractiveDesktop)
    if($Report.ExitCode -notin @(0,3010) -or $Report.Status -notin @('MachinePassed_UserLogonRequired','MachinePassed_UserReady')){return 'Stop'}
    foreach($name in @('Preflight','DevCpp','Jdk','Python','VSCode','Environment','SmokeTests')){
        $row=@($Report.Components | Where-Object Name -eq $name)
        if($row.Count -ne 1 -or $row[0].Status -notin @('Passed','Installed','Skipped')){return 'Stop'}
    }
    if($Report.Status -eq 'MachinePassed_UserLogonRequired'){
        if($Report.RebootRequired -or $Report.ExitCode -eq 3010){return 'ManualRestart'}
        return 'PendingAccount'
    }
    foreach($name in @('UserProvisioning','ChromeExtension')){
        $row=@($Report.Components | Where-Object Name -eq $name)
        $allowed=if($name -eq 'ChromeExtension'){@('Passed','Disabled')}else{@('Passed')}
        if($row.Count -ne 1 -or $row[0].Status -notin $allowed){return 'Stop'}
    }
    if(-not $Report.RebootRequired -and $Report.ExitCode -ne 3010){return 'Ready'}
    if($AutomaticRestart -and $InteractiveDesktop){return 'Restart'}
    'ManualRestart'
}

function Get-LabResumeTaskSpec {
    param($State,[string]$StatePath)
    [pscustomobject]@{Name=$State.TaskName;UserSid=$State.UserSid;Execute=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe');
        Arguments=('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -NoElevation -ResumeStatePath "{1}"' -f (Join-Path $State.StageRoot 'Start-Lab.ps1'),$StatePath);
        WorkingDirectory=$State.StageRoot;Description=('SchoolLab automatic resume '+$State.Id);LogonType='Interactive';RunLevel='Highest';Delay='PT30S'}
}

function Test-LabResumeTaskIdentity {
    param($Task,$Spec)
    if(-not $Task -or @($Task.Actions).Count -ne 1){return $false}
    $account=[string]$Task.Principal.UserId
    try{if($account -notmatch '^S-1-'){ $account=([Security.Principal.NTAccount]$account).Translate([Security.Principal.SecurityIdentifier]).Value }}catch{return $false}
    $Task.TaskPath -eq '\' -and $Task.TaskName -ceq $Spec.Name -and $Task.Description -ceq $Spec.Description -and $account -ceq $Spec.UserSid -and
        [string]$Task.Principal.LogonType -eq 'Interactive' -and [string]$Task.Principal.RunLevel -eq 'Highest' -and
        $Task.Actions[0].Execute -ieq $Spec.Execute -and $Task.Actions[0].Arguments -ceq $Spec.Arguments -and $Task.Actions[0].WorkingDirectory -ieq $Spec.WorkingDirectory
}

function Register-LabResumeTask {
    param($State,[string]$StatePath)
    Import-Module ScheduledTasks -ErrorAction Stop
    $spec=Get-LabResumeTaskSpec $State $StatePath
    $existing=Get-ScheduledTask -TaskPath '\' -TaskName $spec.Name -ErrorAction SilentlyContinue
    if($existing -and -not (Test-LabResumeTaskIdentity $existing $spec)){throw 'Refuse to replace an unrelated scheduled task.'}
    $action=New-ScheduledTaskAction -Execute $spec.Execute -Argument $spec.Arguments -WorkingDirectory $spec.WorkingDirectory
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $spec.UserSid;$trigger.Delay=$spec.Delay
    $principal=New-ScheduledTaskPrincipal -UserId $spec.UserSid -LogonType Interactive -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::FromHours(2))
    $task=Register-ScheduledTask -TaskPath '\' -TaskName $spec.Name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $spec.Description -Force
    if(-not (Test-LabResumeTaskIdentity $task $spec)){throw 'Scheduled resume task verification failed; no automatic restart will be requested.'}
}

function Remove-LabResumeTask {
    param($State,[string]$StatePath)
    Import-Module ScheduledTasks -ErrorAction Stop
    $spec=Get-LabResumeTaskSpec $State $StatePath
    $existing=Get-ScheduledTask -TaskPath '\' -TaskName $spec.Name -ErrorAction SilentlyContinue
    if(-not $existing){return}
    if(-not (Test-LabResumeTaskIdentity $existing $spec)){throw 'Refuse to remove an unrelated scheduled task.'}
    Unregister-ScheduledTask -TaskPath '\' -TaskName $spec.Name -Confirm:$false
}

function Remove-LabOlderResumeTasks {
    param([string]$InstallRoot,[string]$UserSid,[string]$ComputerName,[string]$ExceptId)
    $folder=Join-Path $InstallRoot 'Resume'
    if(-not (Test-Path -LiteralPath $folder)){return}
    foreach($file in Get-ChildItem -LiteralPath $folder -Filter '*.json' -File){
        $old=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
        if($old.UserSid -ne $UserSid -or $old.Id -eq $ExceptId){continue}
        Assert-LabResumeState $old $file.FullName $InstallRoot $UserSid $ComputerName
        Remove-LabResumeTask $old $file.FullName
        if($old.Status -in @('Running','WaitingForReboot','RestartFailed')){$old.Status='Superseded';Write-LabResumeState $file.FullName $old}
    }
}

function Invoke-LabAutomaticRestart {
    param($State,[string]$StatePath,[string]$Reason,[datetime]$BootUtc,[int]$CountdownSeconds=60,
        [scriptblock]$EnsureTaskAction={param($s,$p) Register-LabResumeTask $s $p},
        [scriptblock]$WaitAction={param($seconds) Start-Sleep -Seconds $seconds},
        [scriptblock]$RestartAction={
            # /t > 0 implicitly forces applications closed on Windows. Keep
            # the countdown in PowerShell; /t 0 without /f respects open apps.
            & "$env:SystemRoot\System32\shutdown.exe" /r /t 0 /d p:4:2 /c 'SchoolLab setup completed: final restart and verification after sign-in.'
            if($LASTEXITCODE -ne 0){throw "Windows rejected the restart request: $LASTEXITCODE"}
        })
    if($CountdownSeconds -lt 0 -or $CountdownSeconds -gt 600){throw 'Restart countdown must be between 0 and 600 seconds.'}
    if($State.RestartCount -ge $State.MaximumRestarts){
        $State.Status='RestartLimitReached';$State.Reason=$Reason;Write-LabResumeState $StatePath $State
        return $false
    }
    # Verify a working, account-bound task BEFORE changing state or restarting.
    $null=& $EnsureTaskAction $State $StatePath
    $State.RestartCount++;$State.BootUtc=$BootUtc.ToUniversalTime().ToString('o');$State.Status='WaitingForReboot';$State.Reason=$Reason
    $State.UpdatedAt=[datetime]::UtcNow.ToString('o');Write-LabResumeState $StatePath $State
    Write-Host "SchoolLab: restart in $CountdownSeconds seconds. Save your work. Ctrl+C cancels this countdown." -ForegroundColor Yellow
    Write-Host 'After restart, sign in to this SAME Windows account. Readiness is checked from the local disk; no USB is required.'
    $remaining=$CountdownSeconds
    while($remaining -gt 0){$seconds=[math]::Min(5,$remaining);& $WaitAction $seconds;$remaining-=$seconds;Write-Host "Restart in $remaining seconds..."}
    try{& $RestartAction}catch{$State.Status='RestartFailed';$State.Reason="$_";Write-LabResumeState $StatePath $State;throw}
    $true
}

Export-ModuleMember -Function Write-LabResumeState,New-LabResumeState,Assert-LabResumeState,Get-LabResumeDecision,Get-LabFinalRestartDecision,Get-LabResumeTaskSpec,Test-LabResumeTaskIdentity,Register-LabResumeTask,Remove-LabResumeTask,Remove-LabOlderResumeTasks,Invoke-LabAutomaticRestart
