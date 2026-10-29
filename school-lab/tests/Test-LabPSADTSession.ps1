#requires -Version 5.1
[CmdletBinding()]
param([string]$TemplateRoot = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $TemplateRoot) { $TemplateRoot = Join-Path $root 'downloads\psadt-4.1.8' }
$TemplateRoot = (Resolve-Path -LiteralPath $TemplateRoot).Path
Import-Module (Join-Path $TemplateRoot 'PSAppDeployToolkit\PSAppDeployToolkit.psd1') -Force
# Evaluate the actual production hashtable, avoiding a test that checks a copy.
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'package\Invoke-AppDeployToolkit.ps1'), [ref]$tokens, [ref]$parseErrors)
$assignment = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$sessionOptions'
}, $true)
if (-not $assignment) { throw 'Missing production session options' }
$config = Import-PowerShellDataFile (Join-Path $root 'package\LabConfig.psd1')
$DeployMode = 'Silent'
$sessionOptions = & ([scriptblock]::Create($assignment.Right.Extent.Text))
if ($sessionOptions.RequireAdmin -ne $true -or $sessionOptions.SessionState -isnot [Management.Automation.SessionState]) {
    throw 'Production session argument types are incorrect'
}
# The integration probe uses the current unelevated token and installs nothing.
# Test paths and logging override are isolated from deployment logs.
$sessionOptions.RequireAdmin = $false
$sessionOptions.ScriptDirectory = $TemplateRoot
$sessionOptions.AppName = 'SchoolLab Session Probe'
$sessionOptions.DisableLogging = $true
$session = Open-ADTSession @sessionOptions -PassThru
if (-not $session) { throw 'Open-ADTSession returned no session' }
$result = Start-ADTProcess -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList '-NoProfile -Command "exit 7"' -IgnoreExitCodes '*' -PassThru -CreateNoWindow
if ($result.ExitCode -ne 7) { throw 'PSADT did not retain the child process exit code' }
Write-Host 'PASS: production session options bound; real PSADT 4.1.8 session opened; child exit 7 captured. No installer executed.'
Close-ADTSession -ExitCode 0
