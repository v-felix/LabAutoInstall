#requires -Version 5.1
Set-StrictMode -Version 2

function New-LabUserMutex {
    # Keep the name a single string and select the two-argument constructor.
    # New-Object with an inline '+' expression can bind a third [ref] argument
    # on Windows PowerShell 5.1.
    $mutexName = 'Local\SchoolLab-User-{0}' -f [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return [System.Threading.Mutex]::new($false, $mutexName)
}

function Get-LabProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Expand-LabPath {
    param([string]$Path)
    [Environment]::ExpandEnvironmentVariables($Path)
}

function ConvertTo-LabArgument {
    param([AllowEmptyString()][string]$Value)
    # CommandLineToArgvW / C runtime quoting, including trailing backslashes.
    '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Invoke-LabCommand {
    param([string]$FilePath, [string[]]$Arguments = @(), [int]$TimeoutSeconds = 90,
        [string]$WorkingDirectory = $env:TEMP, [hashtable]$Environment = @{})
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = (($Arguments | ForEach-Object { ConvertTo-LabArgument $_ }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    foreach ($key in $Environment.Keys) { $info.EnvironmentVariables[$key] = [string]$Environment[$key] }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw "Cannot start $FilePath" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw "Timed out after ${TimeoutSeconds}s: $FilePath"
        }
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.GetAwaiter().GetResult();
            StdErr = $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Assert-LabCommand {
    param([string]$FilePath, [string[]]$Arguments = @(), [string]$Expected = '',
        [string]$WorkingDirectory = $env:TEMP)
    $result = Invoke-LabCommand -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    $output = $result.StdOut + $result.StdErr
    if ($result.ExitCode -ne 0 -or ($Expected -and $output -notmatch $Expected)) {
        throw "Command failed ($($result.ExitCode)): $FilePath $($Arguments -join ' ')`n$output"
    }
    $output.Trim()
}

function Merge-LabPath {
    param([AllowEmptyString()][string]$Existing, [string[]]$Additions)
    $seen = @{}
    foreach ($entry in ($Existing -split ';')) {
        $normalized = (Expand-LabPath $entry.Trim().Trim('"')).TrimEnd('\', '/').ToLowerInvariant()
        if ($normalized) { $seen[$normalized] = $true }
    }
    $new = @()
    foreach ($entry in $Additions) {
        $normalized = (Expand-LabPath $entry.Trim().Trim('"')).TrimEnd('\', '/').ToLowerInvariant()
        if ($normalized -and -not $seen.ContainsKey($normalized)) {
            $new += $entry.TrimEnd('\', '/')
            $seen[$normalized] = $true
        }
    }
    if (-not $new.Count) { return $Existing }
    if ($Existing) { return ($new -join ';') + ';' + $Existing }
    $new -join ';'
}

function Set-LabMachineEnvironment {
    param([string]$JavaHome, [string[]]$PathEntries)
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    try {
        $old = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = if ($key.GetValueNames() -contains 'Path') { $key.GetValueKind('Path') } else {
            [Microsoft.Win32.RegistryValueKind]::ExpandString }
        $new = Merge-LabPath -Existing $old -Additions $PathEntries
        if ($new.Length -gt 30000) { throw 'Machine PATH would exceed the supported length.' }
        if ($new -cne $old) { $key.SetValue('Path', $new, $kind) }
        $key.SetValue('JAVA_HOME', $JavaHome, [Microsoft.Win32.RegistryValueKind]::String)
    } finally { $key.Close() }
    $env:JAVA_HOME = $JavaHome
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not ('SchoolLab.NativeEnvironment' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SchoolLab {
    public static class NativeEnvironment {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w,
            string l, uint flags, uint timeout, out UIntPtr result);
    }
}
'@
    }
    $broadcast = [UIntPtr]::Zero
    [SchoolLab.NativeEnvironment]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero,
        'Environment', 2, 3000, [ref]$broadcast) | Out-Null
}

function Get-LabPendingReboot {
    $reasons = @()
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path -LiteralPath $key) { $reasons += $key }
    }
    $session = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    if (Get-LabProperty $session 'PendingFileRenameOperations') { $reasons += 'PendingFileRenameOperations' }
    $reasons
}

function Get-LabApplications {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (Test-Path -LiteralPath $root) {
            foreach ($key in Get-ChildItem -LiteralPath $root) {
                $app = Get-ItemProperty -LiteralPath $key.PSPath
                if ((Get-LabProperty $app 'DisplayName' '') -match 'Java|JDK|Temurin|Python|Visual Studio Code|Dev.C\+\+|Dev-Cpp|MinGW|TDM-GCC') {
                    [pscustomobject]@{ Name = $app.DisplayName; Version = Get-LabProperty $app 'DisplayVersion' '';
                        InstallLocation = Get-LabProperty $app 'InstallLocation' ''; RegistryKey = $key.Name }
                }
            }
        }
    }
}

function Get-LabMinGW {
    param([hashtable]$Config, [object[]]$Applications = @())
    $bins = @()
    if ($Config.MinGWBin) {
        $bins = @(Expand-LabPath $Config.MinGWBin)
    } else {
        $patterns = @($Config.MinGWSearchPatterns)
        foreach ($app in $Applications) {
            if ($app.Name -match 'Dev.C\+\+|Dev-Cpp|TDM-GCC|MinGW' -and $app.InstallLocation) {
                $patterns += (Join-Path $app.InstallLocation 'MinGW*\bin')
                $patterns += (Join-Path $app.InstallLocation 'TDM-GCC*\bin')
                $patterns += (Join-Path $app.InstallLocation 'bin')
            }
        }
        foreach ($pattern in $patterns) {
            $bins += @(Get-Item -Path (Expand-LabPath $pattern) -ErrorAction SilentlyContinue |
                Where-Object PSIsContainer | ForEach-Object FullName)
        }
    }
    $valid = @()
    foreach ($bin in ($bins | Sort-Object -Unique)) {
        $compiler = Join-Path $bin 'g++.exe'
        $debugger = Join-Path $bin 'gdb.exe'
        if ((Test-Path -LiteralPath $compiler) -and (Test-Path -LiteralPath $debugger)) {
            try {
                $target = Assert-LabCommand $compiler @('-dumpmachine')
                $version = Assert-LabCommand $compiler @('--version')
                $gdbVersion = Assert-LabCommand $debugger @('--version')
                if ($target -notmatch 'mingw|windows') { continue }
                $arch = if ($target -match 'x86_64') { 'x64' } elseif ($target -match 'i[3-6]86') { 'x86' } else { continue }
                $valid += [pscustomobject]@{ Bin = $bin; Gpp = $compiler; Gdb = $debugger;
                    Target = $target; Architecture = $arch; Version = $version; GdbVersion = $gdbVersion }
            } catch { Write-Warning "Rejected MinGW at ${bin}: $_" }
        }
    }
    if ($valid.Count -eq 0) { throw 'No working MinGW g++.exe + gdb.exe pair. Set MinGWBin in LabConfig.psd1.' }
    if ($valid.Count -gt 1) { throw "Multiple MinGW pairs found. Set MinGWBin explicitly: $($valid.Bin -join '; ')" }
    $valid[0]
}

function Get-LabDevCpp {
    param([hashtable]$Config, [object[]]$Applications = @())
    $roots = @((Expand-LabPath $Config.DevCppDirectory))
    foreach ($pattern in $Config.DevCppSearchPatterns) {
        $roots += @(Get-Item -Path (Expand-LabPath $pattern) -ErrorAction SilentlyContinue | Where-Object PSIsContainer | ForEach-Object FullName)
    }
    foreach ($app in $Applications) {
        if ($app.Name -match 'Dev.C\+\+|Dev-Cpp') {
            if ($app.InstallLocation) { $roots += $app.InstallLocation }
            $key = Get-Item -LiteralPath ('Registry::' + $app.RegistryKey) -ErrorAction SilentlyContinue
            if ($key) {
                $icon = [string]$key.GetValue('DisplayIcon','')
                $icon = ($icon -replace ',\d+$','').Trim('"')
                if ($icon) { $roots += Split-Path -Parent $icon }
            }
        }
    }
    foreach ($path in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
        $exe = Join-Path $path 'devcpp.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            return [pscustomobject]@{ Directory=$path; Executable=$exe; Version=(Get-Item -LiteralPath $exe).VersionInfo.FileVersion }
        }
    }
    return $null
}

