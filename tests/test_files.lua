-- Tests for BulkSell/files.lua (quiet JSON reads) and BulkSell/sidecar.lua (RNG Charm Crafting bonuses).

local mock = require("mock_reframework")
local eq = mock.eq
local env = mock.install()
local files = require("BulkSell.files")
local sidecar = require("BulkSell.sidecar")

local PATH = "BulkSell/some-file.json"

-- Regex for fs.glob: dot escaped, either path separator.
eq(files.pattern("A/b-c.json"), "^A[\\\\/]b-c\\.json$", "glob regex")

-- Older REFramework without fs.read: json.load_file is used.
eq(fs, nil, "no fs before enable_fs")
eq(files.read_json(PATH), "missing", "fallback: missing")
env.files[PATH] = { a = 1 }
local status, value = files.read_json(PATH)
eq(status, "ok", "fallback: ok")
eq(value.a, 1, "fallback: value")
env.files[PATH] = nil
local fallback_calls = env.load_file_calls

-- Current REFramework: fs.read + fs.glob + json.load_string, no json.load_file.
env.enable_fs()
eq(files.read_json(PATH), "missing", "missing file")
env.put_raw(PATH, "text-ok", { a = 2 })
status, value = files.read_json(PATH)
eq(status, "ok", "ok file")
eq(value.a, 2, "ok value")
env.put_raw(PATH, "")
eq(files.read_json(PATH), "corrupt", "existing empty file is corrupt")
env.put_raw(PATH, "garbage")
eq(files.read_json(PATH), "corrupt", "unparsable file is corrupt")
env.put_raw(PATH, "5", 5)
eq(files.read_json(PATH), "corrupt", "non-table JSON is corrupt")
eq(files.exists(PATH), true, "glob sees the file (backslash path)")
env.raw[PATH] = nil
eq(files.exists(PATH), false, "glob misses a missing file")
eq(env.load_file_calls, fallback_calls, "json.load_file never used with fs")

-- fs.glob is slow in game: never used for a file with content, once for several files.
local OTHER = "BulkSell/other-file.json"
env.put_raw(PATH, "text-ok", { a = 2 })
local globs = env.glob_calls
eq(files.read_json(PATH), "ok", "file with content")
eq(env.glob_calls, globs, "no glob for a file with content")
eq(files.read_json(OTHER), "missing", "missing file")
eq(env.glob_calls, globs + 1, "one glob for a file that reads empty")
eq(files.read_json(OTHER, false), "missing", "known missing")
eq(env.glob_calls, globs + 1, "no glob when the caller knows")
local present = files.existing({ PATH, OTHER })
eq(present[PATH], true, "existing: present")
eq(present[OTHER], false, "existing: absent")
globs = env.glob_calls
local read = files.reader({ PATH, OTHER, "BulkSell/third.json" })
eq(env.glob_calls, globs + 1, "one glob for two empty reads")
eq(read(PATH), "ok", "reader: content")
eq(read(OTHER), "missing", "reader: missing")
eq(read("BulkSell/third.json"), "missing", "reader: missing too")
env.put_raw(OTHER, "")
read = files.reader({ OTHER })
eq(read(OTHER), "corrupt", "reader: existing empty file is corrupt")
eq(read("BulkSell/not-listed.json"), "missing", "reader: other paths read normally")
env.raw[OTHER] = nil
env.raw[PATH] = nil

-- Without fs.glob an empty read cannot be told from a missing file.
local glob = fs.glob
fs.glob = nil
env.put_raw(PATH, "")
eq(files.read_json(PATH), "missing", "empty without glob reads as missing")
eq(files.exists(PATH), nil, "exists unknown without glob")
fs.glob = glob
env.raw[PATH] = nil

-- Sidecar parsing --------------------------------------------------------------
local function reader(by_path)
    return function(path)
        local entry = by_path[path]
        if entry == nil then return "missing" end
        if entry == "corrupt" then return "corrupt" end
        return "ok", entry
    end
end

local A = "TalismanCrafting/special-bonuses-slot-0-a.json"
local B = "TalismanCrafting/special-bonuses-slot-0-b.json"
local function store(entries)
    entries._format = entries._format or "box-map-v1"
    return { version = 2, revision = 1, profile = { slot = 0, play_start = "1" }, entries = entries }
end
local function entry(box, free0, packed)
    return { box_index = box, identity = { free0 = free0, free1 = 1, packed = packed }, kind = "set", pair = 1 }
end

local result = sidecar.load(nil, reader({}))
assert(result.blocked and result.blocked:find("save slot"), "unknown save slot blocks")

result = sidecar.load(0, reader({}))
eq(result.blocked, nil, "no sidecars: nothing blocked")
eq(table.concat(result.files, ", "), "a missing, b missing", "file status line")

result = sidecar.load(0, reader({ [A] = store({ ["3"] = entry(3, 190, { 3005, 0, 0, 2110 }) }) }))
eq(result.blocked, nil, "valid store")
eq(result.files[1], "a ok (1 entries)", "entry count")
eq(sidecar.protects(result, 3, "anything"), true, "protected by box index")
eq(sidecar.protects(result, 77, "190:3005:0:0:2110"), true, "protected by identity at another box")
eq(sidecar.protects(result, 77, "190:3005:0:0:2111"), false, "other talisman not protected")

result = sidecar.load(0, reader({ [B] = store({ ["4"] = entry(4, 191.0, { 3048.0, 0, 0, 1100 }) }) }))
eq(sidecar.protects(result, 99, "191:3048:0:0:1100"), true, "whole-number floats accepted")

result = sidecar.load(0, reader({ [A] = { version = 1, revision = 0, profile = { slot = 0, play_start = "1" } } }))
eq(result.blocked, nil, "version 1 store without entries is fine")

local corrupt_cases = {
    { "corrupt file", "corrupt" },
    { "unknown format", store({ _format = "other" }) },
    { "entries missing", { version = 2, revision = 0 } },
    { "entry without identity", store({ ["3"] = { box_index = 3 } }) },
    { "non-numeric key", store({ abc = entry(3, 190, { 1, 0, 0, 0 }) }) },
    { "fractional identity", store({ ["3"] = entry(3, 190.5, { 1, 0, 0, 0 }) }) },
    { "short packed list", store({ ["3"] = entry(3, 190, { 1, 0 }) }) },
    { "not a table", 5 },
}
for _, case in ipairs(corrupt_cases) do
    result = sidecar.load(0, reader({ [B] = case[2] }))
    assert(result.blocked and result.blocked:find("special-bonuses-slot-0-b.json", 1, true), case[1] .. " blocks selling")
    eq(result.files[2], "b corrupt", case[1] .. " status")
end

print("files and sidecar tests passed")
