#requires -Version 5.1
[CmdletBinding()]
param([string]$PayloadDirectory = '', [string]$OutputDirectory = '', [string]$ExtensionSourceDirectory = '')
$ErrorActionPreference = 'Stop'
if (-not $ExtensionSourceDirectory) { $ExtensionSourceDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) '1-sfit-tracker' }
if (-not $PayloadDirectory) { $PayloadDirectory = Join-Path $PSScriptRoot 'downloads\current' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot ('dist\SchoolLab-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
Import-Module (Join-Path $PSScriptRoot 'package\Lab.Core.psm1') -Force
$sources = Get-Content -LiteralPath (Join-Path $PayloadDirectory 'sources-lock.json') -Raw | ConvertFrom-Json
if ($sources.SchemaVersion -ne 1) { throw 'Unsupported sources lock.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'OutputDirectory must be new; never modify a released package in place.' }
foreach ($name in @('PSADT','DevCpp','Jdk','Python','VSCode','CppTools')) {
    if (@($sources.Assets | Where-Object Name -eq $name).Count -ne 1) { throw "Need exactly one source entry: $name" }
}
foreach ($asset in $sources.Assets) {
    $file = Resolve-LabPackagePath $PayloadDirectory $asset.File
    if ($asset.SHA256 -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $asset.SHA256) {
        throw "Invalid source hash: $($asset.File). Complete Get-OfflinePayloads first."
    }
    if ($asset.Name -in @('Jdk','Python','VSCode')) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        $publisher = switch ($asset.Name) { Jdk { 'Eclipse' }; Python { 'Python Software Foundation' }; VSCode { 'Microsoft Corporation' } }
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch [regex]::Escape($publisher)) {
            throw "Signature/publisher check failed for $($asset.Name): $($signature.Status) $($signature.SignerCertificate.Subject)"
        }
    }
}
$codeSource = $sources.Assets | Where-Object Name -eq 'VSCode'
if ($codeSource.Url -notmatch '/VSCodeSetup-x64-') { throw 'Require Stable System Installer source, not User Setup or Insiders.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$toolkit = $sources.Assets | Where-Object Name -eq 'PSADT'
if ($toolkit.Version -ne '4.1.8') { throw 'Require PSADT 4.1.8 template v4 release.' }
Expand-Archive -LiteralPath (Join-Path $PayloadDirectory $toolkit.File) -DestinationPath $OutputDirectory
$manifest = Join-Path $OutputDirectory 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
if (-not (Test-Path -LiteralPath $manifest) -or (Import-PowerShellDataFile $manifest).ModuleVersion -ne '4.1.8') {
    throw 'Unexpected PSADT archive layout/version. Use Template_v4 release ZIP, not GitHub source ZIP.'
}
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'package') -File | Copy-Item -Destination $OutputDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.vi.md') -Destination $OutputDirectory
# Keep deployment instructions short; detailed engineering notes stay in source.
$components = [ordered]@{}
foreach ($name in @('DevCpp','Jdk','Python','VSCode')) {
    $asset = $sources.Assets | Where-Object Name -eq $name
    $relative = 'Files\' + $asset.File
    Copy-Item -LiteralPath (Join-Path $PayloadDirectory $asset.File) -Destination (Join-Path $OutputDirectory $relative)
    $components[$name] = @{ Version = $asset.Version; File = $relative; SourceUrl = $asset.Url }
}
New-Item -ItemType Directory -Path (Join-Path $OutputDirectory 'Files\Extensions') -Force | Out-Null
$extensions = @()
foreach ($asset in ($sources.Assets | Where-Object { $_.File -like '*.vsix' })) {
    $source = Join-Path $PayloadDirectory $asset.File
    $metadata = Get-LabVsixMetadata $source
    if ($metadata.Engine -notmatch '^\^?(\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?$') { throw "Review unsupported VS Code engine range: $($metadata.Engine)" }
    $minimumCode = [version]$Matches[1]
    if ([version]$components.VSCode.Version -lt $minimumCode -or [version]$components.VSCode.Version -ge [version]("{0}.0.0" -f ($minimumCode.Major + 1))) {
        throw "VSIX $($metadata.Id) requires VS Code $($metadata.Engine), selected $($components.VSCode.Version)."
    }
    if ($metadata.Platform -notin @('win32-x64','universal','')) { throw "Wrong VSIX platform: $($metadata.Id) $($metadata.Platform)" }
    if ($metadata.Id -eq 'ms-vscode.cpptools' -and $metadata.Platform -ne 'win32-x64') { throw 'C/C++ VSIX must be win32-x64.' }
    $relative = 'Files\Extensions\' + [IO.Path]::GetFileName($source)
    Copy-Item -LiteralPath $source -Destination (Join-Path $OutputDirectory $relative)
    $metadata | Add-Member NoteProperty File $relative
    $metadata | Add-Member NoteProperty SHA256 $asset.SHA256
    $extensions += $metadata
}
if ('ms-vscode.cpptools' -notin $extensions.Id) { throw 'Missing Microsoft C/C++ VSIX.' }
$config = Import-PowerShellDataFile (Join-Path $OutputDirectory 'LabConfig.psd1')
foreach ($id in $config.RequiredExtensionIds) {
    if ($id -notin $extensions.Id) { throw "Missing required language extension: $id" }
}
$extensions = @(Get-LabExtensionOrder $extensions)
$chromeExtension = $null
if ($config.EnableChromeExtension) {
    $metadataText = & node (Join-Path $PSScriptRoot 'Validate-Sfit.js') $ExtensionSourceDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Invalid SFIT config.js or manifest. Fix source before building.' }
    $chromeExtension = $metadataText | ConvertFrom-Json
    $target = Join-Path $OutputDirectory 'Files\ChromeExtension'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($name in @('manifest.json','config.js','core.js','background.js','content-script.js','block.html','block.js','status.html','status.js','ui.css','logo.png','deployment.json')) {
        Copy-Item -LiteralPath (Join-Path $ExtensionSourceDirectory $name) -Destination $target
    }
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:exe '/reference:System.Web.Extensions.dll' ("/out:" + (Join-Path $OutputDirectory 'Files\Sfit.NativeHost.exe')) (Join-Path $PSScriptRoot 'package\Sfit.NativeHost.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot build SFIT native messaging bridge.' }
}
$files = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse | ForEach-Object {
    @{ Path = $_.FullName.Substring($OutputDirectory.Length + 1); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
$lock = [ordered]@{ SchemaVersion = 1; PackageId = (Get-Date -Format 'yyyyMMdd') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8);
    PSADTVersion = '4.1.8'; CreatedAt = (Get-Date -Format o); Components = $components; Extensions = $extensions;
    RequiredExtensionIds=@($config.RequiredExtensionIds); ChromeExtension=$chromeExtension; Files = $files }
$lock | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'package-lock.json') -Encoding UTF8
Test-LabPackage $OutputDirectory (Get-Content -LiteralPath (Join-Path $OutputDirectory 'package-lock.json') -Raw | ConvertFrom-Json)
Write-Host "Offline package verified: $OutputDirectory"
Write-Host 'Copy the whole folder to USB / read-only LAN share. Run Install-Lab.cmd on a pilot workstation.'
