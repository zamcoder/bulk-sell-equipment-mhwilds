"""Summarizes BulkSellProbe output files (trace, snapshots, methods) from reframework/data/BulkSellProbe.

Usage:
  python -I tools/probe_report.py trace <trace.json> [--all]
  python -I tools/probe_report.py diff <snapshot_before.json> <snapshot_after.json>
  python -I tools/probe_report.py methods <methods.json> <type-or-substring>...
"""
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def short(method):
    return method.replace("app.savedata.", "s.").replace("System.", "")


def trace_report(path, show_all):
    data = load(path)
    print(f"hooked={data['hooked']} errors={len(data.get('hook_errors') or [])}")
    counts = data.get("counts") or {}
    print("\n== call counts (desc) ==")
    for method, count in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"{count:6d}  {short(method)}")
    print("\n== calls in order ==")
    trace = data.get("trace") or []
    start = trace[0]["clock"] if trace else 0
    for record in trace:
        method = record["method"]
        if not show_all and counts.get(method, 0) > 40:
            continue
        args = record.get("args") or []
        ret = record.get("ret")
        this = record.get("this")
        print(f"{record['seq']:5d} +{record['clock'] - start:8.3f}s {short(method)} args={args} ret={ret}"
              + (f" this={this}" if this and this.startswith("<app.GUI") else ""))


def rows_by_index(snapshot):
    result = {}
    for box in snapshot.get("boxes") or []:
        columns = box["columns"]
        for row in box["rows"]:
            result[(box["field"], row[0])] = dict(zip(columns, row))
    return result


def diff_values(prefix, before, after, out):
    if isinstance(before, dict) and isinstance(after, dict):
        for key in sorted(set(before) | set(after)):
            diff_values(f"{prefix}.{key}", before.get(key), after.get(key), out)
    elif isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
        for i, (b, a) in enumerate(zip(before, after)):
            diff_values(f"{prefix}[{i}]", b, a, out)
    elif before != after:
        out.append((prefix, before, after))


def diff_report(before_path, after_path):
    before, after = load(before_path), load(after_path)
    print(f"money_api: {before.get('money_api')} -> {after.get('money_api')}")
    rb, ra = rows_by_index(before), rows_by_index(after)
    print("\n== changed box rows ==")
    for key in sorted(set(rb) | set(ra)):
        if rb.get(key) != ra.get(key):
            print(f"{key}:")
            b, a = rb.get(key) or {}, ra.get(key) or {}
            for column in b.keys() | a.keys():
                if b.get(column) != a.get(column):
                    print(f"   {column}: {b.get(column)} -> {a.get(column)}")
    other = []
    for section in ("equipped_index", "loadouts", "equip_bitsets", "equip", "save", "money"):
        diff_values(section, before.get(section), after.get(section), other)
    print("\n== other differences ==")
    for path, b, a in other[:200]:
        print(f"{path}: {json.dumps(b)[:200]} -> {json.dumps(a)[:200]}")


def methods_report(path, needles):
    data = load(path)
    for group in ("seeds", "related", "gui_methods"):
        for type_name, methods in (data.get(group) or {}).items():
            if any(n.lower() in type_name.lower() for n in needles):
                print(f"== [{group}] {type_name} ({len(methods)})")
                for m in methods:
                    print("   " + m)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "trace":
        trace_report(sys.argv[2], "--all" in sys.argv)
    elif mode == "diff":
        diff_report(sys.argv[2], sys.argv[3])
    elif mode == "methods":
        methods_report(sys.argv[2], sys.argv[3:])
