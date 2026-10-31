#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'package\Lab.Core.psm1') -Force
$scratch = Join-Path $root ('test-results\logic-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$script:passed = 0
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw "$Message expected=[$Expected] actual=[$Actual]" }
    $script:passed++
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action } catch {
        if ("$_" -notmatch $Pattern) { throw "Wrong error, expected '$Pattern': $_" }
        $script:passed++
        return
    }
    throw "Expected an error matching '$Pattern'"
}

# Parse every authored PowerShell file using the actual executing engine (5.1 in CI).
foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension -in @('.ps1','.psm1','.psd1') -and $_.FullName -notmatch '\\(downloads|dist|test-results)\\'
})) {
    $tokens = $null; $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal @($parseErrors).Count 0 "Parse $($file.Name)"
}
$old = 'C:\Windows;%SystemRoot%\System32;;"C:\A B\bin";C:\old'
$merged = Merge-LabPath $old @('C:\New','c:\new\','c:\WINDOWS\','C:\A B\bin\')
Assert-Equal $merged ('C:\New;' + $old) 'PATH preserves original bytes and deduplicates additions'
Assert-Equal (Merge-LabPath $merged @('C:\New')) $merged 'PATH rerun is idempotent'
Assert-Equal (Merge-LabPath '' @('C:\New','c:\new')) 'C:\New' 'Empty PATH'
Assert-Equal (Merge-LabPath 'C:\Windows' @('%SystemRoot%')) 'C:\Windows' 'Expanded comparison'
Assert-Equal (Get-LabVersionAction '' '3.15.1') 'Install' 'Missing install'
Assert-Equal (Get-LabVersionAction '3.15.1' '3.15.1') 'Skip' 'Exact match'
Assert-Equal (Get-LabVersionAction '3.14.9' '3.15.1') 'Install' 'Upgrade'
Assert-Equal (Get-LabVersionAction '27+34' '27+35') 'Install' 'JDK build upgrade'
Assert-Throws { Get-LabVersionAction '27+36' '27+35' } 'Refusing downgrade'
Assert-Throws { Get-LabVersionAction '3.16.0' '3.15.1' } 'Refusing downgrade'
Assert-Throws { Resolve-LabPackagePath $scratch '..\escape' } 'escapes root'
Assert-Throws { Resolve-LabPackagePath $scratch 'C:\escape' } 'Absolute package path'
Assert-Equal (Test-LabX64Executable "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe") $true 'x64 PE'
Assert-Equal (Test-LabX64Executable "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe") $false 'Reject x86 PE'

# Regression: create the real per-user mutex on PowerShell 5.1 and verify that
# another process is excluded while held, then can acquire it after release.
$mutexProbe = Join-Path $scratch 'mutex-probe.ps1'
Set-Content -LiteralPath $mutexProbe -Encoding UTF8 -Value @'
param([string]$ModulePath)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath -Force
$probe = New-LabUserMutex
$held = $false
try {
    $held = $probe.WaitOne(0)
    if ($held) { exit 12 }
    exit 0
} finally {
    if ($held) { $probe.ReleaseMutex() }
    $probe.Dispose()
}
'@
$userMutex = New-LabUserMutex
$mutexHeld = $false
try {
    Assert-Equal ($userMutex -is [System.Threading.Mutex]) $true 'Per-user mutex constructor'
    $mutexHeld = $userMutex.WaitOne(0)
    Assert-Equal $mutexHeld $true 'Acquire per-user mutex'
    $probeArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$mutexProbe,(Join-Path $root 'package\Lab.Core.psm1'))
    $probe = Invoke-LabCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" $probeArgs
    Assert-Equal $probe.ExitCode 0 'Another process cannot acquire held mutex'
    $userMutex.ReleaseMutex()
    $mutexHeld = $false
    $probe = Invoke-LabCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" $probeArgs
    Assert-Equal $probe.ExitCode 12 'Another process acquires released mutex'
} finally {
    if ($mutexHeld) { $userMutex.ReleaseMutex() }
    $userMutex.Dispose()
}

