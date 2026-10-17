<#
.SYNOPSIS
  Installs the mod, a development script set, or a release zip into the game's reframework folder.

.DESCRIPTION
  Files only take effect after REFramework "Reset Scripts" or a game restart.
  (no switch)       copy src\reframework (the mod)
  -Dev <set>        also copy dev\<set>\reframework (for example probe-lite, probe-v1)
  -RemoveDev        delete every file any dev set could have installed
  -Remove           delete the mod and every dev file
  -Release <zip>    delete the mod and every dev file, then install the reframework folder of a
                    release zip built by package.ps1 (to go back to the last release)
#>
param(
    [string]$GameDir = '',
    [string]$Dev = '',
    [switch]$RemoveDev,
    [switch]$Remove,
    [string]$Release = ''
)

$ErrorActionPreference = 'Stop'

if (-not $GameDir) {
    . (Join-Path $PSScriptRoot 'paths.ps1')
    $GameDir = Find-WildsGameDir
}
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $GameDir 'reframework'
if (-not (Test-Path $target)) { throw "REFramework folder not found: $target" }
$target = (Resolve-Path $target).Path

$modSource = Join-Path $root 'src\reframework'
$devSets = @(Get-ChildItem -Path (Join-Path $root 'dev') -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'reframework') })

function Get-SetFiles([string]$source) {
    Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
        [pscustomobject]@{ Full = $_.FullName; Relative = $_.FullName.Substring($source.Length).TrimStart('\') }
    }
}

function Remove-Set([string]$source) {
    foreach ($file in Get-SetFiles $source) {
        $dest = Join-Path $target $file.Relative
        if (Test-Path $dest) {
            Remove-Item -Path $dest -Confirm:$false
            Write-Output "removed $($file.Relative)"
        }
    }
}

function Copy-Set([string]$source) {
    foreach ($file in Get-SetFiles $source) {
        $dest = Join-Path $target $file.Relative
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -Path $file.Full -Destination $dest -Force
        Write-Output "copied  $($file.Relative)"
    }
}

# The mod owns autorun\BulkSell.lua and the whole autorun\BulkSell\ folder, so a removal
# also catches files that an older build had and the current source no longer has.
function Remove-Mod {
    $entry = Join-Path $target 'autorun\BulkSell.lua'
    $folder = Join-Path $target 'autorun\BulkSell'
    if (Test-Path $entry) { Remove-Item -Path $entry -Confirm:$false; Write-Output 'removed autorun\BulkSell.lua' }
    if (Test-Path $folder) { Remove-Item -Path $folder -Recurse -Confirm:$false; Write-Output 'removed autorun\BulkSell\' }
}

function Install-Release([string]$zipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $zipPath).Path)
    try {
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith('reframework/') -or $entry.FullName.EndsWith('/')) { continue }
            $relative = $entry.FullName.Substring('reframework/'.Length).Replace('/', '\')
            $dest = [System.IO.Path]::GetFullPath((Join-Path $target $relative))
            if (-not $dest.StartsWith($target + '\')) { throw "Unsafe path in zip: $($entry.FullName)" }
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
            Write-Output "release $relative"
        }
    } finally {
        $zip.Dispose()
    }
}

if ($RemoveDev -or $Remove -or $Release) {
    foreach ($set in $devSets) { Remove-Set (Join-Path $set.FullName 'reframework') }
}
if ($Remove -or $Release) { Remove-Mod }
if ($Release) {
    Install-Release $Release
    return
}
if ($Remove -or $RemoveDev) { return }

Copy-Set $modSource
if ($Dev) {
    $devSource = Join-Path $root "dev\$Dev\reframework"
    if (-not (Test-Path $devSource)) { throw "Unknown dev set '$Dev'. Available: $(($devSets | ForEach-Object Name) -join ', ')" }
    Copy-Set $devSource
}
