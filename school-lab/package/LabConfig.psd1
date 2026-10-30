@{
    # Edit before building; the builder hashes this file into the package lock.
    PackageRevision = '2.5.0'
    EnableChromeExtension = $true
    ChromeExtensionDirectory = '%ProgramFiles%\SchoolLab\ChromeExtension\OLBDB'
    ChromeExecutable = '' # Empty: discover Chrome Stable in standard locations.
    # Preserve every existing profile; provision/reuse our own exam profile.
    # Its unique directory is recorded per Windows account, not guessed by name.
    ChromeProfileDirectory = 'Dedicated'
    ChromeProfileName = 'OLBDB'
    ChromeAutomationTimeoutSeconds = 120
    MinimumFreeGB = 7
    BlockOnPendingReboot = $true
    InstallerTimeoutMinutes = 45
    # Existing installations are reused only when their exact locked version matches.
    # A newer managed version is never silently downgraded.
    JdkDirectory = '%ProgramFiles%\SchoolLab\JDK'
    PythonDirectory = '%ProgramFiles%\SchoolLab\Python'
    VSCodeDirectory = '%ProgramFiles%\Microsoft VS Code'
    SupportDirectory = '%ProgramFiles%\SchoolLab\Support'
    DevCppDirectory = '%ProgramFiles(x86)%\Embarcadero\Dev-Cpp'
    DevCppSearchPatterns = @('%ProgramFiles(x86)%\Dev-Cpp', '%ProgramFiles%\Dev-Cpp',
        '%ProgramFiles(x86)%\Embarcadero\Dev-Cpp', '%ProgramFiles%\Embarcadero\Dev-Cpp', 'C:\Dev-Cpp')
    RequiredExtensionIds = @('ms-vscode.cpptools','redhat.java','vscjava.vscode-java-debug',
        'ms-python.python','ms-python.debugpy','ms-python.vscode-pylance')
    # Specify the FULL bin directory if automatic discovery is ambiguous.
    MinGWBin = ''
    MinGWSearchPatterns = @(
        '%ProgramFiles%\Dev-Cpp\MinGW*\bin'
        '%ProgramFiles%\Dev-Cpp\TDM-GCC*\bin'
        '%ProgramFiles(x86)%\Dev-Cpp\MinGW*\bin'
        '%ProgramFiles(x86)%\Dev-Cpp\TDM-GCC*\bin'
        'C:\Dev-Cpp\MinGW*\bin'
        'C:\Dev-Cpp\TDM-GCC*\bin'
        'C:\Program Files (x86)\Embarcadero\Dev-Cpp\TDM-GCC*\bin'
        'C:\TDM-GCC*\bin'
        'C:\MinGW\bin'
    )
    # Prefer C++17; fall back to C++14/C++11 for older Dev-C++ compilers.
    # Set c++17 explicitly when the curriculum requires it (fail instead of fallback).
    CppStandard = 'Auto'
    # Persistent user initialization handles first use AND existing default profiles.
    # Add existing named VS Code profiles here. Names are passed to the supported CLI.
    AdditionalVSCodeProfiles = @()
    # Bootstrap is supplemental: only users launching VS Code for the first time benefit.
    EnableExtensionBootstrap = $true
    # Keep the approved versions until IT builds a new package.
    PinVSCodeUpdates = $true
}
