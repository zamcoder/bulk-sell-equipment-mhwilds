-- Smoke test for Bulk Sell against a fake REFramework API and a fake Equipment Box.

local mock = require("mock_reframework")
local eq = mock.eq
local env = mock.install()
local new_type, add_field, add_method = mock.new_type, mock.add_field, mock.add_method
local new_object, new_array, boxed = mock.new_object, mock.new_array, mock.boxed_array

BULKSELL_TEST = {}
local LIST_CHANGED = "The list changed; review and press Sell again."

-- Fake save data ------------------------------------------------------------
local work_td = new_type("app.savedata.cEquipWork", { parent = "System.Object" })
for _, name in ipairs({ "Category_Gender", "FreeVal0", "FreeVal1", "FreeVal4" }) do add_field(work_td, name, "System.Int32") end
add_field(work_td, "BowgunCustomizeId", "System.Int16[]")
add_field(work_td, "EquipmentAccessoryIdArray", "System.Int16[]")
add_method(work_td, "get_Category", "System.Int32", {}, function(self) return self.values.category end)
add_method(work_td, "isFavorite", "System.Boolean", {}, function(self) return self.values.FreeVal4 ~= 0 end)
add_method(work_td, "init", "System.Void", {}, function(self)
    local v = self.values
    v.category, v.Category_Gender, v.FreeVal0, v.FreeVal1, v.FreeVal4 = -1, 141, 0, 0, 0
    v.BowgunCustomizeId = boxed("System.Int16", { -1, -1, -1, -1 })
end)

local function work(category, amulet_type, level, packed, decorations, flags)
    return new_object("app.savedata.cEquipWork", {
        category = category,
        Category_Gender = flags or 21,
        FreeVal0 = amulet_type,
        FreeVal1 = level,
        FreeVal4 = 0,
        BowgunCustomizeId = boxed("System.Int16", packed or { 0, 0, 0, 0 }),
        EquipmentAccessoryIdArray = boxed("System.Int16", decorations or { -1, -1, -1 }),
    })
end

local items = {
    work(2, 189, 1, nil, nil, 0x80),                         -- 0 unused box entry
    work(2, 189, 1, { 1001, 0, 0, 1003 }),                   -- 1 R5 skill 1 lv1, W1 (equipped)
    work(2, 189, 1, { 1001, 0, 0, 1003 }),                   -- 2 duplicate of 1
    work(2, 190, 1, { 3005, 0, 0, 2110 }),                   -- 3 R6 skill 5 lv3, A2 A1 A1 (RNG bonus)
    work(2, 189, 1, { 2005, 0, 0, 1000 }),                   -- 4 R5 skill 5 lv2, A1 (covered by 3)
    work(1, 0, 0),                                           -- 5 a weapon
    work(2, 50, 3),                                          -- 6 a crafted talisman
    work(2, 191, 1, { 7003, 0, 0, 1000 }, { 0, -1, -1 }),    -- 7 R7 with decoration id 0 attached
    work(2, 189, 1, { 1001, 0, 0, 0 }),                      -- 8 R5 in a loadout
    work(2, 189, 1, { 2009, 0, 0, 1000 }),                   -- 9 R5 skill 9 lv2, A1: the only Skill9
}
local box = new_array("app.savedata.cEquipWork", items)
local function at(index) return items[index + 1] end

new_type("app.savedata.cEquipIndex", { parent = "System.Object" })
new_type("app.savedata.cMysetBaseParam", { parent = "System.Object" })
new_type("app.savedata.cEquipMyset", { parent = "System.Object" })
local function equip_index(amulet_box)
    return new_object("app.savedata.cEquipIndex", { Index = boxed("System.Int32", { 10, 11, 12, 13, 14, 15, amulet_box, 16, -1, -1 }) })
end
local function loadout(amulet_box)
    return new_object("app.savedata.cEquipMyset", {
        _MysetParam = new_object("app.savedata.cMysetBaseParam", { _EquipIndex = equip_index(amulet_box) }),
    })
end

local calls = { remove_accessory = 0, update_myset = 0 }
local equip_td = new_type("app.savedata.cEquipParam", { parent = "System.Object" })
add_method(equip_td, "isEquipIndexInMyset", "System.Boolean", { "System.Int32" }, function(_, index) return index == 8 end)
add_method(equip_td, "removeAccessory", "System.Void", { "app.savedata.cEquipWork", "System.Int32", "System.Boolean" },
    function() calls.remove_accessory = calls.remove_accessory + 1 end)
