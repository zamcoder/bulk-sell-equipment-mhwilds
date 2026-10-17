<#
.SYNOPSIS
  Copies the Monster Hunter Wilds Steam save, plus the Bulk Sell and RNG Charm Crafting data
  folders, to a timestamped backup folder.

.DESCRIPTION
  Safe to run while the game is running: every file is opened with ReadWrite+Delete sharing,
  so the game can keep writing its save during the copy. Each file is read twice and only
  accepted when both reads hash the same. After copying, every source file is hashed again;
  if anything changed during the backup (an autosave), the whole backup is taken again.
  A manifest.json lists every file with its area, size and SHA256; restore-save.ps1 uses it.

  Areas in the backup folder:
    save\           <SaveRoot> (Steam userdata\<id>\2246340\remote)
    mod-data\<name> <GameDir>\reframework\data\<name>, for BulkSell and TalismanCrafting
#>
param(
    [string]$SaveRoot = '',
    [string]$GameDir = '',
    [string]$BackupRoot = (Join-Path $env:USERPROFILE 'Documents\MHWilds_SaveBackups'),
    [string]$Label = ''
)

$ErrorActionPreference = 'Stop'

if (-not $SaveRoot -or -not $GameDir) { . (Join-Path $PSScriptRoot 'paths.ps1') }
if (-not $SaveRoot) { $SaveRoot = Find-WildsSaveRoot }
if (-not $GameDir) { $GameDir = Find-WildsGameDir }
if (-not (Test-Path $SaveRoot)) { throw "Save folder not found: $SaveRoot" }

$MOD_DATA = @('BulkSell', 'TalismanCrafting')
$sha = [System.Security.Cryptography.SHA256]::Create()

function Read-Shared([string]$path) {
    $share = [System.IO.FileShare]'ReadWrite, Delete'
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        $buffer = New-Object System.IO.MemoryStream
        $stream.CopyTo($buffer)
        return ,$buffer.ToArray()
    } finally {
        $stream.Dispose()
    }
}

function Get-Hash([byte[]]$bytes) {
    return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
}

# Every file to back up: @{ Area; Source; Relative } (Relative is the path inside the backup).
function Get-Sources {
    $list = @()
    foreach ($file in Get-ChildItem -Path $SaveRoot -File -Recurse) {
        $list += [pscustomobject]@{ Area = 'save'; Source = $file.FullName; Relative = 'save\' + $file.FullName.Substring($SaveRoot.Length).TrimStart('\') }
    }
    foreach ($name in $MOD_DATA) {
        $folder = Join-Path $GameDir "reframework\data\$name"
        if (-not (Test-Path $folder)) { continue }
        $folder = (Resolve-Path $folder).Path
        foreach ($file in Get-ChildItem -Path $folder -File -Recurse) {
            $list += [pscustomobject]@{ Area = "mod-data\$name"; Source = $file.FullName; Relative = "mod-data\$name\" + $file.FullName.Substring($folder.Length).TrimStart('\') }
        }
    }
    return $list
}

function Read-Stable([string]$path) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $first = Read-Shared $path
        $second = Read-Shared $path
        $hash = Get-Hash $first
        if ($hash -eq (Get-Hash $second)) { return @{ Bytes = $first; Hash = $hash } }
        Start-Sleep -Milliseconds 500
    }
    throw "File kept changing during backup (autosave in progress?): $path"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$name = if ($Label) { "${stamp}_$Label" } else { $stamp }
$dest = Join-Path $BackupRoot $name

for ($round = 1; $round -le 3; $round++) {
    if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force -Confirm:$false }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $manifest = @()
    foreach ($item in Get-Sources) {
        $copy = Read-Stable $item.Source
        $target = Join-Path $dest $item.Relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        [System.IO.File]::WriteAllBytes($target, $copy.Bytes)
        $manifest += [pscustomobject]@{
            area          = $item.Area
            file          = $item.Relative
            source        = $item.Source
            size          = $copy.Bytes.Length
            sha256        = $copy.Hash
            lastWriteTime = (Get-Item $item.Source).LastWriteTime.ToString('s')
        }
    }
    # The set is only consistent if nothing changed while it was being copied.
    $changed = @($manifest | Where-Object { -not (Test-Path $_.source) -or (Get-Hash (Read-Shared $_.source)) -ne $_.sha256 })
    $added = @(Get-Sources | Where-Object { $manifest.source -notcontains $_.Source })
    if ($changed.Count -eq 0 -and $added.Count -eq 0) { break }
    if ($round -eq 3) { throw 'Files kept changing during the backup; try again in a moment.' }
    Write-Output "Something changed during the backup (round $round); taking it again."
}

[pscustomobject]@{
    createdAt = (Get-Date).ToString('s')
    saveRoot  = $SaveRoot
    gameDir   = $GameDir
    files     = $manifest
} | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $dest 'manifest.json') -Encoding utf8

Write-Output "Backup written to: $dest"
$manifest | Select-Object area, file, size, lastWriteTime | Format-Table -AutoSize | Out-String -Width 220
