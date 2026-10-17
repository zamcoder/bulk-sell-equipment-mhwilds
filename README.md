# Bulk Sell Equipment for Monster Hunter Wilds

A REFramework script that finds the appraised talismans you no longer need and sells them all at once. It sells the same way the game's **View/Sell Equipment** screen does: same price, same game calls.

> This version sells **appraised talismans** only: Unknown, Historical, Secret and Golden Age Charm (rarity 5–8). It never touches weapons, armor or crafted talismans.

## How it decides

Bulk Sell asks of every appraised talisman: do you still need it?

- **Never sold:** talismans that are equipped, in a loadout, favorited, have decorations, or have an RNG Charm Crafting bonus.
- **Default:** only duplicates are sold, plus talismans that a talisman you keep matches or beats on every skill and slot.
- **More space:** choose **Keep the best 3 per skill** (or 10, 5, 2, 1). For every skill and for every slot shape (for example a size-3 slot), your 3 best talismans stay. Every other unique talisman up to your rarity limit is sold.
- **Your control:** tick or untick any row; your choice beats the rules. Nothing is sold until you confirm.
- **The promise:** the rules never lower your best level of any skill, and never remove the last talisman that can hold a slot shape. Only your own ticks can, and the confirmation names exactly what you would lose.

## How "Keep the best N per skill" works

The mod goes through these steps, in this order:

1. **Protected talismans stay.** Equipped, in a loadout, favorite, with decorations, or with an RNG Charm Crafting bonus. Your own ticks come next: a ticked row is sold, an unticked one is kept, whatever the rules say.
2. **Duplicates and covered talismans go.** A talisman is *covered* when a talisman you keep has every one of its skills at the same or a higher level, and slots that can hold everything its slots can (a size-3 slot holds a size-2 decoration; weapon and armor slots are compared separately). Of identical copies one stays: a protected one first, then your Keep tick, then the cheaper one, then the lowest box number.
3. **Every skill gets a ranking.** All talismans that are not covered and have the skill are ordered:
   1. higher level of that skill;
   2. bigger slots in total (A3 counts 3, A2 A1 counts 3, A1 counts 1);
   3. more slots;
   4. more weapon slots;
   5. stronger other skills, where each skill level counts against the best level of that skill in your box (Ambush 2 of a box best of 2 counts as much as Attack Boost 3 of a box best of 3);
   6. lower rarity (the cheaper talisman stays);
   7. a fixed order by the talisman's content, never by box position.

   **The top N of every skill stay.**
4. **Every slot shape gets a ranking too.** For each slot layout in your box (for example A3, A2 A1 or W1 A1 A1), the talismans whose slots can hold it are ordered by the strength of all their skills, then by their slots. **The top N of every slot shape stay**, so your best A3 talismans are never all sold for their skills.
5. **The rest is sold if it is unique and within your rarity limit.** A talisman that is in nobody's top N, for none of its skills and not for its slot shape, is sold. Exceptions: its rarity is above your limit, or it has an **Always keep** skill at the level you chose.

### Example: one skill, ranked

These are the 11 talismans with **Poison Resistance** in a real box of 1,029 talismans, in their ranking order. "Keep" means it stays with that Keep option; "Sell" means it is sold (it was outside the top N of this skill, of its other skills and of its slot shape).

| # | Talisman | Slots | Why this place | Best 10 | Best 5 | Best 3 |
|---|---|---|---|---|---|---|
| 1 | R8 Attack Boost 3, **Poison Resistance 3** | W1 A1 A1 | level 3, the biggest slots (3 in total) | Keep | Keep | Keep |
| 2 | R7 Critical Eye 3, **Poison Resistance 3** | A1 A1 | level 3, slots 2 | Keep | Keep | Keep |
| 3 | R7 Poison Attack 3, **Poison Resistance 3** | A1 A1 | the same as #2 in every key; a fixed content order decides | Keep | Keep | Keep |
| 4 | R7 Blast Attack 3, **Poison Resistance 3** | A1 | level 3, but slots 1 | Keep | Keep | Sell |
| 5 | R6 Focus 2, **Poison Resistance 2**, Survival Expert 2 | A2 A1 | level 2, slots 3 | Keep | Keep | Sell |
| 6 | R7 Attack Boost 3, **Poison Resistance 2**, Divine Blessing 1 | A1 A1 | level 2, slots 2 in two slots | Keep | Sell | Sell |
| 7 | R7 Sleep Attack 3, **Poison Resistance 2**, Intimidator 1 | A2 | level 2, slots 2 in one slot | Keep | Sell | Sell |
| 8 | R6 Exhaust Functionality 1, Resentment 1, **Poison Resistance 2** | A1 | level 2, slots 1 | Keep | Sell | Sell |
| 9 | R8 Critical Eye 3, Counterstrike 1, **Poison Resistance 1** | W1 A1 | level 1, slots 2 in two slots | Keep | Sell | Sell |
| 10 | R7 Critical Status 3, Wide-Range 3, **Poison Resistance 1** | A2 | level 1, slots 2 in one slot, strong other skills | Keep | Sell | Sell |
| 11 | R7 Spread/Power Shots 1, Maximum Might 1, **Poison Resistance 1** | A2 | level 1, slots 2 in one slot, weaker other skills | Keep¹ | Sell | Sell |

