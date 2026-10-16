-- Talisman analysis for Bulk Sell. Pure Lua with no game access, so it can be
-- unit tested outside the game.
--
-- Charm shape (built by the game layer):
--   key        unique id (Equipment Box index)
--   rarity     integer rarity shown in game
--   skills     { { id = integer, level = integer }, ... }
--   slots      { { kind = "W" | "A", level = integer }, ... }   W = weapon, A = armor
--   protected  nil, or a short reason string ("equipped", "loadout", ...)
--   price      zenny received when sold (optional, used for totals)
--
-- Verdict shape: { action = "keep" | "sell", reason = string, ref = key?, detail = string? }
--   reason "protected"  never sold (detail = why)
--   reason "rule"       matched a user rule (detail = which rule)
--   reason "dominated"  another kept charm (ref) has every skill and slot at least as good
--   reason "duplicate"  identical to the kept charm ref
--   reason "best"       nothing kept is at least as good

local analysis = {}

local SLOT_KINDS = { "W", "A" }

local function descending(a, b) return a > b end

-- Normalizes a charm into lookup tables used by the dominance checks.
function analysis.prepare(charm)
    local skill_levels, skill_ids = {}, {}
    for _, skill in ipairs(charm.skills or {}) do
        if skill.level > 0 then
            if not skill_levels[skill.id] then skill_ids[#skill_ids + 1] = skill.id end
            skill_levels[skill.id] = math.max(skill_levels[skill.id] or 0, skill.level)
        end
    end
    table.sort(skill_ids)

    local slots = {}
    for _, kind in ipairs(SLOT_KINDS) do slots[kind] = {} end
    for _, slot in ipairs(charm.slots or {}) do
        if slot.level > 0 then
            local list = assert(slots[slot.kind], "unknown slot kind " .. tostring(slot.kind))
            list[#list + 1] = slot.level
        end
    end
    for _, kind in ipairs(SLOT_KINDS) do table.sort(slots[kind], descending) end

    local parts = {}
    for _, id in ipairs(skill_ids) do parts[#parts + 1] = id .. ":" .. skill_levels[id] end
    local signature = table.concat(parts, ",")
    for _, kind in ipairs(SLOT_KINDS) do
        signature = signature .. "|" .. kind .. table.concat(slots[kind], ",")
    end

    return {
        charm = charm,
        skill_levels = skill_levels,
        skill_ids = skill_ids,
        slots = slots,
        signature = signature,
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

-- True when prepared charm `upper` has every skill of `lower` at an equal or
-- higher level, and slots that can hold everything `lower`'s slots can.
function analysis.covers(upper, lower)
    for id, level in pairs(lower.skill_levels) do
        if (upper.skill_levels[id] or 0) < level then return false end
    end
    for _, kind in ipairs(SLOT_KINDS) do
        if not slots_cover(upper.slots[kind], lower.slots[kind]) then return false end
    end
    return true
end

-- Rule-based selling. Returns the matched rule name, or nil.
local function rule_reason(entry, options)
    local rules = options.rules
    if not rules or not rules.max_rarity then return nil end
    if entry.charm.rarity > rules.max_rarity then return nil end
    local keep_skills = options.keep_skills or {}
    for id, level in pairs(entry.skill_levels) do
        local min_level = keep_skills[id]
        if min_level and level >= min_level then return nil end
    end
    return "max_rarity"
end

-- Protected copies win, then the lowest key (oldest box slot).
local function choose_keeper(members)
    local best = members[1]
    for i = 2, #members do
        local a, b = members[i].charm, best.charm
        local a_protected, b_protected = a.protected ~= nil, b.protected ~= nil
        if (a_protected and not b_protected) or (a_protected == b_protected and a.key < b.key) then
            best = members[i]
        end
    end
    return best
end

-- Decides, for every charm, whether to keep or sell it. Returns verdicts keyed by charm.key.
--
-- options.sell_dominated  (default true) sell charms that a kept charm covers, and extra duplicates.
-- options.rules           { max_rarity = n } sells unprotected charms with rarity <= n.
-- options.keep_skills     { [skill_id] = min_level } exempts charms from rules.
-- options.yield           optional function called periodically, so the game can spread work over frames.
--
-- Rules run first, and charms they sell are not used as keepers. A charm sold as
-- dominated is therefore always covered by a charm that stays in the box.
function analysis.plan(charms, options)
    options = options or {}
    local verdicts, survivors = {}, {}

    for _, charm in ipairs(charms) do
        local entry = analysis.prepare(charm)
        if charm.protected then
            verdicts[charm.key] = { action = "keep", reason = "protected", detail = charm.protected }
            survivors[#survivors + 1] = entry
        else
            local rule = rule_reason(entry, options)
            if rule then
                verdicts[charm.key] = { action = "sell", reason = "rule", detail = rule }
            else
                survivors[#survivors + 1] = entry
            end
        end
    end

    if options.sell_dominated == false then
        for _, entry in ipairs(survivors) do
            verdicts[entry.charm.key] = verdicts[entry.charm.key] or { action = "keep", reason = "best" }
        end
        return verdicts
    end

    -- Identical charms form one group; its keeper stands for the group in dominance checks.
    local groups, by_signature = {}, {}
    for _, entry in ipairs(survivors) do
        local group = by_signature[entry.signature]
        if not group then
            group = { members = {} }
            by_signature[entry.signature] = group
            groups[#groups + 1] = group
        end
        group.members[#group.members + 1] = entry
    end
    for _, group in ipairs(groups) do group.keeper = choose_keeper(group.members) end

    -- A charm can only be covered by charms that have all of its skills, so each
    -- group is only compared against the shortest skill list it appears in.
    local by_skill = {}
    for _, group in ipairs(groups) do
        for _, id in ipairs(group.keeper.skill_ids) do
            local list = by_skill[id]
            if not list then
                list = {}
                by_skill[id] = list
            end
            list[#list + 1] = group
        end
    end

    for i, group in ipairs(groups) do
        local candidates = groups
        for _, id in ipairs(group.keeper.skill_ids) do
            if #by_skill[id] < #candidates then candidates = by_skill[id] end
        end
        -- Different groups never cover each other both ways, so any cover is strict.
        for _, other in ipairs(candidates) do
            if other ~= group and analysis.covers(other.keeper, group.keeper) then
                group.dominated_by = other
                break
            end
        end
        if options.yield and i % 64 == 0 then options.yield() end
    end

    -- Strict dominance has no cycles, so following it always ends at a kept group.
    local function top(group)
        while group.dominated_by do group = group.dominated_by end
        return group
    end

    for _, group in ipairs(groups) do
        local front = group.dominated_by and top(group)
        for _, entry in ipairs(group.members) do
            local key = entry.charm.key
            if not verdicts[key] then
                if front then
                    verdicts[key] = { action = "sell", reason = "dominated", ref = front.keeper.charm.key }
                elseif entry ~= group.keeper then
                    verdicts[key] = { action = "sell", reason = "duplicate", ref = group.keeper.charm.key }
                else
                    verdicts[key] = { action = "keep", reason = "best" }
                end
            end
        end
    end

    return verdicts
end

-- Totals for the confirmation screen.
function analysis.summarize(charms, verdicts)
    local summary = { sell = 0, keep = 0, zenny = 0, by_reason = {} }
    for _, charm in ipairs(charms) do
        local verdict = verdicts[charm.key]
        summary[verdict.action] = summary[verdict.action] + 1
        summary.by_reason[verdict.reason] = (summary.by_reason[verdict.reason] or 0) + 1
        if verdict.action == "sell" then summary.zenny = summary.zenny + (charm.price or 0) end
    end
    return summary
end

return analysis