function Write-LabJson {
    param([string]$Path, $Value)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Test-LabClassroomContext {
    $sessionId = (Get-Process -Id $PID).SessionId
    if ($sessionId -eq 0) { return $false }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($shell in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$sessionId")) {
        $owner = Invoke-CimMethod -InputObject $shell -MethodName GetOwnerSid
        if ($owner.ReturnValue -eq 0 -and $owner.Sid -eq $sid) { return $true }
    }
    return $false
}

function Get-LabExecutableVersion {
    param([string]$Path, [ValidateSet('Jdk', 'Python', 'VSCode')][string]$Kind)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        switch ($Kind) {
            Jdk {
                $text = Assert-LabCommand $Path @('-fullversion')
                if ($text -match 'version "([^"\s]+)') { return $Matches[1] }
            }
            Python {
                return (Assert-LabCommand $Path @('-I', '-c', 'import platform; print(platform.python_version())')).Trim()
            }
            VSCode {
                return (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
            }
        }
    } catch { return '' }
    return ''
}

function Get-LabVersionAction {
    param([string]$Installed, [string]$Required)
    if (-not $Installed) { return 'Install' }
    if ($Installed -ceq $Required) { return 'Skip' }
    $old = ConvertTo-LabVersion $Installed
    $new = ConvertTo-LabVersion $Required
    if ($old -gt $new) { throw "Refusing downgrade from $Installed to locked version $Required." }
    'Install'
}

function ConvertTo-LabVersion {
    param([string]$Value)
    $parts = @($Value.Split('+')[0].Split('.') | ForEach-Object { [int]$_ })
    while ($parts.Count -lt 3) { $parts += 0 }
    if ($Value.Contains('+')) { $parts += [int]($Value.Split('+')[1] -replace '-.*$', '') }
    while ($parts.Count -lt 4) { $parts += 0 }
    [version]($parts -join '.')
}

function Test-LabX64Executable {
    param([string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { return $false }
        $stream.Position = 0x3c
        $offset = $reader.ReadInt32()
        if ($offset -lt 0 -or $offset + 6 -gt $stream.Length) { return $false }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { return $false }
        $reader.ReadUInt16() -eq 0x8664
    } finally { $reader.Dispose() }
}

function Resolve-LabPackagePath {
    param([string]$Root, [string]$RelativePath)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if ([IO.Path]::IsPathRooted($RelativePath)) { throw "Absolute package path: $RelativePath" }
    $full = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw "Package path escapes root: $RelativePath" }
    $full
}

function Test-LabPackage {
    param([string]$Root, $Lock)
    if ($Lock.SchemaVersion -ne 1 -or $Lock.PSADTVersion -ne '4.1.8') { throw 'Unsupported package lock / PSADT version.' }
    if (@($Lock.Files).Count -eq 0) { throw 'Package lock is empty.' }
    foreach ($item in $Lock.Files) {
        $path = Resolve-LabPackagePath $Root $item.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing package file: $($item.Path)" }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.SHA256) {
            throw "SHA256 mismatch: $($item.Path)"
        }
    }
    foreach ($required in @('LabConfig.psd1','Lab.Core.psm1','Invoke-AppDeployToolkit.ps1','Initialize-LabUser.ps1',
        'PSAppDeployToolkit\PSAppDeployToolkit.psd1', $Lock.Components.Jdk.File,
        $Lock.Components.Python.File, $Lock.Components.VSCode.File)) {
        if (@($Lock.Files | Where-Object Path -eq $required).Count -ne 1) { throw "Unlocked required file: $required" }
    }
    $requiredIds = @(Get-LabProperty $Lock 'RequiredExtensionIds' @())
    $chrome = Get-LabProperty $Lock 'ChromeExtension'
    if ($chrome) {
        foreach ($required in @('Install-ChromeExtension.ps1','Update-SfitSchedule.ps1','Sfit.UiAutomation.cs','Sfit.Shortcut.cs','Chrome.Profile.psm1',
            'Files\Sfit.NativeHost.exe','Files\ChromeExtension\manifest.json','Files\ChromeExtension\config.js','Files\ChromeExtension\background.js')) {
            if (@($Lock.Files | Where-Object Path -eq $required).Count -ne 1) { throw "Unlocked Chrome extension file: $required" }
        }
        $record = @($Lock.Files | Where-Object Path -eq 'Files\ChromeExtension\config.js')
        if ($chrome.id -notmatch '^[a-p]{32}$' -or $record[0].SHA256 -ine $chrome.configSha256) { throw 'Invalid Chrome ID / config hash in lock.' }
    }
    if ($requiredIds.Count) {
        if (-not (Get-LabProperty $Lock.Components 'DevCpp')) { throw 'Missing locked Dev-C++ installer.' }
        $dev = $Lock.Components.DevCpp.File
        if (@($Lock.Files | Where-Object Path -eq $dev).Count -ne 1) { throw 'Unlocked Dev-C++ installer.' }
        foreach ($id in $requiredIds) {
            if (@($Lock.Extensions | Where-Object Id -eq $id).Count -ne 1) { throw "Missing required extension: $id" }
        }
        foreach ($extension in $Lock.Extensions) {
            $record = @($Lock.Files | Where-Object Path -eq $extension.File)
            if ($record.Count -ne 1 -or $record[0].SHA256 -ne $extension.SHA256) { throw "Unlocked VSIX: $($extension.Id)" }
        }
    }
}