add_method(equip_td, "updateEquipMyset", "System.Void", {}, function() calls.update_myset = calls.update_myset + 1 end)
local equip = new_object("app.savedata.cEquipParam", {
    _EquipBox = box,
    _EquipIndex = equip_index(1),
    _EquipMySet = new_array("app.savedata.cEquipMyset", { loadout(8), loadout(-1) }),
})

local money_gain = 1   -- multiplier applied by the fake addMoney; 0 simulates a zenny cap
local basic_td = new_type("app.savedata.cBasicParam", { parent = "System.Object" })
add_method(basic_td, "getMoney", "System.Int32", {}, function(self) return self.values.money end)
add_method(basic_td, "addMoney", "System.Void", { "System.Int32", "System.Boolean" },
    function(self, amount) self.values.money = self.values.money + amount * money_gain end)
local basic = new_object("app.savedata.cBasicParam", { money = 1000000 })

new_type("app.savedata.cUserSaveParam", { parent = "System.Object" })
local save = new_object("app.savedata.cUserSaveParam", { _Equip = equip, _BasicData = basic })

local saving = false
local manager_td = new_type("app.SaveDataManager", { parent = "System.Object" })
add_method(manager_td, "getCurrentUserSaveData", "app.savedata.cUserSaveParam", {}, function() return save end)
add_method(manager_td, "get_IsSaveLoadFlowRunning", "System.Boolean", {}, function() return saving end)
add_method(manager_td, "get_IsShowSaving", "System.Boolean", {}, function() return false end)
env.singletons["app.SaveDataManager"] = new_object("app.SaveDataManager", { CurrentUserDataIndex = 0 })

local full_screen = false
local gui_manager_td = new_type("app.GUIManager", { parent = "System.Object" })
add_method(gui_manager_td, "isOpenFullScreenUI", "System.Boolean", {}, function() return full_screen end)
env.singletons["app.GUIManager"] = new_object("app.GUIManager")

local equip_list_td = new_type("app.GUI080001", { parent = "System.Object" })
add_method(equip_list_td, "onOpen", "System.Void", {}, function() end)
add_method(equip_list_td, "onClose", "System.Void", {}, function() end)

new_type("app.HunterDef.Skill")
local message_td = new_type("app.MessageUtil", { parent = "System.Object" })
add_method(message_td, "getHunterSkillName", "System.Guid", { "app.HunterDef.Skill" }, function(_, id) return { skill = id } end, true)
add_method(message_td, "getText", "System.String", { "System.Guid", "System.Int32" }, function(_, guid) return "Skill" .. guid.skill end, true)

local prices = { [189] = 3000, [190] = 6000, [191] = 9000 }
new_type("app.user_data.AmuletData.cData", { parent = "System.Object" })
local amulet_util_td = new_type("app.AmuletUtil", { parent = "System.Object" })
add_method(amulet_util_td, "getAmuletData", "app.user_data.AmuletData.cData", { "app.savedata.cEquipWork" },
    function(_, w) return new_object("app.user_data.AmuletData.cData", { _Price = prices[w.values.FreeVal0] }) end, true)

-- The game's "selling rate" is the sale price itself (half the value). set_box_override
-- makes getEquipSet answer for another entry (the mod must fall back); price_override
-- makes the game's price disagree with the value table (the mod must refuse).
local set_box_override = { [4] = 99 }
local price_override = {}
new_type("app.EquipDef.EquipWorkInfo", { parent = "System.Object" })
add_method(mock.types["app.EquipDef.EquipWorkInfo"], "get_BoxIndex", "System.Int32", {}, function(self) return self.values.box end)
new_type("app.EquipDef.EquipSet", { parent = "System.Object" })
add_method(mock.types["app.EquipDef.EquipSet"], "get_WorkInfo", "app.EquipDef.EquipWorkInfo", {}, function(self) return self.values.info end)
local equip_util_td = new_type("app.EquipUtil", { parent = "System.Object" })
add_method(equip_util_td, "getEquipSet", "app.EquipDef.EquipSet", { "System.Int32" }, function(_, index)
    return new_object("app.EquipDef.EquipSet", { info = new_object("app.EquipDef.EquipWorkInfo", { box = set_box_override[index] or index }) })
end, true)
add_method(equip_util_td, "getEquipSellingRate", "System.Int32", { "app.EquipDef.EquipSet" }, function(_, set)
    local box_index = set.values.info.values.box
    if price_override[box_index] then return price_override[box_index] end
    local entry = items[box_index + 1]
    return entry and (prices[entry.values.FreeVal0] or 0) // 2 or 0
end, true)

