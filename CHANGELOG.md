# Changelog

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