# Exercise the actual initializer entry and failure reporting with isolated state.
# The deliberately missing settings stop execution before PATH, extensions or
# Documents are touched. The old constructor crashed before writing this report.
$isolatedState = Join-Path $scratch 'initializer-state'
$missingSettings = Join-Path $scratch 'missing-settings.json'
$entryProbe = Invoke-LabCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'package\Initialize-LabUser.ps1'),'-SettingsPath',$missingSettings) `
    -Environment @{ LOCALAPPDATA = $isolatedState }
Assert-Equal $entryProbe.ExitCode 69020 'Initializer returns controlled failure for missing settings'
$entryReport = Get-Content -LiteralPath (Join-Path $isolatedState 'SchoolLab\result.json') -Raw | ConvertFrom-Json
Assert-Equal $entryReport.Status 'Failed' 'Initializer writes failure report after acquiring mutex'
Assert-Equal ($entryReport.Error -like '*missing-settings.json*') $true 'Initializer reaches settings load'
Assert-Equal (Test-Path -LiteralPath (Join-Path $isolatedState 'SchoolLab\initialize.log')) $true 'Initializer records failure log'

# Exercise quoting through a real Windows process, including Unicode and metacharacters.
$echoScript = Join-Path $scratch 'echo args.ps1'
Set-Content -LiteralPath $echoScript -Encoding UTF8 -Value 'param([string]$Value) [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); [Console]::Write($Value)'
foreach ($sample in @('plain','C:\space path\','a"b','a\\"b','a&b|c%PATH%','tiếng Việt','')) {
    $result = Invoke-LabCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-File',$echoScript,$sample)
    Assert-Equal $result.ExitCode 0 'Argument process exit'
    Assert-Equal $result.StdOut $sample 'Argument round trip'
}
$failure = Invoke-LabCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-Command','[Console]::Error.Write("TEST_STDERR"); exit 42')
Assert-Equal $failure.ExitCode 42 'Nonzero exit is retained'
Assert-Equal $failure.StdErr 'TEST_STDERR' 'stderr is retained'
Assert-Throws { Invoke-LabCommand "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-Command','Start-Sleep 20') -TimeoutSeconds 1 } 'Timed out'

$a = [pscustomobject]@{ Id = 'a'; Dependencies = @('b'); ExtensionPack = @() }
$b = [pscustomobject]@{ Id = 'b'; Dependencies = @(); ExtensionPack = @() }
Assert-Equal ((Get-LabExtensionOrder @($a,$b) | ForEach-Object Id) -join ',') 'b,a' 'Dependency first'
Assert-Throws { Get-LabExtensionOrder @($a) } 'Missing offline VSIX dependency'
Assert-Throws { Get-LabExtensionOrder @($b,$b) } 'Duplicate extension IDs'
$cycle = [pscustomobject]@{ Id = 'b'; Dependencies = @('a'); ExtensionPack = @() }
Assert-Throws { Get-LabExtensionOrder @($a,$cycle) } 'Cyclic'
$pack = [pscustomobject]@{ Id = 'pack'; Dependencies = @(); ExtensionPack = @('b') }
Assert-Equal ((Get-LabExtensionOrder @($pack,$b) | ForEach-Object Id) -join ',') 'pack,b' 'Pack closure does not impose dependency order'
$pythonPack = [pscustomobject]@{ Id='python';Dependencies=@();ExtensionPack=@('debugpy') }
$debugpy = [pscustomobject]@{ Id='debugpy';Dependencies=@('python');ExtensionPack=@() }
Assert-Equal ((Get-LabExtensionOrder @($debugpy,$pythonPack) | ForEach-Object Id) -join ',') 'python,debugpy' 'Python pack back-reference is not a hard dependency cycle'

# Support both classic and current commit-folder VS Code layouts, without a shell.
$fakeCode = Join-Path $scratch 'Code'
New-Item -ItemType Directory -Path (Join-Path $fakeCode 'bin') -Force | Out-Null
foreach ($relative in @('resources\app\out\cli.js','abc123\resources\app\out\cli.js')) {
    $cli = Join-Path $fakeCode $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $cli) -Force | Out-Null
    Set-Content -LiteralPath $cli -Value '// fixture'
    Set-Content -LiteralPath (Join-Path $fakeCode 'bin\code.cmd') -Value ('"%~dp0..\Code.exe" "%~dp0..\' + $relative + '" %*')
    Assert-Equal (Get-LabCodeLayout $fakeCode).CliPath $cli 'Select CLI from installed launcher'
}
Set-Content -LiteralPath (Join-Path $fakeCode 'bin\code.cmd') -Value 'unknown layout'
Assert-Throws { Get-LabCodeLayout $fakeCode } 'Unrecognized'
Set-Content -LiteralPath (Join-Path $fakeCode 'bin\code.cmd') -Value '"%~dp0..\Code.exe" "%~dp0..\..\evil\resources\app\out\cli.js"'
Assert-Throws { Get-LabCodeLayout $fakeCode } 'outside'

$mingw = [pscustomobject]@{ Gpp = 'C:\Dev Cpp\bin\g++.exe'; Gdb = 'C:\Dev Cpp\bin\gdb.exe'; Bin = 'C:\Dev Cpp\bin'; Architecture = 'x86' }
$workspace = Join-Path $scratch 'workspace'
New-LabCppWorkspace $workspace $mingw
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $workspace '.vscode') -Filter *.json) {
    $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $script:passed++
}
$tasks = Get-Content -LiteralPath (Join-Path $workspace '.vscode\tasks.json') -Raw | ConvertFrom-Json
Assert-Equal $tasks.tasks[0].type 'process' 'Build handles paths with spaces without a shell'
Assert-Equal $tasks.tasks[0].args[3] '${file}' 'VS Code substitution preserved'
$intel = Get-Content -LiteralPath (Join-Path $workspace '.vscode\c_cpp_properties.json') -Raw | ConvertFrom-Json
Assert-Equal $intel.configurations[0].intelliSenseMode 'windows-gcc-x86' 'MinGW bitness, not OS bitness'
Set-Content -LiteralPath (Join-Path $workspace 'main.cpp') -Value 'STUDENT WORK'
New-LabCppWorkspace $workspace $mingw
Assert-Equal (Get-Content -LiteralPath (Join-Path $workspace 'main.cpp') -Raw).Trim() 'STUDENT WORK' 'Student source is preserved'

$languages = New-LabLanguageWorkspaces -Root (Join-Path $scratch 'languages') -JavaHome 'C:\Program Files\SchoolLab\JDK' `
    -PythonHome 'C:\Program Files\SchoolLab\Python' -JavaVersion '27+35' -MinGW $mingw -Standard 'c++11'
