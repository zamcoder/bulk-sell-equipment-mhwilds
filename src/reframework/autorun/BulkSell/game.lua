-- Game access for Bulk Sell: reads talismans from the Equipment Box and sells them.
--
-- Field names come from the RSZ dump of this game version, and the talisman
-- encoding matches what other mods use on this build:
--   Category_Gender            bit 0x80 marks an unused box entry
--   FreeVal0                   amulet type; 189..192 are appraised talismans of rarity 5..8
--   FreeVal1                   talisman level; appraised talismans are always 1
--   FreeVal4                   favorite flag (also exposed as isFavorite())
--   BowgunCustomizeId[0..2]    skills: level * 1000 + app.HunterDef.Skill value (0 = none)
--   BowgunCustomizeId[3]       slots: lv1 * 1000 + lv2 * 100 + lv3 * 10 + flag; a non-zero flag
--                              means the first slot is the weapon slot (appraised talismans
--                              have at most one, always first)
--   EquipmentAccessoryIdArray  attached decorations (-1 = none)
--
-- Selling repeats, in the same order, the calls the game's own View/Sell
-- Equipment makes (recorded with the dev probe): removeAccessory for each slot,
-- addMoney(price, true), cEquipWork:init(), cEquipParam:updateEquipMyset().
-- The box is not compacted afterwards, so other box indices never move.

local game = {}

local AMULET_CATEGORY = 2   -- app.EquipDef.CATEGORY.AMULET
local INVALID_CATEGORY = -1
local AMULET_SLOT = 6       -- app.EquipDef.EQUIP_INDEX.AMULET
local EMPTY_BOX_FLAG = 0x80
local APPRAISED_LEVEL = 1
local RARITY_BY_TYPE = { [189] = 5, [190] = 6, [191] = 7, [192] = 8 }
local NAMES_BY_RARITY = { [5] = "Unknown Charm", [6] = "Historical Charm", [7] = "Secret Charm", [8] = "Golden Age Charm" }

local SELL_METHODS = {
    { "in_myset", "app.savedata.cEquipParam", "isEquipIndexInMyset(System.Int32)" },
    { "remove_accessory", "app.savedata.cEquipParam", "removeAccessory(app.savedata.cEquipWork, System.Int32, System.Boolean)" },
    { "update_myset", "app.savedata.cEquipParam", "updateEquipMyset()" },
    { "add_money", "app.savedata.cBasicParam", "addMoney(System.Int32, System.Boolean)" },
    { "get_money", "app.savedata.cBasicParam", "getMoney()" },
    { "work_init", "app.savedata.cEquipWork", "init()" },
    { "full_screen_ui", "app.GUIManager", "isOpenFullScreenUI()" },
}

local cache = { methods = nil, skill_names = {}, prices = {} }
local equip_list_open = false   -- app.GUI080001 (equipment lists, including View/Sell Equipment)

local function method(type_name, signature)
    local td = sdk.find_type_definition(type_name)
    return td and td:get_method(signature)
end

local function methods()
    if not cache.methods then
        local m = {
            current_save = method("app.SaveDataManager", "getCurrentUserSaveData()"),
            skill_name = method("app.MessageUtil", "getHunterSkillName(app.HunterDef.Skill)"),
            text = method("app.MessageUtil", "getText(System.Guid, System.Int32)"),
            amulet_data = method("app.AmuletUtil", "getAmuletData(app.savedata.cEquipWork)"),
            is_favorite = method("app.savedata.cEquipWork", "isFavorite()"),
            equip_set = method("app.EquipUtil", "getEquipSet(System.Int32)"),
            game_price = method("app.EquipUtil", "getEquipSellingRate(app.EquipDef.EquipSet)"),
        }
        for _, entry in ipairs(SELL_METHODS) do m[entry[1]] = method(entry[2], entry[3]) end
        cache.methods = m
    end
    return cache.methods
end

-- Array elements and some fields come back as boxed System.Int16/Int32 objects.
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
    if ok then return value end
    return nil
end