function Get-LabVsixMetadata {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('extension/package.json')
        if (-not $entry) { throw "Invalid VSIX: $Path" }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { $json = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        $platform = ''
        $manifest = $zip.GetEntry('extension.vsixmanifest')
        if ($manifest) {
            $reader = New-Object IO.StreamReader($manifest.Open())
            try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $node = $xml.SelectSingleNode("//*[local-name()='Identity']")
            if ($node) { $platform = $node.GetAttribute('TargetPlatform') }
        }
        if (-not $platform) { $platform = Get-LabProperty (Get-LabProperty $json '__metadata') 'targetPlatform' '' }
        [pscustomobject]@{ Id = "$($json.publisher).$($json.name)"; Version = $json.version;
            Platform = $platform; Dependencies = @(Get-LabProperty $json 'extensionDependencies' @());
            ExtensionPack = @(Get-LabProperty $json 'extensionPack' @()); Engine = $json.engines.vscode }
    } finally { $zip.Dispose() }
}

function Get-LabExtensionOrder {
    param([object[]]$Extensions)
    $remaining = @($Extensions)
    $ordered = @()
    if (@($remaining.Id | Sort-Object -Unique).Count -ne $remaining.Count) { throw 'Duplicate extension IDs in package.' }
    foreach ($extension in $remaining) {
        foreach ($dependency in @($extension.Dependencies) + @($extension.ExtensionPack)) {
            if ($dependency -and $dependency -notin $remaining.Id) { throw "Missing offline VSIX dependency: $dependency (from $($extension.Id))" }
        }
    }
    while ($remaining.Count) {
        $ready = @($remaining | Where-Object {
            $orderedIds = @($ordered | ForEach-Object Id)
            # Packs may refer back to their parent (Python <-> Pylance). Only
            # HARD dependencies impose installation order; packs require closure.
            $unmet = @(@($_.Dependencies) | Where-Object { $_ -and $_ -notin $orderedIds })
            $unmet.Count -eq 0
        })
        if (-not $ready.Count) { throw 'Cyclic VSIX dependencies.' }
        $ordered += $ready
        $remaining = @($remaining | Where-Object { $_.Id -notin $ready.Id })
    }
    $ordered
}

