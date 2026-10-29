#requires -Version 5.1
<# Run on ONE connected preparation machine. Downloads files; does not install. #>
[CmdletBinding()]
param([string]$Destination = '')
$ErrorActionPreference = 'Stop'
if (-not $Destination) { $Destination = Join-Path $PSScriptRoot 'downloads\current' }
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module (Join-Path $PSScriptRoot 'package\Lab.Core.psm1') -Force
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$Destination = (Resolve-Path -LiteralPath $Destination).Path
$sourceLockPath = Join-Path $Destination 'sources-lock.json'

function Get-LabAsset {
    param([string]$Url, [string]$File, [string]$SHA256 = '')
    $target = Join-Path $Destination $File
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "Downloading $File"
        $partial = $target + '.partial'
        Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing -TimeoutSec 1200
        if ($SHA256 -and (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $SHA256) {
            throw "Publisher SHA256 mismatch: $File"
        }
        Move-Item -LiteralPath $partial -Destination $target
    }
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($SHA256 -and $hash -ne $SHA256) { throw "Cached file hash mismatch: $File" }
    $hash
}

if (Test-Path -LiteralPath $sourceLockPath) {
    # Resume EXACT versions. To choose newer releases, use a new Destination.
    $sources = Get-Content -LiteralPath $sourceLockPath -Raw | ConvertFrom-Json
    foreach ($asset in $sources.Assets) {
        $asset.SHA256 = Get-LabAsset $asset.Url $asset.File $asset.SHA256
        $sources | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sourceLockPath -Encoding UTF8
    }
    Write-Host "Using existing pinned downloads: $sourceLockPath"
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Complete-OfflinePayloads.ps1') -Destination $Destination
    if ($LASTEXITCODE -ne 0) { throw 'Completing offline payloads failed.' }
    exit 0
}

$available = Invoke-RestMethod 'https://api.adoptium.net/v3/info/available_releases'
$jdkMajor = ($available.available_releases | Measure-Object -Maximum).Maximum
$jdk = @(Invoke-RestMethod ("https://api.adoptium.net/v3/assets/latest/$jdkMajor/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"))[0]
if (-not $jdk.binary.installer.link) { throw 'Latest GA Temurin release has no Windows x64 MSI.' }
$pythonReleases = Invoke-RestMethod 'https://www.python.org/api/v2/downloads/release/?is_published=true'
$python = $pythonReleases | Where-Object { $_.name -match '^Python 3\.[0-9]+\.[0-9]+$' -and -not $_.pre_release } |
    Sort-Object { [version]($_.name -replace '^Python ', '') } -Descending | Select-Object -First 1
$pythonVersion = $python.name -replace '^Python ', ''
$releaseId = ($python.resource_uri.TrimEnd('/') -split '/')[-1]
$pythonFiles = Invoke-RestMethod ("https://www.python.org/api/v2/downloads/release_file/?release=$releaseId")
$pythonFile = $pythonFiles | Where-Object { $_.url -eq "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe" } | Select-Object -First 1
if (-not $pythonFile -or -not $pythonFile.sha256_sum) {
    throw 'Latest Python has no full x64 EXE + SHA256. Review its new deployment format; do not silently use an older version.'
}
$code = Invoke-RestMethod 'https://update.code.visualstudio.com/api/update/win32-x64/stable/latest'
if ($code.url -notmatch '/VSCodeSetup-x64-' -or -not $code.sha256hash) { throw 'Not a VS Code Stable x64 System Installer.' }
$toolkit = Invoke-RestMethod 'https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/tags/4.1.8'
$toolkitAsset = $toolkit.assets | Where-Object name -eq 'PSAppDeployToolkit_Template_v4.zip'
$cpp = Invoke-RestMethod 'https://api.github.com/repos/microsoft/vscode-cpptools/releases/latest'
if ($cpp.prerelease -or $cpp.draft) { throw 'C/C++ release is not stable.' }
$cppAsset = $cpp.assets | Where-Object name -eq 'cpptools-windows-x64.vsix'
if (-not $cppAsset) { throw 'Stable C/C++ release has no Windows x64 VSIX.' }
$assets = @(
    [pscustomobject]@{ Name = 'PSADT'; Version = '4.1.8'; File = 'psadt.zip'; Url = $toolkitAsset.browser_download_url; SHA256 = ((Get-LabProperty $toolkitAsset 'digest' '') -replace '^sha256:', '') }
    [pscustomobject]@{ Name = 'Jdk'; Version = $jdk.version.openjdk_version; File = 'jdk.msi'; Url = $jdk.binary.installer.link; SHA256 = $jdk.binary.installer.checksum }
    [pscustomobject]@{ Name = 'Python'; Version = $pythonVersion; File = 'python.exe'; Url = $pythonFile.url; SHA256 = $pythonFile.sha256_sum }
    [pscustomobject]@{ Name = 'VSCode'; Version = $code.productVersion; File = 'vscode.exe'; Url = $code.url; SHA256 = $code.sha256hash }
    [pscustomobject]@{ Name = 'CppTools'; Version = $cpp.tag_name.TrimStart('v'); File = 'cpptools-win32-x64.vsix'; Url = $cppAsset.browser_download_url; SHA256 = ((Get-LabProperty $cppAsset 'digest' '') -replace '^sha256:', '') }
)
# Persist resolved URLs and publisher hashes BEFORE downloads, allowing exact resume.
$sources = [pscustomobject]@{ SchemaVersion = 1; ResolvedAt = (Get-Date -Format o); Assets = $assets }
$sources | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sourceLockPath -Encoding UTF8
foreach ($asset in $assets) {
    $asset.SHA256 = Get-LabAsset $asset.Url $asset.File $asset.SHA256
    $sources | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sourceLockPath -Encoding UTF8
}
$assets | Select-Object Name,Version,File | Format-Table -AutoSize
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Complete-OfflinePayloads.ps1') -Destination $Destination
if ($LASTEXITCODE -ne 0) { throw 'Completing offline payloads failed.' }
Write-Host "Downloads ready. Next: .\Build-OfflinePackage.ps1 -PayloadDirectory `"$Destination`""
