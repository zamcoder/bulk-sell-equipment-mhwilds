"""Syntax-checks every Lua file of the mod and runs the Lua unit tests.

Uses Lua 5.4 through lupa (installed in .venv), the same Lua version REFramework embeds.
Usage: .venv\\Scripts\\python.exe -I tools\\check.py
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parent.parent
LUA_DIRS = [ROOT / "src", ROOT / "dev"]
AUTORUN = (ROOT / "src" / "reframework" / "autorun").as_posix()
TESTS = (ROOT / "tests").as_posix()


def new_runtime():
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = f"{AUTORUN}/?.lua;{AUTORUN}/?/init.lua;{TESTS}/?.lua"
    lua.globals().PROJECT_ROOT = ROOT.as_posix()
    # Route Lua print through Python so output order stays correct.
    lua.globals().print = lambda *args: print("\t".join(str(a) for a in args), flush=True)
    return lua


def check_syntax():
    lua = new_runtime()
    compile_file = lua.eval("function(path) local f, err = loadfile(path) return f ~= nil, err end")
    errors = 0
    for base in LUA_DIRS:
        for path in sorted(base.rglob("*.lua")):
            ok, err = compile_file(path.as_posix())
            if not ok:
                errors += 1
                print(f"SYNTAX {err}", flush=True)
    return errors


def run_tests():
    failures = 0
    for path in sorted((ROOT / "tests").glob("test_*.lua")):
        print(f"== {path.name}", flush=True)
        try:
            new_runtime().globals().dofile(path.as_posix())
        except lua54.LuaError as exc:
            failures += 1
            print(f"ERROR {exc}", flush=True)
    return failures


if __name__ == "__main__":
    syntax_errors = check_syntax()
    failures = run_tests()
    print(f"syntax errors: {syntax_errors}, failing test files: {failures}", flush=True)
    sys.exit(1 if syntax_errors or failures else 0)
