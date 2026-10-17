-- Helpers shared by the analysis tests: compact charm builder, seeded random boxes and
-- options (ported from the planning property scripts), and a deep comparison.

local M = {}

-- charm(key, rarity, "skill:level,...", "W1,A2", protected); price = rarity * 100.
function M.charm(key, rarity, skills, slots, protected)
    local c = { key = key, rarity = rarity, skills = {}, slots = {}, protected = protected, price = rarity * 100 }
    for id, level in (skills or ""):gmatch("(%d+):(%d+)") do
        c.skills[#c.skills + 1] = { id = tonumber(id), level = tonumber(level) }
    end
    for kind, level in (slots or ""):gmatch("([WA])(%d)") do
        c.slots[#c.slots + 1] = { kind = kind, level = tonumber(level) }
    end
    c.fingerprint = "fp:" .. (skills or "") .. "|" .. (slots or "") .. "|R" .. rarity
    return c
end

local PRICE = { [5] = 1500, [6] = 3000, [7] = 4500, [8] = 8000 }
-- Appraised slot templates of the game, with the rarity that usually carries them.
local TEMPLATES = {
    { {}, 5 }, { { { "W", 1 } }, 8 }, { { { "A", 1 } }, 6 }, { { { "A", 1 }, { "A", 1 } }, 6 },
    { { { "A", 1 }, { "A", 1 }, { "A", 1 } }, 5 }, { { { "A", 2 } }, 7 }, { { { "A", 2 }, { "A", 1 } }, 6 },
    { { { "A", 3 } }, 7 }, { { { "W", 1 }, { "A", 1 } }, 8 }, { { { "W", 1 }, { "A", 1 }, { "A", 1 } }, 8 },
}

local function sample(n, k)
    local pool = {}
    for i = 1, n do pool[i] = i end
    for i = 1, k do
        local j = math.random(i, n)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local out = {}
    for i = 1, k do out[i] = pool[i] end
    return out
end

-- Seeded by the caller with math.randomseed.
function M.random_box(n, o)
    o = o or {}
    local dup_rate, prot_rate = o.dup_rate or 0.15, o.prot_rate or 0.05
    local n_skills, max_level = o.n_skills or 12, o.max_level or 3
    local box = {}
    for key = 1, n do
        local c
        if #box > 0 and math.random() < dup_rate then
            local src = box[math.random(#box)]
            c = { key = key, rarity = (o.consistent_rarity or math.random() < 0.7) and src.rarity or math.random(5, 8),
                skills = {}, slots = {} }
            for i, s in ipairs(src.skills) do c.skills[i] = { id = s.id, level = s.level } end
            for i, s in ipairs(src.slots) do c.slots[i] = { kind = s.kind, level = s.level } end
        else
            local ids = sample(n_skills, math.random(1, math.min(3, n_skills)))
            local skills = {}
            for i, id in ipairs(ids) do skills[i] = { id = id, level = math.random(1, max_level) } end
            local template = TEMPLATES[math.random(#TEMPLATES)]
            local slots = {}
            for i, s in ipairs(template[1]) do slots[i] = { kind = s[1], level = s[2] } end
            c = { key = key, rarity = o.consistent_rarity and template[2] or math.random(5, 8), skills = skills, slots = slots }
        end
        c.price = PRICE[c.rarity]
        if math.random() < prot_rate then c.protected = "equipped" end
        local parts = {}
        for _, s in ipairs(c.skills) do parts[#parts + 1] = s.id .. ":" .. s.level end
        local slot_parts = {}
        for _, s in ipairs(c.slots) do slot_parts[#slot_parts + 1] = s.kind .. s.level end
        c.fingerprint = "fp:" .. table.concat(parts, ";") .. "|" .. table.concat(slot_parts, ",") .. "|R" .. c.rarity
        box[#box + 1] = c
    end
    return box
end

function M.random_decos(n_skills, owned)
    local decos = {}
    for id = 1, n_skills do
        if math.random() < 0.8 then
            local d = { kind = math.random() < 0.6 and "A" or "W", size = math.random() < 0.6 and 1 or math.random(2, 3) }
            if d.kind == "W" then d.size = 1 end
            if owned then d.free = math.random(0, 3) end
            decos[id] = d
        end
    end
    return decos
end

local function pick_one(list) return list[math.random(#list)] end

function M.random_options(box, n_skills)
    local o = {}
    local r = math.random()
    o.mode = r < 0.3 and "covered" or (r < 0.9 and "best" or "manual")
    o.best_n = pick_one({ 1, 2, 3, 5 })
    o.max_rarity = pick_one({ 5, 6, 7, 8 })
    local keep, ignore, places = {}, {}, {}
    local any_keep, any_ignore, any_places = false, false, false
    for id = 1, n_skills do
        if math.random() < 0.1 then keep[id] = math.random(1, 3); any_keep = true end
        if math.random() < 0.1 then ignore[id] = true; any_ignore = true end
        if math.random() < 0.1 then places[id] = math.random(1, 5); any_places = true end
    end
    if any_keep then o.keep_skills = keep end
    if any_ignore then o.ignore_skills = ignore end
    if any_places then o.skill_places = places end
    local picks, any_pick = {}, false
    for _, c in ipairs(box) do
        if math.random() < 0.06 then
            picks[c.key] = math.random() < 0.5 and "keep" or "sell"
            any_pick = true
        end
    end
    if any_pick then o.picks = picks end
    if math.random() < 0.3 then o.decorations = M.random_decos(n_skills, math.random() < 0.5) end
    if math.random() < 0.15 then o.slot_floor = false end
    o.preview = false
    return o
end

function M.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = M.copy(v) end
    return out
end

-- Returns true, or false and the path of the first difference.
function M.deep_equal(a, b, path, skip)
    path = path or "value"
    if type(a) ~= type(b) then return false, path .. string.format(" (%s vs %s)", tostring(a), tostring(b)) end
    if type(a) ~= "table" then
        if a == b then return true end
        return false, path .. string.format(" (%s vs %s)", tostring(a), tostring(b))
    end
    for k, v in pairs(a) do
        if not (skip and skip[k]) then
            local ok, where = M.deep_equal(v, b[k], path .. "." .. tostring(k), skip)
            if not ok then return false, where end
        end
    end
    for k, v in pairs(b) do
        if not (skip and skip[k]) and a[k] == nil then
            return false, path .. "." .. tostring(k) .. " (missing vs " .. tostring(v) .. ")"
        end
    end
    return true
end

function M.sell_count(verdicts)
    local n = 0
    for _, v in pairs(verdicts) do
        if v.action == "sell" then n = n + 1 end
    end
    return n
end

-- A tiny test runner shared by the analysis test files.
function M.runner()
    local tests = {}
    local r = {}
    function r.test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
    function r.run()
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
    end
    return r
end

function M.eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "value", tostring(expected), tostring(actual)), 2)
    end
end

return M
