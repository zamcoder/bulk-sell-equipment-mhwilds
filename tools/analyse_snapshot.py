"""Runs BulkSell's analysis.lua on a probe snapshot, to preview results on a real box offline.

Usage: .venv\\Scripts\\python.exe -I tools\\analyse_snapshot.py <snapshot.json> [--rule-max-rarity N]
"""
import collections
import json
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUTORUN = (ROOT / "src" / "reframework" / "autorun").as_posix()
RARITY_BY_TYPE = {189: 5, 190: 6, 191: 7, 192: 8}
SALE_PRICE = {5: 1500, 6: 3000, 7: 4500, 8: 8000}   # assumed: half of AmuletData._Price


def decode(row, ix):
    """Same decoding as BulkSell/game.lua."""
    rarity = RARITY_BY_TYPE.get(row[ix["FreeVal0"]])
    if row[ix["get_Category()"]] != 2 or rarity is None or row[ix["FreeVal1"]] != 1:
        return None
    packed = row[ix["BowgunCustomizeId"]]
    skills = [{"id": v % 1000, "level": v // 1000} for v in packed[:3] if v > 0]
    slot_value = packed[3]
    weapon_first = slot_value % 10 != 0
    slots = []
    for i, level in enumerate((slot_value // 1000 % 10, slot_value // 100 % 10, slot_value // 10 % 10)):
        if level > 0:
            slots.append({"kind": "W" if (i == 0 and weapon_first) else "A", "level": level})
    decorations = any(d >= 0 for d in row[ix["EquipmentAccessoryIdArray"]])
    return {"key": row[0], "rarity": rarity, "skills": skills, "slots": slots,
            "decorations": decorations, "favorite": row[ix["FreeVal4"]] != 0}


def main():
    snapshot = json.load(open(sys.argv[1], encoding="utf-8"))
    rule = None
    if "--rule-max-rarity" in sys.argv:
        rule = int(sys.argv[sys.argv.index("--rule-max-rarity") + 1])
    box = next(b for b in snapshot["boxes"] if b["field"] == "_EquipBox")
    ix = {c: i for i, c in enumerate(box["columns"])}
    equipped = snapshot["equipped_index"][6]
    loadout = {l["index"][6] for l in snapshot["loadouts"] if isinstance(l.get("index"), list) and len(l["index"]) > 6}

    charms = []
    for row in box["rows"]:
        charm = decode(row, ix)
        if not charm:
            continue
        key = charm["key"]
        protected = None
        if key == equipped:
            protected = "equipped"
        elif key in loadout:
            protected = "loadout"
        elif charm["favorite"]:
            protected = "favorite"
        elif charm["decorations"]:
            protected = "decorations"
        charm["protected"] = protected
        charm["price"] = SALE_PRICE[charm["rarity"]]
        charms.append(charm)

    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = f"{AUTORUN}/?.lua"
    analysis = lua.eval('(require("BulkSell.analysis"))')
    to_lua = lua.eval("function(t) return t end")
    table = lua.table_from

    def lua_charm(c):
        t = table({"key": c["key"], "rarity": c["rarity"], "price": c["price"]})
        t["skills"] = table([table(s) for s in c["skills"]])
        t["slots"] = table([table(s) for s in c["slots"]])
        if c["protected"]:
            t["protected"] = c["protected"]
        return t

    lua_charms = table([lua_charm(c) for c in charms])
    options = table({"sell_dominated": True})
    if rule:
        options["rules"] = table({"max_rarity": rule})
    verdicts = analysis.plan(to_lua(lua_charms), options)

    by_reason = collections.Counter()
    sell_by_rarity = collections.Counter()
    keep_by_rarity = collections.Counter()
    zenny = 0
    for c in charms:
        v = verdicts[c["key"]]
        by_reason[(v["action"], v["reason"], v["detail"])] += 1
        if v["action"] == "sell":
            sell_by_rarity[c["rarity"]] += 1
            zenny += c["price"]
        else:
            keep_by_rarity[c["rarity"]] += 1
    print(f"appraised talismans: {len(charms)}")
    for (action, reason, detail), n in sorted(by_reason.items(), key=lambda kv: (kv[0][0], -kv[1])):
        print(f"  {action:4s} {reason:10s} {detail or '':12s} {n}")
    print("sell by rarity:", dict(sorted(sell_by_rarity.items())))
    print("keep by rarity:", dict(sorted(keep_by_rarity.items())))
    print(f"estimated zenny: {zenny:,}")


if __name__ == "__main__":
    main()
