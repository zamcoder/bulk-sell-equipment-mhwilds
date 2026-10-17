-- Talisman analysis for Bulk Sell. Pure Lua with no game access, so it can be
-- unit tested outside the game. tests/fixtures/selection_reference.lua is the
-- reviewed model this file must match verdict for verdict.
--
-- Charm shape (built by the game layer):
--   key          unique id (Equipment Box index)
--   rarity       integer rarity shown in game
--   skills       { { id = integer, level = integer }, ... }
--   slots        { { kind = "W" | "A", level = integer }, ... }   W = weapon, A = armor
--   protected    nil, or a short reason string ("equipped", "loadout", ...)
--   price        zenny received when sold (optional, used for totals)
--
-- Options of analysis.plan:
--   mode           "manual" | "covered" (default) | "best"
--   best_n         1..10 (default 5): places per skill and per slot shape (mode "best")
--   max_rarity     5..8 (default 8): unique talismans are sold only up to this rarity (mode "best")
--   keep_skills    { [id] = min_level }: Always keep; exempt from the unique rule
--   ignore_skills  { [id] = true }: Don't care (Always keep wins a conflict)
--   skill_places   { [id] = n }: places for one skill (mode "best")
--   picks          { [key] = "keep" | "sell" }, already reconciled with the box
--   decorations    nil | { [id] = { kind, size, free? } }: decoration-aware cover (hidden for now)
--   slot_floor     default true: slot shapes get places like skills
--   preview        default true: exact counts for every entry of the Keep combo
--   yield          optional function, called every few thousand units of work
--
-- Verdict shape:
--   { action = "keep" | "sell", reason, detail, ref, refs, needs, unique, covered_by, rank,
--     drops, ignored_drops, shape_lost }
--   keep reasons  protected | picked | top_n | exempt | rarity | best | auto_off
--   sell reasons  picked | duplicate | dominated | rule
--   ref   (duplicate, dominated) the kept talisman that matches or beats it
--   refs  (unique rule sale) the kept talismans that rank above it for each of its skills and its slot shape

local analysis = {}

local KINDS = { "W", "A" }
local SCALE = 840          -- LCM(1..8): exact integer normalisation of skill levels
local MAX_SLOTS = 3
local WORK_PER_YIELD = 800    -- one unit is about one cover check or two sort comparisons
local PREPARE_COST = 24       -- prepare() costs about as much as 24 cover checks
local SORT_CHUNK = 128        -- longer lists are sorted in chunks, so the work can pause
analysis.PREVIEW_N = { 10, 5, 3, 2, 1 }

local function descending(a, b) return a > b end

-- Calls `yield` after every WORK_PER_YIELD units of work, so no game frame waits long.
local function work_counter(yield)
    if not yield then return function() end end
    local done = 0
    return function(units)
        done = done + (units or 1)
        if done >= WORK_PER_YIELD then
            done = 0
            yield()
        end
    end
end

