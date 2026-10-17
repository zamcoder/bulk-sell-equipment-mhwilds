-- Persistent settings for Bulk Sell, stored in reframework/data/BulkSell/config.json.

local files = require("BulkSell.files")

local config = {}

local PATH = "BulkSell/config.json"
local VERSION = 1

local DEFAULTS = {
    version = VERSION,
    window_open = false,
    sell_dominated = true,
    rule_enabled = false,
    rule_max_rarity = 5,
    -- [skill id as string] = minimum level that exempts a charm from the rarity rule
    keep_skills = { _format = "skill-id-to-min-level" },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

-- Values of the wrong type are replaced by defaults, so a hand-edited file cannot break the mod.
local function merge(defaults, loaded)
    local result = copy(defaults)
    if type(loaded) ~= "table" then return result end
    for key, default in pairs(defaults) do
        local value = loaded[key]
        if type(value) == type(default) then
            result[key] = type(value) == "table" and merge(default, value) or value
        end
    end
    if type(loaded.keep_skills) == "table" then
        for id, level in pairs(loaded.keep_skills) do
            if id ~= "_format" and tonumber(id) and type(level) == "number" then result.keep_skills[id] = level end
        end
    end
    return result
end

-- A missing or corrupt file gives the defaults.
function config.load()
    local status, loaded = files.read_json(PATH)
    return merge(DEFAULTS, status == "ok" and loaded or nil)
end

function config.save(values)
    return files.write_json(PATH, values)
end

-- keep_skills as { [skill id number] = min level } for analysis.plan.
function config.keep_skills(values)
    local result = {}
    for id, level in pairs(values.keep_skills) do
        local number = tonumber(id)
        if number then result[number] = level end
    end
    return result
end

config.DEFAULTS = DEFAULTS

return config
