#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'package\Lab.Core.psm1') -Force
$scratch=Join-Path $root ('test-results\context-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force|Out-Null
$script:passed=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:passed++}
function Snapshot {
    [pscustomobject]@{CurrentSid='S-1-5-21-111-222-333-1001';CurrentAccount='PC\Admin';SessionId=3;
        ShellSid='S-1-5-21-111-222-333-1001';ShellSessionId=3;ShellProcessId=100;
        SessionSid='S-1-5-21-111-222-333-1001';SessionState=0;InputDesktop='Default';Errors=@()}
}
$s=Snapshot;$c=Resolve-LabClassroomContext $s
Assert ($c.Ready -and $c.Method -eq 'NativeShellToken') 'Same administrator SID must pass'
$s.CurrentAccount='Other spelling / Microsoft account display name'
Assert (Resolve-LabClassroomContext $s).Ready 'Identity must use SID, not account display names'
$s=Snapshot;$s.SessionSid='';$s.SessionState=-1;$s.Errors=@('WTS unavailable')
Assert ((Resolve-LabClassroomContext $s).Method -eq 'NativeShellToken') 'Shell token must work when WTS query/translation fails'
$s=Snapshot;$s.ShellSid='';$s.ShellSessionId=-1;$s.ShellProcessId=0;$s.Errors=@('Explorer token could not be read')
Assert ((Resolve-LabClassroomContext $s).Ready -and (Resolve-LabClassroomContext $s).Method -eq 'NativeWTSSession') 'Active WTS SID must provide fallback without WMI'
foreach($field in @('ShellSid','SessionSid')){
    $s=Snapshot;$s.$field='S-1-5-21-111-222-333-1002'
    $c=Resolve-LabClassroomContext $s
    Assert (-not $c.Ready -and $c.Status -eq 'DifferentAccount') "Mismatched $field must stop even when the other SID matches"
}
$s=Snapshot;$s.ShellSessionId=4
Assert ((Resolve-LabClassroomContext $s).Status -eq 'DifferentSession') 'Do not accept a shell from another session'
foreach($sid in @('S-1-5-18','S-1-5-19','S-1-5-20')){
    $s=Snapshot;$s.CurrentSid=$sid
    Assert ((Resolve-LabClassroomContext $s).Status -eq 'ServiceSession') 'Service accounts must never initialize classroom profiles'
}
foreach($session in @(0,-1)){
    $s=Snapshot;$s.SessionId=$session
    Assert ((Resolve-LabClassroomContext $s).Status -eq 'ServiceSession') 'Noninteractive session must stop'
}
foreach($desktop in @('Winlogon','Screen-saver')){
    $s=Snapshot;$s.InputDesktop=$desktop
    Assert ((Resolve-LabClassroomContext $s).Status -eq 'DesktopLocked') 'Secure/locked input desktop must stop'
}
$s=Snapshot;$s.InputDesktop=''
Assert ((Resolve-LabClassroomContext $s).Status -eq 'DesktopUnavailable') 'Missing input desktop is not proof of another user'
foreach($state in @(1,4,5)){
    $s=Snapshot;$s.SessionState=$state
    Assert ((Resolve-LabClassroomContext $s).Status -eq 'SessionInactive') 'Disconnected/inactive session must stop'
}
$s=Snapshot;$s.ShellSid='';$s.SessionSid=''
Assert ((Resolve-LabClassroomContext $s).Status -eq 'Unverified') 'Do not infer identity just because there is one admin account'
$s=Snapshot;$s.CurrentSid='not-a-sid'
Assert ((Resolve-LabClassroomContext $s).Status -eq 'Unverified') 'Invalid current SID must not pass'

