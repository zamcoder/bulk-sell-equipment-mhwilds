-- Smoke test for dev/BulkSellProbe.lua against a fake REFramework API.

local mock = require("mock_reframework")
local eq = mock.eq
local env = mock.install()
local new_type, add_field, add_method = mock.new_type, mock.add_field, mock.add_method
local new_object, new_array, boxed = mock.new_object, mock.new_array, mock.boxed_array

-- Fake type system ---------------------------------------------------------
local work_td = new_type("app.savedata.cEquipWork", { parent = "System.Object" })
add_field(work_td, "Category", "System.Int32")
add_field(work_td, "FreeVal0", "System.Int32")
add_field(work_td, "FreeVal1", "System.UInt32")
add_field(work_td, "BowgunCustomizeId", "System.Int32[]")
add_method(work_td, "get_Category", "System.Int32", {}, function(self) return self.values.Category end)
add_method(work_td, "isLock", "System.Boolean", {}, function() return false end)
local clear_calls = 0
add_method(work_td, "clear", "System.Void", {}, function() clear_calls = clear_calls + 1 end)

local index_td = new_type("app.savedata.cEquipIndex", { parent = "System.Object" })
add_field(index_td, "Index", "System.Int32[]")
local myset_param_td = new_type("app.savedata.cMysetBaseParam", { parent = "System.Object" })
add_field(myset_param_td, "IsEmpty", "System.Int32")
add_field(myset_param_td, "MysetName", "System.String")
add_field(myset_param_td, "_EquipIndex", "app.savedata.cEquipIndex")
local myset_td = new_type("app.savedata.cEquipMyset", { parent = "System.Object" })
add_field(myset_td, "_MysetParam", "app.savedata.cMysetBaseParam")

local function equip_index(values)
    return new_object("app.savedata.cEquipIndex", { Index = new_array("System.Int32", values) })
end

local function myset(name_text, empty, values)
    return new_object("app.savedata.cEquipMyset", {
        _MysetParam = new_object("app.savedata.cMysetBaseParam", {
            IsEmpty = empty, MysetName = mock.string(name_text), _EquipIndex = equip_index(values),
        }),
    })
end

local bitset_td = new_type("ace.Bitset", { parent = "System.Object" })
add_field(bitset_td, "_Value", "System.UInt32[]")

local equip_td = new_type("app.savedata.cEquipParam", { parent = "System.Object" })
add_field(equip_td, "_EquipBox", "app.savedata.cEquipWork[]")
add_field(equip_td, "_EquipIndex", "app.savedata.cEquipIndex")
add_field(equip_td, "_EquipMySet", "app.savedata.cEquipMyset[]")
add_field(equip_td, "_OuterArmorFlags", "ace.Bitset")
local sell_method = add_method(equip_td, "sellEquip", "System.Boolean", { "System.Int32" }, function() return true end)
add_method(equip_td, "get_EquipBox", "app.savedata.cEquipWork[]", {}, function(self) return self.values._EquipBox end)

local basic_td = new_type("app.savedata.cBasicParam", { parent = "System.Object" })
add_field(basic_td, "_Money", "System.Int32")
add_method(basic_td, "addMoney", "System.Void", { "System.Int32" }, function(self, n) self.values._Money = self.values._Money + n end)
add_method(basic_td, "getMoney", "System.Int32", {}, function(self) return self.values._Money end)

local save_td = new_type("app.savedata.cUserSaveParam", { parent = "System.Object" })
add_field(save_td, "_Equip", "app.savedata.cEquipParam")
add_field(save_td, "_BasicData", "app.savedata.cBasicParam")
add_field(save_td, "_Name", "System.String")

local judge_td = new_type("app.AmuletJudgeUtil.JudgeResultData", { parent = "System.Object" })
add_field(judge_td, "AmuletType", "System.Int32")
add_field(judge_td, "Skills", "System.Int32[]")
local judge_util_td = new_type("app.AmuletJudgeUtil", { parent = "System.Object" })
add_method(judge_util_td, "convertEquipWorkToJudgeResult", "app.AmuletJudgeUtil.JudgeResultData",
    { "app.savedata.cEquipWork" }, function(_, work)
        return new_object("app.AmuletJudgeUtil.JudgeResultData", { AmuletType = work.values.FreeVal0, Skills = boxed("System.Int32", { 7, 8, 9 }) })
    end, true)
local impure_calls = 0
add_method(judge_util_td, "convertAndSave", "System.Boolean", { "app.savedata.cEquipWork" },
    function() impure_calls = impure_calls + 1 return true end, true)

local amulet_util_td = new_type("app.AmuletUtil", { parent = "System.Object" })
local amulet_data_td = new_type("app.user_data.AmuletData.cData", { parent = "System.Object" })
add_field(amulet_data_td, "_Price", "System.Int32")
add_method(amulet_util_td, "getAmuletData", "app.user_data.AmuletData.cData", { "app.savedata.cEquipWork" },
    function() return new_object("app.user_data.AmuletData.cData", { _Price = 3000 }) end, true)

