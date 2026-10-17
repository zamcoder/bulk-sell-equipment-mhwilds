-- Player-facing texts for verdicts: the Verdict column, the Why column, and the same texts
-- in receipts. Pure Lua; `ctx` carries what the texts need:
--   ctx.names     { [skill id] = localized name }
--   ctx.by_key    { [box] = charm } (charms carry skills_label and slots_label)
--   ctx.info      the info table of analysis.plan (rank lists)
--   ctx.settings  the settings the plan was made with
--   ctx.ignore    { [skill id] = true } Don't care skills of that plan

local lang = require("BulkSell.lang")
local T = lang.T

local explain = {}

local PROTECTED = {
    equipped = "why_protected_equipped",
    loadout = "why_protected_loadout",
    favorite = "why_protected_favorite",
    decorations = "why_protected_decorations",
    ["special bonus"] = "why_protected_bonus",
}

function explain.skill_name(ctx, id)
    return ctx.names[id] or T("skill_id", id)
end

-- "W1|A2,1" -> "W1 A2 A1", "W|A3" -> "A3".
function explain.shape_label(shape)
    local w, a = shape:match("^W([%d,]*)|A([%d,]*)$")
    local parts = {}
    for level in (w or ""):gmatch("%d") do parts[#parts + 1] = "W" .. level end
    for level in (a or ""):gmatch("%d") do parts[#parts + 1] = "A" .. level end
    return #parts > 0 and table.concat(parts, " ") or "-"
end

function explain.protected_text(reason)
    return PROTECTED[reason] and T(PROTECTED[reason]) or tostring(reason)
end

-- Class for receipts and filters: keep, pick (a Sell pick), unique (rule), safe (covered or duplicate).
function explain.class(v)
    if v.action == "keep" then return "keep" end
    if v.reason == "picked" then return "pick" end
    if v.reason == "rule" then return "unique" end
    return "safe"
end

function explain.verdict_label(ctx, v)
    if v.action == "keep" then
        local r = v.reason
        if r == "protected" then return T("v_keep_protected") end
        if r == "picked" then return T("v_keep_pick") end
        if r == "top_n" then return T("v_keep_best_n", ctx.settings.best_n) end
        if r == "exempt" then return T("v_keep_always") end
        if r == "rarity" then return T("v_keep_rarity", ctx.settings.max_rarity) end
        if r == "auto_off" then return T("v_keep_not_ticked") end
        if v.detail == "safety_check" then return T("v_keep_held_back") end
        return T("v_keep")
    end
    if v.reason == "picked" then return T("v_sell_pick") end
    if v.reason == "rule" then return T("v_sell_unique") end
    if v.reason == "duplicate" then return T("v_sell_duplicate") end
    return T("v_sell_covered")
end

-- Don't care skills of `charm` that `ref` does not have at that level: they do not count, so
-- the Why text says so.
local function ignoring(ctx, charm, ref)
    if not ctx.ignore or not next(ctx.ignore) or not ref then return "" end
    local names = {}
    for _, skill in ipairs(charm.skills) do
        if ctx.ignore[skill.id] then
            local have = 0
            for _, other in ipairs(ref.skills) do
                if other.id == skill.id then have = math.max(have, other.level) end
            end
            if have < skill.level then names[#names + 1] = explain.skill_name(ctx, skill.id) .. " " .. skill.level end
        end
    end
    if #names == 0 then return "" end
    return T("why_ignoring", table.concat(names, ", "))
end

local function rank_text(ctx, label, rank)
    local info = ctx.info
    if type(label) == "number" then
        return T("why_rank_skill", explain.skill_name(ctx, label), rank, #(info.lists[label] or {}))
    end
    local shape = tostring(label):match("^shape:(.*)$") or label
    return T("why_rank_shape", explain.shape_label(shape), rank, #(info.shape_lists[shape] or {}))
end

local function first_loss(ctx, v)
    local drop = v.drops and v.drops[1] or (v.ignored_drops and v.ignored_drops[1])
    if drop then return T("why_last_skill", explain.skill_name(ctx, drop.id), drop.level) end
    if v.shape_lost then return T("why_last_shape", explain.shape_label(v.shape_lost)) end
    return nil
end

-- The Why text, and whether it is a warning (the player's pick removes something).
function explain.why(ctx, charm, v)
    local by_key = ctx.by_key
    if v.action == "sell" then
        if v.reason == "duplicate" then
            return T("why_same_as", v.ref) .. ignoring(ctx, charm, by_key[v.ref])
        end
        if v.reason == "dominated" then
            local ref = by_key[v.ref]
            return T("why_covered_by", v.ref, ref and ref.skills_label or "?") .. ignoring(ctx, charm, ref)
        end
        if v.reason == "rule" then
            if v.rank then
                return T("why_not_in_best", ctx.settings.best_n) .. " · " .. T("why_closest", rank_text(ctx, v.rank.skill, v.rank.rank))
            end
            return T("why_not_in_best", ctx.settings.best_n) .. " · " .. T("why_beaten_by_sold")
        end
        -- Sell pick
        local loss = first_loss(ctx, v)
        if loss then return T("why_pick") .. " · " .. loss, true end
        if v.covered_by then return T("why_pick_covered", v.covered_by) end
        return T("why_pick_unique")
    end
    local r = v.reason
    if r == "protected" then return explain.protected_text(v.detail) end
    if r == "picked" then return T("why_pick") end
    if r == "top_n" then
        local d = v.detail
        if d.skill then return rank_text(ctx, d.skill, d.rank) end
        return rank_text(ctx, "shape:" .. d.shape, d.rank)
    end
    if r == "exempt" then
        local min = ctx.settings.keep_skills[tostring(v.detail)] or 1
        return T("why_always_keep", explain.skill_name(ctx, v.detail), min)
    end
    if r == "rarity" then return T("why_rarity", ctx.settings.max_rarity) end
    if r == "auto_off" then return T("why_auto_off") end
    if v.detail == "safety_check" then return T("why_safety_check"), true end
    return T("why_best")
end

return explain
