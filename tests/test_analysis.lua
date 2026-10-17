local analysis = require("BulkSell.analysis")
local support = require("analysis_support")

local charm, eq = support.charm, support.eq
local runner = support.runner()
local test = runner.test

local function covers(upper, lower)
    return analysis.covers(analysis.prepare(upper), analysis.prepare(lower))
end

local function verdict_of(verdicts, key)
    return assert(verdicts[key], "missing verdict for " .. tostring(key))
end

local function plan(charms, options)
    local o = support.copy(options or {})
    if o.preview == nil then o.preview = false end
    return analysis.plan(charms, o)
end

local function list_text(list)
    local parts = {}
    for i, v in ipairs(list or {}) do parts[i] = tostring(v) end
    return table.concat(parts, ",")
end

-- Cover ------------------------------------------------------------------------

test("skill superset at higher level covers", function()
    eq(covers(charm(1, 5, "10:2,20:1"), charm(2, 5, "10:1")), true)
    eq(covers(charm(1, 5, "10:1"), charm(2, 5, "10:2")), false, "lower level")
    eq(covers(charm(1, 5, "10:3"), charm(2, 5, "10:1,20:1")), false, "missing skill")
end)

test("slots compare by kind and level", function()
    eq(covers(charm(1, 5, "", "W3"), charm(2, 5, "", "W1")), true)
    eq(covers(charm(1, 5, "", "W1"), charm(2, 5, "", "W3")), false, "lower slot")
    eq(covers(charm(1, 5, "", "A3"), charm(2, 5, "", "W1")), false, "armor slot cannot hold weapon deco")
    eq(covers(charm(1, 5, "", "W3,W1"), charm(2, 5, "", "W1,W2")), true, "unordered input")
    eq(covers(charm(1, 5, "", "W3"), charm(2, 5, "", "W1,W1")), false, "one slot cannot hold two")
end)

test("signature text is the v0.2.2 text", function()
    eq(analysis.prepare(charm(1, 5, "20:1,10:2", "A1,W1,A2")).signature, "10:2,20:1|W1|A2,1")
    eq(analysis.prepare(charm(1, 5, "20:1,10:2", "A1"), { [20] = true }).signature, "10:2|W|A1", "Don't care left out")
end)

-- Covered mode (the default, same verdicts as v0.2.2) ---------------------------

test("dominated charm is sold and points at a kept charm", function()
    local verdicts = plan({ charm(1, 5, "10:1"), charm(2, 6, "10:2", "A1") })
    eq(verdict_of(verdicts, 1).action, "sell")
    eq(verdict_of(verdicts, 1).reason, "dominated")
    eq(verdict_of(verdicts, 1).ref, 2)
    eq(verdict_of(verdicts, 2).action, "keep")
    eq(verdict_of(verdicts, 2).reason, "best")
end)

test("dominance chains resolve to the top charm", function()
    local verdicts = plan({ charm(1, 5, "10:1"), charm(2, 5, "10:2"), charm(3, 5, "10:3") })
    eq(verdict_of(verdicts, 1).ref, 3)
    eq(verdict_of(verdicts, 2).ref, 3)
    eq(verdict_of(verdicts, 3).action, "keep")
end)

test("duplicates keep the lowest key", function()
    local verdicts = plan({ charm(7, 5, "10:1", "W1"), charm(3, 5, "10:1", "W1"), charm(9, 5, "10:1", "W1") })
    eq(verdict_of(verdicts, 3).action, "keep")
    eq(verdict_of(verdicts, 7).reason, "duplicate")
    eq(verdict_of(verdicts, 7).ref, 3)
    eq(verdict_of(verdicts, 9).ref, 3)
end)

test("protected charms are never sold and win duplicate ties", function()
    local verdicts = plan({
        charm(1, 5, "10:1"),
        charm(2, 5, "10:1", nil, "equipped"),
        charm(3, 5, "10:1", nil, "loadout"),
        charm(4, 5, "10:3"),
    })
    eq(verdict_of(verdicts, 2).reason, "protected")
    eq(verdict_of(verdicts, 3).reason, "protected")
    eq(verdict_of(verdicts, 1).action, "sell")
    eq(verdict_of(verdicts, 1).ref, 4)
    eq(verdict_of(verdicts, 4).action, "keep")
end)

