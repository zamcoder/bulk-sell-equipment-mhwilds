local picks = require("BulkSell.picks")
local analysis = require("BulkSell.analysis")
local reference = require("fixtures.selection_reference")
local support = require("analysis_support")
local eq = support.eq
local runner = support.runner()
local test = runner.test

-- A fake reframework/data folder: files hold decoded JSON, or "garbage" for a corrupt file.
local function disk()
    local d = { files = {}, writes = 0, fail_write = false, mangle = nil }
    function d.read(path)
        local value = d.files[path]
        if value == nil then return "missing" end
        if value == "garbage" then return "corrupt" end
        return "ok", support.copy(value)
    end
    function d.write(path, value)
        if d.fail_write then return false end
        d.writes = d.writes + 1
        d.files[path] = d.mangle and d.mangle(support.copy(value)) or support.copy(value)
        return true
    end
    return d
end

local function keys_text(map)
    local keys = {}
    for k, v in pairs(map) do keys[#keys + 1] = tostring(k) .. "=" .. (type(v) == "table" and v.action or tostring(v)) end
    table.sort(keys)
    return table.concat(keys, ",")
end

test("reconcile follows the table in the spec", function()
    local entries = {
        [10] = { action = "sell", fp = "a" },   -- unchanged -> active
        [11] = { action = "sell", fp = "b" },   -- now protected -> dropped
        [12] = { action = "sell", fp = "c" },   -- changed -> dropped
        [13] = { action = "keep", fp = "d" },   -- changed, identical copy at 20 -> moved
        [14] = { action = "keep", fp = "e" },   -- gone, no copy -> dropped
        [15] = { action = "keep", fp = "f" },   -- now protected -> stays stored, not active
    }
    local charms = {
        { key = 10, fingerprint = "a" }, { key = 11, fingerprint = "b", protected = "favorite" },
        { key = 12, fingerprint = "x" }, { key = 13, fingerprint = "y" }, { key = 20, fingerprint = "d" },
        { key = 21, fingerprint = "d" }, { key = 15, fingerprint = "f", protected = "equipped" },
    }
    local active, kept, notices = picks.reconcile(entries, charms)
    eq(keys_text(active), "10=sell,20=keep", "active picks")
    eq(keys_text(kept), "10=sell,15=keep,20=keep", "stored picks")
    eq(#notices, 4, "notices")
    eq(notices[1].what, "now favorite", "protected notice")
    eq(notices[3].what, "moved to #20", "moved notice")
    -- Same result as the reference model's reconcile.
    local ref_active, ref_kept = reference.reconcile(entries, charms)
    eq(keys_text(ref_active), keys_text(active), "reference active")
    eq(keys_text(ref_kept), keys_text(kept), "reference stored")
end)

test("save and load round trip through alternating files", function()
    local d = disk()
    local store = picks.new(0, "638763618528919137")
    store.entries[2292] = { action = "sell", fp = "191:3048:3078:0:1100", at = "2026-10-17 10:03:40" }
    store.entries[7] = { action = "keep", fp = "190:1:2:3:4" }
    assert(picks.save(store, d.write, d.read), "first save")
    eq(store.last_file, "a", "first copy")
    eq(store.revision, 1, "revision")
    local file = d.files["BulkSell/picks/slot-0-a.json"]
    eq(file._format, "bulk-sell-picks", "format")
    eq(file.picks._format, "box index -> pick", "map format")
    eq(file.picks["2292"].fp, "191:3048:3078:0:1100", "string keys")
    eq(file.play_start, "638763618528919137", "play start")
    store.entries[7] = nil
    assert(picks.save(store, d.write, d.read), "second save")
    eq(store.last_file, "b", "copies alternate")
    local loaded = picks.load(0, "638763618528919137", d.read)
    eq(loaded.revision, 2, "newest copy wins")
    eq(keys_text(loaded.entries), "2292=sell", "entries")
    eq(loaded.entries[2292].at, "2026-10-17 10:03:40", "time kept")
    eq(loaded.blocked, nil, "not blocked")
end)

test("a write that does not read back is reported", function()
    local d = disk()
    local store = picks.new(0, "1")
    store.entries[5] = { action = "sell", fp = "x" }
    store.dirty = true
    d.fail_write = true
    eq(picks.save(store, d.write, d.read), false, "write failed")
    eq(store.dirty, true, "still dirty")
    d.fail_write = false
    d.mangle = function(v) v.revision = 99 return v end
    eq(picks.save(store, d.write, d.read), false, "read back mismatch")
    d.mangle = function(v) v.picks["5"] = nil return v end
    eq(picks.save(store, d.write, d.read), false, "missing entry on read back")
    d.mangle = nil
    eq(picks.save(store, d.write, d.read), true, "then it works")
    eq(store.dirty, false, "clean")
end)

test("a corrupt copy falls back to the other one", function()
    local d = disk()
    local store = picks.new(1, "9")
    store.entries[3] = { action = "keep", fp = "f" }
    picks.save(store, d.write, d.read)   -- a, revision 1
    store.entries[4] = { action = "sell", fp = "g" }
    picks.save(store, d.write, d.read)   -- b, revision 2
    d.files["BulkSell/picks/slot-1-b.json"] = "garbage"
    local loaded = picks.load(1, "9", d.read)
    eq(loaded.blocked, nil, "the older copy is used")
    eq(keys_text(loaded.entries), "3=keep", "older entries")
    eq(loaded.last_file, "a", "next write goes to b")
end)

test("no readable copy pauses selling until the player continues", function()
    local d = disk()
    d.files["BulkSell/picks/slot-0-a.json"] = "garbage"
    local store = picks.load(0, "1", d.read)
    assert(store.blocked, "blocked")
    eq(picks.save(store, d.write, d.read), false, "no write while blocked")
    d.files["BulkSell/picks/slot-0-a.json"] = { _format = "something else" }
    assert(picks.load(0, "1", d.read).blocked, "wrong format blocks too")
    picks.continue_without(store)
    eq(store.blocked, nil, "unblocked")
    assert(picks.save(store, d.write, d.read), "saved")
    eq(picks.load(0, "1", d.read).blocked, nil, "readable again")
end)

test("picks of another character or save slot are ignored", function()
    local d = disk()
    local store = picks.new(0, "111")
    store.entries[3] = { action = "keep", fp = "f" }
    picks.save(store, d.write, d.read)
    local other = picks.load(0, "222", d.read)
    eq(next(other.entries), nil, "other character starts empty")
    eq(other.blocked, nil, "and is not blocked")
    eq(next(picks.load(1, "111", d.read).entries), nil, "other slot has its own files")
    eq(picks.paths(2).a, "BulkSell/picks/slot-2-a.json", "per-slot path")
end)

test("invalid entries are dropped when loading", function()
    local d = disk()
    d.files["BulkSell/picks/slot-0-a.json"] = {
        _format = "bulk-sell-picks", save_slot = 0, revision = 4, play_start = "1",
        picks = { _format = "box index -> pick", ["5"] = { action = "sell", fp = "x" }, ["abc"] = { action = "sell", fp = "y" },
            ["6"] = { action = "steal", fp = "z" }, ["7"] = { action = "keep" }, ["8"] = "keep" },
    }
    local store = picks.load(0, "1", d.read)
    eq(keys_text(store.entries), "5=sell", "only the valid entry")
end)

test("clicks, Mark shown and Undo", function()
    local store = picks.new(0, "1")
    local a = { key = 1, fingerprint = "fa" }
    local b = { key = 2, fingerprint = "fb", protected = "favorite" }
    local c = { key = 3, fingerprint = "fc" }
    eq(picks.click(store, a, "sell"), true, "click on a planned sale")
    eq(store.entries[1].action, "keep", "becomes a Keep pick")
    eq(store.entries[1].fp, "fa", "with its fingerprint")
    picks.click(store, a, "keep")
    eq(store.entries[1], nil, "a second click removes the pick")
    eq(picks.click(store, b, "keep"), false, "protected rows ignore clicks")
    eq(picks.mark(store, { a, b, c }, "sell"), 2, "Mark shown skips protected rows")
    eq(keys_text(store.entries), "1=sell,3=sell", "marked")
    eq(picks.mark(store, { a }, "auto"), 1, "Auto removes picks")
    eq(keys_text(store.entries), "3=sell", "auto")
    eq(picks.undo(store), true, "undo")
    eq(keys_text(store.entries), "1=sell,3=sell", "undone one step")
    eq(picks.undo(store), false, "only one step")
    local sell, keep = picks.count(store)
    eq(sell, 2, "count sell")
    eq(keep, 0, "count keep")
    eq(picks.remove(store, { 1, 9 }), 1, "sold picks removed")
    eq(keys_text(store.entries), "3=sell", "after a sale")
end)

test("a Sell pick reconciled into the plan sells that talisman", function()
    local charms = { support.charm(1, 5, "10:3"), support.charm(2, 5, "10:2") }
    local store = picks.new(0, "1")
    store.entries[1] = { action = "sell", fp = charms[1].fingerprint }
    local active = picks.reconcile(store.entries, charms)
    local verdicts = analysis.plan(charms, { picks = active, preview = false })
    eq(verdicts[1].reason, "picked", "picked")
    eq(verdicts[2].action, "keep", "the other stays")
end)

runner.run()