function New-LabCppWorkspace {
    param([string]$Destination, $MinGW, [string]$Standard = 'c++17')
    New-Item -ItemType Directory -Path (Join-Path $Destination '.vscode') -Force | Out-Null
    $files = @{
        'main.cpp' = "#include <iostream>`nint main() { std::cout << `"SCHOOLLAB_CPP_OK`" << std::endl; return 0; }`n"
        '.vscode\tasks.json' = (@{ version = '2.0.0'; tasks = @(@{
            label = 'SchoolLab: build'; type = 'process'; command = $MinGW.Gpp
            args = @('-g', '-O0', "-std=$Standard", '${file}', '-o', '${fileDirname}\${fileBasenameNoExtension}.exe')
            options = @{ cwd = '${fileDirname}'; env = @{ PATH = $MinGW.Bin + ';${env:PATH}' } }
            problemMatcher = @('$gcc'); group = @{ kind = 'build'; isDefault = $true }
        }) } | ConvertTo-Json -Depth 12)
        '.vscode\launch.json' = (@{ version = '0.2.0'; configurations = @(@{
            name = 'SchoolLab: debug current C++ file'; type = 'cppdbg'; request = 'launch'
            program = '${fileDirname}\${fileBasenameNoExtension}.exe'; args = @(); stopAtEntry = $false
            cwd = '${fileDirname}'; externalConsole = $true; MIMode = 'gdb'; miDebuggerPath = $MinGW.Gdb
            preLaunchTask = 'SchoolLab: build'; environment = @(@{ name = 'PATH'; value = $MinGW.Bin + ';${env:PATH}' })
        }) } | ConvertTo-Json -Depth 12)
        '.vscode\c_cpp_properties.json' = (@{ version = 4; configurations = @(@{
            name = 'SchoolLab MinGW'; compilerPath = $MinGW.Gpp; includePath = @('${workspaceFolder}/**')
            defines = @(); cStandard = 'c17'; cppStandard = $Standard
            intelliSenseMode = 'windows-gcc-' + $MinGW.Architecture
        }) } | ConvertTo-Json -Depth 10)
        '.vscode\extensions.json' = '{"recommendations":["ms-vscode.cpptools"]}'
    }
    foreach ($name in $files.Keys) {
        $target = Join-Path $Destination $name
        # Never overwrite student work. Managed template is refreshed by the installer.
        if (-not (Test-Path -LiteralPath $target)) { [IO.File]::WriteAllText($target,$files[$name],(New-Object Text.UTF8Encoding($false))) }
    }
}

