# Bulk Sell Equipment: beginner's guide

This guide shows you how to use the mod, step by step, with examples. You do not need to read the whole thing. Start with **Part 1**, and use the other parts when you need them.

- [Part 1: your first sale in 6 steps](#part-1-your-first-sale-in-6-steps)
- [Part 2: which Keep option should I choose?](#part-2-which-keep-option-should-i-choose)
- [Part 3: reading the window](#part-3-reading-the-window)
- [Part 4: how to... (recipes)](#part-4-how-to-recipes)
- [Part 5: the confirmation](#part-5-the-confirmation)
- [Part 6: messages and what to do](#part-6-messages-and-what-to-do)
- [Part 7: words used in the window](#part-7-words-used-in-the-window)

---

## Part 1: your first sale in 6 steps

**Before you start:** back up your save (it is in `Steam\userdata\<your id>\2246340\remote`). A sale cannot be undone, and the game has no buyback. Play solo, stand at camp or in the field, and close every game menu.

1. **Open the window.** Press **Insert** (the REFramework menu). Open **Script Generated UI → Bulk Sell Equipment** and click **Show window**.
2. **Scan.** Click **Scan Equipment Box**. This only reads your talismans. You now see a line like:
   > Scanned 11:53:38 · 1029 appraised (13 protected) · Box 2087 / 2400 (313 free)
3. **Choose what to keep.** Open the **Keep** list. Every choice shows how many talismans it would sell and for how much, for example:
   > Keep the best 10 per skill - 273 to sell (1,363,000 z)

   For a first try, choose **Keep every unique talisman**: it only sells exact duplicates and talismans that a talisman you keep fully beats.
4. **Look at the list.** Every row says what happens and why. You can untick a row to keep that talisman. Nothing is sold yet.
5. **Test with one.** Click **Sell just 1 (test)**, then **Yes, sell**. The mod sells the cheapest talisman in the list. Check that your zenny went up.
6. **Sell the rest.** Click **Sell N talismans**, tick what the confirmation asks for, and click **Yes, sell**. Then let the game autosave (fast travel once). Sales are only kept after the game saves.

That's it. The rest of this guide helps you sell more, or keep exactly what you want.

---

## Part 2: which Keep option should I choose?

| You want... | Choose | What it sells |
|---|---|---|
| Only to sell what you tick yourself | **Keep everything (sell only what I tick)** | Nothing on its own |
| A safe clean-up | **Keep every unique talisman** | Duplicates, and talismans another kept talisman matches or beats on every skill and slot |
| Some space | **Keep the best 10 per skill** | Everything outside your 10 best talismans for every skill and slot shape |
| A lot of space | **Keep the best 5** or **3 per skill** | More: only your 5 (or 3) best per skill and slot shape stay |
| As much space as possible | **Keep the best 2** or **1 per skill** | Almost everything except the very best per skill and slot shape |

**Example from a real box (1,029 talismans, 2,087 of 2,400 box slots used):**

| Keep option | Sold | Zenny | Box after |
|---|---|---|---|
| Keep every unique talisman | 0 | 0 z | 2,087 / 2,400 |
| Keep the best 10 per skill | 273 | 1,363,000 z | 1,814 / 2,400 |
| Keep the best 5 per skill | 563 | 2,878,000 z | 1,524 / 2,400 |
| Keep the best 3 per skill | 735 | 3,852,500 z | 1,352 / 2,400 |
| Keep the best 1 per skill | 914 | 4,831,500 z | 1,173 / 2,400 |

(This box had no duplicates or covered talismans left, so the safe clean-up sells nothing.)

**Tip: sell in steps.** Choose best 10, sell, look at what is left. Then best 5 (in this box: 290 more), and so on. Each step you can check the list.

**Why is it safe?** For every skill, your best talismans stay, so your best level of every skill stays in your box. The same goes for every slot shape (for example your best talismans with a size-3 slot). The [README](../README.md#how-keep-the-best-n-per-skill-works) explains the ranking in detail, with a full example.

**The rarity slider.** With the *best N* options you also see **Sell unique talismans only up to rarity**. At **8** every rarity can be sold. At **6**, only R5 and R6 unique talismans are sold; R7 and R8 stay (duplicates and covered ones are still sold).

---

## Part 3: reading the window

The window has these parts, from top to bottom:

**A. Scan line**
> Scanned 11:53:38 · 1029 appraised (13 protected) · Box 2087 / 2400 (313 free)

It turns yellow under 50 free box slots and red under 10.

**B. Keep option and Skills panel**
- The **Keep** list, the **rarity** slider (for *best N*), and the **(?)** that explains the idea.
- **Skills: 0 keep all · 0 custom · 0 don't care**: click it to open the per-skill settings (see Part 4).

**C. Summary**
> Sell 273 · keep 756 · about 1,363,000 z · box after the sale 1814 / 2400
> Duplicates 0 · covered 0 · unique 273 · your picks 0 (sell 0 / keep 0) · protected 13
> To sell by rarity: R5 1 · R6 60 · R7 147 · R8 65
> Your best 10 for every skill and slot shape stay. No skill level leaves your box.

- The **green line** is the promise: nothing you would miss leaves the box.
- A **yellow line** instead means one of your own choices (a tick or a Don't care skill) would remove a skill level. The confirmation will show exactly what.
- **Last change: ...** tells you what your last click or scan changed; **Show changed** lists those talismans.

**D. Sell buttons**
- **Sell N talismans**: everything planned.
- **Sell the N shown**: only the rows the filter shows (see E).
- **Sell just 1 (test)**: the cheapest row shown.

**E. Tools** (click to open): stars and export (see Part 4).

**F. The list**
- **Show**: To sell, To keep, All, Your picks, Unique sales, Changed by last edit, Last of their kind.
- **Find**: type a skill name (for example `attack`) or a box number (`#857`).
- **R5 R6 R7 R8**: show only these rarities.
- **Mark shown: Sell / Keep / Auto**: tick, untick, or reset every row shown. **Undo** takes one step back.

Columns:

| Column | Meaning |
|---|---|
| Sell | Ticked = will be sold. Click it to change your mind (a `*` appears next to the box number) |
| Box | The talisman's place in your Equipment Box |
| Talisman, Slots, Price | What it is and what you get for it |
| Verdict | **Sell · duplicate**, **Sell · covered**, **Sell · unique**, **Sell · your pick**, or **Keep · ...** |
| Why | The reason, for example "Same as #1032 (kept)" or "Ambush #1 of 21" |

**Reading the Why column, with examples:**

| Why says | It means |
|---|---|
| Same as #1032 (kept) | An identical talisman stays (box 1032) |
| Covered by #875 R8 Critical Eye 3, Flayer 1 | Box 875 has all its skills at the same or a higher level, and slots that are at least as good |
| Not in your best 3 · closest Item Prolonger #10 of 12 | It is unique, but outside the top 3 for every one of its skills. Its best place was 10th of 12 for Item Prolonger |
| Ambush #1 of 21 | It stays: it is your best Ambush talisman (of 21) |
| Slot shape A3 #2 of 18 | It stays: your second-best talisman with a size-3 slot |
| Favorite: remove the star in game to sell it | It is protected and never sold |

---

## Part 4: how to... (recipes)

### Keep one talisman the mod wants to sell
Untick its **Sell** box. The row becomes **Keep · your pick** and gets a `*`. Your ticks are saved and beat every rule.

### Sell one talisman the mod wants to keep
Tick its **Sell** box. It becomes **Sell · your pick**. If it is the last talisman with some skill level, the Why column says so in red (for example "Your pick · LAST Fire Resistance 3"), and the confirmation asks you to accept that loss.

### Undo your ticks
**Show → Your picks**, then **Mark shown: Auto**. Every pick is removed and the rules decide again.

### Keep every talisman with a certain skill
Open **Skills**, find the skill (type it in **Find skill**), and set its Keep to **Keep all**. Talismans with that skill are never sold as unique. "Keep all Lv2+" does the same only for level 2 and higher. Note: duplicates and covered copies are still sold, because a better talisman with the same skill stays.

### Keep more (or fewer) talismans for one skill
In **Skills**, set the skill to **Best 10** (or Best 1...). Example: Keep the best 3 per skill for everything, but Best 10 for Attack Boost.

### Stop caring about a skill (for example resistances)
In **Skills**, type `Resistance` in **Find skill**, then click **Don't care** after "Set the N shown to". The mod asks first when it changes more than 10 skills.

Don't care means: the skill no longer counts when talismans are compared. A talisman whose only advantage is that skill is now sold as covered or duplicate. If that removes your best level of a Don't care skill, the summary shows a yellow line and the confirmation lists it in red, for example:
> Fire Resistance 3 (best left 2) #2292 - Don't care

Changed your mind? Click **Undo** in the Skills panel, or **Reset all**.

### Sell every R5 talisman, like the old rarity rule
**Show → All**, untick **R6 R7 R8** (only R5 stays ticked), then **Mark shown: Sell**. Protected talismans are skipped. The confirmation lists anything you would lose.

### Free up space safely, in steps
1. Choose **Keep the best 10 per skill**, sell, and let the game save.
2. Next time, choose **best 5**, check the list, sell.
3. Then **best 3** if you still need space.

### Lock what you keep, with the game's own star
Open **Tools**, click **Star the N kept...**, then **Yes**. Every kept talisman gets the game's favorite star. Bulk Sell never sells a favorite, other mods such as Talisman Analyser skip favorites too, and you see the star in the game's own lists, so it is a good reminder before you sell or meld by hand. **Remove stars Bulk Sell added (N)...** removes exactly those stars again; stars you set yourself are never touched.

### Export your talismans to mhwilds.wiki-db.com
1. Open **Tools**. Choose **Export** (all talismans, what stays after the sale, or only what would be sold) and **Names** (the site's language).
2. Click **Copy for mhwilds.wiki-db.com**. The text is on your clipboard and also saved in `reframework/data/BulkSell/export/`.
3. Open https://mhwilds.wiki-db.com/sim/?hl=en, go to the **Talisman** tab, paste into **Import/Export Charms**, and press **Import**.

Careful: importing **replaces** the whole talisman list on the site. **Save CSV** writes a spreadsheet file instead.

### Get told when new talismans arrive
1. Open **Script Generated UI → Bulk Sell Equipment** and tick **Tell me about new items while the menu is closed (auto-clean)**. Optionally also tick **Also tell me when the Equipment Box is almost full**.
2. Play as usual. When a quest reward or the Melding Pot puts new items in your box, a message appears on the right of the screen for a few seconds, in the style of the game's own notices:
   > **Bulk Sell**
   > 3 new items in your Equipment Box since your last scan. Open Bulk Sell (Insert) to check.

   It waits until the quest result screen is gone, you can play on while it shows, and it never sells anything. Want to see it first? Click **Show a test message** and close the REFramework menu.
3. Press **Insert**. The window scans again by itself and shows "3 new talismans since you last cleared them." Click **Show new** to see only those.
4. Sell what you do not need with **Sell the N shown**, or click **Clear** to forget them.

Tip: star the talismans you crafted on purpose, so they never show up as something to sell.

### Compare zenny with the Melding Pot
The summary shows both, for example:
> Selling these gives 1,363,000 z. Melding them would give 1,713 Melding Pot points instead, but melding makes new talismans to appraise, so it does not empty your box.

---

## Part 5: the confirmation

When you click a Sell button, the mod shows a confirmation instead of selling:

> Sell 273 talismans for 1,363,000 z? This cannot be undone.
> 273 are unique: no identical or better talisman stays. For each of their skills and slot shapes you keep at least 10 that rank higher.
> [ ] I understand that unique talismans are sold.

- **Unique tick:** needed when the sale includes unique talismans. The mod remembers it for the same settings, and asks again when you change the settings or sell more unique talismans than before.
- **Red block:** "This sale removes: ..." lists every skill level or slot shape that would leave your box, with the box numbers. Only your own ticks or Don't care settings can cause it. Tick **I accept losing these** only if you really want that.
- **Yes, sell** only appears when every required box is ticked. The confirmation expires after 20 seconds, and changing anything withdraws it ("The list changed; review and press Sell again").
- While selling, **Stop** ends the run after the current talisman. A receipt is written in `reframework/data/BulkSell/receipts/`.

---

## Part 6: messages and what to do

| Message | What to do |
|---|---|
| The box may have changed. Rescanning... | Nothing. The mod scans again because you closed the menu or opened a game menu. Wait a second. |
| Close the game menu first. / Close the equipment menu first. | Close the game menu; selling waits until no menu is open. |
| Waiting for the game to finish saving. | Wait a moment. |
| Nothing more to sell: every talisman is unique. | Your box has no duplicates or covered talismans. Choose a *Keep the best N* option to sell more. |
| RNG Charm Crafting file ... could not be read | Selling stays off to protect bonus talismans. Close the game, fix or delete that file, start again. |
| Your saved Sell/Keep ticks could not be read | Click **Continue without my picks** (your ticks are lost), or close the game and restore the files. |
| Held back by a safety check - please report | The mod refused to sell one talisman because a check failed. Please report it with the files below. |
| Some names were not available in that language | That export used the game-language name for a few skills. |

**Reporting a problem:** tick **Write debug files** (Script Generated UI → Bulk Sell Equipment), scan again, and attach the newest file from `reframework/data/BulkSell/debug/`, your last receipt and `re2_framework_log.txt` from the game folder.

---

## Part 7: words used in the window

| Word | Meaning |
|---|---|
| Appraised talisman | Unknown, Historical, Secret or Golden Age Charm (R5 to R8). The only talismans this mod handles |
| Protected | Equipped, in a loadout, a favorite, with decorations, or with an RNG Charm Crafting bonus. Never sold |
| Duplicate | An exact copy (same skills, levels and slots) of a talisman that stays |
| Covered | Another talisman that stays has every one of its skills at the same or a higher level, and slots that can hold everything its slots can |
| Unique | Neither a duplicate nor covered: no talisman that stays is as good on every point |
| Slot shape | The set of slots, for example A3, A2 A1 or W1 A1 A1 (W = weapon slot, A = armor slot) |
| Best N | Your N highest-ranked talismans for a skill or a slot shape |
| Pick | Your own tick or untick on a row; it beats the rules (marked `*`) |
| Keep all | A skill setting: talismans with this skill are never sold as unique |
| Don't care | A skill setting: this skill is ignored when talismans are compared |
