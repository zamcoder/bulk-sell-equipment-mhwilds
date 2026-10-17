-- Smoke test for Bulk Sell against a fake REFramework API and a fake Equipment Box.

local mock = require("mock_reframework")
local eq = mock.eq
local env = mock.install()
env.guard_draw = true   -- the UI must never call the game
local new_type, add_field, add_method = mock.new_type, mock.add_field, mock.add_method
local new_object, new_array, boxed = mock.new_object, mock.new_array, mock.boxed_array

BULKSELL_TEST = {}
local LIST_CHANGED = "The list changed; review and press Sell again."

-- On a failed check, show what the last frame drew.
local real_assert = assert
local function assert(condition, message, ...)
    if not condition then print("---- last frame:\n" .. table.concat(env.texts, "\n")) end
    return real_assert(condition, message, ...)
end

-- Fake save data ------------------------------------------------------------
local work_td = new_type("app.savedata.cEquipWork", { parent = "System.Object" })
for _, name in ipairs({ "Category_Gender", "FreeVal0", "FreeVal1", "FreeVal4" }) do add_field(work_td, name, "System.Int32") end
add_field(work_td, "BowgunCustomizeId", "System.Int16[]")
add_field(work_td, "EquipmentAccessoryIdArray", "System.Int16[]")
add_method(work_td, "get_Category", "System.Int32", {}, function(self) return self.values.category end)
add_method(work_td, "isFavorite", "System.Boolean", {}, function(self) return self.values.FreeVal4 ~= 0 end)
local favorite_calls, favorite_works = 0, true   -- false: the star does not change (the job must stop)
add_method(work_td, "changeFavorite", "System.Void", { "System.Boolean" }, function(self, want)
    favorite_calls = favorite_calls + 1
    if favorite_works then self.values.FreeVal4 = want and 1 or 0 end
end)
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
    work(2, 189, 1, { 1001, 0, 0, 1003 }),                   -- 1 R5 Skill1 1, W1 (equipped)
    work(2, 189, 1, { 1001, 0, 0, 1003 }),                   -- 2 duplicate of 1
    work(2, 190, 1, { 3005, 0, 0, 2110 }),                   -- 3 R6 Skill5 3, A2 A1 A1 (RNG bonus)
    work(2, 189, 1, { 2005, 0, 0, 1000 }),                   -- 4 R5 Skill5 2, A1 (covered by 3)
    work(1, 0, 0),                                           -- 5 a weapon
    work(2, 50, 3),                                          -- 6 a crafted talisman
    work(2, 191, 1, { 3007, 0, 0, 1000 }, { 0, -1, -1 }),    -- 7 R7 Skill7 3, A1, decoration attached
    work(2, 189, 1, { 1001, 0, 0, 0 }),                      -- 8 R5 Skill1 1 in a loadout
    work(2, 189, 1, { 2009, 0, 0, 1000 }),                   -- 9 R5 Skill9 2, A1: the only Skill9 2
    work(2, 190, 1, { 1009, 1011, 0, 0 }),                   -- 10 R6 Skill9 1, Skill11 1: unique
    work(2, 192, 1, { 3011, 0, 0, 0 }),                      -- 11 R8 Skill11 3: the best Skill11
    work(2, 191, 1, { 1007, 1011, 0, 0 }),                   -- 12 R7 Skill7 1, Skill11 1: unique
    work(2, 190, 1, { 1009, 1007, 0, 0 }),                   -- 13 R6 Skill9 1, Skill7 1: unique
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
add_method(equip_td, "getEmptyBoxNum", "System.Int32", {}, function()
    local n = 0
    for _, w in ipairs(items) do if (w.values.Category_Gender & 0x80) ~= 0 then n = n + 1 end end
    return n
end)
local equip = new_object("app.savedata.cEquipParam", {
    _EquipBox = box,
    _EquipIndex = equip_index(1),
    _EquipMySet = new_array("app.savedata.cEquipMyset", { loadout(8), loadout(-1) }),
})

local money_gain = 1   -- multiplier applied by the fake addMoney; 0 simulates a zenny cap
local after_money      -- optional function run after every addMoney
local basic_td = new_type("app.savedata.cBasicParam", { parent = "System.Object" })
add_method(basic_td, "getMoney", "System.Int32", {}, function(self) return self.values.money end)
add_method(basic_td, "addMoney", "System.Void", { "System.Int32", "System.Boolean" }, function(self, amount)
    self.values.money = self.values.money + amount * money_gain
    if after_money then after_money() end
end)
local basic = new_object("app.savedata.cBasicParam", { money = 1000000 })

new_type("app.savedata.cUserSaveParam", { parent = "System.Object" })
local save = new_object("app.savedata.cUserSaveParam", { _Equip = equip, _BasicData = basic, PlayStartDateTime = 638763618528919137 })

local saving = false
local manager_td = new_type("app.SaveDataManager", { parent = "System.Object" })
add_method(manager_td, "getCurrentUserSaveData", "app.savedata.cUserSaveParam", {}, function() return save end)
add_method(manager_td, "get_IsSaveLoadFlowRunning", "System.Boolean", {}, function() return saving end)
add_method(manager_td, "get_IsShowSaving", "System.Boolean", {}, function() return false end)
local save_manager = new_object("app.SaveDataManager", { CurrentUserDataIndex = 0 })
env.singletons["app.SaveDataManager"] = save_manager

