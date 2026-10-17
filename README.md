# Bulk Sell Equipment for Monster Hunter Wilds

A REFramework script that finds the appraised talismans you no longer need and sells them all at once. It sells the same way the game's **View/Sell Equipment** screen does: same price, same game calls.

> This version sells **appraised talismans** only: Unknown, Historical, Secret and Golden Age Charm (rarity 5–8). It never touches weapons, armor or crafted talismans.

## Features

- **Scans the whole Equipment Box** on the game thread. The work is spread over frames, so a full box of 2,400 slots scans without stutter.
- **Decides what can go:**
  - **Covered:** a talisman you keep has every skill at the same or a higher level, and slots that fit the same decorations. Weapon slots and armor slots are compared separately.
  - **Duplicates:** identical copies beyond the one that is kept.
  - **Rarity rule** (optional): sell everything up to a chosen rarity. Talismans with skills you list as kept are exempt.
- **Shows every talisman before anything is sold.** The list gives its price, the verdict and, for covered talismans and duplicates, the talisman that is kept instead.
- **Pays the game's own price:** 1,500 / 3,000 / 4,500 / 8,000 z for rarity 5 / 6 / 7 / 8.
- **Writes a JSON receipt** for every sale run.

## Safety

These talismans are never sold:

- the equipped talisman
- talismans used in any equipment loadout
- favorites
- talismans with decorations attached
- crafted talismans
- talismans that [RNG Charm Crafting](https://www.nexusmods.com/monsterhunterwilds/mods/4900) gave a Set or Group bonus

The mod also checks itself while it sells:

- **A confirmation only sells the list it showed.** If the rules change or the box is scanned again before you press "Yes, sell", the confirmation is withdrawn.
- **The whole list is checked against the plan before the first talisman is sold**, and each box entry is checked again right before it is sold. A talisman that changed since the scan is skipped. So is a covered talisman or duplicate whose kept talisman is gone.
- **The confirmation lists the skills whose best level would go down.** For example: "Removes your last Fire Resistance (#2292)".
- **Selling waits** while a game menu is open or the game is saving.
- **The sale price is checked twice.** It must equal half the talisman's value, which is what the game pays.
- **A run stops on its own** if zenny does not go up by exactly the expected amount.
- **The confirmation expires** after 20 seconds, and a **Stop** button ends a run early.
- **Selling turns off, with the reason shown, when the mod cannot check something:**
  - a game update removed a function the mod relies on (the window names it);
  - RNG Charm Crafting's bonus file exists but cannot be read;
  - the save slot is unknown.

Sales cannot be undone. Back up your save first. It is in `Steam\userdata\<your id>\2246340\remote`.

The game writes sales to disk at its next autosave. If you close the game before that autosave, the sales are lost.

## Requirements

- Monster Hunter Wilds on PC (Steam). Tested on Steam build 24705561 (October 2026).
- [REFramework](https://github.com/praydog/REFramework-nightly/releases). A recent nightly build is recommended.

## Installation

**Fluffy Mod Manager:** import the zip as it is (do not unpack it) and enable **Bulk Sell Equipment**.

**Manual:** copy the `reframework` folder from the zip into the game folder, the one that contains `MonsterHunterWilds.exe`.

## Usage

1. Stand in the field or at camp with no game menu open. Press **Insert** to open REFramework.
2. Open **Script Generated UI**, then **Bulk Sell Equipment**, then click **Show window**.
3. Click **Scan Equipment Box**. Scanning only reads your talismans.
4. Pick your rules:
   - The **covered talismans and duplicates** option is on by default.
   - To use the rarity rule, tick **Also sell by rarity** and choose the highest rarity to sell.
   - Add the skills you want to keep under **Add kept skill**.
5. Review the list. **Show** switches between *To sell*, *To keep* and *All*.
6. Optionally, click **Sell just 1 (test)** first.
7. Click **Sell N talismans**, then **Yes, sell**.
8. Let the game autosave, for example by fast travelling.

## Files

| File | Contents |
|---|---|
| `reframework/data/BulkSell/config.json` | Your rules and kept skills |
| `reframework/data/BulkSell/receipts/sold_*.json` | One receipt per sale run: each talisman sold, its price and why it was sold, plus zenny before and after |

## Compatibility

- **RNG Charm Crafting:** talismans with its Set or Group bonus are protected. They are recognised by box index and by the talisman itself.
  - The REFramework log may show `[JSON] Failed to load file TalismanCrafting/special-bonuses-slot-0-b.json` when the game starts. RNG Charm Crafting writes that line itself while that file does not exist yet, and it is harmless. Bulk Sell reads the file without adding log lines.
  - If the window says an RNG Charm Crafting file could not be read, selling stays off. This is deliberate: selling could otherwise remove a bonus talisman. Fix the file or remove it with the game closed, then scan again.
- **Other mods:** mods that change talisman data or the View/Sell Equipment screen have not been tested together with this one.
- **Online play:** the mod was tested solo only.

## Known limitations

- **Crafted talismans are left out entirely.** They are never sold, and they are not used as the "kept instead" talisman when comparing.
- **The covered check ignores decorations you could add.** For example, a free slot does not count as a skill it could hold. Decoration-aware comparison is planned.
- **The interface is in English.** Skill names follow the game's language.

## Uninstall

Disable the mod in Fluffy Mod Manager, or delete these from the game folder:

- `reframework/autorun/BulkSell.lua`
- the `reframework/autorun/BulkSell/` folder

You can delete `reframework/data/BulkSell/` as well. It only holds settings and receipts.

## Development

| Path | Contents |
|---|---|
| `src/reframework/` | The mod, as it is shipped |
| `dev/<set>/reframework/` | Development scripts that are never shipped, one set per test session: `probe-lite` (read-only checks) and `probe-v1` (the original discovery probe: snapshots, method dumps, call traces) |
| `tests/` | Lua unit tests and smoke tests against a fake REFramework API, and `test_tools.ps1` for the PowerShell tools |
| `tools/` | Development scripts |

The scripts in `tools/`:

- `check.py` runs a syntax check and all Lua tests with Lua 5.4.
- `deploy.ps1` copies the mod into the game.
  - `-Dev <set>` also copies one dev set.
  - `-RemoveDev` removes the dev files.
  - `-Remove` uninstalls everything.
  - `-Release <zip>` puts a release build back.
- `backup-save.ps1` copies the Steam save and the BulkSell / TalismanCrafting data folders safely, even while the game is running.
- `restore-save.ps1` puts such a backup back. It refuses while the game runs, checks every hash, and backs up the current state first. `-DryRun` only shows what would change.
- `package.ps1` builds the release zip in `dist/`.

To run the tests:

```powershell
python -m venv .venv
.venv\Scripts\python.exe -m pip install lupa
.venv\Scripts\python.exe -I tools\check.py
powershell -ExecutionPolicy Bypass -File tests\test_tools.ps1
```

## Author and license

- **Author:** zamcoder on GitHub, published as **evilryosaki** on [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/5148).
- **License:** [MIT](LICENSE).
- **Changes:** see [CHANGELOG.md](CHANGELOG.md).

## Credits

- [praydog](https://github.com/praydog) for REFramework.
- [alphazolam/RE_RSZ](https://github.com/alphazolam/RE_RSZ) and [seifhassine/REasy](https://github.com/seifhassine/REasy) for the RSZ dumps that map the save data.
- [Quique20](https://github.com/Quique20/RathsMonsterHunterMods) for the talisman skill and slot encoding notes in *charm_editor*.
- [eigeen](https://github.com/eigeen/ref-mhws-item-editor) for showing that save data must be changed on the game thread.
- [kvasszn/ree-save-editor](https://github.com/kvasszn/ree-save-editor) for the meaning of save-data fields.
