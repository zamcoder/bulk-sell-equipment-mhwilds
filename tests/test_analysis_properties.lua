-- Property tests (guarantees G1-G10 of the selection model on seeded random boxes),
-- differential tests against the frozen reference model and the frozen v0.2.2 analysis,
-- and a timing guard for the largest box.

local analysis = require("BulkSell.analysis")
local reference = require("fixtures.selection_reference")
local v022 = require("fixtures.analysis_v022")
local support = require("analysis_support")

local eq, copy = support.eq, support.copy
local runner = support.runner()
local test = runner.test

local TRIALS = 200

local function sold_set(verdicts)
    local set, n = {}, 0
    for key, v in pairs(verdicts) do
        if v.action == "sell" then
            set[key] = true
            n = n + 1
        end
    end
    return set, n
end

local function same_set(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

local function problem_set(problems)
    local set = {}
    for _, p in ipairs(problems or {}) do set[p.key .. ":" .. p.what] = true end
    return set
end

local function covers_raw(upper, lower, ignore)
    return analysis.covers(analysis.prepare(upper, ignore), analysis.prepare(lower, ignore))
end

local function ignore_of(options)
    local ignore = {}
    for id in pairs(options.ignore_skills or {}) do
        if not (options.keep_skills or {})[id] then ignore[id] = true end
    end
    return ignore
end

-- Verdicts must match the reference exactly; the displayed closest rank may name another
-- label with the same rank number (the reference breaks that tie by table order).
local SKIP_RANK = { rank = true }
local function assert_same_as_reference(box, options, verdicts, info, what)
    local ref_verdicts, ref_info = reference.plan(box, options)
    for _, c in ipairs(box) do
        local a, b = verdicts[c.key], ref_verdicts[c.key]
        local ok, where = support.deep_equal(a, b, "box " .. c.key, SKIP_RANK)
        if not ok then error(what .. ": verdict differs at " .. where, 2) end
        if (a.rank == nil) ~= (b.rank == nil) or (a.rank and a.rank.rank ~= b.rank.rank) then
            error(what .. ": closest rank differs for box " .. c.key, 2)
        end
        if a.rank then eq(info.ranks[c.key][a.rank.skill], a.rank.rank, what .. ": rank label of box " .. c.key) end
    end
    local ok, where = support.deep_equal(info.floor, ref_info.floor, "floor")
    if not ok then error(what .. ": " .. where, 2) end
    if not same_set(problem_set(info.problems), problem_set(ref_info.problems)) then error(what .. ": checker problems differ", 2) end
    if ref_info.preview then
        ok, where = support.deep_equal(info.preview.manual, ref_info.preview.manual, "preview.manual")
        if ok then ok, where = support.deep_equal(info.preview.covered, ref_info.preview.covered, "preview.covered") end
        for _, n in ipairs(analysis.PREVIEW_N) do
            if ok then ok, where = support.deep_equal(info.preview.best[n], ref_info.preview.best[n], "preview.best." .. n) end
        end
        if not ok then error(what .. ": " .. where, 2) end
    end
end

local function check_guarantees(box, options, verdicts, info, what)
    local by = {}
    for _, c in ipairs(box) do by[c.key] = c end
    local picks = options.picks or {}
    local ignore = ignore_of(options)
    eq(#info.problems, 0, what .. ": checker problems")
    for _, c in ipairs(box) do
        local v = verdicts[c.key]
        if c.protected then eq(v.action, "keep", what .. ": G1 protected box " .. c.key) end
        if not c.protected and picks[c.key] then eq(v.action, picks[c.key], what .. ": G7 pick on box " .. c.key) end
        if v.action == "sell" then
            local refs = {}
            if v.ref then refs[#refs + 1] = v.ref end
            for _, r in ipairs(v.refs or {}) do refs[#refs + 1] = r end
            for _, r in ipairs(refs) do
                eq(verdicts[r].action, "keep", what .. ": G2 ref " .. r .. " of box " .. c.key .. " kept")
                if picks[r] == "sell" then eq(by[r].protected ~= nil, true, what .. ": G7 Sell pick used as ref") end
            end
            if (v.reason == "dominated" or v.reason == "duplicate") and not v.needs then
                eq(covers_raw(by[v.ref], c, ignore), true, what .. ": G2 ref covers box " .. c.key)
            end
            if v.reason == "rule" then
                eq(options.mode, "best", what .. ": rule sale outside best mode")
                eq(c.rarity <= (options.max_rarity or 8), true, what .. ": rule sale above the limit")
                -- G3: for every counted skill, at least n_s refs hold it at its level or higher.
                for _, s in ipairs(c.skills) do
                    if not ignore[s.id] then
                        local need = (options.skill_places or {})[s.id] or options.best_n or 5
                        local have = 0
                        for _, r in ipairs(v.refs) do
                            for _, rs in ipairs(by[r].skills) do
                                if rs.id == s.id and rs.level >= s.level then have = have + 1 break end
                            end
                        end
                        eq(have >= need, true, what .. ": G3 certificate of box " .. c.key .. " skill " .. s.id)
                    end
                end
            end
            -- G4 (a slot shape can only be lost when the slot floor is off; the UI never turns it off).
            if v.reason ~= "picked" then
                eq(v.drops, nil, what .. ": G4 automatic skill loss on box " .. c.key)
                if options.slot_floor ~= false then eq(v.shape_lost, nil, what .. ": G4 automatic shape loss on box " .. c.key) end
            end
        end
    end
end

test("G1-G9 hold and verdicts equal the reference on random boxes", function()
    math.randomseed(20261016)
    for trial = 1, TRIALS do
        local n_skills = math.random(6, 15)
        local box = support.random_box(math.random(30, 200), {
            dup_rate = 0.05 + math.random() * 0.25, n_skills = n_skills, max_level = math.random() < 0.5 and 3 or 4,
        })
        local options = support.random_options(box, n_skills)
        local what = "trial " .. trial .. " (" .. options.mode .. ")"
        local verdicts, info = analysis.plan(box, options)
        check_guarantees(box, options, verdicts, info, what)
        assert_same_as_reference(box, options, verdicts, info, what)

        -- G5: planning what stays sells nothing.
        local kept, kept_keys = {}, {}
        for _, c in ipairs(box) do
            if verdicts[c.key].action == "keep" then
                kept[#kept + 1] = c
                kept_keys[c.key] = true
            end
        end
        local again = copy(options)
        if again.picks then
            local picks = {}
            for key, action in pairs(again.picks) do if kept_keys[key] then picks[key] = action end end
            again.picks = picks
        end
        local _, n_again = sold_set(analysis.plan(kept, again))
        eq(n_again, 0, what .. ": G5 idempotent")

        -- G6: the order of the input does not matter.
        local shuffled = {}
        for i, c in ipairs(box) do shuffled[i] = c end
        for i = #shuffled, 2, -1 do
            local j = math.random(i)
            shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        end
        local verdicts_shuffled = analysis.plan(shuffled, options)
        for _, c in ipairs(box) do
            local a, b = verdicts[c.key], verdicts_shuffled[c.key]
            eq(a.action == b.action and a.reason == b.reason and a.ref == b.ref, true, what .. ": G6 box " .. c.key)
        end

        -- Decoration-aware cover never sells a floor member.
        if options.decorations and options.mode == "best" then
            for key in pairs(info.floor) do
                local v = verdicts[key]
                eq(v.action == "keep" or v.reason == "picked", true, what .. ": floor member " .. key .. " sold")
            end
        end

        -- G9: the preview equals separate plans (every 10th trial).
        if trial % 10 == 0 and options.mode ~= "manual" then
            local with_preview = copy(options)
            with_preview.preview = true
            local pv_verdicts, pv_info = analysis.plan(box, with_preview)
            assert_same_as_reference(box, with_preview, pv_verdicts, pv_info, what .. " with preview")
            for _, n in ipairs(analysis.PREVIEW_N) do
                local separate = copy(options)
                separate.mode, separate.best_n = "best", n
                local _, count = sold_set(analysis.plan(box, separate))
                eq(pv_info.preview.best[n].sell, count, what .. ": G9 preview best " .. n)
            end
            local separate = copy(options)
            separate.mode = "covered"
            local _, count = sold_set(analysis.plan(box, separate))
            eq(pv_info.preview.covered.sell, count, what .. ": G9 preview covered")
        end
    end
end)

test("G10: starring every kept talisman leaves the plan unchanged", function()
    math.randomseed(5)
    for trial = 1, 60 do
        local box = support.random_box(math.random(40, 160), { dup_rate = 0.2, n_skills = math.random(6, 12) })
        local options = { mode = "best", best_n = ({ 1, 2, 3, 5 })[math.random(4)], max_rarity = math.random(6, 8), preview = false }
        local verdicts = analysis.plan(box, options)
        local starred = copy(box)
        for _, c in ipairs(starred) do
            if verdicts[c.key].action == "keep" and not c.protected then c.protected = "favorite" end
        end
        eq(same_set(sold_set(verdicts), sold_set(analysis.plan(starred, options))), true, "trial " .. trial)
    end
end)

test("G8: covered and manual modes equal v0.2.2 when copies share rarity", function()
    math.randomseed(150)
    for trial = 1, 150 do
        local box = support.random_box(math.random(20, 200), { dup_rate = 0.2, n_skills = math.random(5, 14), consistent_rarity = true })
        for _, pair in ipairs({ { { mode = "covered" }, { sell_dominated = true } }, { { mode = "manual" }, { sell_dominated = false } } }) do
            local new = analysis.plan(box, { mode = pair[1].mode, preview = false })
            local old = v022.plan(box, pair[2])
            for _, c in ipairs(box) do
                local a, b = old[c.key], new[c.key]
                local reason = b.reason == "auto_off" and "best" or b.reason
                eq(a.action == b.action and a.reason == reason and a.ref == b.ref, true,
                    "trial " .. trial .. " " .. pair[1].mode .. " box " .. c.key)
            end
        end
    end
end)

test("with copies of mixed rarity, the same signatures are sold and zenny is never lower", function()
    math.randomseed(151)
    for trial = 1, 150 do
        local box = support.random_box(math.random(20, 200), { dup_rate = 0.25, n_skills = math.random(5, 14) })
        local old = v022.plan(box, { sell_dominated = true })
        local new = analysis.plan(box, { mode = "covered", preview = false })
        local count, zenny = {}, 0
        for _, c in ipairs(box) do
            local sig = analysis.prepare(c).signature
            if old[c.key].action == "sell" then
                count[sig] = (count[sig] or 0) + 1
                zenny = zenny - c.price
            end
            if new[c.key].action == "sell" then
                count[sig] = (count[sig] or 0) - 1
                zenny = zenny + c.price
            end
        end
        for sig, n in pairs(count) do eq(n, 0, "trial " .. trial .. " signature " .. sig) end
        eq(zenny >= 0, true, "trial " .. trial .. " zenny")
    end
end)

test("the real box matches the reference and the planned numbers", function()
    local box = require("fixtures.box_20261017")
    local expected = { [10] = { 273, 1363000 }, [5] = { 563, 2878000 }, [3] = { 735, 3852500 }, [2] = { 821, 4315500 }, [1] = { 914, 4831500 } }
    local options = { mode = "best", best_n = 3, max_rarity = 8 }
    local verdicts, info = analysis.plan(box, options)
    assert_same_as_reference(box, options, verdicts, info, "real box best 3")
    for n, want in pairs(expected) do
        eq(info.preview.best[n].sell, want[1], "best " .. n .. " count")
        eq(info.preview.best[n].zenny, want[2], "best " .. n .. " zenny")
    end
    eq(info.preview.covered.sell, 0, "every talisman is unique")
    local migrated = analysis.plan(box, { mode = "best", best_n = 1, max_rarity = 5, preview = false })
    local keys = {}
    for key in pairs(sold_set(migrated)) do keys[#keys + 1] = key end
    table.sort(keys)
    eq(table.concat(keys, ","), "1906,2072", "the migrated v0.2.2 rule sells the same two talismans")
    for _, opts in ipairs({ { mode = "covered" }, { mode = "best", best_n = 1, max_rarity = 7, keep_skills = { [1] = 3 } },
        { mode = "best", best_n = 5, ignore_skills = { [50] = true, [51] = true } } }) do
        local v, i = analysis.plan(box, opts)
        assert_same_as_reference(box, opts, v, i, "real box " .. opts.mode)
    end
end)

-- The time between two yields is what one game frame may wait for. Measured with the
-- garbage collector stopped (its pauses do not depend on where this code yields), per
-- stretch the fastest of 5 runs, and compared with the typical stretch of the same run:
-- a busy PC slows every stretch alike, while a loop that forgets to count its work makes
-- one stretch much longer than the others.
test("2400 talismans: fast enough, and no long stretch without a yield", function()
    math.randomseed(7)
    local box = support.random_box(2400, { dup_rate = 0.1, n_skills = 120 })
    math.randomseed(8)
    local decos = support.random_decos(120, false)
    for _, base in ipairs({ { mode = "best", best_n = 3 }, { mode = "best", best_n = 3, decorations = decos }, { mode = "covered" } }) do
        local name = base.mode .. (base.decorations and " + decorations" or "")
        local started = os.clock()
        analysis.plan(box, copy(base))
        local seconds = os.clock() - started
        local fastest
        for _ = 1, 5 do
            local gaps, last = {}, nil
            local opts = copy(base)
            opts.yield = function()
                local now = os.clock()
                gaps[#gaps + 1] = now - last
                last = now
            end
            collectgarbage("collect")
            collectgarbage("stop")
            last = os.clock()
            analysis.plan(box, opts)
            gaps[#gaps + 1] = os.clock() - last
            collectgarbage("restart")
            if not fastest then
                fastest = gaps
            else
                eq(#gaps, #fastest, name .. ": the same yields in every run")
                for i, gap in ipairs(gaps) do fastest[i] = math.min(fastest[i], gap) end
            end
        end
        local longest = 0
        for _, gap in ipairs(fastest) do longest = math.max(longest, gap) end
        local sorted = copy(fastest)
        table.sort(sorted)
        local median = sorted[(#sorted + 1) // 2]
        local limit = math.max(0.008, 12 * median)
        print(string.format("     %s: %.3f s, %d yields, longest stretch %.1f ms (median %.1f ms, limit %.1f ms)",
            name, seconds, #fastest - 1, longest * 1000, median * 1000, limit * 1000))
        eq(seconds < (base.decorations and 6 or 3), true, name .. ": total time")   -- decorations: the heaviest path
        eq(longest <= limit, true, name .. ": longest stretch between yields")
    end
end)

runner.run()
