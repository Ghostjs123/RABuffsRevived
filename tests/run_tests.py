"""Runs RABuffs' Lua in Lua 5.1 (the client's version) against the fake game in mock.lua.

    pip install -r tests/requirements.txt
    python tests/run_tests.py              # every test
    python tests/run_tests.py forever cast # only tests whose names contain these words

Each test in tests.lua gets a fresh Lua state, loads the addon files in RABuffs.toc's order and drives it.
"""
import os
import sys

import lupa.lua51 as lupa

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.dirname(TESTS_DIR)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def addon_files():
    files = []
    for line in read(os.path.join(ADDON_DIR, "RABuffs.toc")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def new_runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(read(os.path.join(TESTS_DIR, "mock.lua")))
    sources = lua.table()
    for i, name in enumerate(addon_files(), start=1):
        sources[i] = lua.table(name=name, source=read(os.path.join(ADDON_DIR, name)))
    lua.globals().ADDON_SOURCES = sources
    lua.execute(read(os.path.join(TESTS_DIR, "tests.lua")))
    return lua


def main(filters):
    names = sorted(new_runtime().eval("TestNames()").values())
    if filters:
        names = [n for n in names if any(f in n for f in filters)]
    failed = 0
    for name in names:
        lua = new_runtime()
        ok, message = lua.eval("RunTest")(name)
        if ok:
            print(f"ok    {name}")
        else:
            failed += 1
            print(f"FAIL  {name}\n{message}\n")
    print(f"\n{len(names) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