-- RNG Charm Crafting sidecar (real format) giving box 3 a Set bonus.
local SIDECAR_A = "TalismanCrafting/special-bonuses-slot-0-a.json"
local SIDECAR_B = "TalismanCrafting/special-bonuses-slot-0-b.json"
env.files[SIDECAR_A] = {
    version = 2, revision = 0, profile = { slot = 0, play_start = "1" },
    entries = {
        _format = "box-map-v1",
        ["3"] = { box_index = 3, identity = { free0 = 190, free1 = 1, packed = { 3005, 0, 0, 2110 } }, kind = "set", pair = 1 },
    },
}
env.enable_fs()

-- Decoding ------------------------------------------------------------------
local game = require("BulkSell.game")
local charms, stats = game.read_talismans()
eq(stats.slots, 10, "box slots")
eq(stats.used, 9, "used slots")
eq(stats.amulets, 8, "amulets")
eq(stats.appraised, 7, "appraised talismans")
eq(stats.protected, 4, "protected talismans")
eq(stats.blocked, nil, "nothing blocks selling")
local by_key = {}
for _, charm in ipairs(charms) do by_key[charm.key] = charm end
eq(by_key[0], nil, "unused entry skipped")
eq(by_key[5], nil, "weapon skipped")
eq(by_key[6], nil, "crafted talisman skipped")
eq(#by_key[1].slots, 1, "W1 slot count")
eq(by_key[1].slots[1].kind, "W", "weapon slot first")
eq(#by_key[3].slots, 3, "three armor slots")
eq(by_key[3].slots[1].kind, "A", "armor slot")
eq(by_key[3].slots[1].level, 2, "armor slot level")
eq(by_key[3].skills[1].id, 5, "skill id")
eq(by_key[3].skills[1].level, 3, "skill level")
eq(#by_key[8].slots, 0, "no slots")
eq(by_key[1].protected, "equipped", "equipped protected")
eq(by_key[3].protected, "special bonus", "sidecar protected")
eq(by_key[7].protected, "decorations", "decoration id 0 counts as attached")
eq(by_key[8].protected, "loadout", "loadout protected")
eq(by_key[2].protected, nil, "duplicate unprotected")
eq(by_key[2].base_price, 3000, "base price by type")
eq(by_key[2].price, 1500, "sale price from the game")
eq(by_key[2].price_source, "game", "price source game")
eq(by_key[3].price, 3000, "game price for R6")
eq(by_key[4].price, 1500, "half the value when the game price is for another entry")
eq(by_key[4].price_source, "fallback", "price source fallback")
eq(by_key[3].fingerprint, "190:3005:0:0:2110", "fingerprint")
eq(game.skill_name(5), "Skill5", "skill name")
local logged_sidecar = false
for _, line in ipairs(env.logs) do
    if line:find("RCC sidecar: a ok %(1 entries%), b missing") then logged_sidecar = true end
end
assert(logged_sidecar, "sidecar status logged")

-- UI and game-thread jobs -------------------------------------------------------
dofile(PROJECT_ROOT .. "/src/reframework/autorun/BulkSell.lua")
local T = BULKSELL_TEST
assert(env.entries.UpdateBehavior, "game-thread runner registered")
local gui_hooks = {}
for _, hook in ipairs(env.hooks) do gui_hooks[hook.method.name] = hook end
assert(gui_hooks.onOpen and gui_hooks.onClose, "equipment list open/close tracked")

local function frames(n)
    for _ = 1, n or 50 do env.entries.UpdateBehavior() end
end

local function rescan()
    env.draw({ "Scan Equipment Box" })
    frames()
    env.draw()
end

env.draw({ "Show window##BulkSell" })
assert(env.has_text("Scan reads your talismans"), "window shown")
rescan()
assert(env.has_text("Sell 2, keep 5, for about 3,000 z%."), "summary after scan")
assert(env.has_text("Covered 1, duplicates 1, rarity rule 0, protected 4"), "reasons after scan")
assert(env.has_text("Sell: duplicate") and env.has_text("Sell: covered"), "sell rows listed")
assert(env.has_text("^1,500 z$"), "price column")

-- Nothing touches the game while the REFramework menu is closed.
env.drawing_ui = false
local before_calls = env.game_calls()
frames(20)
eq(env.game_calls(), before_calls, "no game calls while the menu is closed")
env.drawing_ui = true

-- Selling waits while a game menu or the equipment list is open, or while the game saves.
full_screen = true
frames(1)
env.draw()
assert(env.has_text("Close the game menu first"), "blocked by full-screen menu")
full_screen = false
gui_hooks.onOpen.post(nil)
frames(1)
env.draw()
assert(env.has_text("Close the equipment menu first"), "blocked by equipment list")
gui_hooks.onClose.post(nil)
saving = true
frames(1)
env.draw()
assert(env.has_text("Waiting for the game to finish saving"), "waits while the game saves")
saving = false
frames(1)
env.draw()

-- A confirmation is withdrawn when the rules change before "Yes, sell".
env.draw({ "Sell 2 talismans##BulkSellAll" })
env.draw()
assert(env.has_text("Sell 2 talismans for 3,000 z%? This cannot be undone"), "confirmation shown")
env.draw(nil, { ["Sell talismans that a kept talisman fully covers (and extra duplicates)"] = false })
env.draw()
assert(env.has_text(LIST_CHANGED), "notice after a rule change")
assert(not env.has_text("This cannot be undone"), "confirmation withdrawn")
frames()
env.draw()
assert(env.has_text("Sell 0, keep 7"), "new plan after the rule change")
eq(basic.values.money, 1000000, "nothing sold")
env.draw(nil, { ["Sell talismans that a kept talisman fully covers (and extra duplicates)"] = true })
frames()
env.draw()

-- ...and when the box is scanned again.
env.draw({ "Sell 2 talismans##BulkSellAll" })
rescan()
assert(env.has_text(LIST_CHANGED) and not env.has_text("This cannot be undone"), "rescan withdraws the confirmation")

-- confirm_sell refuses a confirmation made for another plan revision.
env.draw({ "Sell 2 talismans##BulkSellAll" })
T.state.scan.revision = T.state.scan.revision + 1
T.actions.confirm_sell()
eq(T.state.job, nil, "no sale started for a stale revision")
eq(T.state.notice, LIST_CHANGED, "stale revision notice")
rescan()

-- A key that is not a planned sale stops the run before anything is sold.
env.draw({ "Sell 2 talismans##BulkSellAll" })
T.state.confirm.keys = { 2, 9 }
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(2).values.category, 2, "valid key not sold when another key is invalid")
eq(at(9).values.category, 2, "kept talisman not sold")
eq(basic.values.money, 1000000, "no zenny change")
assert(env.has_text("Stopped: The sale list does not match the plan"), "mismatch reported")

-- Sell one talisman as a test.
env.draw({ "Sell just 1 (test)##BulkSellOne" })
env.draw()
assert(env.has_text("Sell 1 talisman %(R5  Skill1 1  W1%) for 1,500 z%?"), "single confirmation")
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(2).values.category, -1, "box 2 cleared")
eq(basic.values.money, 1001500, "zenny credited")
eq(calls.remove_accessory, 3, "decorations removed from every slot like the game does")
eq(calls.update_myset, 1, "loadouts updated after the sale")
assert(env.has_text("Sold 1 talismans for 1,500 z%."), "sale result")
local receipt_path, receipt
for path, data in pairs(env.files) do
    if path:find("^BulkSell/receipts/sold_") and data.sold == 1 then receipt_path, receipt = path, data end
end
assert(receipt, "receipt written")
eq(receipt.talismans[1].box, 2, "receipt box")
eq(receipt.talismans[1].price, 1500, "receipt price")
eq(receipt.talismans[1].price_source, "game", "receipt price source")
eq(receipt.skipped, "none", "receipt without skips")
eq(receipt.money_before, 1000000, "receipt money before")
eq(receipt.money_after, 1001500, "receipt money after")
assert(env.has_text("Receipt: reframework/data/" .. receipt_path), "receipt path shown")
assert(env.has_text("Sell 1, keep 5"), "rescanned after selling")

-- The rarity rule would sell the only Skill9: the plan and the confirmation say so.
env.draw(nil, { ["Also sell by rarity"] = true })
frames()
env.draw()
assert(env.has_text("Sell 2, keep 4"), "rarity rule sells unprotected R5")
assert(env.has_text("rarity rule 2"), "rule reason counted")
assert(env.has_text("lowers your best level of 1 skills"), "plan warns about a lost skill")
env.draw({ "Sell 2 talismans##BulkSellAll" })
env.draw()
assert(env.has_text("Removes your last Skill9 %(#9%)"), "red line in the confirmation")
env.draw({ "Cancel##BulkSellCancel" })

-- Kept skills exempt talismans from the rarity rule.
env.draw({ "Add kept skill##BulkSellKeepAdd" }, { ["Skill##BulkSellKeepSkill"] = 4 })
frames()
env.draw()
assert(env.has_text("Skill9 1%+"), "kept skill listed")
assert(env.has_text("Sell 1, keep 5"), "kept skill exempts the Skill9 talisman")
assert(not env.has_text("lowers your best level"), "no lost skill any more")
local saved = assert(env.files["BulkSell/config.json"], "settings saved")
eq(saved.rule_enabled, true, "saved rule")
eq(saved.keep_skills["9"], 1, "saved kept skill")
env.draw({ "Remove##BulkSellKeep9" })
frames()
env.draw()
assert(env.has_text("Sell 2, keep 4"), "kept skill removed")
env.draw(nil, { ["Also sell by rarity"] = false })
frames()
env.draw()
assert(env.has_text("Sell 1, keep 5"), "rule off again")

-- A sale price that disagrees with the value table is never paid.
set_box_override[4] = nil
price_override[4] = 9999
rescan()
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
assert(env.has_text("Stopped: The game's sale price does not match"), "price mismatch stops")
eq(at(4).values.category, 2, "mismatched talisman not sold")
eq(basic.values.money, 1001500, "no zenny change on a price mismatch")
price_override[4] = nil
rescan()

-- A talisman favorited after the scan is kept by the last check.
at(4).values.FreeVal4 = 1
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(4).values.category, 2, "favorite not sold")
assert(env.has_text("Sold 0 talismans for 0 z%."), "nothing sold")
assert(env.has_text("1 were kept after a last check"), "skip reported")
assert(env.has_text("Nothing to sell with the current rules"), "rescan protects the favorite")

