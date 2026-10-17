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

local picks = {}

local FORMAT = "bulk-sell-picks"
local MAP_FORMAT = "box index -> pick"
local VERSION = 1
local MAX_ENTRIES = 2400
local ACTIONS = { sell = true, keep = true }

function picks.paths(slot)
    local base = "BulkSell/picks/slot-" .. tostring(slot)
    return { a = base .. "-a.json", b = base .. "-b.json" }
end

-- An empty store for one save slot and character.
function picks.new(slot, play_start)
    return { slot = slot, play_start = play_start, revision = 0, entries = {}, dirty = false,
        last_file = nil, blocked = nil, undo = nil }
end

-- Entries of a decoded file, or nil when the file is not a valid picks file of this slot.
local function decode(value, slot, play_start)
    if type(value) ~= "table" or value._format ~= FORMAT or math.tointeger(value.save_slot) ~= slot then return nil end
    if type(value.picks) ~= "table" or value.picks._format ~= MAP_FORMAT then return nil end
    if play_start and value.play_start ~= nil and tostring(value.play_start) ~= tostring(play_start) then return nil, "other" end
    local entries, n = {}, 0
    for key, pick in pairs(value.picks) do
        local box = key ~= "_format" and type(key) == "string" and key:match("^%d+$") and tonumber(key)
        if box and type(pick) == "table" and ACTIONS[pick.action] and type(pick.fp) == "string" and n < MAX_ENTRIES then
            entries[box] = { action = pick.action, fp = pick.fp, at = type(pick.at) == "string" and pick.at or nil }
            n = n + 1
        end
    end
    return entries, math.tointeger(value.revision) or 0
end

-- Loads the newest valid copy. `read_json(path)` returns "ok", value | "missing" | "corrupt".
-- Returns the store; store.blocked is a reason when a file exists but no copy is usable.
function picks.load(slot, play_start, read_json)
    local store = picks.new(slot, play_start)
    local best_entries, best_revision, best_name
    local unreadable = false
    for _, name in ipairs({ "a", "b" }) do
        local status, value = read_json(picks.paths(slot)[name])
        local entries, revision
        if status == "ok" then entries, revision = decode(value, slot, play_start) end
        if entries then
            if not best_revision or revision > best_revision then
                best_entries, best_revision, best_name = entries, revision, name
            end
        elseif status ~= "missing" and revision ~= "other" then
            unreadable = true
        end
    end
    if best_entries then
        -- The other copy may be an older or half-written one; the newest valid copy wins.
        store.entries, store.revision, store.last_file = best_entries, best_revision, best_name
    elseif unreadable then
        store.blocked = "Your saved Sell/Keep ticks could not be read (reframework/data/BulkSell/picks/)."
    end
    return store
end

-- The player chose to go on without the unreadable picks; the next write replaces them.
function picks.continue_without(store)
    store.blocked = nil
    store.entries = {}
    store.dirty = true
end

-- Writes the other copy with the next revision and reads it back.
-- Returns true, or false when the file could not be written or did not read back.
function picks.save(store, write_json, read_json)
    if store.blocked or store.slot == nil then return false end
    local name = store.last_file == "a" and "b" or "a"
    local path = picks.paths(store.slot)[name]
    local map, n = { _format = MAP_FORMAT }, 0
    for key, pick in pairs(store.entries) do
        map[tostring(key)] = { action = pick.action, fp = pick.fp, at = pick.at }
        n = n + 1
    end
    local revision = store.revision + 1
    local value = {
        version = VERSION, _format = FORMAT, save_slot = store.slot, revision = revision, count = n,
        play_start = store.play_start ~= nil and tostring(store.play_start) or nil,
        picks = map,
    }
    if not write_json(path, value) then return false end
    local status, back = read_json(path)
    local entries, back_revision = decode(status == "ok" and back or nil, store.slot, store.play_start)
    if not entries or back_revision ~= revision then return false end
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    if count ~= n then return false end
    store.revision, store.last_file, store.dirty = revision, name, false
    return true
end

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
