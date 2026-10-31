#requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'package\Desktop.Setup.psm1') -Force
$s=[pscustomobject]@{CurrentSid='S-1-5-21-1-2-3-1001';ShellSid='S-1-5-21-1-2-3-1002';SessionSid='S-1-5-21-1-2-3-1002';SessionId=8;ShellSessionId=8;SessionState=0;InputDesktop='Default'}
$target=Get-LabDesktopTarget $s
if($target.Sid -ne $s.ShellSid -or $target.Session -ne 8){throw 'Cross-admin desktop target incorrect'}
$passed=1
foreach($change in @(@('ShellSessionId',9),@('SessionId',0),@('InputDesktop','Winlogon'),@('SessionState',4),@('SessionSid','S-1-5-21-1-2-3-9999'),@('ShellSid','S-1-5-18'))){
    $copy=$s|ConvertTo-Json|ConvertFrom-Json;$copy.($change[0])=$change[1]
    $failed=$false;try{Get-LabDesktopTarget $copy|Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'Unsafe target accepted'};$passed++
}
$r=[pscustomobject]@{Nonce='nonce';PackageId='package';UserSid=$target.Sid;SessionId=8}
if(-not(Test-LabDesktopResult $r 'nonce' 'package' $target)){throw 'Valid result rejected'};$passed++
foreach($change in @(@('Nonce','wrong'),@('PackageId','old'),@('UserSid',$s.CurrentSid),@('SessionId',9))){
    $copy=$r|ConvertTo-Json|ConvertFrom-Json;$copy.($change[0])=$change[1]
    if(Test-LabDesktopResult $copy 'nonce' 'package' $target){throw 'Wrong actor result accepted'};$passed++
}
Write-Host "PASS: $passed desktop handoff identity/result checks; no tasks or installations executed."
