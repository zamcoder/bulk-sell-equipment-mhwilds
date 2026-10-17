-- A small map per save slot (box index -> entry), stored in two JSON files that are written
-- in turn with a rising revision and read back after each write, so a crash during a write
-- leaves the previous copy intact. A copy made for another character (other
-- PlayStartDateTime) is ignored. Pure Lua: file access goes through the functions passed in.
--
-- kind = {
--   base          path prefix; the files are <base><slot>-a.json and -b.json
--   format        the file's _format
--   map_format    the map's _format
--   field         name of the map in the file
--   decode(e)     a stored entry as Lua table, or nil when invalid
--   encode(e)     the entry as written
--   blocked       text shown when a file exists but no copy can be read
-- }

local ab = {}

local VERSION = 1
local MAX_ENTRIES = 2400

function ab.paths(kind, slot)
    local base = kind.base .. tostring(slot)
    return { a = base .. "-a.json", b = base .. "-b.json" }
end

function ab.new(slot, play_start)
    return { slot = slot, play_start = play_start, revision = 0, entries = {}, dirty = false,
        last_file = nil, blocked = nil, undo = nil }
end

-- Entries and revision of a decoded file; nil when it is not a valid file of this slot,
-- or nil, "other" when it belongs to another character.
local function decode(kind, value, slot, play_start)
    if type(value) ~= "table" or value._format ~= kind.format or math.tointeger(value.save_slot) ~= slot then return nil end
    local map = value[kind.field]
    if type(map) ~= "table" or map._format ~= kind.map_format then return nil end
    if play_start and value.play_start ~= nil and tostring(value.play_start) ~= tostring(play_start) then return nil, "other" end
    local entries, n = {}, 0
    for key, stored in pairs(map) do
        local box = key ~= "_format" and type(key) == "string" and key:match("^%d+$") and tonumber(key)
        local entry = box and n < MAX_ENTRIES and kind.decode(stored)
        if entry then
            entries[box] = entry
            n = n + 1
        end
    end
    return entries, math.tointeger(value.revision) or 0
end

-- Loads the newest valid copy. `read_json(path)` returns "ok", value | "missing" | "corrupt".
function ab.load(kind, slot, play_start, read_json)
    local store = ab.new(slot, play_start)
    local best_entries, best_revision, best_name
    local unreadable = false
    for _, name in ipairs({ "a", "b" }) do
        local status, value = read_json(ab.paths(kind, slot)[name])
        local entries, revision
        if status == "ok" then entries, revision = decode(kind, value, slot, play_start) end
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
        store.blocked = kind.blocked
    end
    return store
end

-- Writes the other copy with the next revision and reads it back.
-- Returns true, or false when the file could not be written or did not read back.
function ab.save(kind, store, write_json, read_json)
    if store.blocked or store.slot == nil then return false end
    local name = store.last_file == "a" and "b" or "a"
    local path = ab.paths(kind, store.slot)[name]
    local map, n = { _format = kind.map_format }, 0
    for key, entry in pairs(store.entries) do
        map[tostring(key)] = kind.encode(entry)
        n = n + 1
    end
    local revision = store.revision + 1
    local value = {
        version = VERSION, _format = kind.format, save_slot = store.slot, revision = revision, count = n,
        play_start = store.play_start ~= nil and tostring(store.play_start) or nil,
        [kind.field] = map,
    }
    if not write_json(path, value) then return false end
    local status, back = read_json(path)
    local entries, back_revision = decode(kind, status == "ok" and back or nil, store.slot, store.play_start)
    if not entries or back_revision ~= revision then return false end
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    if count ~= n then return false end
    store.revision, store.last_file, store.dirty = revision, name, false
    return true
end

return ab
