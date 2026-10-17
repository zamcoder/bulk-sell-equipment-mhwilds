-- Smoke tests for the dev scripts used in test sessions: probe-lite (session 1a).

local mock = require("mock_reframework")
local eq = mock.eq
local env = mock.install()
local new_type, add_field, add_method = mock.new_type, mock.add_field, mock.add_method
local new_object, new_array, boxed = mock.new_object, mock.new_array, mock.boxed_array

-- Fake game -------------------------------------------------------------------
local work_td = new_type("app.savedata.cEquipWork", { parent = "System.Object" })
add_method(work_td, "get_Category", "System.Int32", {}, function(self) return self.values.category end)
local function work(category, values)
    values = values or {}
    values.category = category
    values.Category_Gender = values.Category_Gender or 21
    values.BowgunCustomizeId = values.BowgunCustomizeId or boxed("System.Int16", { 0, 0, 0, 0 })
    values.EquipmentAccessoryIdArray = values.EquipmentAccessoryIdArray or boxed("System.Int16", { -1, -1, -1 })
    return new_object("app.savedata.cEquipWork", values)
end
local items = {
    work(2, { FreeVal0 = 189, FreeVal1 = 1, FreeVal4 = 0, BowgunCustomizeId = boxed("System.Int16", { 1001, 0, 0, 1003 }) }),
    work(1, { FreeVal0 = 3, FreeVal1 = 5 }),
    work(-1, { Category_Gender = 141 }),
}
local box = new_array("app.savedata.cEquipWork", items)

new_type("app.savedata.cEquipIndex", { parent = "System.Object" })
new_type("app.savedata.cMysetBaseParam", { parent = "System.Object" })
new_type("app.savedata.cEquipMyset", { parent = "System.Object" })
new_type("app.savedata.cAccessoryWork", { parent = "System.Object" })
local function equip_index(amulet)
    return new_object("app.savedata.cEquipIndex", { Index = boxed("System.Int32", { 1, 2, 3, 4, 5, 6, amulet, 7, -1, -1 }) })
end
local equip_td = new_type("app.savedata.cEquipParam", { parent = "System.Object" })
add_field(equip_td, "EQUIP_BOX_SIZE", "System.UInt32", true, 2400)
add_method(equip_td, "getEmptyBoxNum", "System.Int32", {}, function() return 1 end)
add_method(equip_td, "getEmptyBoxIndex", "System.Int32", {}, function() return 2 end)
local equip = new_object("app.savedata.cEquipParam", {
    _EquipBox = box,
    _EquipIndex = equip_index(0),
    _EquipMySet = new_array("app.savedata.cEquipMyset", {
        new_object("app.savedata.cEquipMyset", { _MysetParam = new_object("app.savedata.cMysetBaseParam", { _EquipIndex = equip_index(5) }) }),
    }),
    _AccessoryBox = new_array("app.savedata.cAccessoryWork", {
        new_object("app.savedata.cAccessoryWork", { ID = 0, Num = 22 }),
        new_object("app.savedata.cAccessoryWork", { ID = -1, Num = 0 }),
    }),
})

new_type("app.savedata.cUserSaveParam", { parent = "System.Object" })
local save = new_object("app.savedata.cUserSaveParam", { _Equip = equip, PlayStartDateTime = 123456 })

local manager_td = new_type("app.SaveDataManager", { parent = "System.Object" })
add_method(manager_td, "getCurrentUserSaveData", "app.savedata.cUserSaveParam", {}, function() return save end)
add_method(manager_td, "get_IsSaveLoadFlowRunning", "System.Boolean", {}, function() return false end)
add_method(manager_td, "get_IsShowSaving", "System.Boolean", {}, function() return false end)
env.singletons["app.SaveDataManager"] = new_object("app.SaveDataManager", { CurrentUserDataIndex = 0 })

local full_screen = false
local gui_td = new_type("app.GUIManager", { parent = "System.Object" })
add_method(gui_td, "isOpenFullScreenUI", "System.Boolean", {}, function() return full_screen end)
add_method(gui_td, "isQuestResultFlowActive", "System.Boolean", {}, function() return false end)
env.singletons["app.GUIManager"] = new_object("app.GUIManager")

