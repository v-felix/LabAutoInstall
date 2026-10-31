#requires -Version 5.1
<# Run manually after reviewing the listed paths. Without -Apply, list only. #>
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference='Stop'
try {
    $workspaceRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
    $currentRelease=Join-Path $workspaceRoot 'school-lab\dist\SchoolLab-2.7.1-20261031'
    $relativeTargets=@(
        'school-lab\dist\SchoolLab-2.4.0-20261030'
        'school-lab\dist\SchoolLab-2.5.0-20261030'
        'school-lab\dist\SchoolLab-2.5.1-20261031'
        'school-lab\dist\SchoolLab-2.6.0-20261031'
        'school-lab\dist\SchoolLab-2.6.1-20261031'
        'school-lab\dist\SchoolLab-2.6.2-20261031'
        'school-lab\dist\SchoolLab-2.6.3-20261031'
        'school-lab\dist\SchoolLab-2.7.0-20261031'
        'school-lab\test-results'
    )
    function Assert-PlainPath([string]$Path) {
        $parent=[IO.Path]::GetFullPath($Path)
        while($parent){
            if((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
                throw "Linked path refused: $parent"
            }
            $parent=Split-Path -Parent $parent
        }
    }
    Assert-PlainPath $currentRelease
    if(-not (Test-Path -LiteralPath (Join-Path $currentRelease 'package-lock.json') -PathType Leaf)){
        throw 'The current 2.7.1 offline release is missing. No old builds were deleted.'
    }
    Import-Module (Join-Path $PSScriptRoot 'package\Lab.Core.psm1') -Force
    $lock=Get-Content -LiteralPath (Join-Path $currentRelease 'package-lock.json') -Raw|ConvertFrom-Json
    Test-LabPackage $currentRelease $lock
    $config=Import-PowerShellDataFile (Join-Path $currentRelease 'LabConfig.psd1')
    if($config.PackageRevision -ne '2.7.1'){throw 'Unexpected current release version.'}

    # Validate ALL targets before removing anything. Never follow junctions,
    # accept arbitrary paths, or operate outside this checkout.
    $targets=@();[long]$bytes=0
    foreach($relative in $relativeTargets){
        $absolute=[IO.Path]::GetFullPath((Join-Path $workspaceRoot $relative))
        if(-not $absolute.StartsWith($workspaceRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
            $currentRelease -ieq $absolute -or $currentRelease.StartsWith($absolute+'\',[StringComparison]::OrdinalIgnoreCase)){
            throw "Unsafe target refused: $absolute"
        }
        if(-not (Test-Path -LiteralPath $absolute)){continue}
        if((Resolve-Path -LiteralPath $absolute).Path -ine $absolute){throw "Target resolution mismatch: $absolute"}
        Assert-PlainPath $absolute
        if(@(Get-ChildItem -LiteralPath $absolute -Force -Recurse -Attributes ReparsePoint -ErrorAction Stop).Count){
            throw "Target contains linked paths: $absolute"
        }
        $bytes+=(Get-ChildItem -LiteralPath $absolute -File -Force -Recurse|Measure-Object Length -Sum).Sum
        $targets+=$absolute
        Write-Host ('Cleanup target: '+$absolute)
    }
    Write-Host ('Keep: '+$currentRelease)
    if(-not $targets.Count){Write-Host 'Workspace is already clean.';exit 0}
    Write-Host ('Space to reclaim: {0:N1} MiB' -f ($bytes/1MB))
    if(-not $Apply){Write-Host 'Preview only. Run Clean-Workspace.cmd to apply this cleanup.';exit 0}
    foreach($target in $targets){
        # Recheck immediately before each recursive deletion.
        Assert-PlainPath $target
        if(@(Get-ChildItem -LiteralPath $target -Force -Recurse -Attributes ReparsePoint -ErrorAction Stop).Count){throw "Linked path appeared in $target"}
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        Write-Host ('Removed: '+$target)
    }
    Test-LabPackage $currentRelease $lock
    Write-Host 'DONE: old builds and generated test data removed; current release verified.' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ('Cleanup failed: '+$_) -ForegroundColor Red
    exit 1
}
