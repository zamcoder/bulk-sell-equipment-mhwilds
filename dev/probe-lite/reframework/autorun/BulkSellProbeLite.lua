-- Bulk Sell probe-lite: development-only checks for test session 1a, never shipped.
--
-- Every action runs as a job on the game thread (UpdateBehavior), only reads fields
-- and simple getters, and stops as soon as a game menu opens. The UI only reads Lua
-- state. Reports go to reframework/data/BulkSellProbe/<name>_<time>.json.

local OUT = "BulkSellProbe/"
local FRAME_BUDGET = 0.004
local YIELD_EVERY = 256

local state = {
    status = "idle",
    job = nil,
    job_name = nil,
    last_file = nil,
    sort_before = nil,
    ui_panel = false,
    ui_check = false,
    ui_record = nil,
}

-- `ok and value or fallback` breaks when value is false, so use this instead.
local function either(ok, value, fallback)
    if ok then return value end
    return fallback
end

-- Plain value for JSON: numbers and booleans as they are, anything else as text.
local function plain(value)
    local kind = type(value)
    if kind == "number" then return math.tointeger(value) or value end
    if kind == "boolean" or kind == "string" then return value end
    return tostring(value)
end

local function number(value)
    if type(value) == "userdata" then
        local ok, inner = pcall(function() return value:get_field("m_value") end)
        value = ok and inner or nil
    end
    if type(value) == "boolean" then return value end
    if type(value) ~= "number" then return nil end
    return math.tointeger(value) or value
end

local function field(obj, name)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj:get_field(name) end)
    if ok then return value end
    return nil
end