local option_td = new_type("app.OptionUtil", { parent = "System.Object" })
add_method(option_td, "getTextLanguage", "System.Int32", {}, function() return 1 end, true)

local quest_td = new_type("app.cQuestDirector", { parent = "System.Object" })
add_method(quest_td, "get_IsPlayingQuest", "System.Boolean", {}, function() return false end)
local mission_td = new_type("app.MissionManager", { parent = "System.Object" })
add_field(mission_td, "_QuestDirector", "app.cQuestDirector")
add_method(mission_td, "get_IsActiveQuest", "System.Boolean", {}, function() return false end)
add_method(mission_td, "startQuest", "System.Void", { "System.Int32" }, function() error("must never be called") end)
env.singletons["app.MissionManager"] = new_object("app.MissionManager", { _QuestDirector = new_object("app.cQuestDirector") })

env.enable_fs()

local function frames(n)
    for _ = 1, n or 50 do
        for _, entry in pairs(env.entries) do entry() end
    end
end

local function written(prefix)
    for i = #env.written, 1, -1 do
        if env.written[i].path:find(prefix, 1, true) then return env.written[i].data end
    end
end

-- Probe-lite --------------------------------------------------------------------
dofile(PROJECT_ROOT .. "/dev/probe-lite/reframework/autorun/BulkSellProbeLite.lua")
local probe_ui = env.callbacks.draw_ui

local function probe_draw(pressed, inputs)
    for _, label in ipairs(pressed or {}) do env.pressed[label] = true end
    for label, value in pairs(inputs or {}) do env.inputs[label] = value end
    env.texts = {}
    probe_ui()
    for label in pairs(env.pressed) do error("button not drawn: " .. label, 2) end
end

probe_draw({ "Batch A-lite (read-only)" })
frames()
local batch = assert(written("BulkSellProbe/batchA_lite_"), "batch written")
eq(batch.api.fs_read, true, "fs.read seen")
eq(batch.api.json_load_string, true, "json.load_string seen")
eq(batch.box.EQUIP_BOX_SIZE, 2400, "static box size")
eq(batch.box.getEmptyBoxNum, 1, "empty box count")
eq(batch.language, 1, "text language")
eq(batch.saving.get_IsSaveLoadFlowRunning, false, "save flow getter value kept as false")
eq(batch.gui.isQuestResultFlowActive, false, "quest result getter")
eq(batch.mission_manager.getters.get_IsActiveQuest, false, "mission manager getter")
eq(batch.mission_manager.children._QuestDirector.getters.get_IsPlayingQuest, false, "quest director getter")
eq(batch.play_start, "123456", "play start")
eq(batch.save_slot, 0, "save slot")
eq(#batch.talismans, 1, "talisman rows")
eq(batch.talismans[1][6][4], 1003, "packed values")
eq(batch.equipped_index[7], 0, "equipped amulet")
eq(batch.loadout_amulets[1], 5, "loadout amulet")
eq(#batch.accessories, 1, "owned decorations only")
eq(batch.accessories[1][3], 22, "decoration count")

full_screen = true
probe_draw({ "Batch A-lite (read-only)" })
frames(2)
probe_draw()
assert(env.has_text("stopped: a game menu is open"), "batch stops when a menu opens")
full_screen = false

probe_draw({ "Sort test 1/2" })
frames()
probe_draw()
assert(env.has_text("sort test 1/2 done: 3 entries"), "sort test recorded")
items[1].values.FreeVal1 = 2
probe_draw({ "Sort test 2/2" })
frames()
local sort = assert(written("BulkSellProbe/sort_compare_"), "sort compare written")
eq(sort.changed, 1, "one entry changed")
eq(sort.sample[1].index, 0, "changed index")
items[1].values.FreeVal1 = 1

probe_draw({ "UI test panel" })
probe_draw(nil, { ["##BulkSellUiTest1"] = true })
env.close_window = "BulkSell UI test###BulkSellUiTest"
probe_draw()
local ui_test = assert(written("BulkSellProbe/ui_test_"), "ui test written")
eq(ui_test.checkbox_clicks, 1, "checkbox click recorded")
eq(ui_test.bindings.begin_disabled, true, "binding check recorded")

print("dev script tests passed")