local equip_box = new_array("app.savedata.cEquipWork", {
    new_object("app.savedata.cEquipWork", { Category = 2, FreeVal0 = 11, FreeVal1 = 4096, BowgunCustomizeId = boxed("System.Int32", { 1, 2, 3, 4 }) }),
    new_object("app.savedata.cEquipWork", { Category = 0, FreeVal0 = 3, FreeVal1 = 0, BowgunCustomizeId = boxed("System.Int32", { 0, 0, 0, 0 }) }),
    new_object("app.savedata.cEquipWork", { Category = 2, FreeVal0 = 12, FreeVal1 = 8192, BowgunCustomizeId = boxed("System.Int32", { 5, 6, 7, 8 }) }),
})
local equip = new_object("app.savedata.cEquipParam", {
    _EquipBox = equip_box,
    _EquipIndex = equip_index({ 10, 11, 12, 13, 14, 15, 0, 16, -1, -1 }),
    _EquipMySet = new_array("app.savedata.cEquipMyset", {
        myset("Set A", 0, { 10, 11, 12, 13, 14, 15, 2, 16, -1, -1 }),
        myset("", 1, { -1, -1, -1, -1, -1, -1, -1, -1, -1, -1 }),
    }),
    _OuterArmorFlags = new_object("ace.Bitset", { _Value = new_array("System.UInt32", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }) }),
})
local basic = new_object("app.savedata.cBasicParam", { _Money = 24596095 })
local save = new_object("app.savedata.cUserSaveParam", { _Equip = equip, _BasicData = basic, _Name = mock.string("Hunter") })

local manager_td = new_type("app.SaveDataManager", { parent = "System.Object" })
add_field(manager_td, "CurrentUserDataIndex", "System.Int32")
add_method(manager_td, "getCurrentUserSaveData", "app.savedata.cUserSaveParam", {}, function() return save end)
add_method(manager_td, "requestSave", "System.Void", {}, function() end)
add_method(manager_td, "update", "System.Void", {}, function() end)
env.singletons["app.SaveDataManager"] = new_object("app.SaveDataManager", { CurrentUserDataIndex = 0 })

local util_td = new_type("app.EquipUtil", { parent = "System.Object" })
add_method(util_td, "getSellPrice", "System.Int32", { "app.savedata.cEquipWork" }, function() return 100 end, true)
add_method(util_td, "update", "System.Void", {}, function() end, true)
local info_td = new_type("app.EquipDef.EquipWorkInfo", { parent = "System.Object" })
add_method(info_td, "get_BoxIndex", "System.Int32", {}, function(self) return self.values.box end)
local set_td = new_type("app.EquipDef.EquipSet", { parent = "System.Object" })
add_method(set_td, "get_WorkInfo", "app.EquipDef.EquipWorkInfo", {}, function(self) return self.values.info end)
add_method(util_td, "getEquipSet", "app.EquipDef.EquipSet", { "System.Int32" }, function(_, i)
    return new_object("app.EquipDef.EquipSet", { info = new_object("app.EquipDef.EquipWorkInfo", { box = i }) })
end, true)
add_method(util_td, "getEquipSellingRate", "System.Int32", { "app.EquipDef.EquipSet" },
    function(_, set) return set.values.info.values.box == 2 and 8000 or 10000 end, true)
add_method(util_td, "getEquipSellingRateAll", "System.Int32", { "app.EquipDef.EquipSet" }, function() return 10000 end, true)

local gui_td = new_type("app.GUI080200", { parent = "System.Object" })
add_method(gui_td, "onSellDecide", "System.Void", {}, function() end)
add_method(gui_td, "lateUpdate", "System.Void", {}, function() end)
local melding_td = new_type("app.GUI090700", { parent = "System.Object" })
add_method(melding_td, "startExecute", "System.Void", {}, function() end)
local equip_list_td = new_type("app.GUI080001", { parent = "System.Object" })
add_method(equip_list_td, "callbackDecide", "System.Void", {}, function() end)
add_method(equip_list_td, "guiUpdate", "System.Void", {}, function() end)
add_method(equip_list_td, "get_Context", "System.Object", {}, function() end)

