-- Talisman lists for other tools. Pure Lua.
--
-- mhwilds.wiki-db.com (Armor Set Search, Talisman tab, "Import/Export Charms"): one line
-- per talisman, read from the site's own import code:
--   skill1,level1,skill2,level2,skill3,level3,armor1,armor2,armor3,weapon1,weapon2,weapon3
-- A missing skill is an empty name with level 0; slot levels are highest first, 0 = none.
-- Names must be in the site's language. Importing replaces the site's whole list.
--
-- CSV for spreadsheets: UTF-8 with a BOM, one row per talisman with its verdict.

local export = {}

export.SCOPES = { "all", "stays", "sell" }

-- Talismans of a plan for a scope: every appraised one, what stays after the planned
-- sale, or only what would be sold. Box order.
function export.select(charms, verdicts, scope)
    local out = {}
    for _, charm in ipairs(charms) do
        local action = verdicts[charm.key].action
        if scope == "all" or (scope == "stays" and action == "keep") or (scope == "sell" and action == "sell") then
            out[#out + 1] = charm
        end
    end
    return out
end

-- No field may contain the separator.
local function clean(name)
    return (tostring(name or ""):gsub("[,\r\n]", " "))
end

local function slot_levels(charm, kind)
    local levels = {}
    for _, slot in ipairs(charm.slots) do
        if slot.kind == kind then levels[#levels + 1] = slot.level end
    end
    table.sort(levels, function(a, b) return a > b end)
    return { levels[1] or 0, levels[2] or 0, levels[3] or 0 }
end

function export.wikidb_line(charm, names)
    local fields = {}
    for i = 1, 3 do
        local skill = charm.skills[i]
        fields[#fields + 1] = skill and clean(names[skill.id] or ("Skill #" .. skill.id)) or ""
        fields[#fields + 1] = skill and tostring(skill.level) or "0"
    end
    for _, kind in ipairs({ "A", "W" }) do
        for _, level in ipairs(slot_levels(charm, kind)) do fields[#fields + 1] = tostring(level) end
    end
    return table.concat(fields, ",")
end

function export.wikidb(list, names)
    local lines = {}
    for i, charm in ipairs(list) do lines[i] = export.wikidb_line(charm, names) end
    return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

local CSV_HEADER = { "box", "rarity", "skill1", "level1", "skill2", "level2", "skill3", "level3", "slots",
    "armor1", "armor2", "armor3", "weapon1", "price", "verdict", "reason", "kept_instead", "protected" }

local function csv_field(value)
    local text = tostring(value == nil and "" or value)
    if text:find('[,"\r\n]') then text = '"' .. text:gsub('"', '""') .. '"' end
    return text
end

-- `label(verdict)` gives the Verdict text and `why(charm, verdict)` the reason text.
function export.csv(list, verdicts, names, label, why)
    local rows = { "\239\187\191" .. table.concat(CSV_HEADER, ",") }   -- UTF-8 BOM, so spreadsheets read the names right
    for _, charm in ipairs(list) do
        local v = verdicts[charm.key]
        local fields = { charm.key, charm.rarity }
        for i = 1, 3 do
            local skill = charm.skills[i]
            fields[#fields + 1] = skill and (names[skill.id] or ("Skill #" .. skill.id)) or ""
            fields[#fields + 1] = skill and skill.level or ""
        end
        local slot_text = {}
        for _, slot in ipairs(charm.slots) do slot_text[#slot_text + 1] = slot.kind .. slot.level end
        fields[#fields + 1] = table.concat(slot_text, " ")
        local armor, weapon = slot_levels(charm, "A"), slot_levels(charm, "W")
        fields[#fields + 1], fields[#fields + 2], fields[#fields + 3] = armor[1], armor[2], armor[3]
        fields[#fields + 1] = weapon[1]
        fields[#fields + 1] = charm.price or ""
        fields[#fields + 1] = label(v)
        fields[#fields + 1] = why(charm, v)
        fields[#fields + 1] = v.ref or v.covered_by or ""
        fields[#fields + 1] = charm.protected or ""
        for i, value in ipairs(fields) do fields[i] = csv_field(value) end
        rows[#rows + 1] = table.concat(fields, ",")
    end
    return table.concat(rows, "\r\n") .. "\r\n"
end

-- Melding Pot points per rarity (the game's table for appraised talismans).
export.MELD_POINTS = { [5] = 1, [6] = 3, [7] = 6, [8] = 10 }

function export.meld_points(list)
    local points = 0
    for _, charm in ipairs(list) do points = points + (export.MELD_POINTS[charm.rarity] or 0) end
    return points
end

return export
