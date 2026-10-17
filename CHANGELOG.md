# Changelog

## 0.3.0

Sell unique talismans too, with full control.

**New**
- **Keep option** with exact counts for every choice: *Keep everything (sell only what I tick)*, *Keep every unique talisman* (duplicates and covered ones only, the default) and *Keep the best 10 / 5 / 3 / 2 / 1 per skill*. "Best N" keeps your N best talismans for every skill and every slot shape and sells the other unique talismans up to a **rarity limit**. **Always keep** skills are never sold as unique.
- **Ticks per row:** the Sell box of a row overrides the rules for that talisman (`*` marks it). Ticks are saved per save slot and character, and follow the talisman, not just its box entry. **Mark shown** (Sell / Keep / Auto) and **Undo**.
- **Why column:** "Same as #k", "Covered by #k …", "Not in your best 3 · closest Item Prolonger #10 of 12", "Ambush #1 of 21", "In a loadout", and so on.
- **Filters:** To sell, To keep, All, Your picks, Unique sales; **Find** by skill or `#box`; rarity checkboxes. **Sell the N shown**, and **Sell just 1 (test)** now sells the cheapest row shown.
- **Box space** in the scan line (yellow under 50 free slots, red under 10) and "box after the sale" in the summary.

**Safety**
- Unique sales need the tick "I understand that unique talismans are sold". It is asked again when the rules change or the sale has more unique talismans than the one you agreed to.
- Any lost skill level or slot shape (only your own ticks can cause one) is listed in red and needs "I accept losing these".
- The list is scanned again after the REFramework menu was closed, or a full-screen menu or an equipment list was opened; a sale stops when the menu is closed.
- A unique sale is skipped when one of the talismans kept for its skills changed.
- An independent check re-derives every planned sale; a sale that fails it is kept instead.
- If your saved ticks cannot be read, selling waits until you choose **Continue without my picks**.

**Other changes**
- **Settings from 0.2.x are converted once** (the old file stays as `config.v1.json`); the window says what changed. The rarity rule becomes *Keep the best 1 per skill* up to its rarity. Going back to 0.2.x still works.
- Of identical copies, the cheaper one is now kept.
- Receipts also record the rules, your ticks, what you acknowledged and, per talisman, the Why text and the talismans kept for it.
- **Write debug files** (in the Bulk Sell menu) saves the whole plan for bug reports.

## 0.2.3

Safety fixes; no new selling features.

**Fixed**
- **Confirmation now only applies to the list it was shown for.** In 0.2.2, a rule change or a rescan between "Sell N talismans" and "Yes, sell" could sell a different list. Now:
  - the confirmation is withdrawn when the list changes ("The list changed; review and press Sell again");
  - the mod sells exactly the confirmed talismans.
- **Every talisman of a sale is checked against the plan before the first one is sold.** If any of them no longer matches, nothing is sold.

**Safety**
- **Selling waits while the game is saving.**
- **The sale price is checked against the talisman's value.** If the two do not match, selling stops. Each receipt entry now records where its price came from (`price_source`).
- **RNG Charm Crafting bonus talismans are recognised by box index and by the talisman itself.** If that mod's bonus file exists but cannot be read, or the save slot is unknown, selling stays off and the window says why.
- **The confirmation lists skills whose best level would go down**, for example "Removes your last Fire Resistance (#2292)". The summary warns too.
- **The mod no longer asks the game anything while the REFramework menu is closed.**

**Other changes**
- **New name.** The mod is now called "Bulk Sell Equipment" in the REFramework menu and the window title. The window position resets once.
- **Fewer log lines.** Bulk Sell no longer adds `[JSON] Failed to load file` lines for its own or RNG Charm Crafting's files when they do not exist.
- **License.** MIT.

## 0.2.2

- **Fixed:** the sale price is the game's own price (1,500 / 3,000 / 4,500 / 8,000 z for rarity 5–8). 0.2.0 and 0.2.1 paid less for some talismans.

## 0.2.1

- A price column in the list (development build).

## 0.2.0

- First version that sells. It uses the same game calls as View/Sell Equipment:
  - "Sell just 1 (test)";
  - a confirmation that expires;
  - the Stop button;
  - receipts;
  - a check of every talisman right before it is sold.

## 0.1.0-preview

- Read-only preview: it scans the Equipment Box and shows covered and duplicate talismans and the rarity rule.