¹ Number 11 is outside the top 10 for Poison Resistance, but it is number 6 for Spread/Power Shots, so best 10 keeps it for that skill.

- With **best 3**, your three Poison Resistance 3 talismans with the most slots stay, so Poison Resistance 3 is still in your box.
- The talismans sold under best 3 or best 5 are sold because they are outside the top N **for every one of their skills and for their slot shape**, not only for Poison Resistance. Number 6 has Attack Boost 3, for example, but at least 5 Attack Boost talismans rank above it.
- **Best 1** would keep only number 1 here, plus any talisman that is number 1 for another of its skills or its slot shape.

What this means in practice:

- **Your best level of every skill stays**, because the number 1 of each ranking always stays. The same goes for slot shapes.
- **Rare skills stay.** If only 2 talismans have a skill, both are inside any top 3. (A covered one is still sold, but then the talisman that covers it keeps that skill at the same or a higher level.)
- **A good talisman can still be sold** when better ones exist for every one of its skills. For example, an R7 Attack Boost 3 / Evade Window 2 / Item Prolonger 1 with an A2 slot is sold under best 3 when 3 better talismans exist for each of those skills and for the A2 shape. Its Why text shows how close it came: "Not in your best 3 · closest Item Prolonger #10 of 12".
- **Kept talismans show why they stay:** "Ambush #1 of 21" means it is the best Ambush talisman you have; "Slot shape A3 #2 of 18" means it is your second-best A3 talisman.
- **A smaller N sells more.** Best 10 is careful, best 1 keeps only the single best talisman per skill and slot shape. Selling in steps (best 10, then 5, then 3) lets you look at the list each time.
- **Nothing changes until you confirm**, and an independent check re-derives every sale from the result; a sale that does not pass is kept instead.

## Features

- **Scans the whole Equipment Box** on the game thread. The work is spread over frames, so a full box of 2,400 slots scans without stutter.
- **One Keep option, with exact numbers.** Each choice shows how many talismans it would sell and for how much:
  - *Keep everything (sell only what I tick)*
  - *Keep every unique talisman*: duplicates and covered talismans only (the default)
  - *Keep the best 10 / 5 / 3 / 2 / 1 per skill*, with a rarity limit ("sell unique talismans only up to rarity 7", for example) and an **Always keep** list of skills.
- **Ticks per row.** The Sell box of a row overrides the rules for that talisman, and a `*` marks it. Ticks are saved per save slot. **Mark shown** ticks or unticks every row the filter shows, with **Undo**.
- **Shows every talisman before anything is sold:** its price, the verdict and why. For example, "Same as #1032 (kept)", "Covered by #875 R8 Critical Eye 3, Flayer 1", "Not in your best 3 · closest Item Prolonger #10 of 12" or "Ambush #1 of 21".
- **Filters:** To sell, To keep, All, Your picks, Unique sales, plus **Find** (a skill name or `#box`) and rarity checkboxes.
- **Pays the game's own price:** 1,500 / 3,000 / 4,500 / 8,000 z for rarity 5 / 6 / 7 / 8.
- **Writes a JSON receipt** for every sale run, with the rules used and why each talisman was sold.

## Safety

These talismans are never sold:

