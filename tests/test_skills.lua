-- Per-skill settings and the Skills panel's numbers (BulkSell/skills.lua).

local skills = require("BulkSell.skills")
local analysis = require("BulkSell.analysis")
local config = require("BulkSell.config")
local support = require("analysis_support")
local charm, eq = support.charm, support.eq
local runner = support.runner()
local test = runner.test

local function settings()
    return config.validate(nil)
end

local function labels(list)
    local out = {}
    for i, pref in ipairs(list) do out[i] = skills.label(pref) end
    return table.concat(out, ", ")
end

test("one preference per skill", function()
    local s = settings()
    eq(skills.pref_of(s, 10).kind, "default", "nothing stored")
    skills.set(s, 10, { kind = "keep", min = 2 })
    eq(s.keep_skills["10"], 2, "Keep all Lv2+")
    skills.set(s, 10, { kind = "best", n = 5 })
    eq(s.keep_skills["10"], nil, "the old preference goes")
    eq(s.skill_places["10"], 5, "Best 5")
    skills.set(s, 10, { kind = "ignore" })
    eq(s.skill_places["10"], nil, "places gone")
    eq(s.ignore_skills["10"], true, "Don't care")
    eq(skills.pref_of(s, 10).kind, "ignore", "read back")
    skills.set(s, 10, { kind = "default" })
    eq(skills.pref_of(s, 10).kind, "default", "back to Default")
    local v = config.validate(s)
    eq(v.ignore_skills["10"], nil, "nothing left after validation")
end)

test("combo choices follow the best level in the box", function()
    eq(labels((skills.choices(3, { kind = "default" }))),
        "Default, Best 1, Best 2, Best 3, Best 5, Best 10, Keep all, Keep all Lv2+, Keep all Lv3+, Don't care")
    eq(labels((skills.choices(1, { kind = "default" }))), "Default, Best 1, Best 2, Best 3, Best 5, Best 10, Keep all, Don't care",
        "no Lv2+ for a level-1 skill")
    local list, current = skills.choices(3, { kind = "best", n = 4 })
    eq(skills.label(list[current]), "Best 4", "a hand-edited value is shown")
    eq(skills.label(list[#list]), "Don't care", "Don't care stays last")
    local _, keep_index = skills.choices(3, { kind = "keep", min = 2 })
    eq(keep_index, 8, "current choice")
end)

test("panel counts and rows", function()
    local s = settings()
    skills.set(s, 1, { kind = "keep", min = 1 })
    skills.set(s, 2, { kind = "best", n = 3 })
    skills.set(s, 3, { kind = "ignore" })
    skills.set(s, 4, { kind = "ignore" })
    local c = skills.counts(s)
    eq(c.keep, 1, "keep all")
    eq(c.custom, 1, "custom")
    eq(c.ignore, 2, "don't care")
    local charms = { charm(1, 5, "10:3"), charm(2, 5, "10:1,20:2"), charm(3, 5, "20:1") }
    local verdicts = { [1] = { action = "sell" }, [2] = { action = "keep" }, [3] = { action = "keep" } }
    local rows = skills.rows(charms, verdicts, settings(), { [10] = "Attack Boost", [20] = "Ambush" })
    eq(rows[1].name, "Ambush", "sorted by name")
    eq(rows[1].count, 2, "on talismans")
    eq(rows[1].best, 2, "best level")
    eq(rows[1].loss, false, "Ambush keeps its best")
    eq(rows[2].name, "Attack Boost", "second row")
    eq(rows[2].kept, 1, "kept count")
    eq(rows[2].kept_best, 1, "best kept level")
    eq(rows[2].loss, true, "Attack Boost 3 leaves the box")
end)

test("last of their kind", function()
    local charms = {
        charm(1, 5, "10:3"),             -- only Skill10 3
        charm(2, 5, "10:2", "A3"),       -- only A3
        charm(3, 5, "20:2"), charm(4, 5, "20:2", "A1"),   -- two Skill20 2; 4's A1 is also held by 2
    }
    local _, info = analysis.plan(charms, { preview = false })
    local last = skills.last_of_kind(charms, info.entry_of)
    eq(last[1], true, "sole best level")
    eq(last[2], true, "sole slot shape")
    eq(last[3], nil, "one of two")
    eq(last[4], nil, "its slot shape is held by another")
end)

test("what a change was", function()
    local base = { mode = "best", best_n = 3, max_rarity = 8, keep_skills = {}, ignore_skills = {}, skill_places = {}, picks = {} }
    local function with(k, v)
        local o = support.copy(base)
        o[k] = v
        return o
    end
    eq(skills.describe_change(base, base), "box scanned again")
    eq(skills.describe_change(base, with("best_n", 10)), "Keep -> best 10")
    eq(skills.describe_change(base, with("mode", "covered")), "Keep -> every unique talisman")
    eq(skills.describe_change(base, with("max_rarity", 7)), "rarity limit R7")
    eq(skills.describe_change(base, with("ignore_skills", { [5] = true })), "skill settings")
    eq(skills.describe_change(base, with("picks", { [12] = "sell" })), "your picks")
    local both = with("best_n", 5)
    both.picks = { [1] = "keep" }
    eq(skills.describe_change(base, both), "Keep -> best 5, your picks")
end)

test("copy and restore keep the maps apart", function()
    local s = settings()
    skills.set(s, 7, { kind = "ignore" })
    local copy = skills.copy_prefs(s)
    skills.set(s, 7, { kind = "keep", min = 1 })
    skills.restore_prefs(s, copy)
    eq(skills.pref_of(s, 7).kind, "ignore", "restored")
    skills.set(s, 7, { kind = "default" })
    eq(copy.ignore_skills["7"], true, "the copy did not change")
end)

test("Don't care resistances on the real box: the losses name Fire Resistance 3 of #2292", function()
    local box = require("fixtures.box_20261017")
    local ignore = {}
    for _, d in ipairs(require("fixtures.skill_decos")) do
        if d.name:find("Resistance") then ignore[d.id] = true end
    end
    local verdicts = analysis.plan(box, { mode = "covered", ignore_skills = ignore, preview = false })
    local selling, sold = {}, 0
    for _, c in ipairs(box) do
        if verdicts[c.key].action == "sell" then
            selling[c.key] = true
            sold = sold + 1
        end
    end
    eq(sold, 93, "sales")
    local fire
    for _, d in ipairs(analysis.losses(box, selling)) do
        if d.id == 78 then fire = d end
    end
    assert(fire, "Fire Resistance is lost")
    eq(fire.from, 3, "from 3")
    eq(fire.to, 2, "to 2")
    eq(table.concat(fire.boxes, ","), "2292", "box")
    eq(verdicts[2292].ignored_drops[1].id, 78, "the verdict reports it too")
end)

runner.run()
