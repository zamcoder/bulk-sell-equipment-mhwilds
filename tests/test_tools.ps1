# Exercises tools\deploy.ps1, backup-save.ps1 and restore-save.ps1 against a fake game and
# save folder in the temp directory. Never touches the real game or save.
# Usage: powershell -ExecutionPolicy Bypass -File tests\test_tools.ps1
$ErrorActionPreference = 'Stop'
$tools = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools'
$base = Join-Path ([System.IO.Path]::GetTempPath()) 'bulksell-tooltest'
if (Test-Path $base) { Remove-Item $base -Recurse -Force -Confirm:$false }
$game = Join-Path $base 'game'
$save = Join-Path $base 'save'
$backups = Join-Path $base 'backups'
New-Item -ItemType Directory -Force -Path "$game\reframework\autorun", "$game\reframework\data\BulkSell\receipts", "$game\reframework\data\TalismanCrafting", "$save\win64_save" | Out-Null
Set-Content -Path "$game\reframework\data\BulkSell\config.json" -Value '{"version":1}' -Encoding ascii
Set-Content -Path "$game\reframework\data\BulkSell\receipts\sold_1.json" -Value '{"sold":1}' -Encoding ascii
Set-Content -Path "$game\reframework\data\TalismanCrafting\special-bonuses-slot-0-a.json" -Value '{"version":2}' -Encoding ascii
[System.IO.File]::WriteAllBytes("$save\win64_save\data001Slot.bin", [byte[]](1, 2, 3, 4))
Set-Content -Path "$game\reframework\autorun\OtherMod.lua" -Value '-- other mod' -Encoding ascii

function Check($condition, $message) { if (-not $condition) { throw "FAILED: $message" } else { Write-Output "ok   $message" } }

# deploy ---------------------------------------------------------------------
& "$tools\deploy.ps1" -GameDir $game | Out-Null
Check (Test-Path "$game\reframework\autorun\BulkSell.lua") 'deploy copies the mod'
Check (Test-Path "$game\reframework\autorun\BulkSell\files.lua") 'deploy copies modules'
& "$tools\deploy.ps1" -GameDir $game -Dev probe-lite | Out-Null
Check (Test-Path "$game\reframework\autorun\BulkSellProbeLite.lua") 'deploy -Dev probe-lite'
Check (-not (Test-Path "$game\reframework\autorun\BulkSellProbe.lua")) 'probe-v1 not deployed with probe-lite'
& "$tools\deploy.ps1" -GameDir $game -RemoveDev | Out-Null
Check (-not (Test-Path "$game\reframework\autorun\BulkSellProbeLite.lua")) '-RemoveDev removes dev files'
Check (Test-Path "$game\reframework\autorun\BulkSell.lua") '-RemoveDev keeps the mod'
Set-Content -Path "$game\reframework\autorun\BulkSell\stale.lua" -Value '-- old module' -Encoding ascii
& "$tools\package.ps1" | Out-Null
$zip = Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist') -Filter 'BulkSellEquipment-*.zip' | Sort-Object LastWriteTime | Select-Object -Last 1
& "$tools\deploy.ps1" -GameDir $game -Release $zip.FullName | Out-Null
Check (-not (Test-Path "$game\reframework\autorun\BulkSell\stale.lua")) '-Release removes stale module files'
Check (Test-Path "$game\reframework\autorun\BulkSell\sidecar.lua") '-Release installs the zip'
Check (Test-Path "$game\reframework\autorun\OtherMod.lua") 'other mods untouched'
& "$tools\deploy.ps1" -GameDir $game -Remove | Out-Null
Check (-not (Test-Path "$game\reframework\autorun\BulkSell.lua") -and -not (Test-Path "$game\reframework\autorun\BulkSell")) '-Remove removes the mod'
Check (Test-Path "$game\reframework\autorun\OtherMod.lua") 'other mods untouched after -Remove'

# backup + restore -----------------------------------------------------------------
& "$tools\backup-save.ps1" -SaveRoot $save -GameDir $game -BackupRoot $backups -Label t1 | Out-Null
$backup = Get-ChildItem $backups -Directory | Select-Object -First 1
$manifest = Get-Content (Join-Path $backup.FullName 'manifest.json') -Raw | ConvertFrom-Json
Check ($manifest.files.Count -eq 4) 'backup has save + mod data files'
Check (Test-Path (Join-Path $backup.FullName 'mod-data\TalismanCrafting\special-bonuses-slot-0-a.json')) 'sidecar backed up'

# Change things after the backup.
[System.IO.File]::WriteAllBytes("$save\win64_save\data001Slot.bin", [byte[]](9, 9))
Remove-Item "$game\reframework\data\BulkSell\config.json"
Set-Content -Path "$game\reframework\data\TalismanCrafting\special-bonuses-slot-0-b.json" -Value '{"new":true}' -Encoding ascii

$dry = & "$tools\restore-save.ps1" -Backup $backup.FullName -DryRun | Out-String
Check ($dry -match 'dry-run\] delete .*special-bonuses-slot-0-b\.json') 'dry run lists the deletion'
Check ([System.IO.File]::ReadAllBytes("$save\win64_save\data001Slot.bin").Length -eq 2) 'dry run changes nothing'

if (Get-Process -Name MonsterHunterWilds -ErrorAction SilentlyContinue) {
    $refused = $false
    try { & "$tools\restore-save.ps1" -Backup $backup.FullName -BackupRoot $backups | Out-Null } catch { $refused = $_.Exception.Message -match 'running' }
    Check $refused 'real restore refused while the game runs (real restore test skipped)'
} else {
    & "$tools\restore-save.ps1" -Backup $backup.FullName -BackupRoot $backups | Out-Null
    Check ([System.IO.File]::ReadAllBytes("$save\win64_save\data001Slot.bin").Length -eq 4) 'save restored'
    Check (Test-Path "$game\reframework\data\BulkSell\config.json") 'deleted config restored'
    Check (-not (Test-Path "$game\reframework\data\TalismanCrafting\special-bonuses-slot-0-b.json")) 'file added after the backup removed'
    Check ((Get-ChildItem $backups -Directory | Where-Object Name -like '*before-restore').Count -eq 1) 'state before the restore was backed up'
}

# Damaged backups are refused.
Set-Content -Path (Join-Path $backup.FullName 'mod-data\BulkSell\config.json') -Value 'tampered' -Encoding ascii
$damaged = $false
try { & "$tools\restore-save.ps1" -Backup $backup.FullName -DryRun | Out-Null } catch { $damaged = $_.Exception.Message -match 'Hash mismatch' }
Check $damaged 'damaged backup refused'
Write-Output 'tool tests passed'