$pySettings = Get-Content -LiteralPath (Join-Path $languages.Python '.vscode\settings.json') -Raw | ConvertFrom-Json
Assert-Equal $pySettings.'python.defaultInterpreterPath' 'C:\Program Files\SchoolLab\Python\python.exe' 'Explicit Python interpreter'
$javaSettings = Get-Content -LiteralPath (Join-Path $languages.Java '.vscode\settings.json') -Raw | ConvertFrom-Json
Assert-Equal $javaSettings.'java.jdt.ls.java.home' 'C:\Program Files\SchoolLab\JDK' 'Explicit Java language server JDK'
Assert-Equal $javaSettings.'java.configuration.runtimes'[0].name 'JavaSE-27' 'Java runtime name'
$javaBytes=[IO.File]::ReadAllBytes((Join-Path $languages.Java 'LabHello.java'))
Assert-Equal ([BitConverter]::ToString($javaBytes,0,3) -eq 'EF-BB-BF') $false 'Java source must not contain a UTF-8 BOM'
$pyLaunch = Get-Content -LiteralPath (Join-Path $languages.Python '.vscode\launch.json') -Raw | ConvertFrom-Json
Assert-Equal $pyLaunch.configurations[0].type 'debugpy' 'Current Python debug adapter'
foreach ($json in Get-ChildItem -LiteralPath (Join-Path $scratch 'languages') -Filter *.json -File -Recurse) {
    $null = Get-Content -LiteralPath $json.FullName -Raw | ConvertFrom-Json
    $script:passed++
}
Set-Content -LiteralPath (Join-Path $languages.Python 'main.py') -Value 'STUDENT PYTHON'
$null = New-LabLanguageWorkspaces -Root (Join-Path $scratch 'languages') -JavaHome 'C:\Other' -PythonHome 'C:\Other' -JavaVersion '27+35' -MinGW $mingw -Standard 'c++11'
Assert-Equal (Get-Content -LiteralPath (Join-Path $languages.Python 'main.py') -Raw).Trim() 'STUDENT PYTHON' 'Preserve Python student source'
$fakeDev = Join-Path $scratch 'Dev Cpp'
New-Item -ItemType Directory -Path $fakeDev -Force | Out-Null
$devConfig = @{DevCppDirectory=$fakeDev;DevCppSearchPatterns=@()}
Assert-Equal ($null -eq (Get-LabDevCpp $devConfig @())) $true 'Dev-C++ missing is detected'
Copy-Item -LiteralPath "$env:SystemRoot\System32\cmd.exe" -Destination (Join-Path $fakeDev 'devcpp.exe')
Assert-Equal (Get-LabDevCpp $devConfig @()).Directory $fakeDev 'Existing Dev-C++ executable detection'
$jsonPath = Join-Path $scratch 'atomic.json'
Write-LabJson $jsonPath @{Status='Passed';Value=17}
Assert-Equal (Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json).Value 17 'Atomic result write'