-- Exercise the probe --------------------------------------------------------
dofile(PROJECT_ROOT .. "/dev/reframework/autorun/BulkSellProbe.lua")
eq(#env.hooks, 0, "no hooks before the button")

env.draw(nil, { ["Zenny shown in game (optional)"] = "24596095" })

env.draw({ "1. Snapshot save data" })
local snapshot = assert(env.written[1], "snapshot written").data
eq(snapshot.equip_field, "_Equip", "equip field")
local box = snapshot.boxes[1]
eq(box.field, "_EquipBox", "box field")
eq(#box.rows, 3, "box rows")
eq(box.columns[1], "index", "first column")
eq(box.columns[2], "get_Category()", "second column")
eq(box.categories["2"], 2, "amulet count")
eq(box.rows[3][1], 2, "row index")
eq(box.rows[3][2], 2, "row category")
local packed_column
for i, column in ipairs(box.columns) do if column == "BowgunCustomizeId" then packed_column = i end end
eq(box.rows[1][packed_column][4], 4, "boxed int array expanded")

eq(#snapshot.amulet_samples, 2, "amulet samples")
local sample = snapshot.amulet_samples[2]
eq(sample.index, 2, "sample box index")
eq(sample.getters["get_Category()"], 2, "getter called")
eq(sample.getters["isLock()"], false, "is* getter called")
local decoded = sample.decoders["app.AmuletJudgeUtil::convertEquipWorkToJudgeResult(app.savedata.cEquipWork)"]
eq(decoded.type, "app.AmuletJudgeUtil.JudgeResultData", "decoder result reflected")
eq(decoded.fields[1].value, 12, "decoder field value")
eq(sample.decoders["app.AmuletUtil::getAmuletData(app.savedata.cEquipWork)"].fields[1].value, 3000, "amulet data decoder")
eq(impure_calls, 0, "impure method never called")
eq(clear_calls, 0, "mutating method never called")

eq(snapshot.equipped_index[7], 0, "equipped amulet box index")
eq(#snapshot.loadouts, 2, "loadouts")
eq(snapshot.loadouts[1].name, "Set A", "loadout name")
eq(snapshot.loadouts[1].index[7], 2, "loadout amulet box index")
eq(snapshot.loadouts[2].empty, 1, "empty loadout flag")
eq(snapshot.money_api, 24596095, "money via getMoney()")
eq(#snapshot.equip_bitsets._OuterArmorFlags._Value, 10, "bitset fully dumped")
eq(snapshot.equip_bitsets._OuterArmorFlags._Value[10], 10, "bitset value")

local money_paths = {}
for _, hit in ipairs(snapshot.money) do money_paths[hit.path] = hit end
assert(money_paths["save._BasicData._Money"], "money field found by name")

env.draw({ "2. Dump methods + scan GUI types" })
local methods = assert(env.written[2], "methods written").data
assert(#methods.seeds["app.savedata.cEquipParam"] >= 2, "equip methods listed")
assert(methods.gui_methods["app.GUI080200"], "gui sell method found")
eq(methods.gui_methods["app.GUI080200"][1], "System.Void onSellDecide()", "gui method signature")
eq(methods.gui_methods["app.GUI090700"], nil, "gui without keyword methods omitted")

env.draw({ "3. Install trace hooks (until Reset Scripts)" })
assert(#env.hooks > 0, "hooks installed")
local hooked = {}
for _, hook in ipairs(env.hooks) do
    local method_name = hook.method.name
    hooked[method_name] = true
    assert(method_name:sub(1, 4) ~= "get_", "property getter hooked: " .. method_name)
    assert(method_name ~= "update" and method_name ~= "lateUpdate", "per-frame method hooked: " .. method_name)
end
assert(hooked.onSellDecide, "gui sell method hooked")
assert(hooked.sellEquip and hooked.addMoney and hooked.requestSave, "save methods hooked")
eq(hooked.startExecute, nil, "gui without sell methods not hooked")
assert(hooked.callbackDecide, "GUI080001 method hooked")
eq(hooked.guiUpdate, nil, "GUI080001 per-frame method skipped")
assert(hooked.getMoney, "non-property getters of full-trace types are traced")

env.draw({ "4. Start trace" })
for _, hook in ipairs(env.hooks) do
    if hook.method == sell_method then
        hook.pre({ "ctx", equip, 5 })
        eq(hook.post(1), 1, "post returns retval")
    end
end
env.draw({ "5. Stop trace and save" })
local trace = assert(env.written[3], "trace written").data
eq(#trace.trace, 1, "one call recorded")
eq(trace.trace[1].method, "app.savedata.cEquipParam::sellEquip(System.Int32)", "traced method")
eq(trace.trace[1].args[1], 5, "decoded int arg")
eq(trace.trace[1].ret, true, "decoded bool return")
eq(trace.trace[1].this, "<app.savedata.cEquipParam>", "this object")

env.draw({ "6. Dump selling rates" })
local rates = assert(env.written[4], "rates written").data
eq(#rates.rows, 2, "one row per amulet")
eq(rates.rows[2][1], 2, "rate row box index")
eq(rates.rows[2][4][1], 5, "packed values expanded")
eq(rates.rows[2][5], 2, "equip set box index")
eq(rates.rows[2][6], 8000, "selling rate")
eq(rates.rows[2][7], 10000, "selling rate all")

print("probe smoke test passed")