function New-LabLanguageWorkspaces {
    param([string]$Root, [string]$JavaHome, [string]$PythonHome, [string]$JavaVersion, $MinGW, [string]$Standard)
    $cpp = Join-Path $Root 'Cpp'
    New-LabCppWorkspace $cpp $MinGW $Standard
    $java = Join-Path $Root 'Java'
    $python = Join-Path $Root 'Python'
    foreach ($directory in @($java,$python)) { New-Item -ItemType Directory -Path (Join-Path $directory '.vscode') -Force | Out-Null }
    New-Item -ItemType Directory -Path (Join-Path $java 'out') -Force | Out-Null
    $jdkMajor = [int](($JavaVersion -split '[.+]')[0])
    $pythonExe = Join-Path $PythonHome 'python.exe'
    $javaTasks = @{version='2.0.0';tasks=@(
        @{label='SchoolLab: Java build';type='process';command=(Join-Path $JavaHome 'bin\javac.exe');
            args=@('-encoding','UTF-8','-d','${workspaceFolder}/out','${file}');options=@{cwd='${workspaceFolder}'};problemMatcher=@('$javac')},
        @{label='SchoolLab: Java run';type='process';command=(Join-Path $JavaHome 'bin\java.exe');
            args=@('-cp','${workspaceFolder}/out','${fileBasenameNoExtension}');dependsOn='SchoolLab: Java build';
            options=@{cwd='${workspaceFolder}'};problemMatcher=@();group=@{kind='build';isDefault=$true}}
    )}
    $javaSettings = @{'java.jdt.ls.java.home'=$JavaHome; 'java.configuration.runtimes'=@(@{name="JavaSE-$jdkMajor";path=$JavaHome;default=$true});
        'java.server.launchMode'='Standard';'java.import.maven.enabled'=$false;'java.import.gradle.enabled'=$false;
        'java.configuration.updateBuildConfiguration'='disabled';'java.debug.settings.console'='integratedTerminal';
        'java.project.outputPath'='out'; 'java.project.sourcePaths'=@('.')}
    $files = @{
        (Join-Path $java 'LabHello.java') = 'public class LabHello { public static void main(String[] args) { System.out.println("SCHOOLLAB_JAVA_OK"); } }'
        (Join-Path $java '.vscode\settings.json') = ($javaSettings | ConvertTo-Json -Depth 12)
        (Join-Path $java '.vscode\tasks.json') = ($javaTasks | ConvertTo-Json -Depth 12)
        (Join-Path $java '.vscode\extensions.json') = '{"recommendations":["redhat.java","vscjava.vscode-java-debug"]}'
        (Join-Path $java '.vscode\launch.json') = (@{version='0.2.0';configurations=@(@{name='SchoolLab: Java current file';type='java';
            request='launch';mainClass='${fileBasenameNoExtension}';classPaths=@('${workspaceFolder}/out');
            preLaunchTask='SchoolLab: Java build';console='integratedTerminal';cwd='${workspaceFolder}'})} | ConvertTo-Json -Depth 12)
        (Join-Path $python 'main.py') = 'print("SCHOOLLAB_PYTHON_OK")'
        (Join-Path $python '.vscode\settings.json') = (@{'python.defaultInterpreterPath'=$pythonExe;
            'python.terminal.activateEnvironment'=$false;'python.useEnvironmentsExtension'=$false;'python.analysis.typeCheckingMode'='basic'} | ConvertTo-Json)
        (Join-Path $python '.vscode\extensions.json') = '{"recommendations":["ms-python.python","ms-python.debugpy","ms-python.vscode-pylance"]}'
        (Join-Path $python '.vscode\launch.json') = (@{version='0.2.0';configurations=@(@{name='SchoolLab: Python current file';
            type='debugpy';request='launch';program='${file}';python=$pythonExe;console='integratedTerminal';cwd='${fileDirname}';justMyCode=$true})} | ConvertTo-Json -Depth 12)
        (Join-Path $python '.vscode\tasks.json') = (@{version='2.0.0';tasks=@(@{label='SchoolLab: Python run';type='process';
            command=$pythonExe;args=@('-u','${file}');options=@{cwd='${fileDirname}'};problemMatcher=@();group=@{kind='build';isDefault=$true}})} | ConvertTo-Json -Depth 12)
    }
    foreach ($path in $files.Keys) {
        # Windows PowerShell's UTF8 encoding adds a BOM; javac rejects that BOM.
        if (-not (Test-Path -LiteralPath $path)) { [IO.File]::WriteAllText($path,$files[$path],(New-Object Text.UTF8Encoding($false))) }
    }
    [pscustomobject]@{Cpp=$cpp;Java=$java;Python=$python}
}

