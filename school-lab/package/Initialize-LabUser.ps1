#requires -Version 5.1
[CmdletBinding()]
param([string]$SettingsPath = '', [string]$UserDataDirectory = '', [string]$ExtensionsDirectory = '', [switch]$NoShortcuts)
$ErrorActionPreference = 'Stop'
if (-not $SettingsPath) { $SettingsPath = Join-Path $PSScriptRoot 'user-settings.json' }
Import-Module (Join-Path $PSScriptRoot 'Lab.Core.psm1') -Force
$userRoot = Join-Path $env:LOCALAPPDATA 'SchoolLab'
New-Item -ItemType Directory -Path $userRoot -Force | Out-Null
$log = Join-Path $userRoot 'initialize.log'
$mutex = $null
$settings = $null
$held = $false
try {
    $mutex = New-LabUserMutex
    try { $held = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { Write-Host 'Account setup is already running. Wait, then run Check-LabReady.cmd.'; exit 69021 }
    # Called at logon, or immediately by the launcher only after verifying that
    # the current SID owns Explorer in this session. SYSTEM never initializes HKCU.
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) START $env:USERNAME package=$($settings.PackageId)"
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    $env:JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME','Machine')
    $userJavaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME','User')
    if ($userJavaHome -and $userJavaHome -ine $settings.JavaHome) {
        [Environment]::SetEnvironmentVariable('JAVA_HOME',$settings.JavaHome,'User')
    }
    $profiles = @('') + @($settings.AdditionalProfiles)
    $isolation = @()
    if ($UserDataDirectory) { $isolation += @('--user-data-dir',$UserDataDirectory) }
    if ($ExtensionsDirectory) { $isolation += @('--extensions-dir',$ExtensionsDirectory) }
    # Names supplied in config use the supported --profile CLI option. VS Code's
    # internal storage format is deliberately not assumed; see README for limits.
    foreach ($profile in ($profiles | Select-Object -Unique)) {
        $profileArgs = @($isolation)
        if ($profile) { $profileArgs += @('--profile', $profile) }
        $list = Invoke-LabCode $settings.CodeDirectory (@('--list-extensions', '--show-versions') + $profileArgs)
        if ($list.ExitCode -ne 0) { throw "Cannot list extensions for profile '$profile': $($list.StdErr)" }
        $installed = @($list.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() })
        foreach ($extension in $settings.Extensions) {
            $file = Join-Path $PSScriptRoot $extension.File
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $extension.SHA256) {
                throw "VSIX hash mismatch: $file"
            }
            if ("$($extension.Id)@$($extension.Version)" -notin $installed) {
                Write-Host "Installing offline extension: $($extension.Id) $($extension.Version)"
                $result = Invoke-LabCode $settings.CodeDirectory (@('--install-extension', $file, '--force', '--do-not-include-pack-dependencies') + $profileArgs)
                Add-Content -LiteralPath $log -Value ($result.StdOut + $result.StdErr)
                if ($result.ExitCode -ne 0) { throw "Extension install failed: $($extension.Id), profile '$profile'" }
            }
        }
        $verify = Invoke-LabCode $settings.CodeDirectory (@('--list-extensions', '--show-versions') + $profileArgs)
        $actual = @($verify.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() })
        if ($verify.ExitCode -ne 0) { throw 'Extension verification command failed.' }
        foreach ($extension in $settings.Extensions) {
            if ("$($extension.Id)@$($extension.Version)" -notin $actual) {
                throw "Extension version verification failed: $($extension.Id), profile '$profile'"
            }
        }
    }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $workspaces = New-LabLanguageWorkspaces -Root (Join-Path $documents ('SchoolLab\' + $settings.PackageId)) `
        -JavaHome $settings.JavaHome -PythonHome $settings.PythonHome -JavaVersion $settings.JavaVersion -MinGW $settings.MinGW -Standard $settings.CppStandard
    $workspace = $workspaces.Cpp
    # Test the actual bare commands as this user, to catch Store aliases, per-user
    # Python/JAVA_HOME overrides and stale terminals that machine tests cannot see.
    foreach ($pair in @(@('java.exe', (Join-Path $settings.JavaHome 'bin\java.exe')),
        @('javac.exe', (Join-Path $settings.JavaHome 'bin\javac.exe')),
        @('python.exe', (Join-Path $settings.PythonHome 'python.exe')),
        @('pip.exe', (Join-Path $settings.PythonHome 'Scripts\pip.exe')),
        @('g++.exe', $settings.MinGW.Gpp), @('gdb.exe', $settings.MinGW.Gdb))) {
        $command = Get-Command -Name $pair[0] -CommandType Application -ErrorAction Stop | Select-Object -First 1
        if ($command.Source -ine $pair[1]) { throw "PATH conflict: $($pair[0]) resolves to $($command.Source), expected $($pair[1])" }
    }
    $smoke = Test-LabToolchain -JavaHome $settings.JavaHome -PythonHome $settings.PythonHome -MinGW $settings.MinGW `
        -Directory (Join-Path $userRoot 'smoke') -Standard $settings.CppStandard
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $NoShortcuts) {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($language in @('Cpp','Java','Python')) {
            $label = if ($language -eq 'Cpp') { 'C++' } else { $language }
            $shortcut = $shell.CreateShortcut((Join-Path $desktop "SchoolLab $label.lnk"))
            $shortcut.TargetPath = Join-Path $settings.CodeDirectory 'Code.exe'
            $shortcut.Arguments = ConvertTo-LabArgument $workspaces.$language
            $shortcut.WorkingDirectory = $workspaces.$language
            $shortcut.Save()
        }
    }
    @{ Status = 'Passed'; User = $env:USERNAME; PackageId = $settings.PackageId; At = (Get-Date -Format o);
        Workspace = $workspace; Workspaces=$workspaces; Profiles = $profiles; Tests = $smoke; Extensions=@($settings.Extensions | Select-Object Id,Version) } |
        ForEach-Object { Write-LabJson -Path (Join-Path $userRoot 'result.json') -Value $_ }
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) PASSED"
    exit 0
} catch {
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) FAILED $_"
    Write-LabJson (Join-Path $userRoot 'result.json') @{ Status='Failed';PackageId=(Get-LabProperty $settings 'PackageId' '');
        At=(Get-Date -Format o);Error="$_";Stack=$_.ScriptStackTrace }
    exit 69020
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
