# Locates Steam, the Monster Hunter Wilds install and its save folder.
# Dot-source this file: . (Join-Path $PSScriptRoot 'paths.ps1')

$WildsAppId = '2246340'

function Get-SteamRoot {
    $key = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($key -and $key.SteamPath) { return ($key.SteamPath -replace '/', '\') }
    $default = 'C:\Program Files (x86)\Steam'
    if (Test-Path $default) { return $default }
    throw 'Steam installation not found.'
}

function Find-WildsGameDir {
    $steam = Get-SteamRoot
    $libraries = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $libraries += Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $dir = Join-Path $library 'steamapps\common\MonsterHunterWilds'
        if (Test-Path (Join-Path $dir 'MonsterHunterWilds.exe')) { return $dir }
    }
    throw 'Monster Hunter Wilds installation not found; pass -GameDir.'
}

# Several Steam accounts may have played on this PC: the most recently saved one wins.
function Find-WildsSaveRoot {
    $userdata = Join-Path (Get-SteamRoot) 'userdata'
    $candidates = @(Get-ChildItem -Path $userdata -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "$WildsAppId\remote" } |
        Where-Object { Test-Path $_ })
    if ($candidates.Count -eq 0) { throw 'Monster Hunter Wilds save folder not found; pass -SaveRoot.' }
    return $candidates | Sort-Object -Descending -Property {
        (Get-ChildItem -Path $_ -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    } | Select-Object -First 1
}
