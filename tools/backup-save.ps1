<#
.SYNOPSIS
  Copies the Monster Hunter Wilds Steam save folder to a timestamped backup folder.

.DESCRIPTION
  Safe to run while the game is running: every file is opened with ReadWrite+Delete
  sharing, so the game can keep writing its save during the copy. Each file is read
  twice and only accepted when both reads hash the same (retries if an autosave was
  in progress). A manifest.json with sizes and SHA256 hashes is written next to the copy.
#>
param(
    [string]$SaveRoot = '',
    [string]$BackupRoot = (Join-Path $env:USERPROFILE 'Documents\MHWilds_SaveBackups'),
    [string]$Label = ''
)

$ErrorActionPreference = 'Stop'

if (-not $SaveRoot) {
    . (Join-Path $PSScriptRoot 'paths.ps1')
    $SaveRoot = Find-WildsSaveRoot
}
if (-not (Test-Path $SaveRoot)) { throw "Save folder not found: $SaveRoot" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$name = if ($Label) { "${stamp}_$Label" } else { $stamp }
$dest = Join-Path $BackupRoot $name
New-Item -ItemType Directory -Force -Path $dest | Out-Null

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

$manifest = @()
foreach ($file in Get-ChildItem -Path $SaveRoot -File -Recurse) {
    $relative = $file.FullName.Substring($SaveRoot.Length).TrimStart('\')
    $bytes = $null
    $hash = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $first = Read-Shared $file.FullName
        $second = Read-Shared $file.FullName
        $firstHash = Get-Hash $first
        if ($firstHash -eq (Get-Hash $second)) { $bytes = $first; $hash = $firstHash; break }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $bytes) { throw "File kept changing during backup (autosave in progress?): $relative" }

    $target = Join-Path $dest $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    [System.IO.File]::WriteAllBytes($target, $bytes)
    $manifest += [pscustomobject]@{
        file          = $relative
        size          = $bytes.Length
        sha256        = $hash
        lastWriteTime = $file.LastWriteTime.ToString('s')
    }
}

[pscustomobject]@{
    createdAt = (Get-Date).ToString('s')
    source    = $SaveRoot
    files     = $manifest
} | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $dest 'manifest.json') -Encoding utf8

Write-Output "Backup written to: $dest"
$manifest | Format-Table -AutoSize | Out-String -Width 200