-- Sorts `list` in place. `less` must be a strict total order, so the result is the one
-- table.sort gives; long lists are sorted in chunks and merged, with pauses in between
-- (a yield inside a table.sort comparator is not possible).
local function sort(list, less, work)
    local n = #list
    if n <= SORT_CHUNK then
        table.sort(list, less)
        work(n * 3 // 2 + 1)
        return
    end
    local chunk = {}
    for lo = 1, n, SORT_CHUNK do
        local hi = math.min(lo + SORT_CHUNK - 1, n)
        for i = #chunk, hi - lo + 2, -1 do chunk[i] = nil end
        for i = lo, hi do chunk[i - lo + 1] = list[i] end
        table.sort(chunk, less)
        for i = lo, hi do list[i] = chunk[i - lo + 1] end
        work(SORT_CHUNK * 3 // 2)
    end
    local src, dst, width = list, {}, SORT_CHUNK
    while width < n do
        for lo = 1, n, 2 * width do
            local mid, hi = math.min(lo + width - 1, n), math.min(lo + 2 * width - 1, n)
            local i, j, k = lo, mid + 1, lo
            while i <= mid and j <= hi do
                if less(src[j], src[i]) then
                    dst[k] = src[j]
                    j = j + 1
                else
                    dst[k] = src[i]
                    i = i + 1
                end
                k = k + 1
            end
            for x = i, mid do
                dst[k] = src[x]
                k = k + 1
            end
            for x = j, hi do
                dst[k] = src[x]
                k = k + 1
            end
            work((hi - lo + 1) // 2 + 1)
        end
        src, dst = dst, src
        width = width * 2
    end
    if src ~= list then
        for i = 1, n do list[i] = src[i] end
    end
end

-- Normalizes a charm. Skills in `ignore` (Don't care) are left out of every comparison.
function analysis.prepare(charm, ignore)
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
    -- Content tie-break: depends only on the counted skills and the slots, never on box
    -- positions, picks or protection. Up to 3 skills (id * 10 + level, 5 digits each) and
    -- 3 + 3 slot levels.
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
        signature = table.concat(parts, ",") .. "|" .. shape,   -- the v0.2.2 text when nothing is ignored
    }
end

-- Both lists are sorted descending, so pairwise comparison is enough to know
-- whether every lower slot fits a distinct upper slot of at least its level.
local function slots_cover(upper, lower)
    if #upper < #lower then return false end
    for i = 1, #lower do
        if upper[i] < lower[i] then return false end
    end
    return true
end

-- Slots of `upper` can hold everything slots of `lower` can.
function analysis.holds(upper_slots, lower_slots)
    for _, kind in ipairs(KINDS) do
        if not slots_cover(upper_slots[kind], lower_slots[kind]) then return false end
    end
    return true
end

-- True when prepared charm `upper` has every counted skill of `lower` at an equal or
-- higher level, and slots that can hold everything `lower`'s slots can.
function analysis.covers(upper, lower)
    for id, level in pairs(lower.skill_levels) do
        if (upper.skill_levels[id] or 0) < level then return false end
    end
    return analysis.holds(upper.slots, lower.slots)
end

-- Cover where spare slots of `upper` may hold decorations for the skill levels it lacks.
-- `why` (optional) collects the decorations needed: { id, count, kind, size }.
local demand = { W = {}, A = {} }
function analysis.covers_deco(upper, lower, decorations, why)
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

local function build_groups(entries, work)
    local groups, by_signature = {}, {}
    for _, e in ipairs(entries) do
        local g = by_signature[e.signature]
        if not g then
            g = { members = {} }
            by_signature[e.signature] = g
            groups[#groups + 1] = g
        end
        g.members[#g.members + 1] = e
        work()
    end
    for _, g in ipairs(groups) do
        local best = g.members[1]
        for i = 2, #g.members do
            if better_keeper(g.members[i], best) then best = g.members[i] end
        end
        g.keeper = best
        work()
    end
    return groups
end

-- Sets g.dominated_by to the first covering group, in group order. A talisman can only
-- be covered by one that has all of its skills, so each group is compared only against
-- the shortest skill list it appears in. With `decorations`, groups for which locked(g)
-- is true are only checked with plain cover.
local function dominate(groups, decorations, locked, work)
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
        work()
    end
    local mark = {}
    for i, g in ipairs(groups) do
        local low = g.keeper
        local decos = decorations
        if decos and locked and locked(g) then decos = nil end
        local candidates
        local spare_max = MAX_SLOTS - low.nslots
        for _, id in ipairs(low.skill_ids) do
            -- With decorations a skill a decoration can fill does not have to be on the coverer.
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
        local seen, checked = 0, 0
        for _, other in ipairs(candidates) do
            seen = seen + 1
            if other ~= g and other.keeper.phi >= low.phi then
                checked = checked + 1
                local ok
                if decos then ok = analysis.covers_deco(other.keeper, low, decos) else ok = analysis.covers(other.keeper, low) end
                if ok then
                    g.dominated_by = other
                    break
                end
            end
        end
        work(1 + checked * (decos and 3 or 1) + seen // 4)
    end
end

-- Strict cover has no cycles, so following it always ends at a group that stays.
local function top(g)
    while g.dominated_by do g = g.dominated_by end
    return g
end

-- Rank order for skill s (true when a ranks above b): level of s, slot total, slot count,
-- weapon slots, the other counted skills (normalised), then the cheaper talisman and a fixed
-- content order, so picks, protection, sales and box positions never move a talisman in the
-- ranking. Every key is monotone under cover, so a covered talisman ranks below its coverer.
local function skill_order(s)
    return function(a, b)
        local la, lb = a.skill_levels[s], b.skill_levels[s]
        if la ~= lb then return la > lb end
        if a.slot_total ~= b.slot_total then return a.slot_total > b.slot_total end
        if a.nslots ~= b.nslots then return a.nslots > b.nslots end
        if a.wslots ~= b.wslots then return a.wslots > b.wslots end
        local ra, rb = a.norm_total - a.norm[s], b.norm_total - b.norm[s]
        if ra ~= rb then return ra > rb end
        if a.rarity ~= b.rarity then return a.rarity < b.rarity end
        if a.skill_tie ~= b.skill_tie then return a.skill_tie < b.skill_tie end
        return a.slot_tie < b.slot_tie
    end
end

-- Rank order for a slot shape: all counted skills (normalised), slot total, slot count,
-- weapon slots, then the cheaper talisman and the content order.
local function shape_order(a, b)
    if a.norm_total ~= b.norm_total then return a.norm_total > b.norm_total end
    if a.slot_total ~= b.slot_total then return a.slot_total > b.slot_total end
    if a.nslots ~= b.nslots then return a.nslots > b.nslots end
    if a.wslots ~= b.wslots then return a.wslots > b.wslots end
    if a.rarity ~= b.rarity then return a.rarity < b.rarity end
    if a.skill_tie ~= b.skill_tie then return a.skill_tie < b.skill_tie end
    return a.slot_tie < b.slot_tie
end

-- Order of rank labels: skill ids (ascending) before "shape:..." labels (alphabetical).
local function rank_label_first(a, b)
    local na, nb = type(a) == "number", type(b) == "number"
    if na ~= nb then return na end
    return a < b
end

local function ignore_set(options, keep_skills)
    local ignore = {}
    for id in pairs(options.ignore_skills or {}) do
        if not keep_skills[id] then ignore[id] = true end
    end
    return ignore
end

-- Kept entries in box order, plus the same list per counted skill.
local function index_kept(entries, verdict_of, work)
    local kept, by_skill = {}, {}
    for _, e in ipairs(entries) do
        work()
        if verdict_of(e.key).action == "keep" then
            kept[#kept + 1] = e
            for _, id in ipairs(e.skill_ids) do
                local list = by_skill[id]
                if not list then
                    list = {}
                    by_skill[id] = list
                end
                list[#list + 1] = e
            end
        end
    end
    return kept, by_skill
end

-- Kept talismans that could cover `e`: the shortest kept list of its skills (in box order),
-- or every kept talisman when it has no counted skill.
local function cover_candidates(e, kept, kept_by_skill)
    local candidates
    for _, id in ipairs(e.skill_ids) do
        local list = kept_by_skill[id] or {}
        if not candidates or #list < #candidates then candidates = list end
    end
    return candidates or kept
end

-- Decides, for every charm, whether to keep or sell it. Returns verdicts keyed by
-- charm.key, and info (rankings, floor, preview counts, checker problems, notices).
function analysis.plan(charms, options)
    options = options or {}
    local mode = options.mode or "covered"
    local best_n = options.best_n or 5
    local max_rarity = options.max_rarity or 8
    local keep_skills = options.keep_skills or {}
    local places = options.skill_places or {}
    local picks = options.picks or {}
    local slot_floor = options.slot_floor ~= false
    local yield = options.yield
    local work = work_counter(yield)
    local ignore = ignore_set(options, keep_skills)
    local decorations = options.decorations
    if decorations then
        -- No decoration stands in for an Always-keep skill.
        local filtered = {}
        for id, deco in pairs(decorations) do
            if not keep_skills[id] then filtered[id] = deco end
        end
        decorations = filtered
    end
    local info = { notices = {} }

    -- Order independence: everything below works in box order.
    local sorted = {}
    for i, c in ipairs(charms) do sorted[i] = c end
    table.sort(sorted, function(a, b) return a.key < b.key end)

    local entries, entry_of, maxlv = {}, {}, {}
    for _, charm in ipairs(sorted) do
        local e = analysis.prepare(charm, ignore)
        entries[#entries + 1] = e
        entry_of[charm.key] = e
        for _, id in ipairs(e.skill_ids) do
            if e.skill_levels[id] > (maxlv[id] or 0) then maxlv[id] = e.skill_levels[id] end
        end
        work(PREPARE_COST)
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

    -- Stage 2 (independent of mode and N): the plain front of the pool, ranked per skill and per slot shape.
    local groups = build_groups(pool, work)
    dominate(groups, nil, nil, work)
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
        sort(list, skill_order(s), work)
        skills_sorted[#skills_sorted + 1] = s
        for i, e in ipairs(list) do
            ranks[e.key] = ranks[e.key] or {}
            ranks[e.key][s] = i
        end
        work(#list // 4 + 1)
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
        -- The shape order does not depend on the shape, so one sorted front serves every shape.
        local by_shape_order = {}
        for i, e in ipairs(front) do by_shape_order[i] = e end
        sort(by_shape_order, shape_order, work)
        for _, shape in ipairs(shapes_sorted) do
            local list = {}
            for _, e in ipairs(by_shape_order) do
                if analysis.holds(e.slots, shape_slots[shape]) then list[#list + 1] = e end
            end
            shape_lists[shape] = list
            for i, e in ipairs(list) do
                ranks[e.key] = ranks[e.key] or {}
                ranks[e.key]["shape:" .. shape] = i
            end
            work(#front // 2 + #list // 4 + 1)
        end
    end
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

    -- Stage 3: verdicts of every pool entry that is not fixed, for one mode and N (and
    -- optionally another rarity limit), plus the floor.
    local function decide(mode_x, n_x, rarity_x)
        local limit = rarity_x or max_rarity
        local out = {}
        if mode_x == "manual" then
            for _, e in ipairs(pool) do
                if not fixed[e.key] then out[e.key] = { action = "keep", reason = "auto_off" } end
            end
            return out, {}, {}, {}
        end
        local best = mode_x == "best"
        -- Floor: places per skill and per slot shape. In "covered" mode it is only a lock for
        -- decoration-aware cover (N = 1).
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
            elseif e.rarity > limit then
                state[e.key] = "rarity"
                stay[#stay + 1] = e
            else
                local ex = exempt_skill(e)
                if ex then
                    state[e.key] = ex
                    stay[#stay + 1] = e
                else
                    out[e.key] = { action = "sell", reason = "rule", detail = "unique" }
                end
            end
            work()
        end
        -- Covered and duplicates among what stays, so every ref stays. Floor members are
        -- never sold through a decoration-only cover.
        local g2
        if not best and not decorations then
            g2 = groups   -- "covered" mode: what stays is the whole pool, already compared in stage 2
        else
            g2 = build_groups(stay, work)
            dominate(g2, decorations, function(g) return floor[g.keeper.key] ~= nil end, work)
        end
        for _, g in ipairs(g2) do
            local t = g.dominated_by and top(g)
            for _, e in ipairs(g.members) do
                if not fixed[e.key] and not out[e.key] then
                    if t then
                        local v = { action = "sell", reason = "dominated", ref = t.keeper.key }
                        if decorations and not analysis.covers(t.keeper, e) then
                            local why = {}
                            analysis.covers_deco(t.keeper, e, decorations, why)
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
                        out[e.key] = { action = "keep", reason = "exempt", detail = state[e.key] }
                    else
                        out[e.key] = { action = "keep", reason = "best" }
                    end
                end
            end
            work(#g.members)
        end
        return out, floor, floor_of, floor_shape
    end

    local out, floor, floor_of, floor_shape = decide(mode, best_n)
    local verdicts = {}
    for _, e in ipairs(entries) do verdicts[e.key] = fixed[e.key] or out[e.key] end
    work(#entries // 4 + 1)
    info.floor, info.floor_of, info.floor_shape = floor, floor_of, floor_shape
    local kept, kept_by_skill = index_kept(entries, function(key) return verdicts[key] end, work)

    -- Stage 4: a rule sale that a kept talisman covers is shown as covered or duplicate; the
    -- others are unique and carry their certificate (refs): the floor of each of their skills
    -- and of their slot shape.
    if mode == "best" then
        for _, e in ipairs(pool) do
            local v = out[e.key]
            if v and v.reason == "rule" then
                local found
                local candidates = cover_candidates(e, kept, kept_by_skill)
                for _, other in ipairs(candidates) do
                    if other ~= e and analysis.covers(other, e) then
                        if other.signature == e.signature then
                            found = { other, "duplicate" }
                            break
                        end
                        found = found or { other, "dominated" }
                    end
                end
                if found then
                    v = { action = "sell", reason = found[2], ref = found[1].key, detail = "rule" }
                    out[e.key], verdicts[e.key] = v, v
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
                    -- Its best position, for display ("closest Item Prolonger #10"); on a tie
                    -- the lowest skill id, then the slot shape.
                    local b
                    for s, r in pairs(ranks[e.key] or {}) do
                        if not b or r < b.rank or (r == b.rank and rank_label_first(s, b.skill)) then b = { skill = s, rank = r } end
                    end
                    v.rank = b
                end
                work(#candidates + 2)
            end
        end
    end

    -- Sell picks: whether a kept talisman covers them, for the Why text.
    for _, e in ipairs(entries) do
        local v = verdicts[e.key]
        if v.reason == "picked" and v.action == "sell" then
            local candidates = cover_candidates(e, kept, kept_by_skill)
            for _, k in ipairs(candidates) do
                if analysis.covers(k, e) then
                    v.covered_by = k.key
                    break
                end
            end
            if not v.covered_by then v.unique = true end
            work(#candidates + 2)
        end
    end

    -- Stage 5: losses, the counted skill levels and slot shapes no kept talisman reaches any more.
    local kept_max, kept_raw_max = {}, {}
    for _, e in ipairs(kept) do
        for _, id in ipairs(e.skill_ids) do
            if e.skill_levels[id] > (kept_max[id] or 0) then kept_max[id] = e.skill_levels[id] end
        end
        for _, skill in ipairs(e.charm.skills or {}) do
            if skill.level > (kept_raw_max[skill.id] or 0) then kept_raw_max[skill.id] = skill.level end
        end
        work()
    end
    info.kept_max = kept_max
    local shape_held = {}
    for _, e in ipairs(entries) do
        local v = verdicts[e.key]
        if v.action == "sell" then
            for _, id in ipairs(e.skill_ids) do
                if e.skill_levels[id] > (kept_max[id] or 0) then
                    v.drops = v.drops or {}
                    v.drops[#v.drops + 1] = { id = id, level = e.skill_levels[id], kept = kept_max[id] or 0 }
                end
            end
            -- Don't care skills are reported separately.
            for _, skill in ipairs(e.charm.skills or {}) do
                if ignore[skill.id] and skill.level > (kept_raw_max[skill.id] or 0) then
                    v.ignored_drops = v.ignored_drops or {}
                    v.ignored_drops[#v.ignored_drops + 1] = { id = skill.id, level = skill.level, kept = kept_raw_max[skill.id] or 0 }
                end
            end
            if e.nslots > 0 then
                local held = shape_held[e.shape]
                if held == nil then
                    held = false
                    for _, k in ipairs(kept) do
                        if analysis.holds(k.slots, e.slots) then
                            held = true
                            break
                        end
                    end
                    shape_held[e.shape] = held
                    work(#kept // 2 + 1)
                end
                if not held then v.shape_lost = e.shape end
            end
            work()
        end
    end

    -- Stage 6: the independent checker; failing automatic sales are held back.
    local problems = analysis.check(sorted, verdicts, options, work)
    info.problems = problems
    info.held_back = {}
    for _, p in ipairs(problems) do
        local v = verdicts[p.key]
        if v and v.action == "sell" and v.reason ~= "picked" then
            verdicts[p.key] = { action = "keep", reason = "best", detail = "safety_check", was = v }
            info.held_back[#info.held_back + 1] = p.key
        end
    end

    -- Stage 7: exact counts for every entry of the Keep combo, from the same decide().
    if options.preview ~= false then
        local function count(mode_x, n_x, rarity_x)
            local same = mode_x == mode and (mode_x ~= "best" or n_x == best_n) and rarity_x == nil
            local o = same and out or decide(mode_x, n_x, rarity_x)
            local sell, zenny = 0, 0
            for _, e in ipairs(entries) do
                local v = fixed[e.key] or o[e.key]
                if v.action == "sell" then
                    sell = sell + 1
                    zenny = zenny + (e.charm.price or 0)
                end
            end
            work(#entries // 4 + 1)
            return { sell = sell, zenny = zenny }
        end
        info.preview = { manual = count("manual"), covered = count("covered"), best = {} }
        for _, n in ipairs(analysis.PREVIEW_N) do info.preview.best[n] = count("best", n) end
        if mode == "best" and not info.preview.best[best_n] then info.preview.best[best_n] = count("best", best_n) end
        -- What the same N would sell without a rarity limit (the hint under the slider).
        if mode == "best" and max_rarity < 8 then info.preview.unlimited = count("best", best_n, 8) end
    end
    return verdicts, info
end

-- Re-derives every sale's guarantee from the verdicts alone. It shares only prepare,
-- covers and holds with the plan. Returns a list of { key, what }.
function analysis.check(charms, verdicts, options, work)
    options = options or {}
    work = work or function() end
    local mode = options.mode or "covered"
    local best_n = options.best_n or 5
    local max_rarity = options.max_rarity or 8
    local keep_skills = options.keep_skills or {}
    local places = options.skill_places or {}
    local picks = options.picks or {}
    local ignore = ignore_set(options, keep_skills)
    local decorations = options.decorations
    local problems = {}
    local function problem(key, what) problems[#problems + 1] = { key = key, what = what } end

    local prepared, kept, kept_sigs = {}, {}, {}
    for _, c in ipairs(charms) do
        local e = analysis.prepare(c, ignore)
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
        work(PREPARE_COST)
    end

    -- Distinct kept signatures per (skill, level or higher), and the best kept level per skill.
    local at_least, kept_max = {}, {}
    for _, k in ipairs(kept) do
        for id, level in pairs(k.skill_levels) do
            local counts = at_least[id]
            if not counts then
                counts = {}
                at_least[id] = counts
            end
            counts[level] = (counts[level] or 0) + 1
            if level > (kept_max[id] or 0) then kept_max[id] = level end
        end
    end
    for id, counts in pairs(at_least) do
        local run = 0
        for level = kept_max[id], 1, -1 do
            run = run + (counts[level] or 0)
            counts[level] = run
        end
    end
    local holders = {}   -- slot shape -> distinct kept signatures whose slots hold it
    local function holders_of(e)
        local n = holders[e.shape]
        if not n then
            n = 0
            for _, k in ipairs(kept) do
                if analysis.holds(k.slots, e.slots) then n = n + 1 end
            end
            holders[e.shape] = n
            work(#kept // 2 + 1)
        end
        return n
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
                    if not decorations or not analysis.covers_deco(ref, e, decorations) then problem(c.key, "decoration cover fails") end
                elseif not analysis.covers(ref, e) then
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
                    local have = at_least[id] and at_least[id][level] or 0
                    if have < need then problem(c.key, string.format("floor broken: skill %d has %d of %d", id, have, need)) end
                end
                if options.slot_floor ~= false and e.nslots > 0 then
                    local have = holders_of(e)
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
        work(2)
    end
    return problems
end

-- Totals for the summary and the confirmation.
function analysis.summarize(charms, verdicts)
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

-- Keys (sorted) whose action differs between two plans of the same box.
function analysis.diff(old, new)
    local keys = {}
    for key, v in pairs(new) do
        local before = old[key]
        if before and before.action ~= v.action then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

-- Skills whose best level in the box would go down if the charms in `selling`
-- ({ [key] = true }) were sold. Returns a list sorted by skill id of
-- { id, from, to, boxes }; `to` = 0 means no charm with that skill would remain,
-- and `boxes` are the sold keys that held the `from` level.
function analysis.losses(charms, selling)
    local best, left = {}, {}
    for _, charm in ipairs(charms) do
        local sold = selling[charm.key] == true
        for _, skill in ipairs(charm.skills or {}) do
            if skill.level > (best[skill.id] or 0) then best[skill.id] = skill.level end
            if not sold and skill.level > (left[skill.id] or 0) then left[skill.id] = skill.level end
        end
    end
    local drops, by_id = {}, {}
    for id, level in pairs(best) do
        if (left[id] or 0) < level then
            by_id[id] = { id = id, from = level, to = left[id] or 0, boxes = {} }
            drops[#drops + 1] = by_id[id]
        end
    end
    for _, charm in ipairs(charms) do
        if selling[charm.key] then
            for _, skill in ipairs(charm.skills or {}) do
                local drop = by_id[skill.id]
                if drop and skill.level == drop.from then drop.boxes[#drop.boxes + 1] = charm.key end
            end
        end
    end
    table.sort(drops, function(a, b) return a.id < b.id end)
    return drops
end

return analysis