-- A sale whose zenny does not arrive stops the run.
at(4).values.FreeVal4 = 0
rescan()
money_gain = 0
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
assert(env.has_text("Stopped: Zenny changed by 0 instead of 1500"), "zenny mismatch stops")

-- Confirmations can be cancelled.
money_gain = 1
at(4).values.category = 2
at(4).values.Category_Gender = 21
at(4).values.FreeVal0 = 189
at(4).values.FreeVal1 = 1
at(4).values.BowgunCustomizeId = boxed("System.Int16", { 2005, 0, 0, 1000 })
rescan()
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Cancel##BulkSellCancel" })
env.draw()
assert(not env.has_text("This cannot be undone"), "cancelled confirmation hidden")

-- A covered talisman is kept when the talisman that covers it changed after the scan.
at(3).values.BowgunCustomizeId = boxed("System.Int16", { 1009, 0, 0, 0 })
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(4).values.category, 2, "covered talisman kept when its keeper is gone")
assert(env.has_text("1 were kept after a last check"), "keeper check reported")
local last_receipt
for _, data in pairs(env.files) do
    if type(data) == "table" and data.sold == 0 and type(data.skipped) == "table" then last_receipt = data end
end
assert(last_receipt, "receipt with a skip")
eq(last_receipt.skipped[#last_receipt.skipped].reason, "the talisman kept instead is gone", "skip reason in receipt")
at(3).values.BowgunCustomizeId = boxed("System.Int16", { 3005, 0, 0, 2110 })

-- An unreadable RNG Charm Crafting sidecar turns selling off until it is fixed.
env.put_raw(SIDECAR_B, "garbage")
rescan()
assert(env.has_text("RNG Charm Crafting file TalismanCrafting/special%-bonuses%-slot%-0%-b%.json could not be read"),
    "corrupt sidecar blocks selling")
assert(not env.has_text("Sell 1 talismans"), "no sell button while blocked")
env.raw[SIDECAR_B] = nil
rescan()
assert(not env.has_text("could not be read"), "unblocked once the file is gone")

eq(env.load_file_calls, 0, "no json.load_file, so no '[JSON] Failed to load file' log lines")

local expected_errors = { "Zenny changed by 0", "sale price does not match", "does not match the plan" }
local unexpected = {}
for _, line in ipairs(env.logs) do
    if line:find("^error") then
        local known = false
        for _, text in ipairs(expected_errors) do
            if line:find(text, 1, true) then known = true end
        end
        if not known then unexpected[#unexpected + 1] = line end
    end
end
eq(#unexpected, 0, "unexpected error logs: " .. table.concat(unexpected, " | "))
print("bulk sell smoke test passed")
