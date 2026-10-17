-- The player's own Sell / Keep ticks ("picks"), per save slot, in
-- reframework/data/BulkSell/picks/slot-<n>-a.json and -b.json. Pure Lua: file access goes
-- through the functions passed in, so everything here can be tested offline.
--
-- Writes alternate between the two files with a rising revision and are read back, so a
-- crash during a write leaves the previous copy intact. A file made for another character
-- (other PlayStartDateTime) is ignored. When a picks file exists but neither copy can be
-- read, selling waits until the player chooses to continue without their picks.
--
-- Picks are keyed by Equipment Box index and carry the talisman's fingerprint, so a pick
-- never applies to another talisman that later lands in the same box entry.

local ab = require("BulkSell.ab_store")

local picks = {}

local ACTIONS = { sell = true, keep = true }

local KIND = {
    base = "BulkSell/picks/slot-",
    format = "bulk-sell-picks",
    map_format = "box index -> pick",
    field = "picks",
    blocked = "Your saved Sell/Keep ticks could not be read (reframework/data/BulkSell/picks/).",
    decode = function(pick)
        if type(pick) ~= "table" or not ACTIONS[pick.action] or type(pick.fp) ~= "string" then return nil end
        return { action = pick.action, fp = pick.fp, at = type(pick.at) == "string" and pick.at or nil }
    end,
    encode = function(pick) return { action = pick.action, fp = pick.fp, at = pick.at } end,
}

function picks.paths(slot) return ab.paths(KIND, slot) end

-- An empty store for one save slot and character.
picks.new = ab.new

-- Loads the newest valid copy. `read_json(path)` returns "ok", value | "missing" | "corrupt".
-- Returns the store; store.blocked is a reason when a file exists but no copy is usable.
function picks.load(slot, play_start, read_json) return ab.load(KIND, slot, play_start, read_json) end

-- The player chose to go on without the unreadable picks; the next write replaces them.
function picks.continue_without(store)
    store.blocked = nil
    store.entries = {}
    store.dirty = true
end

-- Writes the other copy with the next revision and reads it back.
-- Returns true, or false when the file could not be written or did not read back.
function picks.save(store, write_json, read_json) return ab.save(KIND, store, write_json, read_json) end

-- Matches stored picks with the scanned box (pure). `charms` carry key, fingerprint and
-- protected. Returns the picks for analysis.plan ({ [key] = action }, protected ones left
-- out), the entries to keep storing, and notices ({ key, what }).
--   Sell pick, same talisman, not protected   active
--   Sell pick, same talisman, now protected   dropped, with a notice
--   Sell pick, talisman changed or gone       dropped, with a notice
--   Keep pick, same talisman                  kept (active only while unprotected)
--   Keep pick, talisman changed or gone       moved to the lowest identical talisman without a pick, else dropped
function picks.reconcile(entries, charms)
    local by_key, by_fp = {}, {}
    for _, c in ipairs(charms) do
        by_key[c.key] = c
        if c.fingerprint then
            by_fp[c.fingerprint] = by_fp[c.fingerprint] or {}
            table.insert(by_fp[c.fingerprint], c)
        end
    end
    for _, list in pairs(by_fp) do table.sort(list, function(a, b) return a.key < b.key end) end
    local active, kept, notices = {}, {}, {}
    local keys = {}
    for key in pairs(entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local pick = entries[key]
        local c = by_key[key]
        if c and c.fingerprint == pick.fp then
            if pick.action == "sell" and c.protected then
                notices[#notices + 1] = { key = key, what = "now " .. c.protected }
            else
                kept[key] = pick
                if not c.protected then active[key] = pick.action end
            end
        elseif pick.action == "keep" then
            local moved
            for _, other in ipairs(by_fp[pick.fp] or {}) do
                if not entries[other.key] and not kept[other.key] then
                    moved = other
                    break
                end
            end
            if moved then
                kept[moved.key] = { action = "keep", fp = pick.fp, at = pick.at }
                if not moved.protected then active[moved.key] = "keep" end
                notices[#notices + 1] = { key = key, what = "moved to #" .. moved.key }
            else
                notices[#notices + 1] = { key = key, what = "changed or gone" }
            end
        else
            notices[#notices + 1] = { key = key, what = "changed or gone" }
        end
    end
    return active, kept, notices
end

local function now() return os.date("%Y-%m-%d %H:%M:%S") end

-- A click on a row's Sell box: an unpicked row gets the opposite of what the plan does
-- with it; a picked row loses its pick (the rules decide again). Protected rows ignore it.
function picks.click(store, charm, action)
    if charm.protected then return false end
    local entries = store.entries
    if entries[charm.key] then
        entries[charm.key] = nil
    else
        entries[charm.key] = { action = action == "sell" and "keep" or "sell", fp = charm.fingerprint, at = now() }
    end
    store.dirty = true
    return true
end

-- "Mark shown": Sell, Keep or Auto (no pick) for every unprotected charm in the list.
-- The previous picks are kept for one Undo.
function picks.mark(store, charms, action)
    local undo = {}
    for key, pick in pairs(store.entries) do undo[key] = pick end
    local changed = 0
    for _, c in ipairs(charms) do
        if not c.protected then
            local current = store.entries[c.key]
            if action == "auto" then
                if current then
                    store.entries[c.key] = nil
                    changed = changed + 1
                end
            elseif not current or current.action ~= action or current.fp ~= c.fingerprint then
                store.entries[c.key] = { action = action, fp = c.fingerprint, at = now() }
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        store.undo = undo
        store.dirty = true
    end
    return changed
end

function picks.undo(store)
    if not store.undo then return false end
    store.entries, store.undo, store.dirty = store.undo, nil, true
    return true
end

-- Picks of sold talismans are removed.
function picks.remove(store, keys)
    local removed = 0
    for _, key in ipairs(keys) do
        if store.entries[key] then
            store.entries[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then store.dirty = true end
    return removed
end

function picks.count(store)
    local sell, keep = 0, 0
    for _, pick in pairs(store.entries) do
        if pick.action == "sell" then sell = sell + 1 else keep = keep + 1 end
    end
    return sell, keep
end

return picks
