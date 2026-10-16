<#
.SYNOPSIS
  Builds the release zip for Nexus Mods / Fluffy Mod Manager in dist\.

.DESCRIPTION
  The zip root holds modinfo.ini and the reframework folder: the layout Fluffy Mod
  Manager imports directly, and the one players copy into the game folder for a
  manual install. The development probe (dev\) is never included.
#>
param(
    [string]$Author = 'zamcoder'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src'
$entryScript = Join-Path $source 'reframework\autorun\BulkSell.lua'
$version = (Select-String -Path $entryScript -Pattern 'local VERSION = "([^"]+)"').Matches[0].Groups[1].Value
if (-not $version) { throw "VERSION not found in $entryScript" }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipPath = Join-Path $dist "BulkSellEquipment-$version.zip"
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Confirm:$false }

$modinfo = @(
    'name=Bulk Sell Equipment'
    'nameasbundle=Bulk Sell Equipment'
    'category=Scripts'
    "version=$version"
    'description=Bulk sell unneeded appraised talismans safely. Requires REFramework.'
    'screenshot='
    "author=$Author"
) -join "`r`n"

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $stream = $zip.CreateEntry('modinfo.ini').Open()
    $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)))
    try { $writer.Write($modinfo + "`r`n") } finally { $writer.Dispose() }

    foreach ($file in Get-ChildItem -Path (Join-Path $source 'reframework') -Recurse -File) {
        # Forward slashes: some zip readers mis-handle backslash entry names.
        $name = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name) | Out-Null
    }
} finally {
    $zip.Dispose()
}

Write-Output "Built $zipPath"
$check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($item in $check.Entries) { Write-Output ("  {0,-50} {1,8} bytes" -f $item.FullName, $item.Length) }
} finally {
    $check.Dispose()
}
