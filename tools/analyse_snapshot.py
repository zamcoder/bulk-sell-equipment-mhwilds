"""Runs BulkSell's analysis.lua on a real box offline, and can compare it with the reference model.

Input (detected automatically):
  - a dev probe snapshot (BulkSellProbe/snapshot_*.json) or Batch A-lite file (batchA_lite_*.json);
  - a debug dump written by the mod (BulkSell/debug/plan_*.json): its own options are used unless
    given on the command line, and --reference also checks the verdicts the game recorded.

Usage:
  .venv\\Scripts\\python.exe -I tools\\analyse_snapshot.py <file> [--mode best|covered|manual]
      [--best-n N] [--max-rarity R] [--keep ID:LV,..] [--ignore ID,..] [--places ID:N,..]
      [--picks BOX:sell|keep,..] [--minus-receipts DIR] [--reference] [--list N]

Exit code 1 when --reference finds a difference.
"""
import argparse
import collections
import json
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUTORUN = (ROOT / "src" / "reframework" / "autorun").as_posix()
TESTS = (ROOT / "tests").as_posix()
RARITY_BY_TYPE = {189: 5, 190: 6, 191: 7, 192: 8}
SALE_PRICE = {5: 1500, 6: 3000, 7: 4500, 8: 8000}   # half of AmuletData._Price, as the game pays
PREVIEW_N = (10, 5, 3, 2, 1)