local function size(array)
    if array == nil then return 0 end
    local ok, value = pcall(function() return array:get_size() end)
    return ok and number(value) or 0
end

local function element(array, index)
    local ok, value = pcall(function() return array:get_element(index) end)
    if ok then return value end
    return nil
end

local function amulet_box_index(equip_index)
    return number(element(field(equip_index, "Index"), AMULET_SLOT))
end

local function is_empty(work)
    local flags = number(field(work, "Category_Gender")) or EMPTY_BOX_FLAG
    return (flags & EMPTY_BOX_FLAG) ~= 0
end

local function category(work)
    local ok, value = pcall(function() return work:call("get_Category") end)
    return ok and number(value) or nil
end

function game.save()
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local getter = methods().current_save
    if not manager or not getter then return nil, "Save data manager is not ready." end
    local ok, save = pcall(getter.call, getter, manager)
    if not ok or not save then return nil, "No save data loaded." end
    return save, manager
end

-- Box indices that must never be sold, with the reason shown to the player.
-- Loadouts are checked even when marked empty: a stale index only makes this more careful.
local function protected_boxes(equip)
    local reasons = {}
    local equipped = amulet_box_index(field(equip, "_EquipIndex"))
    if equipped and equipped >= 0 then reasons[equipped] = "equipped" end
    local loadouts = field(equip, "_EquipMySet")
    for i = 0, size(loadouts) - 1 do
        local box = amulet_box_index(field(field(element(loadouts, i), "_MysetParam"), "_EquipIndex"))
        if box and box >= 0 and not reasons[box] then reasons[box] = "loadout" end
    end
    return reasons
end

-- Talismans that RNG Charm Crafting gave a Set/Group bonus; its sidecar is keyed by box index.
-- Both files are loaded directly (REFramework logs a harmless error for a missing one):
-- skipping a file that exists would let a bonus talisman be sold.
local function special_bonus_boxes(save_slot)
    local boxes = {}
    for _, suffix in ipairs({ "a", "b" }) do
        local path = "TalismanCrafting/special-bonuses-slot-" .. tostring(save_slot) .. "-" .. suffix .. ".json"
        local ok, store = pcall(json.load_file, path)
        if ok and type(store) == "table" and type(store.entries) == "table" then
            for key in pairs(store.entries) do
                local box = tonumber(key)
                if box then boxes[box] = true end
            end
        end
    end
    return boxes
end

local function has_decorations(work)
    local decorations = field(work, "EquipmentAccessoryIdArray")
    for i = 0, size(decorations) - 1 do
        local id = number(element(decorations, i))
        if id and id >= 0 then return true end
    end
    return false
end

local function is_favorite(work)
    local getter = methods().is_favorite
    if getter then
        local ok, value = pcall(getter.call, getter, work)
        if ok and type(value) == "boolean" then return value end
    end
    return (number(field(work, "FreeVal4")) or 0) ~= 0
end

-- AmuletData._Price for the talisman type (3000 / 6000 / 9000 / 16000 for rarity 5..8).
local function base_price(work, amulet_type)
    if cache.prices[amulet_type] == nil then
        local getter = methods().amulet_data
        local value = false
        if getter then
            local ok, data = pcall(getter.call, getter, nil, work)
            if ok and data then value = number(field(data, "_Price")) or false end
        end
        cache.prices[amulet_type] = value
    end
    return cache.prices[amulet_type] or nil
end

