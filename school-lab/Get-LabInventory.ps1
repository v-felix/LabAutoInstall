#requires -Version 5.1
<# Safe discovery before creating a package; no installation or machine changes. #>
[CmdletBinding()]
param([string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot ("test-results\inventory-$env:COMPUTERNAME.json") }
Import-Module (Join-Path $PSScriptRoot 'package\Lab.Core.psm1') -Force
$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'package\LabConfig.psd1')
$applications = @(Get-LabApplications)
$minGW = $null
$discoveryError = ''
try { $minGW = Get-LabMinGW $config $applications } catch { $discoveryError = "$_" }
$commands = @()
foreach ($name in @('java.exe','javac.exe','python.exe','pip.exe','g++.exe','gdb.exe','code.cmd')) {
    $commands += @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue |
        Select-Object Name,Source,Version)
}
$os = Get-CimInstance Win32_OperatingSystem
$result = [ordered]@{ Computer = $env:COMPUTERNAME; At = (Get-Date -Format o); OS = $os.Caption;
    Build = $os.BuildNumber; Is64BitOS = [Environment]::Is64BitOperatingSystem;
    MachineJavaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME','Machine');
    MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine');
    PendingReboot = @(Get-LabPendingReboot); Applications = $applications; Commands = $commands;
    MinGW = $minGW; MinGWDiscoveryError = $discoveryError }
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Inventory saved: $OutputPath"
if ($discoveryError) { Write-Warning $discoveryError }
