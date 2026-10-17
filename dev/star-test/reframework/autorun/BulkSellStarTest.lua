-- Star test, development only, never shipped (test session 2a, check V3).
--
-- Finds out whether cEquipWork:changeFavorite(true) sets the favorite star or toggles it.
-- The target talisman comes from BulkSellProbe/star_target.json ({ box, fingerprint }),
-- written before the session; nothing happens unless that box holds exactly that talisman.
-- Sequence: read, true, read, true, read, false, read, true, read. The whole box (fingerprint
-- and favorite flag of every entry) is compared before and after; only the target's star may
-- differ. Results go to BulkSellProbe/star_test_<time>.json.

local files = require("BulkSell.files")

local TARGET_FILE = "BulkSellProbe/star_target.json"
local RARITY_BY_TYPE = { [189] = 5, [190] = 6, [191] = 7, [192] = 8 }

local state = { status = "idle", job = nil, last_file = nil }

local function method(type_name, signature)
    local td = sdk.find_type_definition(type_name)
    return td and td:get_method(signature)
end

local function number(value)
    if type(value) == "userdata" then
        local ok, inner = pcall(function() return value:get_field("m_value") end)
        value = ok and inner or nil
    end
    if type(value) ~= "number" then return nil end
    return math.tointeger(value) or value
end

local function field(obj, name)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj:get_field(name) end)
    return ok and value or nil
end

local function equip_box()
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local getter = method("app.SaveDataManager", "getCurrentUserSaveData()")
    assert(manager and getter, "save data manager not ready")
    local save = assert(getter:call(manager), "no save loaded")
    return assert(field(field(save, "_Equip"), "_EquipBox"), "no Equipment Box")
end

-- Same fingerprint as BulkSell/game.lua ("type:v1:v2:v3:v4"), or nil for anything else.
local function fingerprint(work)
    local flags = number(field(work, "Category_Gender")) or 0x80
    if (flags & 0x80) ~= 0 then return nil end
    local amulet_type = number(field(work, "FreeVal0"))
    if not RARITY_BY_TYPE[amulet_type] or number(field(work, "FreeVal1")) ~= 1 then return nil end
    local packed = field(work, "BowgunCustomizeId")
    local values = { amulet_type }
    for i = 0, 3 do values[#values + 1] = number(packed:get_element(i)) or 0 end
    return table.concat(values, ":")
end

local function favorite(work)
    local getter = method("app.savedata.cEquipWork", "isFavorite()")
    local ok, value = pcall(getter.call, getter, work)
    if ok and type(value) == "boolean" then return value end
    return nil
end

local function box_map(box)
    local map = {}
    for i = 0, box:get_size() - 1 do
        local work = box:get_element(i)
        map[i] = { fp = fingerprint(work) or "-", star = favorite(work) }
        if i % 256 == 255 then coroutine.yield() end
    end
    return map
end

local function busy_reason()
    local gui = sdk.get_managed_singleton("app.GUIManager")
    local open = method("app.GUIManager", "isOpenFullScreenUI()")
    if not gui or not open then return "game menus not ready" end
    local ok, is_open = pcall(open.call, open, gui)
    if not ok or is_open ~= false then return "close the game menu first" end
    return nil
end

local function star_test()
    local busy = busy_reason()
    if busy then error("not now: " .. busy, 0) end
    local status, target = files.read_json(TARGET_FILE)
    if status ~= "ok" or type(target.box) ~= "number" or type(target.fingerprint) ~= "string" then
        error("no valid " .. TARGET_FILE, 0)
    end
    local box = equip_box()
    local work = box:get_element(target.box)
    local found = work and fingerprint(work)
    if found ~= target.fingerprint then
        error(string.format("box %d holds %s, not %s; nothing changed", target.box, tostring(found), target.fingerprint), 0)
    end
    local before = box_map(box)
    local change = assert(method("app.savedata.cEquipWork", "changeFavorite(System.Boolean)"), "changeFavorite missing")
    local steps = { { call = "read", star = favorite(work) } }
    for _, want in ipairs({ true, true, false, true }) do
        if busy_reason() then error("stopped: a game menu opened", 0) end
        change:call(work, want)
        steps[#steps + 1] = { call = tostring(want), star = favorite(work) }
    end
    local after = box_map(box)
    local other_changes, target_fp_same = {}, after[target.box].fp == target.fingerprint
    for i, b in pairs(before) do
        local a = after[i]
        if i ~= target.box and (a.fp ~= b.fp or a.star ~= b.star) and #other_changes < 20 then
            other_changes[#other_changes + 1] = { box = i, before = b.fp, after = a.fp }
        end
    end
    -- A setter leaves true after the second true; a toggle flips it back to false.
    local behaviour = (steps[2].star == true and steps[3].star == true and steps[4].star == false and steps[5].star == true)
        and "sets" or "other"
    local path = "BulkSellProbe/star_test_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    assert(files.write_json(path, {
        target = target, steps = steps, behaviour = behaviour, target_fingerprint_unchanged = target_fp_same,
        other_changes = #other_changes > 0 and other_changes or "none", at = os.date("%Y-%m-%d %H:%M:%S"),
    }), "could not write " .. path)
    state.last_file = path
    state.status = string.format("done: changeFavorite %s; other entries changed: %d", behaviour, #other_changes)
end

re.on_pre_application_entry("UpdateBehavior", function()
    local job = state.job
    if not job then return end
    local started = os.clock()
    repeat
        local ok, err = coroutine.resume(job)
        if not ok then
            state.job = nil
            state.status = "FAILED: " .. tostring(err)
            log.error("[BulkSellStarTest] " .. state.status)
            return
        end
    until coroutine.status(job) == "dead" or os.clock() - started > 0.004
    if coroutine.status(job) == "dead" then state.job = nil end
end)

re.on_draw_ui(function()
    if imgui.tree_node("BulkSell Star test (dev)") then
        imgui.text("Status: " .. state.status)
        if state.last_file then imgui.text("Last file: reframework/data/" .. state.last_file) end
        if not state.job and imgui.button("Star test") then
            state.status = "running..."
            state.job = coroutine.create(star_test)
        end
        imgui.tree_pop()
    end
end)
