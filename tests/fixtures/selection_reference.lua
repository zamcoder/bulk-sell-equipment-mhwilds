-- FROZEN TEST ORACLE: the reviewed selection-model prototype, kept unchanged so that
-- tests can compare BulkSell/analysis.lua against it (differential tests). Do not edit.
--
-- PROTOTYPE (planning only, not project code): FINAL selection model for Bulk Sell v0.3.
-- Lead-designer merge of the three selection designs (safety / power / simple). Pure Lua 5.4.
-- Same charm and verdict shapes as src/.../BulkSell/analysis.lua v0.2.2, plus optional verdict fields.
--
-- charm   = { key, rarity, skills = {{id, level}}, slots = {{kind = "W"|"A", level}}, protected, price }
-- options = {
--   mode          "manual" | "covered" (default) | "best"
--   best_n        1..10 (default 5)             places per skill and per slot shape (mode "best")
--   max_rarity    5..8 (default 8)              unique sales only up to this rarity (mode "best")
--   keep_skills   { [id] = min_level }          Always keep: exempt from the unique rule; no decoration stands in
--   ignore_skills { [id] = true }               Don't care (Always keep wins a conflict)
--   skill_places  { [id] = n }                  per-skill places (mode "best")
--   picks         { [key] = "keep" | "sell" }   already validated against the fingerprint by the caller
--   decorations   nil | { [id] = { kind = "W"|"A", size = n, free = n|nil } }   F2 catalogue
--   slot_floor    default true                  slot shapes get places like skills
--   preview       default true                  per-entry counts for the mode combo
--   yield         optional function called periodically
-- }

local M = {}

local KINDS = { "W", "A" }
local SCALE = 840          -- LCM(1..8): exact integer normalisation of skill levels
local MAX_SLOTS = 3
M.PREVIEW_N = { 10, 5, 3, 2, 1 }

local function descending(a, b) return a > b end