local full_screen = false
local gui_manager_td = new_type("app.GUIManager", { parent = "System.Object" })
add_method(gui_manager_td, "isOpenFullScreenUI", "System.Boolean", {}, function() return full_screen end)
local result_flow, in_quest = false, false
add_method(gui_manager_td, "isQuestResultFlowActive", "System.Boolean", {}, function() return result_flow end)
local mission_td = new_type("app.MissionManager", { parent = "System.Object" })
add_method(mission_td, "get_IsActiveQuest", "System.Boolean", {}, function() return in_quest end)
add_method(mission_td, "get_IsPlayingQuest", "System.Boolean", {}, function() return in_quest end)
add_method(mission_td, "get_IsQuestResult", "System.Boolean", {}, function() return false end)
env.singletons["app.MissionManager"] = new_object("app.MissionManager")
env.singletons["app.GUIManager"] = new_object("app.GUIManager")

local equip_list_td = new_type("app.GUI080001", { parent = "System.Object" })
add_method(equip_list_td, "onOpen", "System.Void", {}, function() end)
add_method(equip_list_td, "onClose", "System.Void", {}, function() end)

new_type("app.HunterDef.Skill")
local message_td = new_type("app.MessageUtil", { parent = "System.Object" })
add_method(message_td, "getHunterSkillName", "System.Guid", { "app.HunterDef.Skill" }, function(_, id) return { skill = id } end, true)
add_method(message_td, "getText", "System.String", { "System.Guid", "System.Int32" }, function(_, guid) return "Skill" .. guid.skill end, true)
-- Names in another language: Japanese (0) works, every other language gives nothing.
new_type("via.Language")
local gui_message_td = new_type("via.gui.message", { parent = "System.Object" })
add_method(gui_message_td, "get", "System.String", { "System.Guid", "via.Language" }, function(_, guid, language)
    if language == 0 then return "JA-Skill" .. guid.skill end
    return ""
end, true)

local prices = { [189] = 3000, [190] = 6000, [191] = 9000, [192] = 16000 }
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
-- The player's version 1 settings: rarity rule up to R5, covered sales on.
local V1_CONFIG = { version = 1, window_open = false, sell_dominated = true, rule_enabled = true, rule_max_rarity = 5,
    keep_skills = { _format = "skill-id-to-min-level" } }
env.files["BulkSell/config.json"] = V1_CONFIG
env.enable_fs()
env.use_fake_clock()

local function set_packed(index, packed) at(index).values.BowgunCustomizeId = boxed("System.Int16", packed) end

-- Puts the R5 Skill5 2 talisman (covered by box 3) back into box 4 after a test sold it.
local function restore_box4()
    local v = at(4).values
    v.category, v.Category_Gender, v.FreeVal0, v.FreeVal1, v.FreeVal4 = 2, 21, 189, 1, 0
    set_packed(4, { 2005, 0, 0, 1000 })
end

-- Decoding ------------------------------------------------------------------
local game = require("BulkSell.game")
local charms, stats = game.read_talismans()
eq(stats.slots, 14, "box slots")
eq(stats.used, 13, "used slots")
eq(stats.amulets, 12, "amulets")
eq(stats.appraised, 11, "appraised talismans")
eq(stats.protected, 4, "protected talismans")
eq(stats.blocked, nil, "nothing blocks selling")
eq(stats.save_slot, 0, "save slot")
eq(stats.play_start, "638763618528919137", "play start")
eq(stats.categories[2], 12, "amulets by category")
eq(stats.categories[1], 1, "weapons by category")
eq(stats.empty_reported, 1, "getEmptyBoxNum")
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

-- The draw guard really catches game calls made while drawing.
mock.in_draw = true
local guard_ok = pcall(sdk.find_type_definition, "app.GUIManager")
mock.in_draw = false
eq(guard_ok, false, "game call during a UI frame is an error")

-- Script, migration and the first scan ---------------------------------------------
dofile(PROJECT_ROOT .. "/src/reframework/autorun/BulkSell.lua")
local T = BULKSELL_TEST
assert(env.entries.UpdateBehavior, "game-thread runner registered")
local gui_hooks = {}
for _, hook in ipairs(env.hooks) do gui_hooks[hook.method.name] = hook end
assert(gui_hooks.onOpen and gui_hooks.onClose, "equipment list open/close tracked")
eq(env.files["BulkSell/config.v1.json"], V1_CONFIG, "version 1 settings kept as config.v1.json")
eq(env.files["BulkSell/config.json"].version, 2, "settings migrated")
eq(T.state.settings.mode, "best", "rule became best")
eq(T.state.settings.best_n, 1, "best 1")
eq(T.state.settings.max_rarity, 5, "up to R5")

local function frames(n)
    for _ = 1, n or 50 do
        env.advance(0.02)
        env.entries.UpdateBehavior()
    end
end

local function rescan()
    env.draw({ "Scan Equipment Box##BulkSellScan" })
    frames()
    env.draw()
end

local function find(text)
    env.draw(nil, { ["Find##BulkSellFind"] = text })
    env.draw()
end