function Test-LabToolchain {
    param([string]$JavaHome, [string]$PythonHome, $MinGW, [string]$Directory, [string]$Standard = 'c++17')
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Directory 'LabHello.java') -Encoding ASCII -Value @'
public class LabHello { public static void main(String[] args) { System.out.println("SCHOOLLAB_JAVA_OK"); } }
'@
    $java = Assert-LabCommand (Join-Path $JavaHome 'bin\javac.exe') @('LabHello.java') -WorkingDirectory $Directory
    $java = Assert-LabCommand (Join-Path $JavaHome 'bin\java.exe') @('-cp', $Directory, 'LabHello') 'SCHOOLLAB_JAVA_OK'
    $python = Assert-LabCommand (Join-Path $PythonHome 'python.exe') @('-I', '-c',
        'import struct, sys, venv; assert struct.calcsize("P")==8; print("SCHOOLLAB_PYTHON_OK")') 'SCHOOLLAB_PYTHON_OK'
    $pip = Assert-LabCommand (Join-Path $PythonHome 'python.exe') @('-I', '-m', 'pip', '--version') 'pip '
    $plainPython = Assert-LabCommand (Join-Path $PythonHome 'python.exe') @('-c',
        'import sys, struct; assert struct.calcsize("P")==8; print("SCHOOLLAB_PYTHON_PLAIN_OK")') 'SCHOOLLAB_PYTHON_PLAIN_OK'
    $plainPip = Assert-LabCommand (Join-Path $PythonHome 'python.exe') @('-m','pip','--version') 'pip '
    $cppTest = Test-LabCppToolchain -MinGW $MinGW -Directory $Directory -Standard $Standard
    [pscustomobject]@{ Java = $java; Python = $python; Pip = $pip; PlainPython=$plainPython; PlainPip=$plainPip; Cpp = $cppTest.Cpp; Gdb = $cppTest.Gdb }
}

