-- RNG Charm Crafting's Set/Group bonus sidecars (TalismanCrafting/special-bonuses-slot-<n>-{a,b}.json).
-- Each entry is keyed by box index and also stores the talisman's identity, so a bonus
-- talisman is recognised either way. Pure: the file reader is passed in.
--
-- Fails closed: a sidecar that exists but cannot be understood, or an unknown save
-- slot, sets `blocked`, and selling stays off until it is fixed.

local sidecar = {}

local FORMAT = "box-map-v1"

local function integer(value)
    return type(value) == "number" and math.tointeger(value) or nil
end

-- Same layout as game.lua's fingerprint: amulet type, then BowgunCustomizeId[0..3].
local function identity_key(identity)
    if type(identity) ~= "table" or type(identity.packed) ~= "table" then return nil end
    local parts = { integer(identity.free0) }
    for i = 1, 4 do parts[i + 1] = integer(identity.packed[i]) end
    for i = 1, 5 do
        if parts[i] == nil then return nil end
    end
    return table.concat(parts, ":")
end

-- Adds one store's entries to result; returns "ok" with the entry count, or "corrupt".
local function read_store(store, result)
    if store.version == 1 and store.entries == nil then return "ok", 0 end   -- v1 stores had no entries yet
    local entries = store.entries
    if type(entries) ~= "table" or entries._format ~= FORMAT then return "corrupt" end
    local count = 0
    for key, entry in pairs(entries) do
        if key ~= "_format" then
            local box = type(key) == "string" and key:match("^%d+$") and tonumber(key)
            local identity = type(entry) == "table" and identity_key(entry.identity)
            if not box or not identity then return "corrupt" end
            result.boxes[box] = true
            result.identities[identity] = true
            count = count + 1
        end
    end
    return "ok", count
end

-- read_json(path) -> "ok", value | "missing" | "corrupt" (files.read_json in the mod).
function sidecar.load(save_slot, read_json)
    local result = { boxes = {}, identities = {}, files = {} }
    if integer(save_slot) == nil then
        result.blocked = "Could not read the save slot number, so RNG Charm Crafting bonuses cannot be checked."
        return result
    end
    for _, suffix in ipairs({ "a", "b" }) do
        local path = string.format("TalismanCrafting/special-bonuses-slot-%d-%s.json", save_slot, suffix)
        local status, store = read_json(path)
        local count
        if status == "ok" then
            if type(store) == "table" then
                status, count = read_store(store, result)
            else
                status = "corrupt"
            end
        end
        result.files[#result.files + 1] = suffix .. " " .. status .. (count and string.format(" (%d entries)", count) or "")
        if status == "corrupt" and not result.blocked then
            result.blocked = "RNG Charm Crafting file " .. path .. " could not be read. Selling is off until it is fixed or removed."
        end
    end
    return result
end

function sidecar.protects(result, box, fingerprint)
    return result.boxes[box] == true or result.identities[fingerprint] == true
end

return sidecar
