#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'package\Reboot.Core.psm1') -Force
$scratch=Join-Path $root ('test-results\reboot-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force|Out-Null
$script:passed=0
function Assert-Equal($Actual,$Expected,[string]$Message){
    if($Actual -cne $Expected){throw "$Message expected=[$Expected] actual=[$Actual]"}
    $script:passed++
}
function Assert-Throws([scriptblock]$Action,[string]$Pattern){
    try{& $Action}catch{if("$_" -notmatch $Pattern){throw "Unexpected error: $_"};$script:passed++;return}
    throw "Expected an error matching $Pattern"
}
function New-Report {
    [pscustomobject]@{Status='MachinePassed_UserReady';ExitCode=3010;RebootRequired=$true;Components=@(
        foreach($name in @('Preflight','DevCpp','Jdk','Python','VSCode','Environment','SmokeTests','UserProvisioning','ChromeExtension')){
            [pscustomobject]@{Name=$name;Status='Passed'}
        })}
}
$report=New-Report
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'Restart' 'Restart only after all steps passed'
Assert-Equal (Get-LabFinalRestartDecision $report $false $true) 'ManualRestart' 'Automatic restart opt-out'
Assert-Equal (Get-LabFinalRestartDecision $report $true $false) 'ManualRestart' 'No unattended interactive desktop'
$report.RebootRequired=$false;$report.ExitCode=0
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'Ready' 'No unnecessary restart'
$report.ExitCode=3010
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'Restart' '3010 retained even without flag'
$report.ExitCode=0;$report.RebootRequired=$true
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'Restart' 'Pending flag retained even with exit 0'
foreach($name in @('Preflight','DevCpp','Jdk','Python','VSCode','Environment','SmokeTests','UserProvisioning','ChromeExtension')){
    $bad=New-Report;($bad.Components|Where-Object Name -eq $name).Status='Failed'
    Assert-Equal (Get-LabFinalRestartDecision $bad $true $true) 'Stop' "No restart with $name failure"
    $bad.Components=@($bad.Components|Where-Object Name -ne $name)
    Assert-Equal (Get-LabFinalRestartDecision $bad $true $true) 'Stop' "No restart with missing $name result"
}
foreach($status in @('DeferredReboot','Failed','MachinePassed_UserSetupFailed','MachinePassed_ChromeSetupFailed','Running')){
    $bad=New-Report;$bad.Status=$status
    Assert-Equal (Get-LabFinalRestartDecision $bad $true $true) 'Stop' "No restart on $status"
}
foreach($code in @(1618,1641,69001,69020,69030)){
    $bad=New-Report;$bad.ExitCode=$code
    Assert-Equal (Get-LabFinalRestartDecision $bad $true $true) 'Stop' "No restart on real failure $code"
}
$report=New-Report;$report.Status='MachinePassed_UserLogonRequired'
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'ManualRestart' 'Pending account never triggers automatic restart'
$report.ExitCode=0;$report.RebootRequired=$false
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'PendingAccount' 'Pending account without restart'
$report=New-Report;($report.Components|Where-Object Name -eq ChromeExtension).Status='Disabled'
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'Restart' 'Optional Chrome disabled'
$report=New-Report;$report.Components+=$report.Components[0]
Assert-Equal (Get-LabFinalRestartDecision $report $true $true) 'Stop' 'Duplicate result not accepted'

$install=Join-Path $scratch 'SchoolLab'
$stage=Join-Path $install ('Staging\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$boot=[datetime]::UtcNow.AddHours(-1)
$state=New-LabResumeState $stage 'test-package' $sid $env:COMPUTERNAME $boot
$path=Join-Path $install ('Resume\'+$state.Id+'.json')
Assert-LabResumeState $state $path $install $sid $env:COMPUTERNAME
$script:passed++
Assert-Equal $state.MaximumRestarts 1 'One final restart maximum'
Assert-Equal $state.Phase 'VerifyOnly' 'Resume never reinstalls applications or Chrome'
Assert-Equal (Get-LabResumeDecision $state $boot.AddHours(1)) 'Stop' 'Unarmed journal cannot resume'
Assert-Throws {Assert-LabResumeState $state $path $install 'S-1-5-18' $env:COMPUTERNAME} 'does not match'
Assert-Throws {Assert-LabResumeState $state $path $install $sid 'OTHER-PC'} 'does not match'
Assert-Throws {Assert-LabResumeState $state (Join-Path $scratch 'foreign.json') $install $sid $env:COMPUTERNAME} 'does not match'
$original=$state.StageRoot;$state.StageRoot=$scratch
Assert-Throws {Assert-LabResumeState $state $path $install $sid $env:COMPUTERNAME} 'does not match'
$state.StageRoot=$original
$state.Phase='Install'
Assert-Throws {Assert-LabResumeState $state $path $install $sid $env:COMPUTERNAME} 'does not match'
$state.Phase='VerifyOnly'
Write-LabResumeState $path $state
Write-LabResumeState $path $state
Assert-Equal (Get-Content -LiteralPath $path -Raw|ConvertFrom-Json).PackageId 'test-package' 'Atomic journal replacement works on 5.1'

$spec=Get-LabResumeTaskSpec $state $path
Assert-Equal $spec.Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') 'Pinned Windows PowerShell 5.1'
Assert-Equal $spec.UserSid $sid 'Same Windows account only'
Assert-Equal $spec.LogonType 'Interactive' 'No stored password or automatic sign-in'
Assert-Equal $spec.RunLevel 'Limited' 'Resume without new UAC prompt'
Assert-Equal $spec.Delay 'PT30S' 'Wait for desktop after login'
Assert-Equal ($spec.Arguments.Contains($stage)) $true 'Resume from protected local stage'
Assert-Equal ($spec.Arguments.Contains($path)) $true 'Resume bound to exact journal'
$task=[pscustomobject]@{TaskName=$spec.Name;TaskPath='\';Description=$spec.Description;
    Principal=[pscustomobject]@{UserId=$sid;LogonType='Interactive';RunLevel='Limited'};
    Actions=@([pscustomobject]@{Execute=$spec.Execute;Arguments=$spec.Arguments;WorkingDirectory=$spec.WorkingDirectory})}
Assert-Equal (Test-LabResumeTaskIdentity $task $spec) $true 'Exact owned task recognized'
$task.Actions[0].Arguments+=' -AnythingElse'
Assert-Equal (Test-LabResumeTaskIdentity $task $spec) $false 'Do not touch task with foreign command'
$task.Actions[0].Arguments=$spec.Arguments;$task.Principal.UserId='S-1-5-18'
Assert-Equal (Test-LabResumeTaskIdentity $task $spec) $false 'Do not touch task for another principal'
$task.Principal.UserId=$sid;$task.TaskPath='\Foreign\'
Assert-Equal (Test-LabResumeTaskIdentity $task $spec) $false 'Do not touch same task name in another folder'

# Exercise the real inbox CIM constructors in memory, without registering a
# task. This catches incorrect parameter names, enums and principal conversion.
Import-Module ScheduledTasks -ErrorAction Stop
$action=New-ScheduledTaskAction -Execute $spec.Execute -Argument $spec.Arguments -WorkingDirectory $spec.WorkingDirectory
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $spec.UserSid
$trigger.Delay=$spec.Delay
$principal=New-ScheduledTaskPrincipal -UserId $spec.UserSid -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::FromHours(2))
$memoryTask=[pscustomobject]@{TaskName=$spec.Name;TaskPath='\';Description=$spec.Description;Principal=$principal;Actions=@($action)}
Assert-Equal (Test-LabResumeTaskIdentity $memoryTask $spec) $true 'Real CIM principal/action match expected identity'
Assert-Equal $trigger.Delay 'PT30S' 'Real logon trigger accepts delay'
Assert-Equal $trigger.UserId $sid 'Real logon trigger uses same SID'
Assert-Equal $settings.ExecutionTimeLimit 'PT2H' 'Verification task has finite execution time'
Assert-Equal $settings.StartWhenAvailable $true 'Verification can start after login delay'
Assert-Equal $settings.DisallowStartIfOnBatteries $false 'Do not skip verification on battery'
Assert-Equal $settings.StopIfGoingOnBatteries $false 'Do not interrupt verification on battery'

# All OS effects are injected. This test NEVER registers a real task, restarts
# the developer computer, or waits for a countdown.
$events=New-Object 'Collections.Generic.List[string]'
$ensure={param($s,$p) $events.Add('TaskVerified')}.GetNewClosure()
$wait={param($seconds)
    $saved=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($saved.Status -ne 'WaitingForReboot' -or $saved.RestartCount -ne 1){throw 'Journal must be durable before countdown'}
    $events.Add('Wait'+$seconds)
}.GetNewClosure()
$restart={$events.Add('RestartRequested')}.GetNewClosure()
Assert-Equal (Invoke-LabAutomaticRestart $state $path 'final' $boot 12 $ensure $wait $restart) $true 'Final restart requested'
Assert-Equal ($events -join ',') 'TaskVerified,Wait5,Wait5,Wait2,RestartRequested' 'Task, journal, countdown, restart order'
Assert-Equal (Get-LabResumeDecision $state $boot) 'AwaitReboot' 'Logoff/login without boot does not pass'
Assert-Equal (Get-LabResumeDecision $state $boot.AddMinutes(1)) 'Resume' 'Actual boot runs verification'
$count=$events.Count
Assert-Equal (Invoke-LabAutomaticRestart $state $path 'repeat' $boot 0 $ensure $wait $restart) $false 'No second automatic restart'
Assert-Equal $events.Count $count 'No OS action after limit reached'
Assert-Equal $state.Status 'RestartLimitReached' 'Limit recorded'
Assert-Equal (Get-LabResumeDecision $state $boot.AddHours(1)) 'Stop' 'Terminal journal never loops'

$state=New-LabResumeState $stage 'test-package' $sid $env:COMPUTERNAME $boot
$path=Join-Path $install ('Resume\'+$state.Id+'.json')
$events.Clear()
$failTask={param($s,$p) throw 'Task registration denied'}
Assert-Throws {Invoke-LabAutomaticRestart $state $path 'final' $boot 0 $failTask $wait $restart} 'Task registration denied'
Assert-Equal $events.Count 0 'No restart if recovery task unavailable'
Assert-Equal $state.RestartCount 0 'No reboot attempt consumed by registration failure'
$failRestart={throw 'Shutdown refused'}
Assert-Throws {Invoke-LabAutomaticRestart $state $path 'final' $boot 0 $ensure $wait $failRestart} 'Shutdown refused'
Assert-Equal $state.Status 'RestartFailed' 'Rejected OS restart recorded'
Assert-Equal (Get-LabResumeDecision $state $boot.AddMinutes(1)) 'Resume' 'Manual reboot can still run verification'
$state.Status='Completed'
Assert-Equal (Get-LabResumeDecision $state $boot.AddHours(2)) 'Stop' 'Completed verification cannot loop'
Assert-Throws {Invoke-LabAutomaticRestart $state $path 'bad countdown' $boot 601 $ensure $wait $restart} 'between 0 and 600'

# Guard the production control-flow boundary: exactly one restart call, after
# Chrome setup, and the post-boot branch exits before any installer invocation.
$launcher=Get-Content -LiteralPath (Join-Path $root 'package\Start-Lab.ps1') -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($launcher,[ref]$tokens,[ref]$errors)
$calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-LabAutomaticRestart'},$true))
Assert-Equal $calls.Count 1 'Exactly one automatic restart call in launcher'
Assert-Equal ($calls[0].Extent.StartOffset -gt $launcher.IndexOf('$chromeExit = $LASTEXITCODE')) $true 'Automatic restart after Chrome step'
Assert-Equal ($launcher.IndexOf('exit $verifyExit') -lt $launcher.IndexOf('Invoke-AppDeployToolkit.ps1')) $true 'Post-boot exit before installer chain'
$config=Import-PowerShellDataFile (Join-Path $root 'package\LabConfig.psd1')
Assert-Equal $config.BlockOnPendingReboot $false 'Pending reboot continues without middle restart'
Assert-Equal $config.RestartCountdownSeconds 60 'Default countdown 60 seconds'
Assert-Equal $config.AutomaticRestart $true 'Automatic final restart enabled'

# Run the real production installer-return handler with a fake PSADT process
# result. No executable is launched. A 3010 must return to its caller so the
# next component can run; true installer errors must still stop the chain.
$installerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'package\Invoke-AppDeployToolkit.ps1'),[ref]$tokens,[ref]$errors)
$handler=$installerAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-LabInstaller'},$true)
. ([scriptblock]::Create($handler.Extent.Text))
function Start-ADTProcess {
    [CmdletBinding()]
    param($FilePath,$ArgumentList,[switch]$PassThru,$IgnoreExitCodes,$Timeout)
    [pscustomobject]@{ExitCode=$script:fakeInstallerExit}
}
function Save-LabReport {$script:saves++}
$current='Jdk';$rows=@{Jdk=[pscustomobject]@{ExitCode=$null}}
$config=@{InstallerTimeoutMinutes=45};$report=@{RebootRequired=$false}
$script:saves=0;$script:fakeInstallerExit=3010
Invoke-LabInstaller 'fake-not-an-executable' @('/norestart')
Assert-Equal $rows.Jdk.ExitCode 3010 'Production handler preserves 3010'
Assert-Equal $report.RebootRequired $true 'Production handler accumulates restart flag'
$script:fakeInstallerExit=0
Invoke-LabInstaller 'next-fake-component' @('/norestart')
Assert-Equal $rows.Jdk.ExitCode 0 'Component after 3010 still runs'
Assert-Equal $report.RebootRequired $true 'Later exit 0 does not clear required restart'
Assert-Equal $script:saves 2 'Both component results are recorded'
$script:fakeInstallerExit=1618
Assert-Throws {Invoke-LabInstaller 'fake-not-an-executable' @('/norestart')} 'failed with exit code 1618'
Assert-Equal $rows.Jdk.ExitCode 1618 'Real installer error retained'
$script:fakeInstallerExit=1641
Assert-Throws {Invoke-LabInstaller 'fake-not-an-executable' @('/norestart')} 'initiated a reboot'
Assert-Equal $rows.Jdk.ExitCode 1641 'Unexpected third-party reboot retained as failure'

@{Passed=$script:passed;PowerShell=$PSVersionTable.PSVersion.ToString();At=(Get-Date -Format o);
    Scope='Decision/journal/task-identity/countdown tests with injected OS effects; no real task or reboot'}|
    ConvertTo-Json|Set-Content -LiteralPath (Join-Path $scratch 'result.json') -Encoding UTF8
Write-Host "PASS: $script:passed restart checks. Results: $scratch"