function Resolve-LabCppStandard {
    param($MinGW, [string]$Requested, [string]$Directory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Directory 'standard.cpp') -Value 'int main() { return 0; }' -Encoding ASCII
    $standards = if ($Requested -eq 'Auto') { @('c++17','c++14','c++11') } else { @($Requested) }
    foreach ($standard in $standards) {
        $probe = Invoke-LabCommand $MinGW.Gpp @("-std=$standard", '-fsyntax-only', 'standard.cpp') -WorkingDirectory $Directory
        if ($probe.ExitCode -eq 0) { return $standard }
    }
    throw "Compiler cannot support requested C++ standard '$Requested': $($MinGW.Gpp)"
}

function Test-LabCppToolchain {
    param($MinGW, [string]$Directory, [string]$Standard = 'c++17')
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Directory 'hello.cpp') -Encoding ASCII -Value @'
#include <iostream>
int main() { std::cout << "SCHOOLLAB_CPP_OK" << std::endl; return 0; }
'@
    $compiled = Assert-LabCommand $MinGW.Gpp @('-g', '-O0', "-std=$Standard", 'hello.cpp', '-o', 'hello.exe') -WorkingDirectory $Directory
    $cpp = Assert-LabCommand (Join-Path $Directory 'hello.exe') @() 'SCHOOLLAB_CPP_OK' -WorkingDirectory $Directory
    # Require a real breakpoint and program run, not just a gdb --version response.
    $debug = Assert-LabCommand $MinGW.Gdb @('--batch', '-ex', 'set pagination off', '-ex', 'break main',
        '-ex', 'run', '-ex', 'bt', '-ex', 'continue', (Join-Path $Directory 'hello.exe')) 'Breakpoint 1.*main' -WorkingDirectory $Directory
    if ($debug -notmatch 'SCHOOLLAB_CPP_OK' -or $debug -notmatch 'exited normally') { throw "GDB smoke test failed: $debug" }
    [pscustomobject]@{ Cpp = $cpp; Gdb = $debug }
}

function Invoke-LabCode {
    param([string]$CodeDirectory, [string[]]$Arguments)
    $layout = Get-LabCodeLayout $CodeDirectory
    Invoke-LabCommand -FilePath (Join-Path $CodeDirectory 'Code.exe') -Arguments (
        @($layout.CliPath) + $Arguments) -TimeoutSeconds 180 -Environment @{
        ELECTRON_RUN_AS_NODE = '1'; VSCODE_CLI = '1'; VSCODE_DEV = ''; VSCODE_IPC_HOOK_CLI = ''
    }
}

function Get-LabCodeLayout {
    param([string]$CodeDirectory)
    # New Windows releases keep resources in a commit-named subdirectory. Read
    # the installed vendor launcher to select the CURRENT CLI, not a stale one.
    $bin = Join-Path $CodeDirectory 'bin'
    $launcher = Get-Content -LiteralPath (Join-Path $bin 'code.cmd') -Raw
    if ($launcher -notmatch '%~dp0(?<relative>\.\.[\\/][^"\r\n]*resources[\\/]app[\\/]out[\\/]cli\.js)') {
        throw 'Unrecognized VS Code Windows CLI layout. Review bin\code.cmd.'
    }
    $path = [IO.Path]::GetFullPath((Join-Path $bin $Matches.relative))
    $root = [IO.Path]::GetFullPath($CodeDirectory).TrimEnd('\') + '\'
    if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path)) {
        throw 'VS Code CLI path is missing or outside the installation directory.'
    }
    [pscustomobject]@{ CliPath = $path; AppRoot = Split-Path -Parent (Split-Path -Parent $path) }
}

Export-ModuleMember -Function *-Lab*