# Retry only transient failures, using the exact production wait function.
# No sleeps, WMI calls, impersonation or account changes occur here.
$bag=@{Calls=0;Waits=0}
$unknown=Resolve-LabClassroomContext $s
$ready=Resolve-LabClassroomContext (Snapshot)
$probe={ $bag.Calls++;if($bag.Calls -lt 3){$unknown}else{$ready} }.GetNewClosure()
$wait={ $bag.Waits++ }.GetNewClosure()
$result=Wait-LabClassroomContext -TimeoutSeconds 3 -Probe $probe -WaitAction $wait
Assert ($result.Ready -and $bag.Calls -eq 3 -and $bag.Waits -eq 2) 'Transient desktop lookup must retry and then pass'
$bag.Calls=0;$bag.Waits=0
$probe={ $bag.Calls++;$unknown }.GetNewClosure()
$result=Wait-LabClassroomContext -TimeoutSeconds 2 -Probe $probe -WaitAction $wait
Assert (-not $result.Ready -and $bag.Calls -eq 3 -and $bag.Waits -eq 2) 'Unverified lookup must time out without allowing setup'
$s=Snapshot;$s.SessionSid='S-1-5-21-111-222-333-1002';$wrong=Resolve-LabClassroomContext $s
$bag.Calls=0;$bag.Waits=0
$probe={ $bag.Calls++;$wrong }.GetNewClosure()
$result=Wait-LabClassroomContext -TimeoutSeconds 3 -Probe $probe -WaitAction $wait
Assert ($result.Status -eq 'DifferentAccount' -and $bag.Calls -eq 1 -and $bag.Waits -eq 0) 'Known account mismatch must not be retried or bypassed'

# Run the actual Windows native reader, read-only. The developer host may be
# interactive or a service; do not require an unlocked desktop for this test.
$context=Get-LabClassroomContext
Assert ($context.Status -ne 'ProbeFailed') ('Native compilation/capture failed: '+$context.Message)
Assert ($null -ne $context.Snapshot) 'Native snapshot missing'
$expectedSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Assert ($context.Snapshot.CurrentSid -eq $expectedSid) 'Native current SID disagrees with Windows identity'
Assert ($context.Snapshot.SessionId -eq (Get-Process -Id $PID).SessionId) 'Native process session is incorrect'
if($context.Snapshot.SessionSid -eq $expectedSid -and $context.Snapshot.SessionState -eq 0 -and $context.Snapshot.InputDesktop -eq 'Default'){
    $fallback=$context.Snapshot|ConvertTo-Json -Depth 8|ConvertFrom-Json
    $fallback.ShellSid='';$fallback.ShellSessionId=-1;$fallback.ShellProcessId=0
    Assert ((Resolve-LabClassroomContext $fallback).Method -eq 'NativeWTSSession') 'Real WTS capture must verify the account when shell-token evidence is unavailable'
}
if($context.Snapshot.ShellSid){
    $shell=Get-CimInstance Win32_Process -Filter ('ProcessId='+$context.Snapshot.ShellProcessId)
    $owner=Invoke-CimMethod -InputObject $shell -MethodName GetOwnerSid
    if($owner.ReturnValue -eq 0){Assert ($owner.Sid -eq $context.Snapshot.ShellSid) 'Native shell token SID disagrees with independent WMI result'}
}
Write-LabJson (Join-Path $scratch 'context.json') $context
Assert ((Get-Content -LiteralPath (Join-Path $scratch 'context.json') -Raw|ConvertFrom-Json).Snapshot.CurrentSid -eq $expectedSid) 'Context diagnostic JSON did not retain SID fields'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'package\Lab.Core.psm1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-LabClassroomContext'},$true)
Assert ($function.Extent.Text -notmatch 'Get-CimInstance|Invoke-CimMethod') 'Production context verification must not depend on WMI'
Write-LabJson (Join-Path $scratch 'result.json') @{Passed=$script:passed;PowerShell=$PSVersionTable.PSVersion.ToString();
    NativeStatus=$context.Status;NativeMethod=$context.Method;Scope='Pure decision/retry fixtures and read-only native Windows context capture; no installation or profile/registry changes'}
Write-Host "PASS: $script:passed classroom-context checks; native result=$($context.Status)/$($context.Method). Results: $scratch"
