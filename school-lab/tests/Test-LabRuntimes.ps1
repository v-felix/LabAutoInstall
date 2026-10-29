#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$JavaHome,[Parameter(Mandatory=$true)][string]$PythonHome,
    [Parameter(Mandatory=$true)][string]$ExtensionDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'package\Lab.Core.psm1') -Force
$scratch=Join-Path $root ('test-results\runtimes-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$config=Import-PowerShellDataFile (Join-Path $root 'package\LabConfig.psd1')
$mingw=Get-LabMinGW $config @(Get-LabApplications)
$savedPath=$env:Path
try {
    $env:Path=$mingw.Bin+';'+$env:Path
    $standard=Resolve-LabCppStandard $mingw Auto $scratch
    $smoke=Test-LabToolchain $JavaHome $PythonHome $mingw $scratch $standard
    $python=Join-Path $PythonHome 'python.exe'
    $null=Assert-LabCommand $python @('-m','venv',(Join-Path $scratch 'venv'))
    $venvPip=Assert-LabCommand (Join-Path $scratch 'venv\Scripts\python.exe') @('-m','pip','--version') 'pip '
    $debugpy=Get-ChildItem -LiteralPath $ExtensionDirectory -Directory | Where-Object Name -Like 'ms-python.debugpy-*' | Select-Object -First 1
    $debugpyLib=Join-Path $debugpy.FullName 'bundled\libs'
    $debug=Assert-LabCommand $python @('-I','-c',
        'import sys;sys.path.insert(0,sys.argv[1]);import debugpy;debugpy.listen(("127.0.0.1",0));print("SCHOOLLAB_DEBUGPY_OK")',$debugpyLib) 'SCHOOLLAB_DEBUGPY_OK'
    $languages=New-LabLanguageWorkspaces (Join-Path $scratch 'workspaces') $JavaHome $PythonHome '27+35' $mingw $standard
    $null=Assert-LabCommand (Join-Path $JavaHome 'bin\javac.exe') @('-encoding','UTF-8','-d',(Join-Path $languages.Java 'out'),(Join-Path $languages.Java 'LabHello.java'))
    $javaTask=Assert-LabCommand (Join-Path $JavaHome 'bin\java.exe') @('-cp',(Join-Path $languages.Java 'out'),'LabHello') 'SCHOOLLAB_JAVA_OK'
    $pyTask=Assert-LabCommand $python @('-u',(Join-Path $languages.Python 'main.py')) 'SCHOOLLAB_PYTHON_OK'
    Write-LabJson (Join-Path $scratch 'result.json') @{Status='Passed';JavaVersion=(Get-LabExecutableVersion (Join-Path $JavaHome 'bin\java.exe') Jdk);
        PythonVersion=(Get-LabExecutableVersion $python Python);Smoke=$smoke;VenvPip=$venvPip;Debugpy=$debug;JavaWorkspace=$javaTask;PythonWorkspace=$pyTask}
    Write-Host "PASS: JDK/Python/venv/pip/C++/GDB, bundled debugpy, and Java/Python workspace commands. $scratch"
} finally { $env:Path=$savedPath }
