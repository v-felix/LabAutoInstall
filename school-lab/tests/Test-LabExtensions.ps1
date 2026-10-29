#requires -Version 5.1
<# Installs VSIXs only into isolated test folders, never the teacher's real profile. #>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CodeDirectory, [string]$PayloadDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if (-not $PayloadDirectory) { $PayloadDirectory=Join-Path $root 'downloads\current' }
Import-Module (Join-Path $root 'package\Lab.Core.psm1') -Force
$scratch=Join-Path $root ('test-results\extensions-'+[guid]::NewGuid().ToString('N'))
$userData=Join-Path $scratch 'UserData'
$extensionDir=Join-Path $scratch 'Extensions'
New-Item -ItemType Directory -Path (Join-Path $userData 'User') -Force | Out-Null
# Any accidental marketplace dependency download should fail through this proxy.
@{'http.proxy'='http://127.0.0.1:9';'http.proxySupport'='override';'extensions.autoUpdate'='off';'update.mode'='none'} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $userData 'User\settings.json') -Encoding UTF8
$sources=Get-Content -LiteralPath (Join-Path $PayloadDirectory 'sources-lock.json') -Raw | ConvertFrom-Json
$catalog=@()
foreach ($asset in ($sources.Assets | Where-Object File -Like '*.vsix')) {
    $file=Join-Path $PayloadDirectory $asset.File
    if ((Get-FileHash -LiteralPath $file).Hash -ne $asset.SHA256) { throw 'VSIX source hash mismatch' }
    $meta=Get-LabVsixMetadata $file
    $meta | Add-Member NoteProperty File $file
    $catalog += $meta
}
$ordered=@(Get-LabExtensionOrder $catalog)
$isolation=@('--user-data-dir',$userData,'--extensions-dir',$extensionDir)
foreach ($extension in $ordered) {
    Write-Host "Testing offline VSIX: $($extension.Id) $($extension.Version)"
    $result=Invoke-LabCode $CodeDirectory (@('--install-extension',$extension.File,'--force','--do-not-include-pack-dependencies')+$isolation)
    Add-Content -LiteralPath (Join-Path $scratch 'cli.log') -Value ($result.StdOut+$result.StdErr)
    if ($result.ExitCode -ne 0) { throw "VSIX test failed: $($extension.Id) $($result.StdErr) $($result.StdOut)" }
}
$list=Invoke-LabCode $CodeDirectory (@('--list-extensions','--show-versions')+$isolation)
if ($list.ExitCode -ne 0) { throw 'List extensions failed' }
$installed=@($list.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() })
foreach ($extension in $ordered) {
    if ("$($extension.Id)@$($extension.Version)" -notin $installed) { throw "Missing extension after CLI install: $($extension.Id)" }
}
@{Status='Passed';CodeVersion=(Get-LabExecutableVersion (Join-Path $CodeDirectory 'Code.exe') VSCode);
    Extensions=$installed;UserData=$userData;ExtensionsDirectory=$extensionDir;At=(Get-Date -Format o)} |
    ForEach-Object { Write-LabJson (Join-Path $scratch 'result.json') $_ }
Write-Host "PASS: $($ordered.Count) offline VSIXs installed and verified in isolated folders. $scratch"