local function ints(array)
    local list = {}
    local ok, n = pcall(function() return array:get_size() end)
    if not ok or type(n) ~= "number" then return "<none>" end
    for i = 0, n - 1 do
        local item_ok, item = pcall(function() return array:get_element(i) end)
        list[#list + 1] = item_ok and number(item) or "<error>"
    end
    return #list > 0 and list or "<empty>"
end

local function full_name(td)
    local ok, name = pcall(function() return td:get_full_name() end)
    return ok and name or "?"
end

local function write(name, data)
    local path = OUT .. name .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local ok, result = pcall(json.dump_file, path, data, 2)
    if not ok or result == false then error("could not write " .. path, 0) end
    state.last_file = path
    log.info("[BulkSellProbeLite] wrote " .. path)
end

-- true while any full-screen game UI is open (or when that cannot be checked).
local function menu_open()
    local manager = sdk.get_managed_singleton("app.GUIManager")
    local td = sdk.find_type_definition("app.GUIManager")
    local check = td and td:get_method("isOpenFullScreenUI()")
    if not manager or not check then return true end
    local ok, open = pcall(check.call, check, manager)
    return not ok or open ~= false
end

local function current_save()
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local td = sdk.find_type_definition("app.SaveDataManager")
    local getter = td and td:get_method("getCurrentUserSaveData()")
    assert(manager and getter, "save data manager not ready")
    return assert(getter:call(manager), "no save loaded"), manager
end

local function call0(obj, signature)
    if obj == nil then return "<missing>" end
    local ok, value = pcall(function() return obj:call(signature) end)
    if not ok then return "<error " .. tostring(value) .. ">" end
    return plain(either(number(value) ~= nil, number(value), value))
end

local function static_call(type_name, signature)
    local td = sdk.find_type_definition(type_name)
    local m = td and td:get_method(signature)
    if not m then return "<missing>" end
    local ok, value = pcall(m.call, m, nil)
    if not ok then return "<error " .. tostring(value) .. ">" end
    return plain(either(number(value) ~= nil, number(value), value))
end

local BOOL_OR_INT = {
    ["System.Boolean"] = true, ["System.Int32"] = true, ["System.UInt32"] = true,
    ["System.Int16"] = true, ["System.Byte"] = true,
}

-- Method and field names of a type, plus values of its zero-argument get_*/is* getters
-- that return a bool, an int or an enum.
local function describe(obj, td, depth)
    local report = { type = full_name(td), methods = {}, fields = {}, getters = {} }
    for _, m in ipairs(td:get_methods() or {}) do
        local params_ok, params = pcall(m.get_param_types, m)
        local count = params_ok and params and #params or -1
        local name = m:get_name()
        report.methods[#report.methods + 1] = string.format("%s %s/%d", full_name(m:get_return_type()), name, count)
        local ret = m:get_return_type()
        local parent = ret and ret:get_parent_type()
        local simple = BOOL_OR_INT[full_name(ret)] or (parent and full_name(parent) == "System.Enum")
        if obj and count == 0 and simple and (name:sub(1, 4) == "get_" or name:sub(1, 2) == "is") then
            local ok, value = pcall(m.call, m, obj)
            report.getters[name] = either(ok, plain(either(number(value) ~= nil, number(value), value)), "<error>")
        end
    end
    table.sort(report.methods)
    for _, f in ipairs(td:get_fields() or {}) do
        local type_name = full_name(f:get_type())
        report.fields[#report.fields + 1] = type_name .. " " .. f:get_name()
        -- One level deeper for quest-related members (the quest state getters may live there).
        if depth > 0 and obj and type_name:find("Quest", 1, true) and not f:is_static() then
            local ok, child = pcall(f.get_data, f, obj)
            if ok and type(child) == "userdata" then
                local child_td_ok, child_td = pcall(function() return child:get_type_definition() end)
                if child_td_ok and child_td then
                    report.children = report.children or {}
                    report.children[f:get_name()] = describe(child, child_td, depth - 1)
                end
            end
        end
    end
    return report
end

local function batch_a_lite()
    local report = { kind = "batch A-lite", started = os.date("%Y-%m-%d %H:%M:%S") }

    report.api = {
        fs_read = type(fs) == "table" and type(fs.read) == "function",
        fs_glob = type(fs) == "table" and type(fs.glob) == "function",
        fs_write = type(fs) == "table" and type(fs.write) == "function",
        json_load_string = type(json.load_string) == "function",
    }
    if report.api.fs_glob then
        local started = os.clock()
        local ok, matches = pcall(fs.glob, "^BulkSell[\\\\/].*")
        report.api.glob_seconds = os.clock() - started
        report.api.glob_bulksell_files = ok and type(matches) == "table" and #matches or "<error>"
        report.api.glob_sample = ok and type(matches) == "table" and matches[1] or "<none>"
    end
    coroutine.yield()

    local save, save_manager = current_save()
    local equip = field(save, "_Equip")
    local equip_td = sdk.find_type_definition("app.savedata.cEquipParam")
    local size_field = equip_td and equip_td:get_field("EQUIP_BOX_SIZE")
    local size_ok, box_size = false, nil
    if size_field then size_ok, box_size = pcall(size_field.get_data, size_field, nil) end
    report.box = {
        EQUIP_BOX_SIZE = either(size_ok, plain(number(box_size)), "<missing>"),
        getEmptyBoxNum = call0(equip, "getEmptyBoxNum()"),
        getEmptyBoxIndex = call0(equip, "getEmptyBoxIndex()"),
    }
    report.language = static_call("app.OptionUtil", "getTextLanguage()")
    report.saving = {
        get_IsSaveLoadFlowRunning = call0(save_manager, "get_IsSaveLoadFlowRunning()"),
        get_IsShowSaving = call0(save_manager, "get_IsShowSaving()"),
    }
    report.play_start = tostring(field(save, "PlayStartDateTime"))
    report.save_slot = number(field(save_manager, "CurrentUserDataIndex"))
    local gui_td = sdk.find_type_definition("app.GUIManager")
    local gui = sdk.get_managed_singleton("app.GUIManager")
    local has_result_flow = gui_td ~= nil and gui_td:get_method("isQuestResultFlowActive()") ~= nil
    report.gui = {
        isOpenFullScreenUI = call0(gui, "isOpenFullScreenUI()"),
        isQuestResultFlowActive = either(has_result_flow, call0(gui, "isQuestResultFlowActive()"), "<missing>"),
    }
    coroutine.yield()

    local mission_td = sdk.find_type_definition("app.MissionManager")
    if mission_td then
        report.mission_manager = describe(sdk.get_managed_singleton("app.MissionManager"), mission_td, 1)
    else
        report.mission_manager = "<type missing>"
    end
    coroutine.yield()

    -- Talismans, equipped and loadout indices, and the decoration box: field reads only.
    local box = field(equip, "_EquipBox")
    local n = number(select(2, pcall(function() return box:get_size() end))) or 0
    report.box.size = n
    report.categories = {}
    report.talisman_columns = { "index", "FreeVal0", "FreeVal1", "FreeVal4", "Category_Gender", "BowgunCustomizeId", "EquipmentAccessoryIdArray" }
    report.talismans = {}
    for i = 0, n - 1 do
        local w = box:get_element(i)
        local category = number(select(2, pcall(function() return w:call("get_Category") end)))
        local key = tostring(category)
        report.categories[key] = (report.categories[key] or 0) + 1
        if category == 2 then
            report.talismans[#report.talismans + 1] = {
                i, number(field(w, "FreeVal0")), number(field(w, "FreeVal1")), number(field(w, "FreeVal4")),
                number(field(w, "Category_Gender")), ints(field(w, "BowgunCustomizeId")), ints(field(w, "EquipmentAccessoryIdArray")),
            }
        end
        if i % YIELD_EVERY == YIELD_EVERY - 1 then coroutine.yield() end
    end
    report.equipped_index = ints(field(field(equip, "_EquipIndex"), "Index"))
    report.loadout_amulets = {}
    local loadouts = field(equip, "_EquipMySet")
    local loadout_count = number(select(2, pcall(function() return loadouts:get_size() end))) or 0
    for i = 0, loadout_count - 1 do
        local index = ints(field(field(field(loadouts:get_element(i), "_MysetParam"), "_EquipIndex"), "Index"))
        report.loadout_amulets[#report.loadout_amulets + 1] = type(index) == "table" and index[7] or "<none>"
    end
    report.accessories = {}
    local accessories = field(equip, "_AccessoryBox")
    local acc_count = number(select(2, pcall(function() return accessories:get_size() end))) or 0
    report.accessory_box_size = acc_count
    for i = 0, acc_count - 1 do
        local a = accessories:get_element(i)
        local id, num = number(field(a, "ID")), number(field(a, "Num"))
        if num and num > 0 then report.accessories[#report.accessories + 1] = { i, id, num } end
        if i % YIELD_EVERY == YIELD_EVERY - 1 then coroutine.yield() end
    end

    report.finished = os.date("%Y-%m-%d %H:%M:%S")
    write("batchA_lite", report)
end

-- Box index -> fingerprint of every entry, to check that sorting the in-game list
-- does not move anything.
local function box_map()
    local save = current_save()
    local box = field(field(save, "_Equip"), "_EquipBox")
    local n = number(select(2, pcall(function() return box:get_size() end))) or 0
    local map = {}
    for i = 0, n - 1 do
        local w = box:get_element(i)
        local packed = ints(field(w, "BowgunCustomizeId"))
        map[i + 1] = table.concat({
            tostring(number(field(w, "Category_Gender"))), tostring(number(field(w, "FreeVal0"))),
            tostring(number(field(w, "FreeVal1"))), type(packed) == "table" and table.concat(packed, ",") or packed,
        }, ":")
        if i % YIELD_EVERY == YIELD_EVERY - 1 then coroutine.yield() end
    end
    return map
end

local function sort_test_before()
    state.sort_before = box_map()
    state.status = string.format("sort test 1/2 done: %d entries recorded. Now sort the in-game Equipment Box once.", #state.sort_before)
end

local function sort_test_after()
    assert(state.sort_before, "press Sort test 1/2 first")
    local after = box_map()
    local diffs = {}
    for i = 1, math.max(#after, #state.sort_before) do
        if after[i] ~= state.sort_before[i] and #diffs < 20 then
            diffs[#diffs + 1] = { index = i - 1, before = state.sort_before[i] or "<none>", after = after[i] or "<none>" }
        end
    end
    local changed = 0
    for i = 1, math.max(#after, #state.sort_before) do
        if after[i] ~= state.sort_before[i] then changed = changed + 1 end
    end
    write("sort_compare", { entries = #after, changed = changed, sample = #diffs > 0 and diffs or "none" })
    state.sort_before = nil
end

local function start(name, fn)
    if state.job then return end
    state.job = coroutine.create(fn)
    state.job_name = name
    state.status = name .. " running..."
end

re.on_pre_application_entry("UpdateBehavior", function()
    local job = state.job
    if not job then return end
    if menu_open() then
        state.job = nil
        state.status = state.job_name .. " stopped: a game menu is open. Close it and press the button again."
        return
    end
    local started = os.clock()
    repeat
        local ok, err = coroutine.resume(job)
        if not ok then
            state.job = nil
            state.status = state.job_name .. " FAILED: " .. tostring(err)
            log.error("[BulkSellProbeLite] " .. state.status)
            return
        end
    until coroutine.status(job) == "dead" or os.clock() - started > FRAME_BUDGET
    if coroutine.status(job) == "dead" then
        state.job = nil
        if state.status == state.job_name .. " running..." then state.status = state.job_name .. " done" end
    end
end)

-- UI test panel: a table with a checkbox, a disabled row and tooltips, recording which
-- REFramework imgui bindings exist and work on this build.
local function binding(name) return type(imgui[name]) == "function" end

local function draw_ui_test()
    local rec = state.ui_record
    imgui.text("1) Tick the box in row 1.  2) Hover the grey row and the text below until a tooltip shows.  3) F12.  4) Close this window.")
    if not imgui.begin_table("BulkSellUiTestTable", 2, 64 | 1920) then
        rec.table_failed = true
        return
    end
    local ok, err = pcall(function()
        imgui.table_setup_column("Sell")
        imgui.table_setup_column("Row")
        imgui.table_headers_row()

        imgui.table_next_row()
        imgui.table_set_column_index(0)
        local changed, value = imgui.checkbox("##BulkSellUiTest1", state.ui_check)
        if changed then
            state.ui_check = value
            rec.checkbox_clicks = (rec.checkbox_clicks or 0) + 1
        end
        imgui.table_set_column_index(1)
        imgui.text("Row 1 (enabled)")

        imgui.table_next_row()
        imgui.table_set_column_index(0)
        local can_disable = rec.bindings.begin_disabled and rec.bindings.end_disabled
        if can_disable then imgui.begin_disabled(true) end
        local disabled_changed = imgui.checkbox("##BulkSellUiTest2", false)
        if can_disable then imgui.end_disabled() end
        if disabled_changed then rec.disabled_checkbox_clicked = true end
        if rec.bindings.is_item_hovered then
            local flag_ok, hovered = pcall(imgui.is_item_hovered, 1024)   -- ImGuiHoveredFlags_AllowWhenDisabled
            if flag_ok and hovered then rec.hovered_disabled = true end
            if not flag_ok then rec.hovered_flag_error = tostring(hovered) end
            if hovered and rec.bindings.set_tooltip then imgui.set_tooltip("Protected: example tooltip on a disabled row") end
        end
        imgui.table_set_column_index(1)
        imgui.text("Row 2 (disabled)")
    end)
    imgui.end_table()
    if not ok then rec.table_error = tostring(err) end

    imgui.text("Hover this text for a tooltip")
    if rec.bindings.is_item_hovered and imgui.is_item_hovered() then
        rec.hovered_text = true
        if rec.bindings.set_tooltip then imgui.set_tooltip("Tooltip on normal text") end
    end
end

local function finish_ui_test()
    state.ui_panel = false
    local ok, err = pcall(write, "ui_test", state.ui_record)
    state.status = ok and "UI test saved" or ("UI test FAILED: " .. tostring(err))
end

re.on_draw_ui(function()
    if imgui.tree_node("BulkSell Probe-lite (dev)") then
        imgui.text("Status: " .. state.status)
        if state.last_file then imgui.text("Last file: reframework/data/" .. state.last_file) end
        if not state.job then
            if imgui.button("Batch A-lite (read-only)") then start("Batch A-lite", batch_a_lite) end
            if imgui.button("Sort test 1/2") then start("Sort test 1/2", sort_test_before) end
            if imgui.button("Sort test 2/2") then start("Sort test 2/2", sort_test_after) end
            if not state.ui_panel and imgui.button("UI test panel") then
                state.ui_panel = true
                state.ui_record = { started = os.date("%Y-%m-%d %H:%M:%S"), bindings = {} }
                for _, name in ipairs({ "begin_disabled", "end_disabled", "set_tooltip", "is_item_hovered", "begin_table",
                    "table_set_column_index", "begin_child_window", "end_child_window", "collapsing_header",
                    "set_clipboard", "set_next_window_size", "push_id", "pop_id" }) do
                    state.ui_record.bindings[name] = binding(name)
                end
            end
        end
        imgui.tree_pop()
    end
    if state.ui_panel then
        local open = imgui.begin_window("BulkSell UI test###BulkSellUiTest", true, 0)
        local ok, err = pcall(draw_ui_test)
        imgui.end_window()
        if not ok then state.ui_record.panel_error = tostring(err) end
        if open == false then finish_ui_test() end
    end
end)