test("protected duplicate becomes the keeper", function()
    local verdicts = plan({ charm(1, 5, "10:1"), charm(2, 5, "10:1", nil, "equipped") })
    eq(verdict_of(verdicts, 1).reason, "duplicate")
    eq(verdict_of(verdicts, 1).ref, 2)
end)

test("summary counts and zenny (the cheaper copy is kept)", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 6, "10:2"), charm(3, 5, "10:2") }
    local verdicts = plan(charms)
    local summary = analysis.summarize(charms, verdicts)
    eq(summary.sell, 2)
    eq(summary.keep, 1)
    eq(verdict_of(verdicts, 3).action, "keep", "R5 copy kept")
    eq(verdict_of(verdicts, 2).reason, "duplicate", "R6 copy sold")
    eq(summary.zenny, 500 + 600)
    eq(summary.by_reason.dominated, 1)
    eq(summary.by_reason.duplicate, 1)
end)

test("every sold charm is covered by a kept charm (random boxes)", function()
    math.randomseed(1234)
    for _ = 1, 30 do
        local charms = {}
        for key = 1, 120 do
            local skills, slots = {}, {}
            for _ = 1, math.random(1, 3) do skills[#skills + 1] = math.random(1, 6) .. ":" .. math.random(1, 3) end
            for _ = 1, math.random(0, 3) do slots[#slots + 1] = (math.random() < 0.5 and "W" or "A") .. math.random(1, 3) end
            charms[#charms + 1] = charm(key, math.random(5, 8), table.concat(skills, ","), table.concat(slots, ","),
                math.random() < 0.05 and "equipped" or nil)
        end
        local verdicts = plan(charms)
        local by_key = {}
        for _, c in ipairs(charms) do by_key[c.key] = c end
        for _, c in ipairs(charms) do
            local verdict = verdicts[c.key]
            if verdict.action == "sell" then
                local keeper = by_key[verdict.ref]
                eq(verdicts[keeper.key].action, "keep", "ref of " .. c.key .. " is kept")
                eq(covers(keeper, c), true, "keeper " .. keeper.key .. " covers " .. c.key)
                eq(c.protected, nil, "protected charm sold")
            end
        end
        for _, a in ipairs(charms) do
            if verdicts[a.key].reason == "best" then
                for _, b in ipairs(charms) do
                    if a ~= b and verdicts[b.key].action == "keep" and covers(b, a) then
                        eq(covers(a, b), true, "kept " .. a.key .. " is strictly covered by kept " .. b.key)
                    end
                end
            end
        end
    end
end)

-- Best N per skill: the unique rule (ported from the v0.2.2 rarity-rule tests) -----

-- 11, 12, 13 are the best holders of skills 10, 20, 30 and cover none of the others.
local HOLDERS = { charm(11, 8, "10:3"), charm(12, 8, "20:3"), charm(13, 8, "30:3") }
local function with_holders(list)
    local out = {}
    for _, c in ipairs(HOLDERS) do out[#out + 1] = c end
    for _, c in ipairs(list) do out[#out + 1] = c end
    return out
end
local BEST1_R5 = { mode = "best", best_n = 1, max_rarity = 5 }

test("best 1 up to R5 sells a low unique talisman unless Always keep applies", function()
    local charms = with_holders({ charm(1, 5, "10:1,20:1"), charm(2, 5, "20:2,30:1"), charm(3, 7, "10:1,30:1") })
    local verdicts = plan(charms, { mode = "best", best_n = 1, max_rarity = 5, keep_skills = { [20] = 2 } })
    eq(verdict_of(verdicts, 1).reason, "rule")
    eq(verdict_of(verdicts, 1).unique, true, "unique")
    eq(list_text(verdict_of(verdicts, 1).refs), "11,12", "certificate")
    eq(verdict_of(verdicts, 2).reason, "exempt", "Always keep")
    eq(verdict_of(verdicts, 2).detail, 20, "exempting skill")
    eq(verdict_of(verdicts, 3).reason, "rarity", "rarity above the limit")
    for _, key in ipairs({ 11, 12, 13 }) do eq(verdict_of(verdicts, key).reason, "top_n", "holder " .. key) end
    eq(verdict_of(verdicts, 11).detail.skill, 10, "floor detail skill")
    eq(verdict_of(verdicts, 11).detail.rank, 1, "floor detail rank")
end)

test("Always keep below its minimum level does not exempt", function()
    local verdicts = plan(with_holders({ charm(1, 5, "10:1,20:1") }),
        { mode = "best", best_n = 1, max_rarity = 5, keep_skills = { [20] = 2 } })
    eq(verdict_of(verdicts, 1).reason, "rule")
end)

test("a talisman sold by the rule is never a ref", function()
    -- 1 is sold by the rule; 2 is worse than 1 but stays (R6) because nothing kept covers it.
    local charms = with_holders({ charm(1, 5, "10:2,20:2", "A1"), charm(2, 6, "10:1", "A1"), charm(14, 8, "30:3,40:3", "A2") })
    local verdicts = plan(charms, BEST1_R5)
    eq(verdict_of(verdicts, 1).reason, "rule")
    eq(verdict_of(verdicts, 2).action, "keep")
    eq(verdict_of(verdicts, 2).reason, "rarity")
    for key, v in pairs(verdicts) do
        if v.ref then eq(verdicts[v.ref].action, "keep", "ref of " .. key) end
        for _, ref in ipairs(v.refs or {}) do eq(verdicts[ref].action, "keep", "certificate of " .. key) end
    end
end)

test("manual mode sells only picks", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 6, "10:2") }
    local verdicts = plan(charms, { mode = "manual" })
    eq(verdict_of(verdicts, 1).reason, "auto_off", "covered talisman kept in manual mode")
    eq(verdict_of(verdicts, 2).reason, "auto_off")
    verdicts = plan(charms, { mode = "manual", picks = { [2] = "sell" } })
    eq(verdict_of(verdicts, 2).reason, "picked")
    eq(verdict_of(verdicts, 2).action, "sell")
    eq(verdict_of(verdicts, 1).action, "keep")
end)

-- Floor and ranking --------------------------------------------------------------

-- Skill 10 at levels 5..1, each with a slot trade-off so that none covers another.
local function ladder(protect)
    return {
        charm(1, 5, "10:5", "", protect and protect[1]), charm(2, 5, "10:4", "A1", protect and protect[2]),
        charm(3, 5, "10:3", "A2"), charm(4, 5, "10:2", "A3"), charm(5, 5, "10:1", "A3,A1"),
    }
end
local NO_SHAPES = { mode = "best", best_n = 2, slot_floor = false }

test("the floor keeps exactly the best N per skill", function()
    local verdicts = plan(ladder(), NO_SHAPES)
    eq(verdict_of(verdicts, 1).reason, "top_n")
    eq(verdict_of(verdicts, 2).reason, "top_n")
    for _, key in ipairs({ 3, 4, 5 }) do
        eq(verdict_of(verdicts, key).reason, "rule", "box " .. key)
        eq(list_text(verdict_of(verdicts, key).refs), "1,2", "refs of " .. key)
    end
    eq(verdict_of(verdicts, 3).rank.rank, 3, "closest rank")
end)

test("protected and picked talismans inside N take a place", function()
    local verdicts = plan(ladder({ "favorite" }), NO_SHAPES)
    eq(verdict_of(verdicts, 1).reason, "protected")
    eq(verdict_of(verdicts, 3).action, "sell", "no extra place for the protected one")
    verdicts = plan(ladder(), { mode = "best", best_n = 2, slot_floor = false, picks = { [2] = "keep" } })
    eq(verdict_of(verdicts, 2).reason, "picked")
    eq(verdict_of(verdicts, 3).action, "sell", "no extra place for a Keep pick")
end)

test("per-skill places and few holders", function()
    local verdicts = plan(ladder(), { mode = "best", best_n = 2, slot_floor = false, skill_places = { [10] = 3 } })
    eq(verdict_of(verdicts, 3).reason, "top_n", "third place")
    eq(verdict_of(verdicts, 4).reason, "rule")
    verdicts = plan(ladder(), { mode = "best", best_n = 5, slot_floor = false })
    eq(support.sell_count(verdicts), 0, "fewer holders than N: all stay")
end)

test("the slot-shape floor keeps the best N talismans that hold a shape", function()
    -- 21..24 are the only A3 talismans; strong slotless holders outrank them on every skill.
    local charms = {}
    for x = 1, 4 do
        charms[#charms + 1] = charm(20 + x, 5, (30 + x) .. ":1", "A3")
        charms[#charms + 1] = charm(40 + x, 8, (30 + x) .. ":3")
    end
    local verdicts = plan(charms, { mode = "best", best_n = 1 })
    eq(verdict_of(verdicts, 21).reason, "top_n", "best A3 holder stays")
    eq(verdict_of(verdicts, 21).detail.shape, "W|A3", "kept for its shape")
    for x = 2, 4 do eq(verdict_of(verdicts, 20 + x).reason, "rule", "A3 talisman " .. (20 + x)) end
    eq(list_text(verdict_of(verdicts, 22).refs), "21,42", "skill and shape certificate")
    verdicts = plan(charms, { mode = "best", best_n = 2 })
    eq(verdict_of(verdicts, 22).reason, "top_n", "two A3 places")
    verdicts = plan(charms, { mode = "best", best_n = 1, slot_floor = false })
    eq(verdict_of(verdicts, 21).reason, "rule", "no shape places")
end)

test("rank ties are broken in the documented order", function()
    local function first(a, b, extra, what)
        local charms = { a, b }
        for _, c in ipairs(extra or {}) do charms[#charms + 1] = c end
        local _, info = plan(charms, { mode = "best", best_n = 1 })
        eq(info.ranks[a.key][10], 1, what)
        eq(info.ranks[b.key][10], 2, what)
    end
    first(charm(1, 5, "10:3,20:1"), charm(2, 5, "10:2,30:1"), nil, "level")
    first(charm(1, 5, "10:2,20:1", "A3"), charm(2, 5, "10:2,30:1", "A1,A1"), nil, "slot total")
    first(charm(1, 5, "10:2,20:1", "A1,A1"), charm(2, 5, "10:2,30:1", "A2"), nil, "slot count")
    first(charm(1, 5, "10:2,20:1", "W1"), charm(2, 5, "10:2,30:1", "A1"), nil, "weapon slots")
    first(charm(1, 5, "10:2,20:2"), charm(2, 5, "10:2,30:1"), { charm(3, 5, "30:3") }, "other skills, normalised")
    first(charm(1, 5, "10:2,20:1"), charm(2, 6, "10:2,30:1"), nil, "cheaper")
    first(charm(1, 6, "10:2,20:1"), charm(2, 6, "10:2,30:1"), nil, "content order of skills")
    first(charm(2, 5, "10:2", "A2,A2"), charm(1, 5, "10:2", "A3,A1"), nil, "content order of slots")
end)

test("protection and picks never move the ranking", function()
    local _, plain = plan(ladder(), NO_SHAPES)
    local _, pinned = plan(ladder({ nil, "equipped" }), { mode = "best", best_n = 2, slot_floor = false, picks = { [4] = "keep" } })
    for key = 1, 5 do eq(pinned.ranks[key][10], plain.ranks[key][10], "rank of " .. key) end
end)

-- Rarity limit, Always keep, Don't care ------------------------------------------

test("rarity limit keeps unique talismans above it, but not covered ones", function()
    local charms = with_holders({ charm(1, 7, "10:1,20:1"), charm(2, 7, "10:2", "") })
    local verdicts = plan(charms, { mode = "best", best_n = 1, max_rarity = 6 })
    eq(verdict_of(verdicts, 1).reason, "rarity")
    eq(verdict_of(verdicts, 2).reason, "dominated", "covered R7 still sold")
    eq(verdict_of(verdicts, 2).ref, 11)
end)

test("Always keep only exempts from the unique rule", function()
    local charms = with_holders({ charm(1, 5, "10:1,20:1"), charm(2, 5, "10:1,20:1") })
    local verdicts = plan(charms, { mode = "best", best_n = 1, keep_skills = { [20] = 1 } })
    eq(verdict_of(verdicts, 1).reason, "exempt")
    eq(verdict_of(verdicts, 2).reason, "duplicate", "identical copy still sold")
    eq(verdict_of(verdicts, 2).ref, 1)
end)

test("Don't care skills are ignored by grouping, cover and places", function()
    local charms = { charm(1, 6, "10:2,30:3"), charm(2, 5, "10:2"), charm(3, 5, "30:1", "A1") }
    local verdicts = plan(charms, { mode = "covered", ignore_skills = { [30] = true } })
    eq(verdict_of(verdicts, 1).reason, "duplicate", "same counted skills")
    eq(verdict_of(verdicts, 1).ref, 2, "cheaper copy kept")
    eq(verdict_of(verdicts, 1).drops, nil, "no counted loss")
    eq(verdict_of(verdicts, 1).ignored_drops[1].id, 30, "Don't care loss reported")
    eq(verdict_of(verdicts, 1).ignored_drops[1].kept, 1, "best kept level of the Don't care skill")
    local _, info = plan(charms, { mode = "best", best_n = 1, ignore_skills = { [30] = true } })
    eq(info.lists[30], nil, "no places for a Don't care skill")
end)

test("Always keep wins over Don't care", function()
    local charms = { charm(1, 6, "10:2,30:3"), charm(2, 5, "10:2") }
    local verdicts = plan(charms, { mode = "covered", ignore_skills = { [30] = true }, keep_skills = { [30] = 1 } })
    eq(verdict_of(verdicts, 1).action, "keep", "skill 30 counts again")
    eq(verdict_of(verdicts, 2).reason, "dominated")
end)

-- Picks and keepers --------------------------------------------------------------

test("a Sell pick is never a ref; its dependents point elsewhere", function()
    local charms = { charm(1, 5, "10:3"), charm(2, 5, "10:2"), charm(3, 5, "10:1") }
    local verdicts = plan(charms, { picks = { [1] = "sell" } })
    eq(verdict_of(verdicts, 1).reason, "picked")
    eq(verdict_of(verdicts, 1).covered_by, nil, "nothing kept covers it")
    eq(verdict_of(verdicts, 1).unique, true)
    eq(verdict_of(verdicts, 2).reason, "best")
    eq(verdict_of(verdicts, 3).ref, 2)
end)

test("a Sell pick on the only holder reports what is lost", function()
    local verdicts = plan({ charm(1, 5, "10:3,20:1"), charm(2, 5, "10:2") }, { picks = { [1] = "sell" } })
    local drops = verdict_of(verdicts, 1).drops
    eq(#drops, 2, "two skills drop")
    eq(drops[1].id, 10)
    eq(drops[1].kept, 2, "best left")
    eq(drops[2].id, 20)
    eq(drops[2].kept, 0, "none left")
end)

test("a Sell pick on a covered talisman names the coverer", function()
    local verdicts = plan({ charm(1, 5, "10:1"), charm(2, 5, "10:2") }, { mode = "manual", picks = { [1] = "sell" } })
    eq(verdict_of(verdicts, 1).covered_by, 2)
    eq(verdict_of(verdicts, 1).unique, nil)
end)

test("a Sell pick on a protected talisman is ignored", function()
    local verdicts, info = plan({ charm(1, 5, "10:1", "", "favorite") }, { picks = { [1] = "sell" } })
    eq(verdict_of(verdicts, 1).reason, "protected")
    eq(#info.notices, 1, "notice")
end)

test("a Keep pick makes its copy the keeper, without an extra place", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 5, "10:1") }
    local verdicts = plan(charms, { picks = { [2] = "keep" } })
    eq(verdict_of(verdicts, 2).reason, "picked")
    eq(verdict_of(verdicts, 1).reason, "duplicate")
    eq(verdict_of(verdicts, 1).ref, 2)
end)

-- Explanations and preview --------------------------------------------------------

test("a rule sale that a kept talisman covers is shown as covered", function()
    local verdicts = plan({ charm(1, 5, "10:3"), charm(2, 5, "10:1") }, { mode = "best", best_n = 1 })
    eq(verdict_of(verdicts, 2).reason, "dominated")
    eq(verdict_of(verdicts, 2).detail, "rule")
    eq(verdict_of(verdicts, 2).ref, 1)
end)

test("an orphan above the rarity limit stays", function()
    -- 2 (R8) is covered only by 1, which the rule sells; nothing else kept covers it.
    local charms = with_holders({ charm(1, 7, "10:2,20:2", "A1"), charm(2, 8, "10:1", "A1"), charm(14, 8, "30:3,40:3", "A2") })
    local verdicts = plan(charms, { mode = "best", best_n = 1, max_rarity = 7 })
    eq(verdict_of(verdicts, 1).reason, "rule")
    eq(verdict_of(verdicts, 2).reason, "rarity")
end)

test("the preview equals separate plans", function()
    math.randomseed(77)
    local box = support.random_box(120, { n_skills = 8 })
    local _, info = analysis.plan(box, { mode = "best", best_n = 4 })
    for _, n in ipairs({ 10, 5, 4, 3, 2, 1 }) do
        local verdicts = plan(box, { mode = "best", best_n = n })
        eq(info.preview.best[n].sell, support.sell_count(verdicts), "best " .. n)
    end
    eq(info.preview.covered.sell, support.sell_count(plan(box, { mode = "covered" })), "covered")
    eq(info.preview.manual.sell, 0, "manual")
    eq(info.preview.unlimited, nil, "no rarity limit, no extra count")
    local _, limited = analysis.plan(box, { mode = "best", best_n = 2, max_rarity = 6 })
    eq(limited.preview.unlimited.sell, support.sell_count(plan(box, { mode = "best", best_n = 2, max_rarity = 8 })),
        "what the same N sells up to R8")
end)

test("planning what stays sells nothing", function()
    math.randomseed(5)
    local box = support.random_box(150, { n_skills = 9 })
    local verdicts = plan(box, { mode = "best", best_n = 2, max_rarity = 7 })
    local kept = {}
    for _, c in ipairs(box) do
        if verdicts[c.key].action == "keep" then kept[#kept + 1] = c end
    end
    eq(support.sell_count(plan(kept, { mode = "best", best_n = 2, max_rarity = 7 })), 0, "idempotent")
end)

-- Decoration-aware cover (hidden until v0.5.1) ----------------------------------

test("decoration cover fills missing levels from spare slots", function()
    local upper = analysis.prepare(charm(1, 5, "10:2", "A1,A1"))
    local lower = analysis.prepare(charm(2, 5, "10:2,20:1"))
    local why = {}
    eq(analysis.covers_deco(upper, lower, { [20] = { kind = "A", size = 1 } }, why), true, "any decoration")
    eq(why[1].id, 20, "needed decoration")
    eq(analysis.covers_deco(upper, lower, { [20] = { kind = "W", size = 1 } }), false, "wrong slot kind")
    eq(analysis.covers_deco(upper, lower, {}), false, "no decoration for the skill")
    eq(analysis.covers_deco(upper, lower, { [20] = { kind = "A", size = 1, free = 0 } }), false, "none owned")
end)

test("owned decorations must also fill the slots they replace", function()
    local upper = analysis.prepare(charm(1, 5, "10:2", "A1,A1"))
    local lower = analysis.prepare(charm(2, 5, "10:2,20:1", "A1"))
    eq(analysis.covers_deco(upper, lower, { [20] = { kind = "A", size = 1, free = 1 } }), false, "free 1 < d + m = 2")
    eq(analysis.covers_deco(upper, lower, { [20] = { kind = "A", size = 1, free = 2 } }), true, "free 2")
end)

test("decoration cover never replaces an Always-keep skill or sells the floor", function()
    local charms = { charm(1, 5, "10:2", "A1,A1"), charm(2, 5, "10:2,20:1") }
    local decos = { [20] = { kind = "A", size = 1 } }
    eq(plan(charms, { mode = "covered", decorations = decos })[2].reason, "best", "2 is the only Skill20: floor lock")
    charms[3] = charm(3, 5, "20:2")
    eq(plan(charms, { mode = "covered", decorations = decos })[2].reason, "dominated", "sold once 3 holds Skill20")
    eq(plan(charms, { mode = "covered", decorations = decos })[2].needs[1].id, 20, "decoration listed")
    eq(plan(charms, { mode = "covered", decorations = decos, keep_skills = { [20] = 1 } })[2].reason, "best",
        "no decoration stands in for an Always-keep skill")
end)

-- Checker -------------------------------------------------------------------------

test("the checker reports injected faults", function()
    local box = require("fixtures.box_20261017")
    local options = { mode = "best", best_n = 3, max_rarity = 7, preview = false }
    local verdicts = analysis.plan(box, options)
    eq(#analysis.check(box, verdicts, options), 0, "a real plan is clean")
    local sold, kept, protected, r8_kept = {}, {}, nil, nil
    for _, c in ipairs(box) do
        local v = verdicts[c.key]
        if v.action == "sell" then sold[#sold + 1] = c.key else kept[#kept + 1] = c.key end
        if c.protected and not protected then protected = c.key end
        if v.action == "keep" and c.rarity == 8 and not c.protected and not r8_kept then r8_kept = c.key end
    end
    table.sort(sold)
    table.sort(kept)
    local sole_top
    for _, c in ipairs(box) do
        local v = verdicts[c.key]
        if v.reason == "top_n" and v.detail.skill and v.detail.rank == 1 then sole_top = c.key break end
    end
    local mutations = {
        { "protected sold", protected, { action = "sell", reason = "rule", detail = "unique" } },
        { "ref points at a sold talisman", sold[1], { action = "sell", reason = "dominated", ref = sold[2] } },
        { "best holder sold by the rule", sole_top, { action = "sell", reason = "rule", detail = "unique" } },
        { "false cover claim", sold[1], { action = "sell", reason = "dominated", ref = kept[1] } },
        { "rule sale above the rarity limit", r8_kept, { action = "sell", reason = "rule", detail = "unique" } },
    }
    for _, m in ipairs(mutations) do
        local mutated = analysis.plan(box, options)
        mutated[assert(m[2], m[1])] = m[3]
        local problems = analysis.check(box, mutated, options)
        eq(#problems > 0, true, m[1])
    end
end)

test("sales that fail the checker are held back", function()
    local real = analysis.check
    analysis.check = function() return { { key = 2, what = "test fault" } } end
    local ok, verdicts, info = pcall(analysis.plan, { charm(1, 5, "10:2"), charm(2, 5, "10:1") }, { preview = false })
    analysis.check = real
    assert(ok, verdicts)
    eq(verdicts[2].action, "keep")
    eq(verdicts[2].detail, "safety_check")
    eq(verdicts[2].was.reason, "dominated")
    eq(info.held_back[1], 2)
end)

test("diff lists keys whose action changed", function()
    local old = { [1] = { action = "keep" }, [2] = { action = "sell" }, [3] = { action = "keep" } }
    local new = { [1] = { action = "keep" }, [2] = { action = "keep" }, [3] = { action = "sell" }, [4] = { action = "sell" } }
    eq(list_text(analysis.diff(old, new)), "2,3")
end)

-- Losses (for any set of sales) ---------------------------------------------------

test("losses: selling the only holder removes the skill", function()
    local drops = analysis.losses({ charm(1, 5, "9:2"), charm(2, 5, "10:1") }, { [1] = true })
    eq(#drops, 1, "one drop")
    eq(drops[1].id, 9, "skill")
    eq(drops[1].from, 2, "from")
    eq(drops[1].to, 0, "to")
    eq(drops[1].boxes[1], 1, "box")
end)

test("losses: a lower level left behind and several top holders", function()
    local charms = { charm(1, 5, "9:3"), charm(2, 5, "9:3"), charm(3, 5, "9:1"), charm(4, 5, "9:3,10:2") }
    eq(#analysis.losses(charms, { [1] = true, [2] = true }), 0, "a top holder stays")
    local drops = analysis.losses(charms, { [1] = true, [2] = true, [4] = true })
    eq(#drops, 2, "two skills drop")
    eq(drops[1].id, 9, "sorted by id")
    eq(drops[1].to, 1, "lower level left")
    eq(#drops[1].boxes, 3, "every sold top holder listed")
    eq(drops[2].id, 10, "second skill")
    eq(drops[2].to, 0, "second skill gone")
end)

test("losses: nothing sold, nothing lost", function()
    eq(#analysis.losses({ charm(1, 5, "9:2") }, {}), 0, "no drops")
end)

-- Work spread over frames ----------------------------------------------------------

test("yield is called while analysing large boxes", function()
    local charms = {}
    for key = 1, 300 do charms[key] = charm(key, 5, (key % 40) .. ":" .. (key % 3 + 1)) end
    local yields = 0
    analysis.plan(charms, { yield = function() yields = yields + 1 end })
    eq(yields > 0, true, "yield called")
end)

runner.run()
