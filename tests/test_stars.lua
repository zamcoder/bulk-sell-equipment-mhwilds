-- The ledger of stars Bulk Sell added (BulkSell/stars.lua on BulkSell/ab_store.lua).

local stars = require("BulkSell.stars")
local support = require("analysis_support")
local eq = support.eq
local runner = support.runner()
local test = runner.test

local function disk()
    local d = { files = {} }
    function d.read(path)
        local value = d.files[path]
        if value == nil then return "missing" end
        if value == "garbage" then return "corrupt" end
        return "ok", support.copy(value)
    end
    function d.write(path, value)
        d.files[path] = support.copy(value)
        return true
    end
    return d
end

local function talisman(key, fp, favorite) return { key = key, fingerprint = fp, favorite = favorite } end

test("round trip in its own files", function()
    local d = disk()
    local store = stars.new(0, "77")
    stars.add(store, talisman(12, "fp12"))
    stars.add(store, talisman(30, "fp30"))
    assert(stars.save(store, d.write, d.read), "saved")
    local file = d.files["BulkSell/stars/slot-0-a.json"]
    eq(file._format, "bulk-sell-stars", "format")
    eq(file.added["12"].fp, "fp12", "entry")
    local loaded = stars.load(0, "77", d.read)
    eq(stars.count(loaded), 2, "two entries")
    eq(loaded.entries[30].fp, "fp30", "fingerprint kept")
    eq(stars.count(stars.load(0, "88", d.read)), 0, "another character has no entries")
    d.files["BulkSell/stars/slot-0-a.json"] = "garbage"
    assert(stars.load(0, "77", d.read).blocked, "unreadable ledger is reported")
end)

test("only stars Bulk Sell added, on the same talisman and still a favorite, can be removed", function()
    local store = stars.new(0, "1")
    stars.add(store, talisman(1, "a"))
    stars.add(store, talisman(2, "b"))
    stars.add(store, talisman(3, "c"))
    local charms = { talisman(1, "a", true), talisman(2, "other", true), talisman(3, "c", false), talisman(4, "d", true) }
    local list = stars.removable(store, charms)
    eq(#list, 1, "one removable")
    eq(list[1].key, 1, "the unchanged favorite")
    local stale = stars.stale_keys(store, charms)
    eq(table.concat(stale, ","), "2,3", "changed talisman and removed star are forgotten")
    stars.forget(store, 2)
    eq(store.entries[2], nil, "forgotten")
    eq(store.dirty, true, "dirty")
end)

runner.run()
