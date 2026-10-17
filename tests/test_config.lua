local stored, writes = {}, {}
json = {
    load_file = function(path) return stored[path] end,
    dump_file = function(path, value)
        stored[path] = value
        writes[#writes + 1] = path
        return true
    end,
}

local config = require("BulkSell.config")

local function eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function reset(file)
    for k in pairs(stored) do stored[k] = nil end
    for i = #writes, 1, -1 do writes[i] = nil end
    stored[config.PATH] = file
end

-- Missing file gives defaults, and defaults are copies.
reset(nil)
local values, notice = config.load()
eq(values.mode, "covered", "default mode")
eq(values.best_n, 5, "default best_n")
eq(values.max_rarity, 8, "default max_rarity")
eq(notice, nil, "no notice for a new player")
eq(#writes, 0, "nothing written for a missing file")
values.keep_skills["12"] = 2
eq(config.DEFAULTS.keep_skills["12"], nil, "defaults not mutated")

-- Round trip of version 2, with the version 1 keys v0.2.x reads.
values.mode, values.best_n, values.max_rarity = "best", 3, 7
values.ignore_skills["40"] = true
assert(config.save(values), "save")
local saved = stored[config.PATH]
eq(saved.version, 2, "version written")
eq(saved.sell_dominated, true, "legacy key: covered sales on")
eq(saved.rule_enabled, false, "legacy key: rule off")
eq(saved.rule_max_rarity, 5, "legacy key: rule rarity")
local loaded = config.load()
eq(loaded.mode, "best", "mode survives")
eq(loaded.best_n, 3, "best_n survives")
eq(loaded.max_rarity, 7, "max_rarity survives")
eq(config.keep_skills(loaded)[12], 2, "keep skill round trip")
local options = config.plan_options(loaded)
eq(options.mode, "best", "plan mode")
eq(options.keep_skills[12], 2, "plan keep skills by number")
eq(options.ignore_skills[40], true, "plan Don't care by number")
eq(loaded.sell_dominated, nil, "legacy keys are not part of the settings")
values.mode = "manual"
config.save(values)
eq(stored[config.PATH].sell_dominated, false, "manual mode turns v0.2.x covered sales off")

-- Invalid values fall back to defaults; junk map entries are dropped.
reset({
    version = 2, mode = "greedy", best_n = 0, max_rarity = 9.5, decorations = "all", window_open = "yes", extra = 1,
    keep_skills = { ["5"] = 1, abc = 3, ["9"] = "x", ["7"] = 8 },
    skill_places = { ["5"] = 3, ["6"] = 4, ["8"] = 11 },
    ignore_skills = { ["5"] = true, ["6"] = true, ["10"] = true, ["11"] = 1 },
})
loaded = config.load()
eq(loaded.mode, "covered", "unknown mode")
eq(loaded.best_n, 5, "best_n out of range")
eq(loaded.max_rarity, 8, "max_rarity not an integer")
eq(loaded.decorations, "off", "unknown decorations")
eq(loaded.window_open, false, "window_open of the wrong type")
eq(loaded.extra, nil, "unknown key dropped")
local keep = config.keep_skills(loaded)
eq(keep[5], 1, "valid keep skill")
eq(keep[9], nil, "non-number level dropped")
eq(keep[7], nil, "level above 7 dropped")
eq(loaded.keep_skills.abc, nil, "non-numeric id dropped")
eq(loaded.skill_places["5"], nil, "Always keep wins over places")
eq(loaded.skill_places["6"], 4, "valid places")
eq(loaded.skill_places["8"], nil, "places above 10 dropped")
eq(loaded.ignore_skills["5"], nil, "Always keep wins over Don't care")
eq(loaded.ignore_skills["6"], nil, "places win over Don't care")
eq(loaded.ignore_skills["10"], true, "valid Don't care")
eq(loaded.ignore_skills["11"], nil, "Don't care must be true")
for _, name in ipairs({ "keep_skills", "skill_places", "ignore_skills" }) do
    for key in pairs(loaded[name]) do eq(type(key), "string", name .. " keys are strings") end
end

-- A newer version is read as version 2.
reset({ version = 3, mode = "best", best_n = 2 })
loaded, notice = config.load()
eq(loaded.mode, "best", "newer version read")
eq(loaded.best_n, 2, "newer version best_n")
eq(notice, nil, "no migration notice")
eq(#writes, 0, "newer file not rewritten")

-- Migration from version 1 (pure).
local function migrate(v1) return config.migrate(v1) end
local m, change = migrate({ version = 1, sell_dominated = true, rule_enabled = true, rule_max_rarity = 6, keep_skills = { ["3"] = 2 } })
eq(m.mode, "best", "rule becomes best")
eq(m.best_n, 1, "best 1")
eq(m.max_rarity, 6, "rule rarity becomes the limit")
eq(m.keep_skills["3"], 2, "keep skills copied")
eq(change, "best", "change reported")
m, change = migrate({ version = 1, sell_dominated = false, rule_enabled = true, rule_max_rarity = 5 })
eq(m.mode, "manual", "rule without covered sales becomes manual")
eq(change, "manual", "and the player is told")
m, change = migrate({ version = 1, sell_dominated = false, rule_enabled = false })
eq(m.mode, "manual", "covered sales off becomes manual")
eq(change, nil, "nothing changes for the player")
m, change = migrate({ version = 1, sell_dominated = true, rule_enabled = false, window_open = true })
eq(m.mode, "covered", "default stays covered")
eq(m.window_open, true, "window_open copied")
eq(change, nil, "no notice")
m = migrate({})
eq(m.mode, "covered", "a file without version is version 1")

-- The real version 1 file of the player: rule on up to R5, covered sales on, no kept skills.
local real_v1 = { version = 1, window_open = true, sell_dominated = true, rule_enabled = true, rule_max_rarity = 5,
    keep_skills = { _format = "skill-id-to-min-level" } }
reset(real_v1)
loaded, notice = config.load()
eq(loaded.mode, "best", "real config: best")
eq(loaded.best_n, 1, "real config: best 1")
eq(loaded.max_rarity, 5, "real config: up to R5")
assert(notice and notice:find("Keep the best 1 per skill", 1, true) and notice:find("R5", 1, true), "migration notice")
eq(stored[config.V1_COPY], real_v1, "version 1 copy written")
eq(stored[config.PATH].version, 2, "migrated file saved")
loaded, notice = config.load()
eq(notice, nil, "the notice is shown once")

-- The v0.2.x loader reads a version 2 file and runs in covered or manual mode.
local legacy = dofile(PROJECT_ROOT .. "/tests/fixtures/config_v022.lua")
reset(nil)
config.save(loaded)
local old = legacy.load()
eq(old.rule_enabled, false, "v0.2.x: rule off")
eq(old.sell_dominated, true, "v0.2.x: covered sales on")

-- Unreadable file (json.load_file throwing) still gives defaults.
json.load_file = function() error("broken") end
eq(config.load().mode, "covered", "defaults when load throws")

-- With fs.read available a missing config is detected without json.load_file,
-- so REFramework logs nothing on the first run.
local load_file_calls = 0
json.load_file = function()
    load_file_calls = load_file_calls + 1
    return nil
end
fs = { read = function() return "" end, glob = function() return {} end }
json.load_string = function() error("nothing to parse") end
eq(config.load().mode, "covered", "defaults for a missing file")
eq(load_file_calls, 0, "json.load_file not used")
-- A corrupt file also gives defaults.
fs = { read = function() return "{broken" end, glob = function() return { "BulkSell\\config.json" } end }
json.load_string = function() return nil end
eq(config.load().best_n, 5, "defaults for a corrupt file")
fs = nil
json.load_string = nil

print("config tests passed")
