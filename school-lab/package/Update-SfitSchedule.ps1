#requires -Version 5.1
[CmdletBinding()]
param([string]$PackageRoot = '')
$ErrorActionPreference = 'Stop'
# ProcessStartInfo callers can inherit PowerShell 7's PSModulePath. Always use
# this engine's inbox Utility module (Get-FileHash is a module function on 5.1).
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -Force
if (-not $PackageRoot) { $PackageRoot = $PSScriptRoot }
$lockPath = Join-Path $PackageRoot 'package-lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
if (-not $lock.ChromeExtension) { exit 0 }
$relative = 'Files\ChromeExtension\config.js'
$path = Join-Path $PackageRoot $relative
$hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -eq $lock.ChromeExtension.configSha256) { exit 0 }
# Allow only the explicitly documented mutable config, never rehash altered code.
foreach ($entry in $lock.Files) {
    if ($entry.Path -eq $relative) { continue }
    $item = [IO.Path]::GetFullPath((Join-Path $PackageRoot $entry.Path))
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\') + '\'
    if (-not $item.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $item -PathType Leaf) -or
        (Get-FileHash -LiteralPath $item -Algorithm SHA256).Hash -ine $entry.SHA256) { throw "Other package file changed or missing: $($entry.Path). Rebuild from source." }
}
$source = Get-Content -LiteralPath $path -Raw -Encoding UTF8
if ($source -notmatch '(?s)\A\s*/\*(?:(?!\*/).)*\*/\s*globalThis\.SFIT_CONFIG\s*=\s*Object\.freeze\((\{.*\})\);\s*\z') { throw 'config.js must contain one header comment and one Object.freeze(JSON) assignment. No executable statements.' }
$c = $Matches[1] | ConvertFrom-Json
foreach ($name in @('startAt','endAt')) {
    if ($c.$name -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$') { throw "Need an explicit timezone in $name" }
}
$formats = [string[]]@("yyyy-MM-dd'T'HH:mm:sszzz","yyyy-MM-dd'T'HH:mm:ss'Z'")
$start = [datetimeoffset]::ParseExact($c.startAt,$formats,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal)
$end = [datetimeoffset]::ParseExact($c.endAt,$formats,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal)
if ($end -le $start) { throw 'endAt must be later than startAt.' }
foreach ($key in @('enabled','singleExamTab','autoOpenExam','hideChatbox')) { if ($c.$key -isnot [bool]) { throw "Invalid boolean: $key" } }
if ($c.allowedHosts -isnot [array] -or $c.resourceHosts -isnot [array]) { throw 'allowedHosts and resourceHosts must be JSON arrays.' }
if ($c.networkMode -notin @('navigation','strict') -or $c.maxLogEntries -isnot [ValueType] -or
    $c.maxLogEntries -lt 10 -or $c.maxLogEntries -gt 1000 -or [math]::Floor([double]$c.maxLogEntries) -ne $c.maxLogEntries) { throw 'Invalid network mode / log limit.' }
foreach ($hostName in @($c.allowedHosts) + @($c.resourceHosts)) { if ($hostName -notmatch '^(?!\.)(?!.*\.\.)(?!.*\.$)[a-zA-Z0-9.-]+$') { throw 'Use exact hostnames, not URLs or wildcard patterns.' } }
$url = [uri]$c.examUrl
if ($url.Scheme -notin @('http','https') -or $url.Host -notin @($c.allowedHosts) -or $url.UserInfo) { throw 'examUrl must match allowedHosts and have no credentials.' }
if (-not $lock.PSObject.Properties['BasePackageId']) { $lock | Add-Member NoteProperty BasePackageId $lock.PackageId }
$lock.PackageId = $lock.BasePackageId + '-sfit-' + $hash.Substring(0,8)
$lock.ChromeExtension.configSha256 = $hash
$lock.ChromeExtension.startAt = $c.startAt; $lock.ChromeExtension.endAt = $c.endAt
$lock.ChromeExtension.enabled = $c.enabled
$lock.ChromeExtension | Add-Member NoteProperty examUrl $c.examUrl -Force
$lock.ChromeExtension | Add-Member NoteProperty allowedHosts @($c.allowedHosts) -Force
$now = [datetimeoffset]::UtcNow
$lock.ChromeExtension.phase = if (-not $c.enabled) {'DISABLED'} elseif ($now -lt $start) {'WAITING'} elseif ($now -lt $end) {'ACTIVE'} else {'ENDED'}
$record = @($lock.Files | Where-Object Path -eq $relative)
if ($record.Count -ne 1) { throw 'Missing unique config.js lock entry.' }
$record[0].SHA256 = $hash
$temporary = $lockPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temporary,($lock | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $lockPath -Force
Write-Host "SFIT schedule accepted: $($c.startAt) -> $($c.endAt). PackageId=$($lock.PackageId)"
