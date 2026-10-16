local analysis = require("BulkSell.analysis")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- charm(key, rarity, "skill:level,...", "W3,A1", protected)
local function charm(key, rarity, skills, slots, protected)
    local c = { key = key, rarity = rarity, skills = {}, slots = {}, protected = protected, price = rarity * 100 }
    for id, level in (skills or ""):gmatch("(%d+):(%d+)") do
        c.skills[#c.skills + 1] = { id = tonumber(id), level = tonumber(level) }
    end
    for kind, level in (slots or ""):gmatch("([WA])(%d)") do
        c.slots[#c.slots + 1] = { kind = kind, level = tonumber(level) }
    end
    return c
end

local function covers(upper, lower)
    return analysis.covers(analysis.prepare(upper), analysis.prepare(lower))
end

local function verdict_of(verdicts, key)
    return assert(verdicts[key], "missing verdict for " .. tostring(key))
end

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

test("dominated charm is sold and points at a kept charm", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 6, "10:2", "A1") }
    local verdicts = analysis.plan(charms)
    eq(verdict_of(verdicts, 1).action, "sell")
    eq(verdict_of(verdicts, 1).reason, "dominated")
    eq(verdict_of(verdicts, 1).ref, 2)
    eq(verdict_of(verdicts, 2).action, "keep")
    eq(verdict_of(verdicts, 2).reason, "best")
end)

test("dominance chains resolve to the top charm", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 5, "10:2"), charm(3, 5, "10:3") }
    local verdicts = analysis.plan(charms)
    eq(verdict_of(verdicts, 1).ref, 3)
    eq(verdict_of(verdicts, 2).ref, 3)
    eq(verdict_of(verdicts, 3).action, "keep")
end)

test("duplicates keep the lowest key", function()
    local charms = { charm(7, 5, "10:1", "W1"), charm(3, 5, "10:1", "W1"), charm(9, 5, "10:1", "W1") }
    local verdicts = analysis.plan(charms)
    eq(verdict_of(verdicts, 3).action, "keep")
    eq(verdict_of(verdicts, 7).reason, "duplicate")
    eq(verdict_of(verdicts, 7).ref, 3)
    eq(verdict_of(verdicts, 9).ref, 3)
end)

test("protected charms are never sold and win duplicate ties", function()
    local charms = {
        charm(1, 5, "10:1"),
        charm(2, 5, "10:1", nil, "equipped"),
        charm(3, 5, "10:1", nil, "loadout"),
        charm(4, 5, "10:3"),
    }
    local verdicts = analysis.plan(charms)
    eq(verdict_of(verdicts, 2).reason, "protected")
    eq(verdict_of(verdicts, 3).reason, "protected")
    eq(verdict_of(verdicts, 1).action, "sell")
    eq(verdict_of(verdicts, 1).ref, 4)
    eq(verdict_of(verdicts, 4).action, "keep")
end)

test("protected duplicate becomes the keeper", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 5, "10:1", nil, "equipped") }
    local verdicts = analysis.plan(charms)
    eq(verdict_of(verdicts, 1).reason, "duplicate")
    eq(verdict_of(verdicts, 1).ref, 2)
end)

test("rule sells low rarity unless a keep skill is present", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 5, "20:2"), charm(3, 7, "30:1") }
    local verdicts = analysis.plan(charms, { rules = { max_rarity = 5 }, keep_skills = { [20] = 2 } })
    eq(verdict_of(verdicts, 1).reason, "rule")
    eq(verdict_of(verdicts, 2).action, "keep", "keep skill")
    eq(verdict_of(verdicts, 3).action, "keep", "rarity above rule")
end)

test("keep skill below its minimum level does not exempt", function()
    local verdicts = analysis.plan({ charm(1, 5, "20:1") }, { rules = { max_rarity = 5 }, keep_skills = { [20] = 2 } })
    eq(verdict_of(verdicts, 1).reason, "rule")
end)

test("a charm sold by rule is not used as a keeper", function()
    -- 1 matches the rule; 2 is worse than 1 but must stay because 1 leaves the box.
    local charms = { charm(1, 5, "10:3"), charm(2, 6, "10:2") }
    local verdicts = analysis.plan(charms, { rules = { max_rarity = 5 } })
    eq(verdict_of(verdicts, 1).reason, "rule")
    eq(verdict_of(verdicts, 2).action, "keep")
end)

test("rules only when dominance is off", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 6, "10:2") }
    local verdicts = analysis.plan(charms, { sell_dominated = false, rules = { max_rarity = 5 } })
    eq(verdict_of(verdicts, 1).reason, "rule")
    eq(verdict_of(verdicts, 2).reason, "best")
end)

test("summary counts and zenny", function()
    local charms = { charm(1, 5, "10:1"), charm(2, 6, "10:2"), charm(3, 5, "10:2") }
    local verdicts = analysis.plan(charms)
    local summary = analysis.summarize(charms, verdicts)
    eq(summary.sell, 2)
    eq(summary.keep, 1)
    eq(summary.zenny, 500 + 500)
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
        local verdicts = analysis.plan(charms)
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
        -- Nothing kept by "best" may be covered by another kept charm.
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

test("yield is called while analysing large boxes", function()
    local charms = {}
    for key = 1, 300 do charms[key] = charm(key, 5, (key % 40) .. ":" .. (key % 3 + 1)) end
    local yields = 0
    analysis.plan(charms, { yield = function() yields = yields + 1 end })
    eq(yields > 0, true, "yield called")
end)

test("2400 charms analyse quickly", function()
    math.randomseed(99)
    local charms = {}
    for key = 1, 2400 do
        local skills = {}
        for _ = 1, 3 do skills[#skills + 1] = math.random(1, 120) .. ":" .. math.random(1, 3) end
        charms[key] = charm(key, math.random(5, 8), table.concat(skills, ","), "W" .. math.random(1, 3) .. ",A" .. math.random(1, 3))
    end
    local started = os.clock()
    analysis.plan(charms)
    local seconds = os.clock() - started
    print(string.format("     2400 charms analysed in %.3f s", seconds))
    eq(seconds < 2, true, "analysis time")
end)

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        print("ok   " .. t.name)
    else
        failed = failed + 1
        print("FAIL " .. t.name .. ": " .. tostring(err))
    end
end
print(string.format("%d passed, %d failed", #tests - failed, failed))
if failed > 0 then error("tests failed", 0) end
