-- Per-skill settings and the Skills panel's numbers. Pure Lua.
--
-- A skill has at most one preference, stored in the settings maps (keyed by the skill
-- id as a string):
--   default                 nothing stored: the Keep option decides
--   { kind = "best", n }    skill_places[id] = n: its own number of places ("best N" mode)
--   { kind = "keep", min }  keep_skills[id] = min: never sold as unique at that level or higher
--   { kind = "ignore" }     ignore_skills[id] = true: Don't care, left out of every comparison

local analysis = require("BulkSell.analysis")
local lang = require("BulkSell.lang")
local T = lang.T

local skills = {}

local BEST_CHOICES = { 1, 2, 3, 5, 10 }

function skills.pref_of(settings, id)
    local key = tostring(id)
    if settings.keep_skills[key] then return { kind = "keep", min = settings.keep_skills[key] } end
    if settings.skill_places[key] then return { kind = "best", n = settings.skill_places[key] } end
    if settings.ignore_skills[key] then return { kind = "ignore" } end
    return { kind = "default" }
end

function skills.set(settings, id, pref)
    local key = tostring(id)
    settings.keep_skills[key], settings.skill_places[key], settings.ignore_skills[key] = nil, nil, nil
    if pref.kind == "keep" then
        settings.keep_skills[key] = pref.min
    elseif pref.kind == "best" then
        settings.skill_places[key] = pref.n
    elseif pref.kind == "ignore" then
        settings.ignore_skills[key] = true
    end
end

function skills.same(a, b)
    return a.kind == b.kind and a.n == b.n and a.min == b.min
end

function skills.label(pref)
    if pref.kind == "best" then return T("skill_pref_best", pref.n) end
    if pref.kind == "keep" then return pref.min <= 1 and T("skill_pref_keep_all") or T("skill_pref_keep_from", pref.min) end
    if pref.kind == "ignore" then return T("skill_pref_dont_care") end
    return T("skill_pref_default")
end

-- The choices of the per-skill combo, for a skill whose best level in the box is `box_max`,
-- plus the current preference when it is not one of them (a hand-edited file).
function skills.choices(box_max, current)
    local list = { { kind = "default" } }
    for _, n in ipairs(BEST_CHOICES) do list[#list + 1] = { kind = "best", n = n } end
    list[#list + 1] = { kind = "keep", min = 1 }
    for level = 2, math.max(box_max or 1, 1) do list[#list + 1] = { kind = "keep", min = level } end
    list[#list + 1] = { kind = "ignore" }
    local found
    for i, pref in ipairs(list) do
        if current and skills.same(pref, current) then found = i end
    end
    if current and not found then
        table.insert(list, #list, current)
        found = #list - 1
    end
    return list, found or 1
end

-- Counts for the panel header.
function skills.counts(settings)
    local c = { keep = 0, custom = 0, ignore = 0 }
    for key in pairs(settings.keep_skills) do if key ~= "_format" then c.keep = c.keep + 1 end end
    for key in pairs(settings.skill_places) do if key ~= "_format" then c.custom = c.custom + 1 end end
    for key in pairs(settings.ignore_skills) do if key ~= "_format" then c.ignore = c.ignore + 1 end end
    return c
end

-- One row per skill found on a talisman: { id, name, count, best, kept, kept_best, loss, pref },
-- sorted by name. Levels are the raw ones, so Don't care skills show what really stays.
function skills.rows(charms, verdicts, settings, names)
    local by_id, rows = {}, {}
    for _, charm in ipairs(charms) do
        local kept = verdicts[charm.key].action == "keep"
        for _, skill in ipairs(charm.skills) do
            local row = by_id[skill.id]
            if not row then
                row = { id = skill.id, name = names[skill.id] or T("skill_id", skill.id), count = 0, best = 0, kept = 0, kept_best = 0 }
                by_id[skill.id] = row
                rows[#rows + 1] = row
            end
            row.count = row.count + 1
            if skill.level > row.best then row.best = skill.level end
            if kept then
                row.kept = row.kept + 1
                if skill.level > row.kept_best then row.kept_best = skill.level end
            end
        end
    end
    for _, row in ipairs(rows) do
        row.loss = row.kept_best < row.best
        row.pref = skills.pref_of(settings, row.id)
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

-- Talismans that are the last of their kind: the only holder of a skill's best level in the
-- box, or the only talisman whose slots can hold its slot shape. `entry_of` holds the
-- prepared entries of analysis.plan (for the slots).
function skills.last_of_kind(charms, entry_of)
    local best, holders = {}, {}
    for _, charm in ipairs(charms) do
        for _, skill in ipairs(charm.skills) do
            local b = best[skill.id]
            if not b or skill.level > b.level then
                best[skill.id] = { level = skill.level, keys = { charm.key } }
            elseif skill.level == b.level then
                b.keys[#b.keys + 1] = charm.key
            end
        end
    end
    local last = {}
    for _, b in pairs(best) do
        if #b.keys == 1 then last[b.keys[1]] = true end
    end
    local shapes = {}
    for _, charm in ipairs(charms) do
        local e = entry_of[charm.key]
        if e and e.nslots > 0 and not shapes[e.shape] then shapes[e.shape] = e.slots end
    end
    local holds = analysis.holds
    for _, slots in pairs(shapes) do
        local only, count = nil, 0
        for _, charm in ipairs(charms) do
            if holds(entry_of[charm.key].slots, slots) then
                count = count + 1
                only = charm.key
                if count > 1 then break end
            end
        end
        if count == 1 then last[only] = true end
    end
    return last
end

local function map_equal(a, b)
    for k, v in pairs(a or {}) do if (b or {})[k] ~= v then return false end end
    for k, v in pairs(b or {}) do if (a or {})[k] ~= v then return false end end
    return true
end

function skills.keep_label(options)
    if options.mode == "manual" then return T("change_keep_manual") end
    if options.mode == "covered" then return T("change_keep_covered") end
    return T("change_keep_best", options.best_n)
end

-- What differs between the analysis options of two plans, as a short text.
function skills.describe_change(before, after)
    local parts = {}
    if before.mode ~= after.mode or (after.mode == "best" and before.best_n ~= after.best_n) then
        parts[#parts + 1] = T("change_keep", skills.keep_label(after))
    end
    if after.mode == "best" and before.max_rarity ~= after.max_rarity then
        parts[#parts + 1] = T("change_rarity", after.max_rarity)
    end
    if not (map_equal(before.keep_skills, after.keep_skills) and map_equal(before.ignore_skills, after.ignore_skills)
        and map_equal(before.skill_places, after.skill_places)) then
        parts[#parts + 1] = T("change_skills")
    end
    if not map_equal(before.picks, after.picks) then parts[#parts + 1] = T("change_picks") end
    if #parts == 0 then return T("change_rescan") end
    return table.concat(parts, ", ")
end

function skills.copy_prefs(settings)
    local copy = {}
    for _, name in ipairs({ "keep_skills", "skill_places", "ignore_skills" }) do
        copy[name] = {}
        for k, v in pairs(settings[name]) do copy[name][k] = v end
    end
    return copy
end

function skills.restore_prefs(settings, copy)
    for name, map in pairs(copy) do
        local fresh = {}
        for k, v in pairs(map) do fresh[k] = v end
        settings[name] = fresh
    end
end

return skills
