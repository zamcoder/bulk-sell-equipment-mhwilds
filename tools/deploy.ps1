<#
.SYNOPSIS
  Copies the mod (and optionally the development probe) into the game's reframework folder.

.DESCRIPTION
  Files only take effect after REFramework "Reset Scripts" or a game restart.
  -Dev     also deploys dev\reframework (the probe; never shipped).
  -Remove  deletes every file this script can deploy (mod and probe).
#>
param(
    [string]$GameDir = '',
    [switch]$Dev,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

if (-not $GameDir) {
    . (Join-Path $PSScriptRoot 'paths.ps1')
    $GameDir = Find-WildsGameDir
}

$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $GameDir 'reframework'
if (-not (Test-Path $target)) { throw "REFramework folder not found: $target" }

$sources = @(Join-Path $root 'src\reframework')
if ($Dev -or $Remove) { $sources += Join-Path $root 'dev\reframework' }

foreach ($source in $sources) {
    if (-not (Test-Path $source)) { continue }
    foreach ($file in Get-ChildItem -Path $source -Recurse -File) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\')
        $dest = Join-Path $target $relative
        if ($Remove) {
            if (Test-Path $dest) {
                Remove-Item -Path $dest -Confirm:$false
                Write-Output "removed $relative"
            }
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item -Path $file.FullName -Destination $dest -Force
            Write-Output "copied  $relative"
        }
    }
}

if ($Remove) {
    $moduleDir = Join-Path $target 'autorun\BulkSell'
    if ((Test-Path $moduleDir) -and -not (Get-ChildItem -Path $moduleDir -Recurse -File)) {
        Remove-Item -Path $moduleDir -Recurse -Confirm:$false
    }
}