def decode(amulet_type, level, packed, decorations, favorite):
    """Same decoding as BulkSell/game.lua; None for anything but an appraised talisman."""
    rarity = RARITY_BY_TYPE.get(amulet_type)
    if rarity is None or level != 1:
        return None
    skills = [{"id": v % 1000, "level": v // 1000} for v in packed[:3] if v > 0]
    slot_value = packed[3]
    weapon_first = slot_value % 10 != 0
    slots = []
    for i, lv in enumerate((slot_value // 1000 % 10, slot_value // 100 % 10, slot_value // 10 % 10)):
        if lv > 0:
            slots.append({"kind": "W" if (i == 0 and weapon_first) else "A", "level": lv})
    return {"rarity": rarity, "price": SALE_PRICE[rarity], "skills": skills, "slots": slots,
            "fingerprint": f"{amulet_type}:" + ":".join(str(v) for v in packed),
            "_decorations": any(d >= 0 for d in decorations), "_favorite": favorite != 0}


def protect(charms, equipped, loadouts):
    """Same order as game.lua (the RNG Charm Crafting bonus is not in these files)."""
    for c in charms:
        key = c["key"]
        c["protected"] = ("equipped" if key == equipped else "loadout" if key in loadouts
                          else "favorite" if c.pop("_favorite") else "decorations" if c.pop("_decorations", False) else None)
        c.pop("_favorite", None)
        c.pop("_decorations", None)
    return charms


def load_probe_snapshot(data):
    box = next(b for b in data["boxes"] if b["field"] == "_EquipBox")
    ix = {c: i for i, c in enumerate(box["columns"])}
    charms = []
    for row in box["rows"]:
        if row[ix["get_Category()"]] != 2:
            continue
        c = decode(row[ix["FreeVal0"]], row[ix["FreeVal1"]], row[ix["BowgunCustomizeId"]],
                   row[ix["EquipmentAccessoryIdArray"]], row[ix["FreeVal4"]])
        if c:
            c["key"] = row[0]
            charms.append(c)
    loadouts = {l["index"][6] for l in data["loadouts"] if isinstance(l.get("index"), list) and len(l["index"]) > 6}
    return protect(charms, data["equipped_index"][6], loadouts)


def load_batch_lite(data):
    ix = {c: i for i, c in enumerate(data["talisman_columns"])}
    charms = []
    for row in data["talismans"]:
        c = decode(row[ix["FreeVal0"]], row[ix["FreeVal1"]], row[ix["BowgunCustomizeId"]],
                   row[ix["EquipmentAccessoryIdArray"]], row[ix["FreeVal4"]])
        if c:
            c["key"] = row[ix["index"]]
            charms.append(c)
    loadouts = {x for x in data["loadout_amulets"] if isinstance(x, int) and x >= 0}
    return protect(charms, data["equipped_index"][6], loadouts)


def int_map(text, value=int):
    out = {}
    for part in (text or "").split(","):
        if part:
            key, _, val = part.partition(":")
            out[int(key)] = value(val) if val else True
    return out


def from_dump_map(m, value=lambda v: v):
    return {int(k): value(v) for k, v in (m or {}).items() if k != "_format"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--mode", choices=("manual", "covered", "best"))
    ap.add_argument("--best-n", type=int)
    ap.add_argument("--max-rarity", type=int)
    ap.add_argument("--keep", help="Always keep: ID:min_level,...")
    ap.add_argument("--ignore", help="Don't care: ID,...")
    ap.add_argument("--places", help="per-skill places: ID:N,...")
    ap.add_argument("--picks", help="BOX:sell|keep,...")
    ap.add_argument("--minus-receipts", help="folder with sold_*.json receipts; their boxes are removed")
    ap.add_argument("--reference", action="store_true", help="compare with tests/fixtures/selection_reference.lua")
    ap.add_argument("--list", type=int, default=0, help="print the first N planned sales")
    args = ap.parse_args()

    data = json.load(open(args.file, encoding="utf-8"))
    dump = None
    if "charms" in data and "options" in data:
        dump = data
        charms = [dict(c, skills=c.get("skills") or [], slots=c.get("slots") or []) for c in data["charms"]]
        o = data["options"]
        options = {"mode": o.get("mode"), "best_n": o.get("best_n"), "max_rarity": o.get("max_rarity"),
                   "keep_skills": from_dump_map(o.get("keep_skills")), "ignore_skills": from_dump_map(o.get("ignore_skills")),
                   "skill_places": from_dump_map(o.get("skill_places")), "picks": from_dump_map(o.get("picks"))}
    elif "boxes" in data:
        charms, options = load_probe_snapshot(data), {}
    elif data.get("kind") == "batch A-lite":
        charms, options = load_batch_lite(data), {}
    else:
        sys.exit("unknown file format")
    if args.mode:
        options["mode"] = args.mode
    if args.best_n:
        options["best_n"] = args.best_n
    if args.max_rarity:
        options["max_rarity"] = args.max_rarity
    if args.keep:
        options["keep_skills"] = int_map(args.keep)
    if args.ignore:
        options["ignore_skills"] = int_map(args.ignore)
    if args.places:
        options["skill_places"] = int_map(args.places)
    if args.picks:
        options["picks"] = int_map(args.picks, str)
    options = {k: v for k, v in options.items() if v not in (None, {})}

    if args.minus_receipts:
        sold = set()
        for path in pathlib.Path(args.minus_receipts).glob("sold_*.json"):
            for t in json.load(open(path, encoding="utf-8")).get("talismans") or []:
                if isinstance(t, dict):
                    sold.add(t["box"])
        charms = [c for c in charms if c["key"] not in sold]
        print(f"removed {len(sold)} boxes sold in receipts")

    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = f"{AUTORUN}/?.lua;{TESTS}/?.lua"
    analysis = lua.eval('(require("BulkSell.analysis"))')

    def to_lua(obj):
        if isinstance(obj, dict):
            return lua.table_from({k: to_lua(v) for k, v in obj.items() if v is not None})
        if isinstance(obj, (list, tuple)):
            return lua.table_from([to_lua(v) for v in obj])
        return obj

    lua_charms = to_lua(charms)
    verdicts, info = analysis.plan(lua_charms, to_lua(options))
    by_key = {c["key"]: c for c in charms}

    def summary_of(v):
        return {"action": v["action"], "reason": v["reason"], "ref": v["ref"], "unique": bool(v["unique"]),
                "refs": [v["refs"][i] for i in range(1, len(v["refs"]) + 1)] if v["refs"] else []}

    counts = collections.Counter()
    sell_by_rarity = collections.Counter()
    zenny = 0
    for c in charms:
        v = verdicts[c["key"]]
        counts[(v["action"], v["reason"])] += 1
        if v["action"] == "sell":
            sell_by_rarity[c["rarity"]] += 1
            zenny += c["price"]
    print(f"appraised talismans: {len(charms)}, protected {sum(1 for c in charms if c.get('protected'))}")
    print("options:", {k: v for k, v in options.items()})
    for (action, reason), n in sorted(counts.items(), key=lambda kv: (kv[0][0], -kv[1])):
        print(f"  {action:4s} {reason:10s} {n}")
    print("sell by rarity:", dict(sorted(sell_by_rarity.items())), f"zenny {zenny:,}")
    preview = info["preview"]
    print(f"Keep combo: manual {preview['manual']['sell']}, covered {preview['covered']['sell']}, " +
          ", ".join(f"best {n}: {preview['best'][n]['sell']} ({preview['best'][n]['zenny']:,} z)" for n in PREVIEW_N))
    print(f"checker problems: {len(info['problems'])}, held back: {len(info['held_back'])}")
    shown = 0
    for c in charms:
        v = verdicts[c["key"]]
        if v["action"] == "sell" and shown < args.list:
            shown += 1
            skills = ", ".join(f"{s['id']}:{s['level']}" for s in c["skills"])
            slots = " ".join(f"{s['kind']}{s['level']}" for s in c["slots"]) or "-"
            print(f"  #{c['key']} R{c['rarity']} {skills} | {slots} -> {v['reason']}"
                  + (f" ref {v['ref']}" if v["ref"] else "") + (" unique" if v["unique"] else ""))

    if not args.reference:
        return 0
    reference = lua.eval('(require("fixtures.selection_reference"))')
    ref_verdicts, _ = reference.plan(to_lua(charms), to_lua(dict(options, preview=False)))
    differences = []
    for c in charms:
        a, b = summary_of(verdicts[c["key"]]), summary_of(ref_verdicts[c["key"]])
        if a != b:
            differences.append((c["key"], "analysis.lua", a, b))
    if dump:
        recorded = {int(k): v for k, v in dump["verdicts"].items() if k != "_format"}
        for c in charms:
            v = recorded.get(c["key"])
            b = summary_of(ref_verdicts[c["key"]])
            a = None if v is None else {"action": v.get("action"), "reason": v.get("reason"), "ref": v.get("ref"),
                                       "unique": bool(v.get("unique")), "refs": v.get("refs") or []}
            if a != b:
                differences.append((c["key"], "game dump", a, b))
    print(f"reference model: {len(differences)} differing verdicts"
          + (" (analysis.lua and the verdicts recorded in game)" if dump else ""))
    for key, where, a, b in differences[:10]:
        print(f"  #{key} {where}: {a} vs reference {b}")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
