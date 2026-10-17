-- What was in the Equipment Box at the last scan (box index -> fingerprint), per save slot,
-- in reframework/data/BulkSell/seen/slot-<n>-a.json and -b.json (see ab_store.lua). Talismans
-- whose box entry holds something else at the next scan are the new arrivals. Pure Lua.

local ab = require("BulkSell.ab_store")

local seen = {}

local KIND = {
    base = "BulkSell/seen/slot-",
    format = "bulk-sell-seen",
    map_format = "box index -> fingerprint",
    field = "boxes",
    blocked = nil,   -- an unreadable baseline only means no arrivals are shown once
    decode = function(e)
        if type(e) ~= "table" or type(e.fp) ~= "string" then return nil end
        return { fp = e.fp }
    end,
    encode = function(e) return { fp = e.fp } end,
}

function seen.paths(slot) return ab.paths(KIND, slot) end
function seen.load(slot, play_start, read_json) return ab.load(KIND, slot, play_start, read_json) end
function seen.save(store, write_json, read_json) return ab.save(KIND, store, write_json, read_json) end

-- Compares a scan with the baseline and makes the scan the new baseline.
-- Returns the keys (box order) that hold a talisman the baseline did not have there.
-- An empty baseline (first scan ever) has no arrivals.
function seen.update(store, charms)
    local had_baseline = next(store.entries) ~= nil
    local arrivals, now = {}, {}
    for _, charm in ipairs(charms) do
        local before = store.entries[charm.key]
        if had_baseline and (not before or before.fp ~= charm.fingerprint) then arrivals[#arrivals + 1] = charm.key end
        now[charm.key] = { fp = charm.fingerprint }
    end
    local changed = false
    for key, entry in pairs(now) do
        local before = store.entries[key]
        if not before or before.fp ~= entry.fp then changed = true break end
    end
    if not changed then
        for key in pairs(store.entries) do
            if not now[key] then changed = true break end
        end
    end
    if changed then
        store.entries = now
        store.dirty = true
    end
    table.sort(arrivals)
    return arrivals
end

return seen
