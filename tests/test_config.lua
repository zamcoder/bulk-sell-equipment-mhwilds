local stored = {}
json = {
    load_file = function(path) return stored[path] end,
    dump_file = function(path, value)
        stored[path] = value
        return true
    end,
}

local config = require("BulkSell.config")

local function eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

-- Missing file gives defaults, and defaults are copies.
local values = config.load()
eq(values.sell_dominated, true, "default sell_dominated")
eq(values.rule_max_rarity, 5, "default rule_max_rarity")
values.keep_skills["12"] = 2
eq(config.DEFAULTS.keep_skills["12"], nil, "defaults not mutated")

-- Round trip.
values.sell_dominated = false
assert(config.save(values), "save")
local loaded = config.load()
eq(loaded.sell_dominated, false, "saved false survives")
eq(config.keep_skills(loaded)[12], 2, "keep skill round trip")

-- Wrong types fall back to defaults; junk keep_skills entries are dropped.
stored["BulkSell/config.json"] = {
    sell_dominated = "yes",
    rule_max_rarity = 7,
    keep_skills = { ["5"] = 1, abc = 3, ["9"] = "x" },
}
loaded = config.load()
eq(loaded.sell_dominated, true, "string replaced by default")
eq(loaded.rule_max_rarity, 7, "valid number kept")
local keep = config.keep_skills(loaded)
eq(keep[5], 1, "valid keep skill")
eq(keep[9], nil, "non-number level dropped")
eq(loaded.keep_skills.abc, nil, "non-numeric id dropped")

-- Unreadable file (json.load_file throwing) still gives defaults.
json.load_file = function() error("broken") end
eq(config.load().rule_enabled, false, "defaults when load throws")

print("config tests passed")