$package = Join-Path $scratch 'package'
$required = @('LabConfig.psd1','Lab.Core.psm1','Session.Context.cs','Reboot.Core.psm1','Start-Lab.ps1','Check-LabReady.ps1','Invoke-AppDeployToolkit.ps1','Initialize-LabUser.ps1',
    'PSAppDeployToolkit\PSAppDeployToolkit.psd1','Files\jdk.msi','Files\python.exe','Files\vscode.exe')
$files = @()
foreach ($relative in $required) {
    $target = Join-Path $package $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Set-Content -LiteralPath $target -Value 'test payload'
    $files += [pscustomobject]@{ Path = $relative; SHA256 = (Get-FileHash -LiteralPath $target).Hash }
}
$lock = [pscustomobject]@{ SchemaVersion = 1; PSADTVersion = '4.1.8'; Files = $files; Components = [pscustomobject]@{
    Jdk = @{ File = 'Files\jdk.msi' }; Python = @{ File = 'Files\python.exe' }; VSCode = @{ File = 'Files\vscode.exe' } } }
Test-LabPackage $package $lock
$script:passed++
Add-Content -LiteralPath (Join-Path $package 'Files\python.exe') -Value 'tampered'
Assert-Throws { Test-LabPackage $package $lock } 'SHA256 mismatch'
Remove-Item -LiteralPath (Join-Path $package 'Files\jdk.msi')
Assert-Throws { Test-LabPackage $package $lock } 'Missing package file'
@{ Passed = $script:passed; PowerShell = $PSVersionTable.PSVersion.ToString(); At = (Get-Date -Format o);
    Scope = 'Logic only; no software installation, PATH edits, registry writes or logon hook' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scratch 'result.json') -Encoding UTF8
Write-Host "PASS: $script:passed assertions. Results: $scratch"
