-- Persistent settings for Bulk Sell, stored in reframework/data/BulkSell/config.json.
--
-- Version 2 (v0.3.0) replaced the rarity rule with the Keep option (mode + best_n +
-- max_rarity). A version 1 file is migrated once: a copy is kept as config.v1.json and
-- the player is told what changed. Every save also writes the version 1 keys, so going
-- back to v0.2.x still works (it then runs in covered or manual mode).

local files = require("BulkSell.files")

local config = {}

local PATH = "BulkSell/config.json"
local V1_COPY = "BulkSell/config.v1.json"
local VERSION = 2
local MODES = { manual = true, covered = true, best = true }
local DECORATIONS = { off = true, owned = true, any = true }

-- Maps keyed by skill id (as a string). REFramework writes an empty table as null, so
-- every map keeps its _format key.
local MAPS = {
    keep_skills = "skill-id-to-min-level",     -- Always keep: exempt from the unique rule
    ignore_skills = "skill-id-to-true",        -- Don't care
    skill_places = "skill-id-to-places",       -- places for one skill in "best" mode
}

local DEFAULTS = {
    version = VERSION,
    window_open = false,
    mode = "covered",
    best_n = 5,
    max_rarity = 8,
    decorations = "off",
    debug = false,              -- write plan dumps and timing lines for bug reports
    keep_skills = { _format = MAPS.keep_skills },
    ignore_skills = { _format = MAPS.ignore_skills },
    skill_places = { _format = MAPS.skill_places },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function integer_in(value, low, high)
    local n = type(value) == "number" and math.tointeger(value)
    return n and n >= low and n <= high and n or nil
end

-- A skill id key: digits only, as written by this file.
local function skill_key(id)
    if type(id) == "number" then id = math.tointeger(id) and tostring(math.tointeger(id)) end
    if type(id) ~= "string" or not id:match("^%d+$") then return nil end
    return tostring(tonumber(id))
end

local function read_map(loaded, name, read_value)
    local result = { _format = MAPS[name] }
    if type(loaded) ~= "table" then return result end
    for id, value in pairs(loaded) do
        local key = id ~= "_format" and skill_key(id) or nil
        if key then
            local v = read_value(value)
            if v ~= nil then result[key] = v end
        end
    end
    return result
end

-- Values of the wrong type or range are replaced by defaults, so a hand-edited file cannot
-- break the mod. Unknown keys are dropped.
function config.validate(loaded)
    local result = copy(DEFAULTS)
    if type(loaded) ~= "table" then return result end
    if type(loaded.window_open) == "boolean" then result.window_open = loaded.window_open end
    if type(loaded.debug) == "boolean" then result.debug = loaded.debug end
    if MODES[loaded.mode] then result.mode = loaded.mode end
    result.best_n = integer_in(loaded.best_n, 1, 10) or DEFAULTS.best_n
    result.max_rarity = integer_in(loaded.max_rarity, 5, 8) or DEFAULTS.max_rarity
    if DECORATIONS[loaded.decorations] then result.decorations = loaded.decorations end
    result.keep_skills = read_map(loaded.keep_skills, "keep_skills", function(v) return integer_in(v, 1, 7) end)
    result.skill_places = read_map(loaded.skill_places, "skill_places", function(v) return integer_in(v, 1, 10) end)
    result.ignore_skills = read_map(loaded.ignore_skills, "ignore_skills", function(v) return v == true or nil end)
    -- One preference per skill: Always keep, then places, then Don't care.
    for key in pairs(result.keep_skills) do
        if key ~= "_format" then
            result.skill_places[key] = nil
            result.ignore_skills[key] = nil
        end
    end
    for key in pairs(result.skill_places) do
        if key ~= "_format" then result.ignore_skills[key] = nil end
    end
    return result
end

-- Version 1 settings in version 2 terms (pure). Returns the new settings and what changed:
--   "best"    the rarity rule became "Keep the best 1 per skill" up to its rarity
--   "manual"  nothing is sold automatically any more (the rule ran without covered sales,
--             or covered sales were off)
--   nil       nothing the player would notice (covered mode, as before)
function config.migrate(loaded)
    loaded = type(loaded) == "table" and loaded or {}
    local v2 = {
        window_open = loaded.window_open,
        keep_skills = loaded.keep_skills,
        mode = "covered",
    }
    local change
    local rule_on = loaded.rule_enabled == true
    local covered_on = loaded.sell_dominated ~= false
    if rule_on and covered_on then
        v2.mode, v2.best_n, v2.max_rarity = "best", 1, integer_in(loaded.rule_max_rarity, 5, 8) or 5
        change = "best"
    elseif not covered_on then
        v2.mode = "manual"
        change = rule_on and "manual" or nil
    end
    return config.validate(v2), change
end

local NOTICES = {
    best = "Your rarity rule is now \"Keep the best 1 per skill\", limited to R%d: it still sells low-rarity talismans, "
        .. "but keeps your best one for every skill and slot shape. To sell more, raise the rarity limit and choose "
        .. "another Keep option. Your old settings are saved in reframework/data/" .. V1_COPY .. ".",
    manual = "Your rarity rule sold talismans without covered ones; that is no longer possible, so Bulk Sell now keeps "
        .. "everything until you choose a Keep option or tick talismans. Your old settings are saved in "
        .. "reframework/data/" .. V1_COPY .. ".",
}

-- Returns the settings and a one-time notice (nil when nothing changed for the player).
-- A missing or corrupt file gives the defaults.
function config.load()
    local status, loaded = files.read_json(PATH)
    if status ~= "ok" then return config.validate(nil), nil end
    local version = math.tointeger(loaded.version or 1) or 1
    if version >= VERSION then return config.validate(loaded), nil end
    local values, change = config.migrate(loaded)
    files.write_json(V1_COPY, loaded)
    config.save(values)
    local notice = change and string.format(NOTICES[change], values.max_rarity) or nil
    return values, notice
end

-- Writes version 2 plus the version 1 keys that v0.2.x reads.
function config.save(values)
    local out = copy(values)
    out.version = VERSION
    out.sell_dominated = values.mode ~= "manual"
    out.rule_enabled = false
    out.rule_max_rarity = 5
    return files.write_json(PATH, out)
end

local function number_map(map, read)
    local result = {}
    for id, value in pairs(map or {}) do
        local number = id ~= "_format" and tonumber(id)
        if number then result[number] = read and read(value) or value end
    end
    return result
end

-- keep_skills as { [skill id number] = min level } for analysis.plan.
function config.keep_skills(values)
    return number_map(values.keep_skills)
end

-- analysis.plan options for these settings (picks and yield are added by the caller).
function config.plan_options(values)
    return {
        mode = values.mode,
        best_n = values.best_n,
        max_rarity = values.max_rarity,
        keep_skills = number_map(values.keep_skills),
        ignore_skills = number_map(values.ignore_skills),
        skill_places = number_map(values.skill_places),
    }
end

config.DEFAULTS = DEFAULTS
config.PATH = PATH
config.V1_COPY = V1_COPY

return config
