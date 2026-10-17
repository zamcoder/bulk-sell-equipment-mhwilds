-- The favorite stars Bulk Sell added, per save slot, in
-- reframework/data/BulkSell/stars/slot-<n>-a.json and -b.json (see ab_store.lua).
-- Only stars the mod added are listed, so "Remove stars Bulk Sell added" never touches a
-- star the player set. An entry carries the talisman's fingerprint and is only acted on
-- while the same talisman is still in that box entry and still a favorite. Pure Lua.

local ab = require("BulkSell.ab_store")

local stars = {}

local KIND = {
    base = "BulkSell/stars/slot-",
    format = "bulk-sell-stars",
    map_format = "box index -> star",
    field = "added",
    blocked = "The list of stars Bulk Sell added could not be read (reframework/data/BulkSell/stars/).",
    decode = function(e)
        if type(e) ~= "table" or type(e.fp) ~= "string" then return nil end
        return { fp = e.fp, at = type(e.at) == "string" and e.at or nil }
    end,
    encode = function(e) return { fp = e.fp, at = e.at } end,
}

function stars.paths(slot) return ab.paths(KIND, slot) end
stars.new = ab.new
function stars.load(slot, play_start, read_json) return ab.load(KIND, slot, play_start, read_json) end
function stars.save(store, write_json, read_json) return ab.save(KIND, store, write_json, read_json) end

function stars.add(store, charm)
    store.entries[charm.key] = { fp = charm.fingerprint, at = os.date("%Y-%m-%d %H:%M:%S") }
    store.dirty = true
end

function stars.forget(store, key)
    if store.entries[key] then
        store.entries[key] = nil
        store.dirty = true
    end
end

-- Listed stars that can be removed now: same talisman, still a favorite. Box order.
function stars.removable(store, charms)
    local list = {}
    for _, charm in ipairs(charms) do
        local entry = store.entries[charm.key]
        if entry and entry.fp == charm.fingerprint and charm.favorite then list[#list + 1] = charm end
    end
    return list
end

-- Entries whose star is no longer the one Bulk Sell added: the talisman is gone, changed,
-- or the player removed the star (a star set again later is the player's own). They are
-- dropped after a scan.
function stars.stale_keys(store, charms)
    local by_key, stale = {}, {}
    for _, charm in ipairs(charms) do by_key[charm.key] = charm end
    for key, entry in pairs(store.entries) do
        local charm = by_key[key]
        if not charm or charm.fingerprint ~= entry.fp or not charm.favorite then stale[#stale + 1] = key end
    end
    table.sort(stale)
    return stale
end

function stars.count(store)
    local n = 0
    for _ in pairs(store.entries) do n = n + 1 end
    return n
end

return stars
