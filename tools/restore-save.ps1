<#
.SYNOPSIS
  Restores a backup made by backup-save.ps1: the Steam save and the BulkSell /
  TalismanCrafting data folders, together.

.DESCRIPTION
  - Refuses to run while Monster Hunter Wilds is running.
  - Verifies every backed-up file against the manifest's SHA256 before touching anything.
  - Backs up the current state first (label "before-restore"), unless -DryRun.
  - Save files are overwritten with the backup's copies (other files in the save folder stay).
  - Each mod data folder that is in the backup is made identical to it (files added since the
    backup are deleted). Folders that were not in the backup are left alone.
  -DryRun prints every action and changes nothing.

  Steam Cloud: if Steam reports a save conflict after a restore, choose the local files.
#>
param(
    [Parameter(Mandatory = $true)][string]$Backup,
    [string]$SaveRoot = '',
    [string]$GameDir = '',
    [string]$BackupRoot = (Join-Path $env:USERPROFILE 'Documents\MHWilds_SaveBackups'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# A dry run writes nothing, so it may run next to the game; a real restore may not.
if (-not $DryRun -and (Get-Process -Name MonsterHunterWilds -ErrorAction SilentlyContinue)) {
    throw 'Monster Hunter Wilds is running. Close the game first.'
}

$manifestPath = Join-Path $Backup 'manifest.json'
if (-not (Test-Path $manifestPath)) { throw "No manifest.json in $Backup" }
$manifest = Get-Content -Path $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
# Backups made before mod data was included name the save folder "source".
if (-not $SaveRoot) { $SaveRoot = if ($manifest.saveRoot) { $manifest.saveRoot } else { $manifest.source } }
if (-not $GameDir) { $GameDir = $manifest.gameDir }
if (-not $SaveRoot) { throw 'The manifest has no saveRoot; pass -SaveRoot.' }

$sha = [System.Security.Cryptography.SHA256]::Create()
function Get-FileHashHex([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try { return [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $stream.Dispose() }
}

# Old backups (before mod data was included) have no area and store "win64_save\..." paths.
$files = @($manifest.files | ForEach-Object {
    $area = if ($_.area) { $_.area } else { 'save' }
    $relative = if ($_.area) { $_.file } else { 'save\' + $_.file }
    $stored = if ($_.area) { Join-Path $Backup $_.file } else { Join-Path $Backup $_.file }
    [pscustomobject]@{ Area = $area; Relative = $relative; Stored = $stored; Sha = $_.sha256 }
})

Write-Output "Verifying $($files.Count) files in $Backup ..."
foreach ($file in $files) {
    if (-not (Test-Path $file.Stored)) { throw "Missing from backup: $($file.Stored)" }
    if ((Get-FileHashHex $file.Stored) -ne $file.Sha) { throw "Hash mismatch, backup is damaged: $($file.Stored)" }
}

function Get-TargetPath($file) {
    if ($file.Area -eq 'save') { return Join-Path $SaveRoot $file.Relative.Substring('save\'.Length) }
    if (-not $GameDir) { throw 'The manifest has no gameDir; pass -GameDir.' }
    return Join-Path (Join-Path $GameDir 'reframework\data') $file.Relative.Substring('mod-data\'.Length)
}

if (-not $DryRun) {
    Write-Output 'Backing up the current state first...'
    & (Join-Path $PSScriptRoot 'backup-save.ps1') -SaveRoot $SaveRoot -GameDir $GameDir -BackupRoot $BackupRoot -Label 'before-restore'
}

$prefix = if ($DryRun) { '[dry-run] ' } else { '' }

# Mod data folders become identical to the backup: delete files the backup does not have.
$areas = @($files | Where-Object { $_.Area -ne 'save' } | Select-Object -ExpandProperty Area -Unique)
foreach ($area in $areas) {
    $folder = Join-Path (Join-Path $GameDir 'reframework\data') $area.Substring('mod-data\'.Length)
    if (-not (Test-Path $folder)) { continue }
    $keep = @($files | Where-Object { $_.Area -eq $area } | ForEach-Object { (Get-TargetPath $_).ToLowerInvariant() })
    foreach ($existing in Get-ChildItem -Path $folder -File -Recurse) {
        if ($keep -notcontains $existing.FullName.ToLowerInvariant()) {
            Write-Output "${prefix}delete $($existing.FullName)"
            if (-not $DryRun) { Remove-Item -Path $existing.FullName -Confirm:$false }
        }
    }
}

foreach ($file in $files) {
    $target = Get-TargetPath $file
    Write-Output "${prefix}restore $target"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item -Path $file.Stored -Destination $target -Force
        if ((Get-FileHashHex $target) -ne $file.Sha) { throw "Restored file does not match the backup: $target" }
    }
}

Write-Output "${prefix}Restore finished from $Backup"