function M.prepare(charm, ignore)
    local levels, ids, ignored = {}, {}, 0
    for _, skill in ipairs(charm.skills or {}) do
        if skill.level > 0 then
            if ignore and ignore[skill.id] then
                ignored = ignored + skill.level
            else
                if not levels[skill.id] then ids[#ids + 1] = skill.id end
                levels[skill.id] = math.max(levels[skill.id] or 0, skill.level)
            end
        end
    end
    table.sort(ids)
    local slots, nslots, total = { W = {}, A = {} }, 0, 0
    for _, slot in ipairs(charm.slots or {}) do
        if slot.level > 0 then
            local list = assert(slots[slot.kind], "unknown slot kind " .. tostring(slot.kind))
            list[#list + 1] = slot.level
            nslots = nslots + 1
            total = total + slot.level
        end
    end
    for _, kind in ipairs(KINDS) do table.sort(slots[kind], descending) end
    local parts, sum = {}, 0
    for _, id in ipairs(ids) do
        parts[#parts + 1] = id .. ":" .. levels[id]
        sum = sum + levels[id]
    end
    local shape = "W" .. table.concat(slots.W, ",") .. "|A" .. table.concat(slots.A, ",")
    -- Content tie-break: depends only on the counted skills and the slots, never on box positions,
    -- picks or protection. Up to 3 skills (id * 10 + level, 5 digits each) and 3 + 3 slot levels.
    local skill_tie, slot_tie = 0, 0
    for i = 1, 3 do
        local id = ids[i]
        skill_tie = skill_tie * 100000 + (id and (id * 10 + levels[id]) or 0)
    end
    for _, kind in ipairs(KINDS) do
        for i = 1, 3 do slot_tie = slot_tie * 10 + (slots[kind][i] or 0) end
    end
    return {
        charm = charm, key = charm.key, rarity = charm.rarity,
        skill_levels = levels, skill_ids = ids, slots = slots, shape = shape,
        nslots = nslots, slot_total = total, wslots = #slots.W, level_sum = sum, phi = sum + nslots,
        ignored = ignored, skill_tie = skill_tie, slot_tie = slot_tie,
        signature = table.concat(parts, ",") .. "|" .. shape,   -- same text as v0.2.2 when nothing is ignored
    }
end

local function slots_cover(upper, lower)
    if #upper < #lower then return false end
    for i = 1, #lower do
        if upper[i] < lower[i] then return false end
    end
    return true
end

-- Slots of `upper` can hold everything slots of `lower` can.
function M.holds(upper_slots, lower_slots)
    for _, kind in ipairs(KINDS) do
        if not slots_cover(upper_slots[kind], lower_slots[kind]) then return false end
    end
    return true
end

function M.covers(upper, lower)
    for id, level in pairs(lower.skill_levels) do
        if (upper.skill_levels[id] or 0) < level then return false end
    end
    return M.holds(upper.slots, lower.slots)
end

-- Decoration-aware cover (decorations research section 4). `why` collects the decorations needed.
local demand = { W = {}, A = {} }
function M.covers_deco(upper, lower, decorations, why)
    local spare = upper.nslots - lower.nslots
    if spare < 0 then return false end
    local count = { W = 0, A = 0 }
    for _, kind in ipairs(KINDS) do
        local list = demand[kind]
        for i, level in ipairs(lower.slots[kind]) do list[i] = level end
        count[kind] = #lower.slots[kind]
    end
    for _, id in ipairs(lower.skill_ids) do
        local d = lower.skill_levels[id] - (upper.skill_levels[id] or 0)
        if d > 0 then
            spare = spare - d
            if spare < 0 then return false end
            local deco = decorations[id]
            if not deco then return false end
            if deco.free then
                local m = 0
                for _, slot_level in ipairs(lower.slots[deco.kind]) do
                    if slot_level >= deco.size then m = m + 1 end
                end
                if deco.free < d + m then return false end
            end
            local list, n = demand[deco.kind], count[deco.kind]
            for _ = 1, d do
                n = n + 1
                list[n] = deco.size
            end
            count[deco.kind] = n
            if why then why[#why + 1] = { id = id, count = d, kind = deco.kind, size = deco.size } end
        end
    end
    for _, kind in ipairs(KINDS) do
        local list, n = demand[kind], count[kind]
        for i = #list, n + 1, -1 do list[i] = nil end
        if n > 1 then table.sort(list, descending) end
        local slots = upper.slots[kind]
        if #slots < n then return false end
        for i = 1, n do
            if slots[i] < list[i] then return false end
        end
    end
    return true
end

-- Keeper of identical copies: protected, then Keep pick, then the cheaper copy, then the lowest box index.
local function pin_rank(e) return (e.charm.protected and 2) or (e.keep_pick and 1) or 0 end
local function better_keeper(a, b)
    local pa, pb = pin_rank(a), pin_rank(b)
    if pa ~= pb then return pa > pb end
    if a.rarity ~= b.rarity then return a.rarity < b.rarity end
    return a.key < b.key
end

local function build_groups(entries)
    local groups, by_signature = {}, {}
    for _, e in ipairs(entries) do
        local g = by_signature[e.signature]
        if not g then
            g = { members = {} }
            by_signature[e.signature] = g
            groups[#groups + 1] = g
        end
        g.members[#g.members + 1] = e
    end
    for _, g in ipairs(groups) do
        local best = g.members[1]
        for i = 2, #g.members do
            if better_keeper(g.members[i], best) then best = g.members[i] end
        end
        g.keeper = best
    end
    return groups
end

-- Sets g.dominated_by (the first covering group, v0.2.2 order). With `decorations`, groups for which
-- locked(g) is true are only checked with plain cover.
local function dominate(groups, decorations, locked, yield, counter)
    local by_skill = {}
    for _, g in ipairs(groups) do
        for _, id in ipairs(g.keeper.skill_ids) do
            local list = by_skill[id]
            if not list then
                list = {}
                by_skill[id] = list
            end
            list[#list + 1] = g
        end
    end
    local mark = {}
    for i, g in ipairs(groups) do
        local low = g.keeper
        local decos = decorations
        if decos and locked and locked(g) then decos = nil end
        local candidates
        local spare_max = MAX_SLOTS - low.nslots
        for _, id in ipairs(low.skill_ids) do
            if not decos or low.skill_levels[id] > spare_max then
                if not candidates or #by_skill[id] < #candidates then candidates = by_skill[id] end
            end
        end
        if not candidates then
            if decos and low.level_sum > spare_max then
                candidates = {}
                for _, id in ipairs(low.skill_ids) do
                    for _, other in ipairs(by_skill[id]) do
                        if mark[other] ~= i then
                            mark[other] = i
                            candidates[#candidates + 1] = other
                        end
                    end
                end
            else
                candidates = groups
            end
        end
        for _, other in ipairs(candidates) do
            if other ~= g and other.keeper.phi >= low.phi then
                if counter then counter.n = counter.n + 1 end
                local ok
                if decos then ok = M.covers_deco(other.keeper, low, decos) else ok = M.covers(other.keeper, low) end
                if ok then
                    g.dominated_by = other
                    break
                end
            end
        end
        if yield and i % 64 == 0 then yield() end
    end
end

local function top(g)
    while g.dominated_by do g = g.dominated_by end
    return g
end

-- Rank order for skill s (true when a ranks above b): level of s, slot total, slot count, weapon
-- slots, the other counted skills (normalised), then a fixed content order (skill_tie, slot_tie), so
-- picks, protection, sales and box positions never move a group in the ranking. Monotone under cover.
local function skill_order(s)
    return function(a, b)
        local la, lb = a.skill_levels[s], b.skill_levels[s]
        if la ~= lb then return la > lb end
        if a.slot_total ~= b.slot_total then return a.slot_total > b.slot_total end
        if a.nslots ~= b.nslots then return a.nslots > b.nslots end
        if a.wslots ~= b.wslots then return a.wslots > b.wslots end
        local ra, rb = a.norm_total - a.norm[s], b.norm_total - b.norm[s]
        if ra ~= rb then return ra > rb end
        if a.rarity ~= b.rarity then return a.rarity < b.rarity end   -- equal talismans: keep the cheaper one
        if a.skill_tie ~= b.skill_tie then return a.skill_tie < b.skill_tie end
        return a.slot_tie < b.slot_tie
    end
end
-- Rank order for a slot shape: all counted skills (normalised), slot total, slot count, weapon slots, box.
local function shape_order(a, b)
    if a.norm_total ~= b.norm_total then return a.norm_total > b.norm_total end
    if a.slot_total ~= b.slot_total then return a.slot_total > b.slot_total end
    if a.nslots ~= b.nslots then return a.nslots > b.nslots end
    if a.wslots ~= b.wslots then return a.wslots > b.wslots end
    if a.rarity ~= b.rarity then return a.rarity < b.rarity end
    if a.skill_tie ~= b.skill_tie then return a.skill_tie < b.skill_tie end
    return a.slot_tie < b.slot_tie
end

function M.plan(charms, options)
    options = options or {}
    local mode = options.mode or "covered"
    local best_n = options.best_n or 5
    local max_rarity = options.max_rarity or 8
    local keep_skills = options.keep_skills or {}
    local places = options.skill_places or {}
    local picks = options.picks or {}
    local slot_floor = options.slot_floor ~= false
    local yield = options.yield
    local ignore = {}
    for id in pairs(options.ignore_skills or {}) do
        if not keep_skills[id] then ignore[id] = true end
    end
    local decorations = options.decorations
    if decorations then
        local filtered = {}
        for id, deco in pairs(decorations) do
            if not keep_skills[id] then filtered[id] = deco end
        end
        decorations = filtered
    end
    local info = { checks = { n = 0 }, notices = {} }

    -- Order independence: everything below works in box order.
    local sorted = {}
    for i, c in ipairs(charms) do sorted[i] = c end
    table.sort(sorted, function(a, b) return a.key < b.key end)

    local entries, entry_of, maxlv = {}, {}, {}
    for _, charm in ipairs(sorted) do
        local e = M.prepare(charm, ignore)
        entries[#entries + 1] = e
        entry_of[charm.key] = e
        for _, id in ipairs(e.skill_ids) do
            if e.skill_levels[id] > (maxlv[id] or 0) then maxlv[id] = e.skill_levels[id] end
        end
    end
    info.entry_of, info.box_max = entry_of, maxlv

    -- Stage 1: fixed verdicts. Sell picks leave the pool before anything is compared or ranked.
    local fixed, pool = {}, {}
    for _, e in ipairs(entries) do
        local pick = picks[e.key]
        if e.charm.protected then
            fixed[e.key] = { action = "keep", reason = "protected", detail = e.charm.protected }
            pool[#pool + 1] = e
            if pick == "sell" then info.notices[#info.notices + 1] = { key = e.key, what = "sell pick on protected ignored" } end
        elseif pick == "sell" then
            fixed[e.key] = { action = "sell", reason = "picked" }
        else
            if pick == "keep" then
                fixed[e.key] = { action = "keep", reason = "picked" }
                e.keep_pick = true
            end
            pool[#pool + 1] = e
        end
    end

    -- Stage 2 (independent of mode and N): plain front of the pool, ranks per skill and per slot shape.
    local groups = build_groups(pool)
    dominate(groups, nil, nil, yield, info.checks)
    local front, lists = {}, {}
    for _, g in ipairs(groups) do
        if not g.dominated_by then
            local e = g.keeper
            front[#front + 1] = e
            e.norm, e.norm_total = {}, 0
            for _, id in ipairs(e.skill_ids) do
                local v = e.skill_levels[id] * SCALE // maxlv[id]
                e.norm[id] = v
                e.norm_total = e.norm_total + v
                local list = lists[id]
                if not list then
                    list = {}
                    lists[id] = list
                end
                list[#list + 1] = e
            end
        end
    end
    local ranks = {}
    local skills_sorted = {}
    for s, list in pairs(lists) do
        table.sort(list, skill_order(s))
        skills_sorted[#skills_sorted + 1] = s
        for i, e in ipairs(list) do
            ranks[e.key] = ranks[e.key] or {}
            ranks[e.key][s] = i
        end
    end
    table.sort(skills_sorted)
    local shape_lists, shapes_sorted, shape_slots = {}, {}, {}
    if slot_floor then
        for _, e in ipairs(pool) do
            if e.nslots > 0 and not shape_slots[e.shape] then
                shape_slots[e.shape] = e.slots
                shapes_sorted[#shapes_sorted + 1] = e.shape
            end
        end
        table.sort(shapes_sorted)
        for _, shape in ipairs(shapes_sorted) do
            local list = {}
            for _, e in ipairs(front) do
                if M.holds(e.slots, shape_slots[shape]) then list[#list + 1] = e end
            end
            table.sort(list, shape_order)
            shape_lists[shape] = list
            for i, e in ipairs(list) do
                ranks[e.key] = ranks[e.key] or {}
                ranks[e.key]["shape:" .. shape] = i
            end
        end
    end
    if yield then yield() end
    info.ranks, info.lists, info.shape_lists = ranks, lists, shape_lists
    info.front_count = #front

    local function exempt_skill(e)
        local found
        for _, skill in ipairs(e.charm.skills or {}) do
            local min = keep_skills[skill.id]
            if min and skill.level >= min and (not found or skill.id < found) then found = skill.id end
        end
        return found
    end

    -- Stages 3-5 for one mode and N. Returns verdicts for every key not fixed, plus the floor.
    local function decide(mode_x, n_x, full)
        local out = {}
        if mode_x == "manual" then
            for _, e in ipairs(pool) do
                if not fixed[e.key] then out[e.key] = { action = "keep", reason = "auto_off" } end
            end
            return out, {}, {}, {}
        end
        local best = mode_x == "best"
        -- Floor: places per skill and per slot shape. In "covered" mode it is only a lock for F2 (N = 1).
        local floor, floor_of, floor_shape = {}, {}, {}
        if best or decorations then
            for _, s in ipairs(skills_sorted) do
                local n = best and (places[s] or n_x) or 1
                local fl = {}
                for i, e in ipairs(lists[s]) do
                    if i > n then break end
                    fl[#fl + 1] = e.key
                    local cur = floor[e.key]
                    if not cur or i < cur.rank then floor[e.key] = { skill = s, rank = i, of = #lists[s] } end
                end
                floor_of[s] = fl
            end
            if slot_floor then
                local n = best and n_x or 1
                for _, shape in ipairs(shapes_sorted) do
                    local fl = {}
                    for i, e in ipairs(shape_lists[shape]) do
                        if i > n then break end
                        fl[#fl + 1] = e.key
                        if not floor[e.key] then floor[e.key] = { shape = shape, rank = i, of = #shape_lists[shape] } end
                    end
                    floor_shape[shape] = fl
                end
            end
        end
        -- Unique rule.
        local stay, state = {}, {}
        for _, e in ipairs(pool) do
            if fixed[e.key] or floor[e.key] or not best then
                stay[#stay + 1] = e
            elseif e.rarity > max_rarity then
                state[e.key] = "rarity"
                stay[#stay + 1] = e
            else
                local ex = exempt_skill(e)
                if ex then
                    state[e.key] = "exempt:" .. ex
                    stay[#stay + 1] = e
                else
                    out[e.key] = { action = "sell", reason = "rule", detail = "unique" }
                end
            end
        end
        -- Covered and duplicates among what stays (so every ref stays). Floor members are never
        -- sold through a decoration-only cover.
        local g2
        if not best and not decorations then
            g2 = groups   -- "covered" mode: what stays is the whole pool, already compared in stage 2
        else
            g2 = build_groups(stay)
            dominate(g2, decorations, function(g) return floor[g.keeper.key] ~= nil end, yield, info.checks)
        end
        for _, g in ipairs(g2) do
            local t = g.dominated_by and top(g)
            for _, e in ipairs(g.members) do
                if not fixed[e.key] and not out[e.key] then
                    if t then
                        local v = { action = "sell", reason = "dominated", ref = t.keeper.key }
                        if decorations and not M.covers(t.keeper, e) then
                            local why = {}
                            M.covers_deco(t.keeper, e, decorations, why)
                            v.needs = why
                        end
                        out[e.key] = v
                    elseif e ~= g.keeper then
                        out[e.key] = { action = "sell", reason = "duplicate", ref = g.keeper.key }
                    elseif floor[e.key] and best then
                        out[e.key] = { action = "keep", reason = "top_n", detail = floor[e.key] }
                    elseif state[e.key] == "rarity" then
                        out[e.key] = { action = "keep", reason = "rarity" }
                    elseif state[e.key] then
                        out[e.key] = { action = "keep", reason = "exempt", detail = tonumber(state[e.key]:sub(8)) }
                    else
                        out[e.key] = { action = "keep", reason = "best" }
                    end
                end
            end
        end
        if not (best and full) then return out, floor, floor_of, floor_shape end
        -- Explanations: a rule sale that a kept talisman covers is shown as covered/duplicate;
        -- the others are unique and carry their certificate (refs).
        local kept, kept_by_skill = {}, {}
        for _, e in ipairs(entries) do
            local v = fixed[e.key] or out[e.key]
            if v.action == "keep" then
                kept[#kept + 1] = e
                for _, id in ipairs(e.skill_ids) do
                    local list = kept_by_skill[id]
                    if not list then
                        list = {}
                        kept_by_skill[id] = list
                    end
                    list[#list + 1] = e
                end
            end
        end
        local function kept_cover(e)
            local candidates
            for _, id in ipairs(e.skill_ids) do
                local list = kept_by_skill[id] or {}
                if not candidates or #list < #candidates then candidates = list end
            end
            local found
            for _, other in ipairs(candidates or kept) do
                if other ~= e and M.covers(other, e) then
                    if other.signature == e.signature then return other, "duplicate" end
                    found = found or other
                end
            end
            return found, found and "dominated" or nil
        end
        for _, e in ipairs(pool) do
            local v = out[e.key]
            if v and v.reason == "rule" then
                local other, kind = kept_cover(e)
                if other then
                    out[e.key] = { action = "sell", reason = kind, ref = other.key, detail = "rule" }
                else
                    v.unique = true
                    local refs, seen = {}, {}
                    for _, id in ipairs(e.skill_ids) do
                        for _, k in ipairs(floor_of[id] or {}) do
                            if not seen[k] then
                                seen[k] = true
                                refs[#refs + 1] = k
                            end
                        end
                    end
                    if slot_floor and e.nslots > 0 then
                        for _, k in ipairs(floor_shape[e.shape] or {}) do
                            if not seen[k] then
                                seen[k] = true
                                refs[#refs + 1] = k
                            end
                        end
                    end
                    table.sort(refs)
                    v.refs = refs
                    -- best rank for display
                    local b
                    for s, r in pairs(ranks[e.key] or {}) do
                        if not b or r < b.rank then b = { skill = s, rank = r } end
                    end
                    v.rank = b
                end
            end
        end
        return out, floor, floor_of, floor_shape
    end

    local out, floor, floor_of, floor_shape = decide(mode, best_n, true)
    local verdicts = {}
    for _, e in ipairs(entries) do verdicts[e.key] = fixed[e.key] or out[e.key] end
    info.floor, info.floor_of, info.floor_shape = floor, floor_of, floor_shape

    -- Sell picks: informational cover and uniqueness.
    do
        local kept = {}
        for _, e in ipairs(entries) do
            if verdicts[e.key].action == "keep" then kept[#kept + 1] = e end
        end
        for _, e in ipairs(entries) do
            local v = verdicts[e.key]
            if v.reason == "picked" and v.action == "sell" then
                for _, k in ipairs(kept) do
                    if M.covers(k, e) then
                        v.covered_by = k.key
                        break
                    end
                end
                if not v.covered_by then v.unique = true end
            end
        end
    end

    -- Losses: counted skill levels and slot shapes that no kept talisman reaches any more.
    local kept_max, kept_raw_max = {}, {}
    local kept_entries = {}
    for _, e in ipairs(entries) do
        if verdicts[e.key].action == "keep" then
            kept_entries[#kept_entries + 1] = e
            for _, id in ipairs(e.skill_ids) do
                if e.skill_levels[id] > (kept_max[id] or 0) then kept_max[id] = e.skill_levels[id] end
            end
            for _, skill in ipairs(e.charm.skills or {}) do
                if skill.level > (kept_raw_max[skill.id] or 0) then kept_raw_max[skill.id] = skill.level end
            end
        end
    end
    info.kept_max = kept_max
    local losses = {}
    for _, e in ipairs(entries) do
        local v = verdicts[e.key]
        if v.action == "sell" then
            for _, id in ipairs(e.skill_ids) do
                if e.skill_levels[id] > (kept_max[id] or 0) then
                    v.drops = v.drops or {}
                    v.drops[#v.drops + 1] = { id = id, level = e.skill_levels[id], kept = kept_max[id] or 0 }
                end
            end
            -- Don't care skills: reported for information only.
            for _, skill in ipairs(e.charm.skills or {}) do
                if ignore[skill.id] and skill.level > (kept_raw_max[skill.id] or 0) then
                    v.ignored_drops = v.ignored_drops or {}
                    v.ignored_drops[#v.ignored_drops + 1] = { id = skill.id, level = skill.level, kept = kept_raw_max[skill.id] or 0 }
                end
            end
            if e.nslots > 0 then
                local held = false
                for _, k in ipairs(kept_entries) do
                    if M.holds(k.slots, e.slots) then
                        held = true
                        break
                    end
                end
                if not held then v.shape_lost = e.shape end
            end
        end
    end

    -- Independent checker; failing sales are held back.
    local problems = M.check(sorted, verdicts, options)
    info.problems = problems
    info.held_back = {}
    for _, p in ipairs(problems) do
        local v = verdicts[p.key]
        if v and v.action == "sell" and v.reason ~= "picked" then
            verdicts[p.key] = { action = "keep", reason = "best", detail = "safety_check", was = v }
            info.held_back[#info.held_back + 1] = p.key
        end
    end

    -- Counts for every entry of the mode combo (exact: the same decide() as the plan).
    if options.preview ~= false then
        local function count(mode_x, n_x)
            local o = mode_x == mode and n_x == best_n and out or decide(mode_x, n_x, false)
            local sell, zenny = 0, 0
            for _, e in ipairs(entries) do
                local v = fixed[e.key] or o[e.key]
                if v.action == "sell" then
                    sell = sell + 1
                    zenny = zenny + (e.charm.price or 0)
                end
            end
            return { sell = sell, zenny = zenny }
        end
        info.preview = { manual = count("manual"), covered = count("covered"), best = {} }
        for _, n in ipairs(M.PREVIEW_N) do info.preview.best[n] = count("best", n) end
    end
    return verdicts, info
end

-- Re-derives every sale's guarantee from the verdicts alone (shares only prepare/covers/holds).
function M.check(charms, verdicts, options)
    options = options or {}
    local mode = options.mode or "covered"
    local best_n = options.best_n or 5
    local max_rarity = options.max_rarity or 8
    local keep_skills = options.keep_skills or {}
    local places = options.skill_places or {}
    local picks = options.picks or {}
    local ignore = {}
    for id in pairs(options.ignore_skills or {}) do
        if not keep_skills[id] then ignore[id] = true end
    end
    local decorations = options.decorations
    local problems = {}
    local function problem(key, what) problems[#problems + 1] = { key = key, what = what } end
    local prepared, kept, kept_sigs = {}, {}, {}
    for _, c in ipairs(charms) do
        local e = M.prepare(c, ignore)
        prepared[c.key] = e
        local v = verdicts[c.key]
        if not v then
            problem(c.key, "no verdict")
        elseif v.action == "keep" then
            if not kept_sigs[e.signature] then
                kept_sigs[e.signature] = true
                kept[#kept + 1] = e
            end
            if not c.protected and picks[c.key] == "sell" then problem(c.key, "sell pick not honoured") end
        else
            if c.protected then problem(c.key, "protected sold") end
            if picks[c.key] == "keep" then problem(c.key, "keep pick not honoured") end
        end
    end
    local box_max, kept_max = {}, {}
    for _, c in ipairs(charms) do
        local e = prepared[c.key]
        for id, level in pairs(e.skill_levels) do
            if level > (box_max[id] or 0) then box_max[id] = level end
            if verdicts[c.key] and verdicts[c.key].action == "keep" and level > (kept_max[id] or 0) then kept_max[id] = level end
        end
    end
    for _, c in ipairs(charms) do
        local v = verdicts[c.key]
        local e = prepared[c.key]
        if v and v.action == "sell" then
            if v.reason == "picked" then
                if picks[c.key] ~= "sell" then problem(c.key, "picked without a pick") end
            elseif v.reason == "duplicate" or v.reason == "dominated" then
                local ref = v.ref and prepared[v.ref]
                if not ref or verdicts[v.ref].action ~= "keep" then
                    problem(c.key, "ref not kept")
                elseif v.needs then
                    if not decorations or not M.covers_deco(ref, e, decorations) then problem(c.key, "decoration cover fails") end
                elseif not M.covers(ref, e) then
                    problem(c.key, "cover fails")
                end
            elseif v.reason == "rule" then
                if mode ~= "best" then problem(c.key, "rule sale outside best mode") end
                if c.rarity > max_rarity then problem(c.key, "rule sale above the rarity limit") end
                for _, skill in ipairs(c.skills or {}) do
                    local min = keep_skills[skill.id]
                    if min and skill.level >= min then problem(c.key, "always-keep skill sold by the rule") end
                end
                for id, level in pairs(e.skill_levels) do
                    local need = places[id] or best_n
                    local have = 0
                    for _, k in ipairs(kept) do
                        if (k.skill_levels[id] or 0) >= level then have = have + 1 end
                    end
                    if have < need then problem(c.key, string.format("floor broken: skill %d has %d of %d", id, have, need)) end
                end
                if options.slot_floor ~= false and e.nslots > 0 then
                    local have = 0
                    for _, k in ipairs(kept) do
                        if M.holds(k.slots, e.slots) then have = have + 1 end
                    end
                    if have < best_n then problem(c.key, string.format("slot floor broken: %d of %d", have, best_n)) end
                end
            else
                problem(c.key, "unknown sell reason " .. tostring(v.reason))
            end
            if v.reason ~= "picked" then
                for id, level in pairs(e.skill_levels) do
                    if level > (kept_max[id] or 0) then problem(c.key, "automatic sale lowers skill " .. id) end
                end
            end
        end
    end
    return problems
end

-- Picks store reconciliation (picks.lua). store = { [key] = { action, fp } }; charms carry fingerprint.
-- Returns active { [key] = action }, the new store, and notices.
function M.reconcile(store, charms)
    local by_key, by_fp = {}, {}
    for _, c in ipairs(charms) do
        by_key[c.key] = c
        if c.fingerprint then
            by_fp[c.fingerprint] = by_fp[c.fingerprint] or {}
            table.insert(by_fp[c.fingerprint], c)
        end
    end
    for _, list in pairs(by_fp) do table.sort(list, function(a, b) return a.key < b.key end) end
    local active, new_store, notices = {}, {}, {}
    local keys = {}
    for key in pairs(store) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local pick = store[key]
        local c = by_key[key]
        if c and c.fingerprint == pick.fp then
            if pick.action == "sell" and c.protected then
                notices[#notices + 1] = { key = key, what = "sell pick dropped: now " .. c.protected }
            else
                new_store[key] = pick
                if not c.protected then active[key] = pick.action end
            end
        elseif pick.action == "keep" then
            -- A Keep pick follows an identical talisman that has no pick of its own.
            local moved
            for _, other in ipairs(by_fp[pick.fp] or {}) do
                if not store[other.key] and not new_store[other.key] then
                    moved = other
                    break
                end
            end
            if moved then
                new_store[moved.key] = { action = "keep", fp = pick.fp, at = pick.at }
                if not moved.protected then active[moved.key] = "keep" end
                notices[#notices + 1] = { key = key, what = "keep pick moved to " .. moved.key }
            else
                notices[#notices + 1] = { key = key, what = "keep pick dropped: talisman changed or gone" }
            end
        else
            notices[#notices + 1] = { key = key, what = "sell pick dropped: talisman changed or gone" }
        end
    end
    return active, new_store, notices
end

function M.summarize(charms, verdicts)
    local s = { sell = 0, keep = 0, zenny = 0, by_reason = {}, unique = 0, unique_rule = 0, unique_picks = 0,
        drops = 0, by_rarity = { [5] = 0, [6] = 0, [7] = 0, [8] = 0 } }
    for _, c in ipairs(charms) do
        local v = verdicts[c.key]
        s[v.action] = s[v.action] + 1
        s.by_reason[v.reason] = (s.by_reason[v.reason] or 0) + 1
        if v.action == "sell" then
            s.zenny = s.zenny + (c.price or 0)
            s.by_rarity[c.rarity] = (s.by_rarity[c.rarity] or 0) + 1
            if v.unique then
                s.unique = s.unique + 1
                if v.reason == "rule" then s.unique_rule = s.unique_rule + 1 else s.unique_picks = s.unique_picks + 1 end
            end
            if v.drops or v.shape_lost then s.drops = s.drops + 1 end
        end
    end
    return s
end

return M