- the equipped talisman
- talismans used in any equipment loadout
- favorites
- talismans with decorations attached
- crafted talismans
- talismans that [RNG Charm Crafting](https://www.nexusmods.com/monsterhunterwilds/mods/4900) gave a Set or Group bonus

The mod also checks itself while it sells:

- **A confirmation only sells the list it showed.** If the rules, a tick or the box change before you press "Yes, sell", the confirmation is withdrawn.
- **Unique talismans need your OK.** When a sale includes talismans with no identical or better copy, the confirmation says so and asks you to tick "I understand that unique talismans are sold". It asks again when the rules change or the sale has more unique talismans than the one you agreed to.
- **Losses need your OK.** If a sale would lower your best level of a skill or remove the last talisman of a slot shape (only your own ticks can cause that), the confirmation lists it in red and asks you to tick "I accept losing these".
- **The list is made again when the box may have changed.** After you close the REFramework menu, open a full-screen game menu or an equipment list, the window says "Rescanning..." and scans again before you can sell.
- **The whole list is checked against the plan before the first talisman is sold**, and each box entry is checked again right before it is sold. A talisman that changed since the scan is skipped. So is a duplicate or covered talisman whose kept talisman is gone, and a unique talisman when one of the talismans kept for its skills changed.
- **Selling waits** while a game menu is open or the game is saving, and **stops** when you close the REFramework menu.
- **The sale price is checked twice.** It must equal half the talisman's value, which is what the game pays.
- **A run stops on its own** if zenny does not go up by exactly the expected amount.
- **The confirmation expires** after 20 seconds, and a **Stop** button ends a run early.
- **An independent check** re-derives every planned sale from the result alone. A sale that fails it is kept instead ("Held back by a safety check").
- **Selling turns off, with the reason shown, when the mod cannot check something:**
  - a game update removed a function the mod relies on (the window names it);
  - RNG Charm Crafting's bonus file exists but cannot be read;
  - the save slot is unknown;
  - your saved ticks cannot be read (until you choose **Continue without my picks**).

Sales cannot be undone, and the game has no buyback. Back up your save first. It is in `Steam\userdata\<your id>\2246340\remote`. If you want to free a lot of space, sell in steps: best 10 first, then best 5, then best 3.

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
4. Choose a **Keep** option. Each one shows how many talismans it sells. For the *best N* options, set the rarity limit and add skills to **Always keep** if you like.
5. Review the list. Untick a row to keep that talisman, or tick a kept one to sell it.
6. Optionally, click **Sell just 1 (test)** first. It sells the cheapest talisman of the rows shown.
7. Click **Sell N talismans** (or **Sell the N shown** for the filtered rows), tick what the confirmation asks for, then **Yes, sell**.
8. Let the game autosave, for example by fast travelling.

**Selling every R5 like the old rarity rule:** Show *All*, leave only **R5** ticked, then **Mark shown: Sell**. The confirmation lists anything you would lose.

## Updating from 0.2.x

Your settings are converted once, and the old file is kept as `reframework/data/BulkSell/config.v1.json`:

- **Rarity rule on** becomes *Keep the best 1 per skill*, limited to that rarity. It still sells low-rarity talismans, but now keeps your best one for every skill and slot shape. To sell more, raise the rarity limit and choose another Keep option.
- **Rarity rule on with covered talismans off** becomes *Keep everything*, because the new options always include covered talismans.
- **Otherwise** nothing changes: *Keep every unique talisman*, as before.

The window tells you once which of these happened. Going back to 0.2.x still works; it then runs with covered talismans and duplicates only.

## Files

| File | Contents |
|---|---|
| `reframework/data/BulkSell/config.json` | Your Keep option, rarity limit and Always keep skills |
| `reframework/data/BulkSell/config.v1.json` | Your 0.2.x settings, kept once when they were converted |
| `reframework/data/BulkSell/picks/slot-<n>-a.json`, `-b.json` | Your ticks for save slot `n`: two copies written in turn, so a crash during a write cannot lose them |
| `reframework/data/BulkSell/receipts/sold_*.json` | One receipt per sale run: each talisman sold, its price and why, the rules and ticks used, plus zenny before and after |
| `reframework/data/BulkSell/debug/plan_*.json` | Only with **Write debug files** ticked (in the Bulk Sell menu): the whole plan, for bug reports |

## Compatibility

- **RNG Charm Crafting:** talismans with its Set or Group bonus are protected. They are recognised by box index and by the talisman itself.
  - The REFramework log may show `[JSON] Failed to load file TalismanCrafting/special-bonuses-slot-0-b.json` when the game starts. RNG Charm Crafting writes that line itself while that file does not exist yet, and it is harmless. Bulk Sell reads the file without adding log lines.
  - If the window says an RNG Charm Crafting file could not be read, selling stays off. This is deliberate: selling could otherwise remove a bonus talisman. Fix the file or remove it with the game closed, then scan again.
  - Bulk Sell never moves talismans between box entries, so RNG Charm Crafting's bonus list stays valid.
- **Other mods:** mods that change talisman data or the View/Sell Equipment screen have not been tested together with this one.
- **Online play:** the mod was tested solo only.

## Known limitations

- **Crafted talismans are left out entirely.** They are never sold, and they are not used as the "kept instead" talisman when comparing.
- **Decorations you could add are not counted.** A free slot does not count as a skill it could hold. Decoration-aware comparison is planned.
- **"Best N" ranks talismans by their numbers only:** skill level, then slots, then the other skills. It does not know which skills you care about. Use ticks, the rarity limit and Always keep for that; per-skill settings are planned.
- **The interface is in English.** Skill names follow the game's language.

## Uninstall

Disable the mod in Fluffy Mod Manager, or delete these from the game folder:

- `reframework/autorun/BulkSell.lua`
- the `reframework/autorun/BulkSell/` folder

You can delete `reframework/data/BulkSell/` as well. It only holds settings, ticks and receipts.

## Development

| Path | Contents |
|---|---|
| `src/reframework/` | The mod, as it is shipped |
| `dev/<set>/reframework/` | Development scripts that are never shipped, one set per test session: `probe-lite` (read-only checks), `star-test` (does changing the favorite star set or toggle it) and `probe-v1` (the original discovery probe: snapshots, method dumps, call traces) |
| `tests/` | Lua unit, property and smoke tests against a fake REFramework API, frozen reference models in `tests/fixtures/`, and `test_tools.ps1` for the PowerShell tools |
| `tools/` | Development scripts |

The scripts in `tools/`:

- `check.py` runs a syntax check and all Lua tests with Lua 5.4.
- `analyse_snapshot.py` runs the analysis on a real box offline (a probe snapshot or a debug plan dump), with any Keep option, and with `--reference` compares the result with the reference model.
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