local function receipts()
    local list = {}
    for _, w in ipairs(env.written) do
        if w.path:find("^BulkSell/receipts/sold_") then list[#list + 1] = w.data end
    end
    return list
end

local KEEP = "Keep##BulkSellKeepMode"
local RARITY = "Sell unique talismans only up to rarity##BulkSellRarity"
local ACK_UNIQUE = "I understand that unique talismans are sold.##BulkSellAckUnique"
local ACK_LOSS = "I accept losing these.##BulkSellAckLoss"

env.draw({ "Show window##BulkSell" })
assert(env.has("Scan reads your talismans"), "window shown")
assert(env.has("Your rarity rule is now \"Keep the best 1 per skill\", limited to R5"), "migration notice")
env.draw({ "OK##BulkSellNotice1" })
env.draw()
assert(not env.has("Your rarity rule is now"), "notice dismissed")
rescan()
assert(env.has("Scanned "), "scan line")
assert(env.has("11 appraised (4 protected) · Box 13 / 14 (1 free)"), "box line")
assert(env.has("Sell 2 · keep 9 · about 3,000 z · box after the sale 11 / 14"), "summary at best 1 up to R5")
assert(env.has("Duplicates 1 · covered 1 · unique 0"), "detail line")
assert(env.has("Limited to R5. Up to R8, best 1 would sell 5 (13,500 z)."), "rarity hint")
local keep_items = env.combos[KEEP]
eq(#keep_items, 7, "Keep options")
eq(keep_items[1], "Keep everything (sell only what I tick)  -  0 to sell (0 z)", "manual entry")
eq(keep_items[2], "Keep every unique talisman (sell duplicates and covered ones)  -  2 to sell (3,000 z)", "covered entry")
eq(keep_items[7], "Keep the best 1 per skill  -  2 to sell (3,000 z)", "best 1 entry")

-- Up to R8, best 1 sells the three unique talismans too.
env.draw(nil, { [RARITY] = 8 })
assert(env.has("Updating the list..."), "debounced update")
frames()
env.draw()
assert(env.has("Sell 5 · keep 6 · about 13,500 z"), "summary up to R8")
assert(env.has("Duplicates 1 · covered 1 · unique 3"), "unique count")
assert(env.has("To sell by rarity: R5 2 · R6 2 · R7 1 · R8 0"), "rarity line")
assert(env.has("Your best 1 for every skill and slot shape stay. No skill level leaves your box."), "promise line")
assert(env.has("Sell · unique"), "unique verdict")
assert(env.has("Not in your best 1 · closest Skill11 #2 of 3"), "why text of box 10")
assert(env.has("Same as #1 (kept)"), "duplicate why")
assert(env.has("Covered by #3 R6  Skill5 3"), "covered why")
eq(env.files["BulkSell/config.json"].max_rarity, 8, "rarity limit saved")
eq(env.files["BulkSell/config.json"].rule_enabled, false, "legacy rule key written off")

-- A rescan uses at most one fs.glob (about 9 ms in game): the missing sidecar copy.
local globs_before = env.glob_calls
rescan()
eq(env.glob_calls - globs_before, 1, "one glob per rescan")

-- Nothing touches the game while the REFramework menu is closed; reopening rescans.
local revision = T.state.scan.revision
env.drawing_ui = false
local before_calls = env.game_calls()
frames(20)
eq(env.game_calls(), before_calls, "no game calls while the menu is closed")
eq(T.state.stale, true, "closing the menu makes the plan stale")
env.drawing_ui = true
frames(1)
env.draw()
eq(T.state.scan.revision > revision, true, "rescanned after the menu opened again")
eq(T.state.stale, false, "fresh again")

-- Selling waits while a game menu or the equipment list is open, or while the game saves.
full_screen = true
frames(1)
env.draw()
assert(env.has("The box may have changed. Rescanning..."), "a full-screen menu makes the plan stale")
full_screen = false
frames(2)
env.draw()
assert(not env.has("Rescanning"), "rescanned once the menu closed")
gui_hooks.onOpen.post(nil)
frames(1)
env.draw()
assert(env.has("Rescanning"), "an equipment list makes the plan stale")
gui_hooks.onClose.post(nil)
frames(2)
env.draw()
assert(not env.has("Rescanning"), "rescanned after the list closed")
saving = true
frames(1)
env.draw()
assert(env.has("Waiting for the game to finish saving"), "waits while the game saves")
saving = false
frames(1)
env.draw()

-- A confirmation is withdrawn when the Keep option changes before "Yes, sell".
env.draw({ "Sell 5 talismans##BulkSellAll" })
env.draw()
assert(env.has("Sell 5 talismans for 13,500 z? This cannot be undone."), "confirmation shown")
assert(env.has("3 are unique: no identical or better talisman stays."), "unique line")
assert(not env.buttons["Yes, sell##BulkSellConfirm"], "no Yes before the unique tick")
env.draw(nil, { [KEEP] = 2 })
env.draw()
assert(env.has(LIST_CHANGED), "notice after a rule change")
assert(not env.has("This cannot be undone"), "confirmation withdrawn")
frames()
env.draw()
assert(env.has("Sell 2 · keep 9"), "covered mode")
assert(env.has("Only duplicates and covered talismans are sold."), "covered promise")
env.draw(nil, { [KEEP] = 7 })
frames()
env.draw()
assert(env.has("Sell 5 · keep 6"), "back to best 1")

-- ...and when the box is scanned again.
env.draw({ "Sell 5 talismans##BulkSellAll" })
rescan()
assert(env.has(LIST_CHANGED) and not env.has("This cannot be undone"), "rescan withdraws the confirmation")

-- confirm_sell refuses a confirmation made for another plan revision.
env.draw({ "Sell 5 talismans##BulkSellAll" })
T.state.confirm.ack_unique = true
T.state.scan.revision = T.state.scan.revision + 1
T.actions.confirm_sell()
eq(T.state.job, nil, "no sale started for a stale revision")
eq(T.state.notice, LIST_CHANGED, "stale revision notice")
rescan()

-- A key that is not a planned sale stops the run before anything is sold.
env.draw({ "Sell 5 talismans##BulkSellAll" })
T.state.confirm.keys = { 2, 9 }
env.draw(nil, { [ACK_UNIQUE] = true })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(2).values.category, 2, "valid key not sold when another key is invalid")
eq(at(9).values.category, 2, "kept talisman not sold")
eq(basic.values.money, 1000000, "no zenny change")
assert(env.has("Stopped: The sale list does not match the plan"), "mismatch reported")
eq(T.state.unique_ack.count, 3, "the tick was given for 3 unique talismans")
T.state.unique_ack = nil   -- start the tick tests below from scratch

-- "Sell just 1 (test)" sells the cheapest planned sale of the list shown.
env.draw({ "Sell just 1 (test)##BulkSellOne" })
env.draw()
assert(env.has("Sell 1 talisman (R5  Skill1 1  W1) for 1,500 z?"), "cheapest first, lowest box on a tie")
assert(env.buttons["Yes, sell##BulkSellConfirm"], "a duplicate needs no tick")
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(2).values.category, -1, "box 2 cleared")
eq(basic.values.money, 1001500, "zenny credited")
eq(calls.remove_accessory, 3, "decorations removed from every slot like the game does")
eq(calls.update_myset, 1, "loadouts updated after the sale")
assert(env.has("Sold 1 talismans for 1,500 z."), "sale result")
local receipt = receipts()[#receipts()]
eq(receipt.sold, 1, "receipt count")
eq(receipt.talismans[1].box, 2, "receipt box")
eq(receipt.talismans[1].price, 1500, "receipt price")
eq(receipt.talismans[1].price_source, "game", "receipt price source")
eq(receipt.talismans[1].why, "duplicate", "old why field")
eq(receipt.talismans[1].class, "safe", "class")
eq(receipt.talismans[1].detail, "Same as #1 (kept)", "detail text")
eq(receipt.talismans[1].kept_instead, 1, "kept instead")
eq(receipt.talismans[1].lost, "none", "nothing lost")
eq(receipt.skipped, "none", "receipt without skips")
eq(receipt.money_before, 1000000, "receipt money before")
eq(receipt.money_after, 1001500, "receipt money after")
eq(receipt.trigger, "manual", "trigger")
eq(receipt.rules.mode, "best", "rules mode")
eq(receipt.rules.best_n, 1, "rules N")
eq(receipt.rules.max_rarity, 8, "rules rarity")
eq(receipt.rules.always_keep, "none", "rules Always keep")
eq(receipt.acknowledged.unique, false, "no unique tick")
eq(receipt.picks.sell, 0, "no picks")
eq(type(receipt.plan_revision), "number", "plan revision")
frames(2)
env.draw()
assert(env.has("Sell 4 · keep 6"), "rescanned after selling")

-- Unique sales need the tick; it is remembered for these rules until there are more.
find("#13")
assert(env.has("1 shown (1 to sell, 3,000 z)"), "find by box")
env.draw({ "Sell the 1 shown##BulkSellShown" })
env.draw()
assert(env.has("1 are unique"), "unique line for one")
assert(not env.buttons["Yes, sell##BulkSellConfirm"], "tick needed")
env.draw(nil, { [ACK_UNIQUE] = true })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
eq(at(13).values.category, -1, "unique talisman sold")
receipt = receipts()[#receipts()]
eq(receipt.talismans[1].class, "unique", "unique class")
eq(receipt.talismans[1].kept_for[1], 7, "kept for Skill7")
eq(receipt.talismans[1].kept_for[2], 9, "kept for Skill9")
eq(receipt.talismans[1].kept_for_total, 2, "kept for total")
eq(receipt.talismans[1].rank, 2, "rank")
eq(receipt.acknowledged.unique, true, "tick recorded")
frames(2)
find("")
env.draw({ "Sell 3 talismans##BulkSellAll" })
env.draw()
assert(env.has("2 are unique"), "two unique")
assert(not env.buttons["Yes, sell##BulkSellConfirm"], "more unique talismans than acknowledged: ask again")
env.draw({ "Cancel##BulkSellCancel" })
find("#10")
env.draw({ "Sell the 1 shown##BulkSellShown" })
env.draw()
assert(env.buttons["Yes, sell##BulkSellConfirm"], "one unique for the same rules: remembered")
env.draw({ "Cancel##BulkSellCancel" })
env.draw(nil, { [RARITY] = 7 })
frames()
env.draw({ "Sell the 1 shown##BulkSellShown" })
env.draw()
assert(not env.buttons["Yes, sell##BulkSellConfirm"], "other rules: ask again")
env.draw({ "Cancel##BulkSellCancel" })

-- A unique sale is skipped when a talisman kept for its skills changed.
find("#12")
env.draw({ "Sell the 1 shown##BulkSellShown" })
env.draw(nil, { [ACK_UNIQUE] = true })
set_packed(11, { 2011, 0, 0, 0 })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(12).values.category, 2, "unique talisman kept when its certificate changed")
assert(env.has("1 were kept after a last check"), "skip reported")
receipt = receipts()[#receipts()]
eq(receipt.skipped[1].reason, "a talisman kept for its skills changed (#11)", "skip reason")
set_packed(11, { 3011, 0, 0, 0 })
frames(2)
env.draw()

-- A row's Sell box makes a pick; it is saved with the fingerprint and survives a rescan.
env.draw(nil, { ["Show##BulkSellFilter"] = 3 })   -- All
find("#10")
env.draw(nil, { ["##BulkSellPick10"] = false })
frames()
env.draw()
assert(env.has("Keep · your pick"), "Keep pick")
assert(env.has("10*"), "pick marker")
env.callbacks.config_save()
local picks_file = env.files["BulkSell/picks/slot-0-a.json"]
assert(picks_file, "picks file written")
eq(picks_file.picks["10"].action, "keep", "pick saved")
eq(picks_file.picks["10"].fp, "190:1009:1011:0:0", "pick fingerprint")
eq(picks_file.play_start, "638763618528919137", "picks file character")
rescan()
assert(env.has("Keep · your pick"), "pick survives a rescan")
set_packed(10, { 1009, 2011, 0, 0 })
rescan()
assert(env.has("1 picks removed: #10 changed or gone"), "pick dropped when the talisman changed")
set_packed(10, { 1009, 1011, 0, 0 })
rescan()

-- Protected rows ignore their (disabled) box and explain why.
find("#3")
env.hover = true
env.draw(nil, { ["##BulkSellPick3"] = true })
env.hover = false
eq(T.state.picks.entries[3], nil, "no pick on a protected talisman")
local protected_tooltip = false
for _, text in ipairs(env.tooltips) do
    if text == "RNG Charm Crafting bonus" then protected_tooltip = true end
end
assert(protected_tooltip, "tooltip on the protected row")

-- Mark shown with Find, then Undo.
find("Skill11")
assert(env.has("3 shown (2 to sell, 7,500 z)"), "find by skill")
env.draw({ "Keep##BulkSellMarkkeep" })
frames()
env.draw()
assert(env.has("3 shown (0 to sell, 0 z)"), "marked Keep")
eq(T.state.picks.entries[11].action, "keep", "the kept one gets a Keep pick too")
env.draw({ "Undo##BulkSellUndo" })
frames()
env.draw()
assert(env.has("3 shown (2 to sell, 7,500 z)"), "undone")

-- A pick made after "Sell" withdraws the confirmation.
find("")
env.draw({ "Sell 3 talismans##BulkSellAll" })
find("#4")
env.draw(nil, { ["##BulkSellPick4"] = false })
eq(T.state.confirm, nil, "confirmation withdrawn by a pick")
T.actions.confirm_sell()
eq(T.state.job, nil, "nothing sold")
env.draw(nil, { ["##BulkSellPick4"] = false })
frames()

-- A Sell pick on the only holder of a skill level needs the loss tick.
find("#9")
env.draw(nil, { ["##BulkSellPick9"] = true })
frames()
env.draw()
assert(env.has("Sell · your pick"), "Sell pick")
assert(env.has("Your pick · LAST Skill9 2"), "loss in the Why column")
assert(env.has("1 planned sales lower a skill or remove a slot shape"), "summary warning")
env.draw({ "Sell the 1 shown##BulkSellShown" })
env.draw()
assert(env.has("This sale removes:"), "loss block")
assert(env.has("Skill9 2 (best left 1) #9"), "loss line")
assert(not env.buttons["Yes, sell##BulkSellConfirm"], "loss tick needed")
env.draw(nil, { [ACK_LOSS] = true })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
eq(at(9).values.category, -1, "picked talisman sold")
eq(T.state.picks.entries[9], nil, "pick removed after the sale")
receipt = receipts()[#receipts()]
eq(receipt.talismans[1].class, "pick", "pick class")
eq(receipt.talismans[1].lost, "Skill9 2", "lost text")
eq(receipt.acknowledged.losses, true, "loss tick recorded")
eq(receipt.picks.sell, 1, "one Sell pick")
frames(2)

-- Closing the menu stops a sale after the current talisman; it is rescanned later.
find("")
env.draw(nil, { [RARITY] = 8 })
frames()
env.draw()
local planned = T.state.scan.summary.sell
eq(planned >= 2, true, "several sales planned")
env.draw({ "Sell " .. planned .. " talismans##BulkSellAll" })
env.draw(nil, { [ACK_UNIQUE] = true })
after_money = function() env.drawing_ui = false end
env.draw({ "Yes, sell##BulkSellConfirm" })
frames(1)
after_money = nil
receipt = receipts()[#receipts()]
eq(receipt.sold, 1, "only one sold")
eq(receipt.stopped, "the REFramework menu was closed.", "stop reason")
eq(receipt.money_after, "unknown", "no game call after the menu closed")
frames(5)
env.drawing_ui = true
frames(2)
env.draw()
eq(T.state.scan.summary.sell, planned - 1, "rescanned when the menu opened again")
eq(at(4).values.category, -1, "the first planned sale (box 4) was the one sold")
restore_box4()

-- Picks belong to a save slot.
find("#12")
env.draw(nil, { ["##BulkSellPick12"] = false })
frames()
env.callbacks.config_save()
save_manager.values.CurrentUserDataIndex = 1
rescan()
eq(T.state.picks.slot, 1, "slot 1 picks")
eq(T.state.picks.entries[12], nil, "slot 0 picks not used in slot 1")
save_manager.values.CurrentUserDataIndex = 0
rescan()
eq(T.state.picks.entries[12].action, "keep", "slot 0 picks back")

-- A picks file that cannot be read pauses selling until the player continues.
env.put_raw("BulkSell/picks/slot-0-a.json", "garbage")
env.put_raw("BulkSell/picks/slot-0-b.json", "garbage")
save_manager.values.CurrentUserDataIndex = 1
rescan()
save_manager.values.CurrentUserDataIndex = 0
rescan()
assert(env.has("Your saved Sell/Keep ticks could not be read"), "paused")
assert(not env.buttons["Sell " .. T.state.scan.summary.sell .. " talismans##BulkSellAll"], "no Sell button while paused")
env.draw({ "Continue without my picks##BulkSellNoPicks" })
frames()
env.draw()
assert(not env.has("could not be read"), "continued")
find("")

-- A sale price that disagrees with the value table is never paid.
env.draw(nil, { [KEEP] = 2 })
frames()
set_box_override[4] = nil
price_override[4] = 9999
rescan()
local money = basic.values.money
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
assert(env.has("Stopped: The game's sale price does not match"), "price mismatch stops")
eq(at(4).values.category, 2, "mismatched talisman not sold")
eq(basic.values.money, money, "no zenny change on a price mismatch")
price_override[4] = nil
rescan()

-- A talisman favorited after the scan is kept by the last check.
at(4).values.FreeVal4 = 1
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(4).values.category, 2, "favorite not sold")
assert(env.has("Sold 0 talismans for 0 z."), "nothing sold")
assert(env.has("1 were kept after a last check"), "skip reported")
frames(2)
env.draw()
assert(env.has("Nothing more to sell: every talisman is unique."), "rescan protects the favorite")

-- A sale whose zenny does not arrive stops the run.
at(4).values.FreeVal4 = 0
rescan()
money_gain = 0
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
assert(env.has("Stopped: Zenny changed by 0 instead of 1500"), "zenny mismatch stops")
money_gain = 1

-- Confirmations can be cancelled, and expire.
restore_box4()
rescan()
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.draw({ "Cancel##BulkSellCancel" })
env.draw()
assert(not env.has("This cannot be undone"), "cancelled confirmation hidden")
env.draw({ "Sell 1 talismans##BulkSellAll" })
env.advance(30)
frames(1)
env.draw()
assert(not env.has("This cannot be undone"), "expired confirmation hidden")

-- A covered talisman is kept when the talisman that covers it changed after the scan.
env.draw({ "Sell 1 talismans##BulkSellAll" })
set_packed(3, { 1009, 0, 0, 0 })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
env.draw()
eq(at(4).values.category, 2, "covered talisman kept when its keeper is gone")
receipt = receipts()[#receipts()]
eq(receipt.skipped[#receipt.skipped].reason, "the talisman kept instead is gone", "skip reason in receipt")
set_packed(3, { 3005, 0, 0, 2110 })

-- An unreadable RNG Charm Crafting sidecar turns selling off until it is fixed.
env.put_raw(SIDECAR_B, "garbage")
rescan()
assert(env.has_text("RNG Charm Crafting file TalismanCrafting/special%-bonuses%-slot%-0%-b%.json could not be read"),
    "corrupt sidecar blocks selling")
assert(not env.buttons["Sell 1 talismans##BulkSellAll"], "no sell button while blocked")
env.raw[SIDECAR_B] = nil
rescan()
assert(not env.has("could not be read"), "unblocked once the file is gone")

-- Skills panel ------------------------------------------------------------------------
-- The box now holds 1, 3, 7, 8 (protected), 4, 10, 11 and 12; rarity limit R8.
local ui_view = require("BulkSell.ui")._view
env.draw(nil, { [KEEP] = 7 })   -- best 1
frames()
env.draw()
assert(env.headers["Skills: 0 keep all · 0 custom · 0 don't care###BulkSellSkills"], "Skills panel header")
assert(env.has("Last change (Keep -> best 1)"), "last change line")
env.draw({ "Show changed##BulkSellShowChanged" })
env.draw()
eq(ui_view.filter, 6, "Show changed switches the filter")
eq(#ui_view.rows > 0, true, "changed rows shown")
env.draw(nil, { ["Show##BulkSellFilter"] = 7 })   -- Last of their kind
env.draw()
local last_keys = {}
for _, c in ipairs(ui_view.rows) do last_keys[c.key] = true end
eq(last_keys[11], true, "the only Skill11 3 is the last of its kind")
eq(last_keys[12], nil, "Skill7 1 and Skill11 1 are not the last of their kind")
env.draw(nil, { ["Show##BulkSellFilter"] = 3 })   -- All
env.draw()

-- One skill through its own combo: Skill9 (best level 1) -> Keep all.
env.draw(nil, { ["##BulkSellSkillPref9"] = 7 })
eq(T.state.settings.keep_skills["9"], 1, "Keep all")
frames()
env.draw()
assert(env.headers["Skills: 1 keep all · 0 custom · 0 don't care###BulkSellSkills"], "header counts the change")
env.draw(nil, { ["##BulkSellSkillPref9"] = 1 })
eq(T.state.settings.keep_skills["9"], nil, "back to Default")
frames()

-- "Set shown" needs a Find term; Don't care on Skill11 makes its level 3 leave the box.
env.draw()
assert(not env.buttons["Don't care##BulkSellSetShownignore"], "Set shown needs a Find term")
env.draw(nil, { ["Find skill##BulkSellSkillFind"] = "skill11" })
env.draw()
assert(env.has("Set the 1 shown to:"), "set shown line")
env.draw({ "Don't care##BulkSellSetShownignore" })
frames()
env.draw()
eq(T.state.settings.ignore_skills["11"], true, "Skill11 is Don't care")
assert(env.has("1 Don't-care skill levels leave your box"), "yellow Don't care line")
assert(not env.has("No skill level leaves your box"), "no green promise")
env.draw({ "Sell 3 talismans##BulkSellAll" })
env.draw()
assert(env.has("Skill11 3 (best left 1) #11 - Don't care"), "red block names the Don't care loss")
assert(not env.buttons["Yes, sell##BulkSellConfirm"], "loss tick needed")
env.draw({ "Cancel##BulkSellCancel" })

-- More than 10 skills at once asks first; Undo puts every skill back.
T.actions.set_skills({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }, { kind = "keep", min = 1 })
env.draw()
assert(env.has("Set 11 skills to Keep all?"), "confirmation for many skills")
eq(T.state.settings.keep_skills["1"], nil, "nothing changed yet")
env.draw({ "Yes##BulkSellSkillsYes" })
eq(T.state.settings.keep_skills["11"], 1, "applied")
eq(T.state.settings.ignore_skills["11"], nil, "one preference per skill")
env.draw({ "Undo##BulkSellSkillsUndo" })
eq(T.state.settings.keep_skills["1"], nil, "undone")
eq(T.state.settings.ignore_skills["11"], true, "Don't care back")
env.draw({ "Reset all##BulkSellSkillsReset" })
env.draw()
assert(env.has("Set every skill back to Default?"), "Reset all asks first")
env.draw({ "Yes##BulkSellSkillsYes" })
eq(T.state.settings.ignore_skills["11"], nil, "reset")
env.draw(nil, { ["Find skill##BulkSellSkillFind"] = "" })
frames()

-- A talisman that changed counts as new at the next scan.
set_packed(10, { 1009, 2011, 0, 0 })
rescan()
assert(env.has("1 new since the last scan"), "new talismans counted")
set_packed(10, { 1009, 1011, 0, 0 })
rescan()

-- Tools: stars ---------------------------------------------------------------------
-- Best 1 keeps 1, 3, 7, 8 (protected), 10 and 11, and sells 4 and 12.
assert(env.headers["Tools: stars and export###BulkSellTools"], "Tools header")
local planned_before = T.state.scan.summary.sell
env.draw({ "Star the 6 kept...##BulkSellStarkept" })
env.draw()
assert(env.has("Star 6 kept talismans?"), "star confirmation")
eq(favorite_calls, 0, "nothing starred before Yes")
env.draw({ "Yes##BulkSellStarYes" })
frames()
env.draw()
eq(favorite_calls, 6, "one call per kept talisman")
assert(env.has("Starred 6 talismans."), "star result")
for _, box_index in ipairs({ 1, 3, 7, 8, 10, 11 }) do eq(at(box_index).values.FreeVal4, 1, "starred box " .. box_index) end
eq(at(4).values.FreeVal4, 0, "a planned sale is not starred")
local ledger = env.files["BulkSell/stars/slot-0-a.json"]
assert(ledger, "stars ledger written")
eq(ledger.added["10"].fp, "190:1009:1011:0:0", "ledger entry with fingerprint")
eq(T.state.scan.summary.sell, planned_before, "starring what is kept does not change the plan")
assert(env.buttons["Remove stars Bulk Sell added (6)...##BulkSellStarremove"], "the added stars can be removed")
for label in pairs(env.buttons) do assert(not label:find("##BulkSellStarkept", 1, true), "nothing left to star") end

-- A star the player set is never removed; the ones Bulk Sell added are.
at(4).values.FreeVal4 = 1
rescan()
env.draw({ "Remove stars Bulk Sell added (6)...##BulkSellStarremove" })
env.draw({ "Yes##BulkSellStarYes" })
frames()
env.draw()
assert(env.has("Removed 6 stars."), "remove result")
eq(at(10).values.FreeVal4, 0, "star removed")
eq(at(4).values.FreeVal4, 1, "the player's own star stays")
eq(next(T.state.stars.entries), nil, "ledger empty")
at(4).values.FreeVal4 = 0
rescan()

-- A star that does not change stops the job.
favorite_works = false
env.draw({ "Star the 6 kept...##BulkSellStarkept" })
env.draw({ "Yes##BulkSellStarYes" })
frames()
env.draw()
assert(env.has("Stopped: The favorite star did not change as asked"), "stopped")
eq(next(T.state.stars.entries), nil, "nothing recorded")
favorite_works = true
frames(2)

-- Tools: export --------------------------------------------------------------------
env.draw({ "Copy for mhwilds.wiki-db.com##BulkSellWikiDb" })
frames()
env.draw()
assert(env.clipboard and env.clipboard:find("Skill9,1,Skill11,1,,0,0,0,0,0,0,0\n", 1, true), "wiki-db line on the clipboard")
assert(env.has("Copied 8 talismans to the clipboard."), "copy result")
local wikidb_file
for path, text in pairs(env.text_files) do
    if path:find("^BulkSell/export/wikidb_game_") then wikidb_file = text end
end
eq(wikidb_file, env.clipboard, "the same text saved as a file")
env.draw(nil, { ["Names##BulkSellExportNames"] = 3 })   -- Japanese
env.draw(nil, { ["Export##BulkSellExportScope"] = 3 })  -- only what would be sold
env.draw({ "Copy for mhwilds.wiki-db.com##BulkSellWikiDb" })
frames()
env.draw()
eq(env.clipboard, "JA-Skill5,2,,0,,0,1,0,0,0,0,0\nJA-Skill7,1,JA-Skill11,1,,0,0,0,0,0,0,0\n", "Japanese names, sales only")
assert(not env.has("Some names were not available"), "all names found")
env.draw(nil, { ["Names##BulkSellExportNames"] = 4 })   -- Korean: the fake game has none
env.draw({ "Copy for mhwilds.wiki-db.com##BulkSellWikiDb" })
frames()
env.draw()
assert(env.clipboard:find("Skill5,2", 1, true), "falls back to the game's names")
assert(env.has("Some names were not available in that language"), "fallback reported")
env.draw({ "Save CSV##BulkSellCsv" })
frames()
env.draw()
local csv
for path, text in pairs(env.text_files) do
    if path:find("^BulkSell/export/talismans_.*%.csv$") then csv = text end
end
assert(csv and csv:sub(1, 3) == "\239\187\191", "CSV with BOM")
assert(csv:find("\r\n4,5,Skill5,2,,,,,A1,1,0,0,0,1500,Sell · covered,Covered by #3 R6  Skill5 3,3,\r\n", 1, true), "CSV row")
local write = fs.write
fs.write = nil
env.draw({ "Save CSV##BulkSellCsv" })
frames()
env.draw()
assert(env.has("The CSV could not be written"), "no fs.write")
fs.write = write
env.draw(nil, { ["Names##BulkSellExportNames"] = 1, ["Export##BulkSellExportScope"] = 1 })
assert(env.has("Selling these gives 6,000 z. Melding them would give 7 Melding Pot points instead"), "planner line")

-- Auto-clean watch -------------------------------------------------------------------
-- Free box entries now: 0, 2, 9 and 13 (4 of 14).
local function new_talisman(index, amulet_type, packed)
    local v = at(index).values
    v.category, v.Category_Gender, v.FreeVal0, v.FreeVal1, v.FreeVal4 = 2, 21, amulet_type, 1, 0
    set_packed(index, packed)
end
local function draw_toast()
    env.texts = {}
    mock.in_draw = true   -- the toast must not call the game either
    env.callbacks.frame()
    mock.in_draw = false
end
assert(env.files["BulkSell/seen/slot-0-a.json"] or env.files["BulkSell/seen/slot-0-b.json"], "new-arrivals baseline saved")
-- Earlier tests changed boxes 3, 4 and 10 and put them back, which counts as new: start clean.
rescan()
env.draw({ "Clear##BulkSellClearNew" })
env.draw(nil, { ["Tell me about new items while the menu is closed (auto-clean)##BulkSellAutoClean"] = true })
eq(T.state.settings.auto_clean, true, "auto-clean on")
env.drawing_ui = false
frames(1)   -- the first look only takes the baseline
draw_toast()
eq(#env.texts, 0, "no message yet")
local calls_after_look = env.game_calls()
frames(100)   -- 2 s: no new look yet
eq(env.game_calls(), calls_after_look, "no game calls between two looks")
new_talisman(2, 190, { 1005, 0, 0, 1000 })   -- R6 Skill5 1, A1: covered by box 3
frames(160)
assert(env.game_calls() > calls_after_look, "the box was looked at again")
draw_toast()
assert(env.has("Equipment Box: 1 new items since your last scan. Open Bulk Sell (Insert) to check."), "toast")
eq(T.state.stale, true, "the plan is stale")
env.advance(13)
draw_toast()
eq(#env.texts, 0, "the toast goes away")

-- Messages wait while the quest result screen is up; quest state changes are logged once.
result_flow, in_quest = true, true
new_talisman(9, 189, { 1001, 0, 0, 1003 })   -- R5 Skill1 1, W1: a copy of box 1
frames(260)
draw_toast()
eq(#env.texts, 0, "held back during the result screen")
result_flow = false
frames(260)
draw_toast()
assert(env.has("Equipment Box: 2 new items since your last scan."), "shown after the result screen")
local quest_lines = 0
for _, line in ipairs(env.logs) do
    if line:find("watch: quest_active false -> true", 1, true) then quest_lines = quest_lines + 1 end
end
eq(quest_lines, 1, "a quest state change is logged once")
in_quest = false

-- Opening the menu rescans; the new talismans are listed and sold as auto-clean.
env.drawing_ui = true
frames(2)
env.draw()
assert(env.has("2 new talismans since you last cleared them."), "arrivals line")
env.draw({ "Show new##BulkSellShowNew" })
env.draw()
eq(ui_view.filter, 8, "New arrivals filter")
eq(#ui_view.rows, 2, "two rows")
env.draw({ "Sell the 2 shown##BulkSellShown" })
env.draw({ "Yes, sell##BulkSellConfirm" })
frames()
receipt = receipts()[#receipts()]
eq(receipt.sold, 2, "both new talismans sold")
eq(receipt.trigger, "auto-clean", "receipt trigger")
frames(2)
env.draw()
assert(not env.has("new talismans since you last cleared them"), "sold arrivals leave the list")
new_talisman(13, 190, { 1005, 0, 0, 1000 })
rescan()
assert(env.has("1 new talismans since you last cleared them."), "a later arrival")
env.draw({ "Clear##BulkSellClearNew" })
env.draw()
assert(not env.has("new talismans since you last cleared them"), "cleared")
env.draw(nil, { ["Show##BulkSellFilter"] = 3 })

-- The box is nearly full (3 of 14 free): one message when it crosses the line.
env.draw(nil, { ["Also tell me when the Equipment Box is almost full##BulkSellCapacityToast"] = true })
env.drawing_ui = false
frames(1)
env.advance(6)
frames(1)
draw_toast()
assert(env.has("Equipment Box: only 3 free slots left."), "capacity toast")
env.advance(13)
frames(260)
draw_toast()
eq(#env.texts, 0, "said once")

-- Auto-clean off: nothing touches the game while the menu is closed.
env.drawing_ui = true
frames(2)
env.draw(nil, { ["Tell me about new items while the menu is closed (auto-clean)##BulkSellAutoClean"] = false })
env.drawing_ui = false
frames(1)
local calls_off = env.game_calls()
frames(300)
eq(env.game_calls(), calls_off, "no game calls with auto-clean off")
env.drawing_ui = true
frames(2)
env.draw()

-- Debug files: a plan dump with string keys only (so it reads back as written) and a timing line.
env.draw(nil, { ["Write debug files (for bug reports)##BulkSellDebug"] = true })
env.draw(nil, { [KEEP] = 7 })
frames()
local dump
for _, w in ipairs(env.written) do
    if w.path:find("^BulkSell/debug/plan_") then dump = w.data end
end
assert(dump, "plan dump written")
eq(dump.options.mode, "best", "dump options")
for _, map in ipairs({ dump.options.keep_skills, dump.options.picks, dump.verdicts, dump.preview.best }) do
    for key in pairs(map) do eq(type(key), "string", "dump keys are strings") end
end
eq(dump.verdicts["4"].action, T.state.scan.verdicts[4].action, "dump verdict")
eq(#dump.charms, #T.state.scan.charms, "dump charms")
local timing = false
for _, line in ipairs(env.logs) do
    if line:find("analyse done in %d+ frames") then timing = true end
end
assert(timing, "timing line logged")
env.draw(nil, { ["Write debug files (for bug reports)##BulkSellDebug"] = false })

eq(env.load_file_calls, 0, "no json.load_file, so no '[JSON] Failed to load file' log lines")

local expected_errors = { "Zenny changed by 0", "sale price does not match", "does not match the plan",
    "favorite star did not change" }
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
