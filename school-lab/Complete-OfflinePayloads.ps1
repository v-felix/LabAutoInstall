#requires -Version 5.1
<# Add Dev-C++ and the complete Java/Python VSIX dependency closure to pinned base downloads. #>
[CmdletBinding()]
param([string]$Destination = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $Destination) { $Destination = Join-Path $PSScriptRoot 'downloads\current' }
$Destination = (Resolve-Path -LiteralPath $Destination).Path
Import-Module (Join-Path $PSScriptRoot 'package\Lab.Core.psm1') -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$lockPath = Join-Path $Destination 'sources-lock.json'
$sources = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
function Save-Sources { $sources | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $lockPath -Encoding UTF8 }
function Save-Asset($Asset) {
    $target = Resolve-LabPackagePath $Destination $Asset.File
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "Downloading $($Asset.Name) $($Asset.Version)"
        Invoke-WebRequest -Uri $Asset.Url -OutFile ($target + '.partial') -UseBasicParsing -TimeoutSec 1200
        if ((Get-FileHash -LiteralPath ($target + '.partial')).Hash -ne $Asset.SHA256) { throw "Publisher hash mismatch: $($Asset.Name)" }
        Move-Item -LiteralPath ($target + '.partial') -Destination $target
    }
    if ((Get-FileHash -LiteralPath $target).Hash -ne $Asset.SHA256) { throw "Cached hash mismatch: $($Asset.Name)" }
}
$dev = @($sources.Assets | Where-Object Name -eq 'DevCpp')
if (-not $dev.Count) {
    # Release URL is from Embarcadero; independent hash matches Microsoft's winget manifest.
    $sources.Assets += [pscustomobject]@{ Name='DevCpp'; Version='6.3'; File='devcpp.exe';
        Url='https://github.com/Embarcadero/Dev-Cpp/releases/download/v6.3/Embarcadero_Dev-Cpp_6.3_TDM-GCC_9.2_Setup.exe';
        SHA256='9EA2F0237E5C72D485F9FA29DEF3F0A11C51F8B252F650BE533E09A5E2ADA247' }
    Save-Sources
}
Save-Asset ($sources.Assets | Where-Object Name -eq 'DevCpp')
$queue = New-Object 'Collections.Generic.Queue[string]'
foreach ($id in @('ms-vscode.cpptools','redhat.java','vscjava.vscode-java-debug','ms-python.python','ms-python.debugpy','ms-python.vscode-pylance','formulahendry.code-runner')) { $queue.Enqueue($id) }
$seen = @{}
while ($queue.Count) {
    $id = $queue.Dequeue()
    if ($seen.ContainsKey($id)) { continue }
    $asset = $null
    foreach ($item in @($sources.Assets | Where-Object File -Like '*.vsix')) {
        $file = Join-Path $Destination $item.File
        if ((Test-Path -LiteralPath $file) -and (Get-LabVsixMetadata $file).Id -eq $id) { $asset = $item; break }
        if ($item.Name -eq "Extension:$id") { $asset = $item; break }
    }
    if (-not $asset) {
        $body = @{filters=@(@{criteria=@(@{filterType=7;value=$id});pageNumber=1;pageSize=1});flags=147} | ConvertTo-Json -Depth 8
        $query = Invoke-RestMethod 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' -Method Post `
            -ContentType 'application/json' -Headers @{Accept='application/json;api-version=7.2-preview.1'} -Body $body
        $versions = @($query.results[0].extensions[0].versions | Where-Object {
            $_.targetPlatform -in @('win32-x64','universal',$null,'') -and
            -not (@($_.properties | Where-Object { $_.key -eq 'Microsoft.VisualStudio.Code.PreRelease' -and $_.value -eq 'true' }).Count)
        })
        $selected = $versions | Select-Object -First 1
        if (-not $selected) { throw "No stable Windows x64/universal VSIX: $id" }
        $same = @($versions | Where-Object version -eq $selected.version)
        $native = $same | Where-Object targetPlatform -eq 'win32-x64' | Select-Object -First 1
        if ($native) { $selected = $native }
        $url = ($selected.files | Where-Object assetType -eq 'Microsoft.VisualStudio.Services.VSIXPackage' | Select-Object -First 1).source
        $hash = ($selected.properties | Where-Object key -eq 'Microsoft.VisualStudio.Services.VsixSha256' | Select-Object -First 1).value
        if (-not $url -or $hash -notmatch '^[a-fA-F0-9]{64}$') { throw "Missing publisher package/hash: $id" }
        $asset = [pscustomobject]@{Name="Extension:$id";Version=$selected.version;File=($id + '.vsix');Url=$url;SHA256=$hash}
        $sources.Assets += $asset
        Save-Sources
    }
    Save-Asset $asset
    $metadata = Get-LabVsixMetadata (Join-Path $Destination $asset.File)
    if ($metadata.Id -ne $id) { throw "Unexpected VSIX identity for $id" }
    $seen[$id] = $true
    foreach ($dependency in @($metadata.Dependencies) + @($metadata.ExtensionPack)) { if ($dependency) { $queue.Enqueue($dependency) } }
    Write-Host "Ready: $id $($metadata.Version) [$($metadata.Platform)]"
}
Write-Host 'Complete offline dependency closure is ready.'