local function decode_slots(value)
    local slots = {}
    local weapon_first = value % 10 ~= 0
    local levels = { value // 1000 % 10, value // 100 % 10, value // 10 % 10 }
    for i, level in ipairs(levels) do
        if level > 0 then
            slots[#slots + 1] = { kind = (i == 1 and weapon_first) and "W" or "A", level = level }
        end
    end
    return slots
end

-- Decodes one appraised talisman, or returns nil for crafted or unknown amulets.
local function decode(work, index)
    local amulet_type = number(field(work, "FreeVal0"))
    local rarity = RARITY_BY_TYPE[amulet_type]
    if not rarity or number(field(work, "FreeVal1")) ~= APPRAISED_LEVEL then return nil end
    local packed = field(work, "BowgunCustomizeId")
    if size(packed) < 4 then return nil end

    local values = {}
    for i = 0, 3 do values[i + 1] = number(element(packed, i)) or 0 end
    local skills = {}
    for i = 1, 3 do
        if values[i] > 0 then skills[#skills + 1] = { id = values[i] % 1000, level = values[i] // 1000 } end
    end

    return {
        key = index,
        rarity = rarity,
        name = NAMES_BY_RARITY[rarity],
        amulet_type = amulet_type,
        skills = skills,
        slots = decode_slots(values[4]),
        base_price = base_price(work, amulet_type),
        -- Re-checked right before selling, so a moved or changed box entry is never sold.
        fingerprint = table.concat({ amulet_type, values[1], values[2], values[3], values[4] }, ":"),
    }
end

-- Sale price as the game computes it for this box entry. Despite its name,
-- EquipUtil.getEquipSellingRate returns the price itself (1500 / 3000 / 4500 / 8000
-- for rarity 5..8, the same as the View/Sell Equipment dialog). Falls back to half
-- the talisman value, which matches the game for every appraised talisman, when the
-- game's value cannot be read for exactly this entry.
local function sale_price(base, index)
    local m = methods()
    if m.equip_set and m.game_price then
        local ok, price = pcall(function()
            local set = m.equip_set:call(nil, index)
            if not set or number(set:call("get_WorkInfo"):call("get_BoxIndex")) ~= index then return nil end
            return number(m.game_price:call(nil, set))
        end)
        if ok and price and price > 0 then return price end
    end
    return base and base // 2 or nil
end

-- Reads every appraised talisman in the Equipment Box. `yield` (optional) is
-- called every 256 entries so the caller can spread the work over frames.
-- Returns charms and box statistics, or nil and a reason.
function game.read_talismans(yield)
    local save, manager = game.save()
    if not save then return nil, manager end
    local equip = field(save, "_Equip")
    local box = field(equip, "_EquipBox")
    if not box then return nil, "Equipment Box not found." end

    local protected = protected_boxes(equip)
    local bonus = special_bonus_boxes(number(field(manager, "CurrentUserDataIndex")) or 0)
    local charms = {}
    local stats = { slots = size(box), used = 0, amulets = 0, appraised = 0, protected = 0 }

    for index = 0, stats.slots - 1 do
        local work = element(box, index)
        if work and not is_empty(work) then
            stats.used = stats.used + 1
            if category(work) == AMULET_CATEGORY then
                stats.amulets = stats.amulets + 1
                local charm = decode(work, index)
                if charm then
                    stats.appraised = stats.appraised + 1
                    charm.price = sale_price(charm.base_price, index)
                    charm.protected = protected[index]
                        or (is_favorite(work) and "favorite")
                        or (bonus[index] and "special bonus")
                        or (has_decorations(work) and "decorations")
                        or nil
                    if charm.protected then stats.protected = stats.protected + 1 end
                    charms[#charms + 1] = charm
                end
            end
        end
        if yield and index % 256 == 255 then yield() end
    end
    return charms, stats
end

-- Localized skill name; must be called on the game thread the first time for each id.
function game.skill_name(id)
    local name = cache.skill_names[id]
    if name == nil then
        local m = methods()
        local ok, text = pcall(function()
            local guid = m.skill_name:call(nil, id)
            return m.text:call(nil, guid, 0)
        end)
        name = (ok and type(text) == "string" and text ~= "") and text or ("Skill #" .. tostring(id))
        cache.skill_names[id] = name
    end
    return name
end

-- Tracks the equipment list screen, so the box is never changed under an open list.
function game.install_hooks()
    local td = sdk.find_type_definition("app.GUI080001")
    if not td then return end
    local function track(signature, open)
        local target = td:get_method(signature)
        if target then
            pcall(sdk.hook, target, function() end, function(retval)
                equip_list_open = open
                return retval
            end)
        end
    end
    track("onOpen()", true)
    track("onClose()", false)
end

-- nil when selling is possible on this build, otherwise the reason it is not.
function game.sell_unavailable()
    local m = methods()
    for _, entry in ipairs(SELL_METHODS) do
        if not m[entry[1]] then return "Game method missing: " .. entry[2] .. "::" .. entry[3] end
    end
    return nil
end

-- nil when no game menu is open, otherwise the reason selling must wait.
function game.menu_block_reason()
    if equip_list_open then return "Close the equipment menu first." end
    local manager = sdk.get_managed_singleton("app.GUIManager")
    local check = methods().full_screen_ui
    if not manager or not check then return "Game menus are not ready." end
    local ok, open = pcall(check.call, check, manager)
    if not ok then return "Could not check whether a game menu is open." end
    if open then return "Close the game menu first." end
    return nil
end

-- Starts a sale session: resolves the objects every sale needs.
function game.begin_sale()
    local save, manager = game.save()
    if not save then return nil, manager end
    local equip = field(save, "_Equip")
    local ctx = {
        m = methods(),
        equip = equip,
        basic = field(save, "_BasicData"),
        box = field(equip, "_EquipBox"),
        bonus = special_bonus_boxes(number(field(manager, "CurrentUserDataIndex")) or 0),
    }
    if not ctx.equip or not ctx.basic or not ctx.box then return nil, "Save data is incomplete." end
    return ctx
end

-- True when the box entry still holds exactly the scanned talisman.
function game.unchanged(ctx, charm)
    local work = element(ctx.box, charm.key)
    if not work or is_empty(work) or category(work) ~= AMULET_CATEGORY then return false end
    local current = decode(work, charm.key)
    return current ~= nil and current.fingerprint == charm.fingerprint
end

-- Sells one talisman after re-checking it. Returns a result table:
--   { sold = true, price = n }                 sold
--   { sold = false, reason = "..." }           skipped, nothing changed
--   { sold = false, fatal = true, reason = "..." }  stop the whole run
function game.sell_one(ctx, charm)
    local index = charm.key
    local m = ctx.m
    local work = element(ctx.box, index)
    if not work or is_empty(work) or category(work) ~= AMULET_CATEGORY then
        return { sold = false, reason = "no longer in the box" }
    end
    local current = decode(work, index)
    if not current or current.fingerprint ~= charm.fingerprint then return { sold = false, reason = "changed since the scan" } end
    if index == amulet_box_index(field(ctx.equip, "_EquipIndex")) then return { sold = false, reason = "equipped" } end
    local ok, in_myset = pcall(m.in_myset.call, m.in_myset, ctx.equip, index)
    if not ok or in_myset ~= false then return { sold = false, reason = "in a loadout" } end
    if is_favorite(work) then return { sold = false, reason = "favorite" } end
    if has_decorations(work) then return { sold = false, reason = "has decorations" } end
    if ctx.bonus[index] then return { sold = false, reason = "RNG Charm Crafting bonus" } end

    local price = sale_price(current.base_price, index)
    if not price or price <= 0 then return { sold = false, fatal = true, reason = "Sale price unavailable." } end
    local before = number(m.get_money:call(ctx.basic))

    for slot = 0, 2 do m.remove_accessory:call(ctx.equip, work, slot, true) end
    m.add_money:call(ctx.basic, price, true)
    m.work_init:call(work)
    m.update_myset:call(ctx.equip)

    if category(work) ~= INVALID_CATEGORY or not is_empty(work) then
        return { sold = false, fatal = true, reason = "The box entry was not cleared after selling." }
    end
    local after = number(m.get_money:call(ctx.basic))
    if not before or not after or after - before ~= price then
        return { sold = true, price = price, fatal = true,
            reason = string.format("Zenny changed by %s instead of %d; stopped to be safe.", tostring(after and before and after - before), price) }
    end
    return { sold = true, price = price }
end

function game.money(ctx)
    return number(ctx.m.get_money:call(ctx.basic))
end

return game
