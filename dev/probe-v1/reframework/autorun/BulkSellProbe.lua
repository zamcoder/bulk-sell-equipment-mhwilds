-- BulkSell probe: development-only discovery tool, never shipped with the mod.
--
-- Does nothing until a button is pressed in REFramework's menu
-- (Insert > Script Generated UI > BulkSell Probe). Reports are written to
-- reframework/data/BulkSellProbe/. Trace hooks are only installed by the
-- "Install trace hooks" button and stay until Reset Scripts or a game restart.

local OUT_DIR = "BulkSellProbe/"
local PREVIEW_ITEMS = 8
local SAMPLE_AMULETS = 3
local TRACE_LIMIT = 20000
local TRACE_PER_METHOD = 40
local RELATED_TYPE_LIMIT = 500

-- All methods of these types are listed in the methods report.
local SEED_TYPES = {
    "app.SaveDataManager",
    "app.savedata.cUserSaveParam",
    "app.savedata.cEquipParam",
    "app.savedata.cEquipWork",
    "app.savedata.cEquipMyset",
    "app.savedata.cEquipIndex",
    "app.savedata.cBasicParam",
    "app.EquipUtil",
    "app.AmuletUtil",
    "app.AmuletJudgeUtil",
    "app.FacilityUtil",
    "app.ItemUtil",
    "app.EquipDef.EquipWorkInfo",
    "app.EquipDef.EquipSet",
    "app.GUIManager",
    "app.GUI080001",
}

-- Seed types that run every frame or are plain data: only TRACE_KEYWORDS methods are traced.
-- Every other seed type has all methods except property getters traced.
local KEYWORD_ONLY_TRACE = {
    ["app.SaveDataManager"] = true,
    ["app.EquipUtil"] = true,
    ["app.AmuletUtil"] = true,
    ["app.AmuletJudgeUtil"] = true,
    ["app.FacilityUtil"] = true,
    ["app.ItemUtil"] = true,
    ["app.EquipDef.EquipWorkInfo"] = true,
    ["app.EquipDef.EquipSet"] = true,
    ["app.GUIManager"] = true,
}

-- GUI seed types (app.GUI080001 is likely the View/Sell Equipment list): every
-- method is traced except property getters and names that suggest per-frame work.
local GUI_SEEDS = { ["app.GUI080001"] = true }
local PER_FRAME_WORDS = { "update", "draw", "visible", "render", "tick", "anim", "late" }

-- Static utilities whose one-argument cEquipWork methods are tried as decoders.
local DECODER_TYPES = { "app.AmuletUtil", "app.AmuletJudgeUtil", "app.EquipUtil" }

local LIST_KEYWORDS = {
    "sell", "sale", "price", "money", "zenny", "remove", "delete", "erase", "lock", "auto",
    "dispose", "discard", "consume", "save", "fitting", "myset", "loadout", "box", "judge",
}

local TRACE_KEYWORDS = {
    "sell", "sale", "price", "money", "remove", "delete", "erase", "dispose", "discard",
    "consume", "save", "decide", "execute",
}

-- Words that make a convert/create/make method unsafe to call from the probe.
local IMPURE_WORDS = {
    "set", "add", "remove", "sell", "delete", "update", "request", "apply", "save",
    "clear", "change", "exec", "erase", "write", "reset",
}

local SKIPPED_METHODS = {
    [".ctor"] = true, [".cctor"] = true, ["Finalize"] = true, ["Equals"] = true,
    ["GetHashCode"] = true, ["ToString"] = true, ["GetType"] = true, ["MemberwiseClone"] = true,
}

local STOP_TYPES = { ["System.Object"] = true, ["System.ValueType"] = true, ["via.clr.ManagedObject"] = true }

-- Boxed primitives keep their value in m_value.
local BOXED = {
    ["System.Boolean"] = true, ["System.Byte"] = true, ["System.SByte"] = true,
    ["System.Int16"] = true, ["System.UInt16"] = true, ["System.Int32"] = true, ["System.UInt32"] = true,
    ["System.Int64"] = true, ["System.UInt64"] = true, ["System.Single"] = true, ["System.Double"] = true,
}

local INT_MASKS = {
    ["System.Byte"] = { 0xFF, false }, ["System.SByte"] = { 0xFF, true },
    ["System.Int16"] = { 0xFFFF, true }, ["System.UInt16"] = { 0xFFFF, false },
    ["System.Int32"] = { 0xFFFFFFFF, true }, ["System.UInt32"] = { 0xFFFFFFFF, false },
}

local state = {
    status = "idle",
    zenny_text = "",
    last_file = nil,
    hooks_installed = false,
    armed = false,
    hooked = 0,
    hook_errors = {},
    trace = {},
    counts = {},
    gui_methods = nil,
}

local function info(message)
    log.info("[BulkSellProbe] " .. message)
end

-- `ok and value or fallback` breaks when value is false, so use this instead.
local function either(ok, value, fallback)
    if ok then return value end
    return fallback
end

local function dump(path, data)
    local ok, result = pcall(json.dump_file, path, data, 2)
    if ok and result ~= false then return true end
    ok, result = pcall(json.dump_file, path, data)
    return ok and result ~= false
end

-- Falls back to the data root when json.dump_file cannot create OUT_DIR
-- (the result also tells us how the real mod must store its files).
local function write_json(name, data)
    local file = name .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local path = OUT_DIR .. file
    data.written_to_subfolder = true
    if not dump(path, data) then
        path = "BulkSellProbe_" .. file
        data.written_to_subfolder = false
        assert(dump(path, data), "json.dump_file failed for " .. path)
    end
    state.last_file = path
    info("wrote " .. path)
    return path
end

local function full_name(td)
    if not td then return "?" end
    local ok, name = pcall(td.get_full_name, td)
    return ok and name or "?"
end

local function type_of(value)
    if type(value) ~= "userdata" then return nil end
    local ok, td = pcall(function() return value:get_type_definition() end)
    if ok then return td end
    return nil
end

local function matches(name, keywords)
    local lower = name:lower()
    for _, keyword in ipairs(keywords) do
        if lower:find(keyword, 1, true) then return true end
    end
    return false
end

local function listed(name) return matches(name, LIST_KEYWORDS) end
local function traced(name) return matches(name, TRACE_KEYWORDS) end

local function instance_fields(td)
    local result = {}
    local current = td
    while current and not STOP_TYPES[full_name(current)] do
        for _, field in ipairs(current:get_fields() or {}) do
            if not field:is_static() then result[#result + 1] = field end
        end
        current = current:get_parent_type()
    end
    return result
end

local function is_enum(td)
    local parent = td and td:get_parent_type()
    return parent ~= nil and full_name(parent) == "System.Enum"
end

local function is_static(method)
    local ok, value = pcall(method.is_static, method)
    return ok and value == true
end

-- JSON-friendly copy of a value. Managed objects become "<TypeName>".
local function plain(value)
    local kind = type(value)
    if kind == "nil" then return "<nil>" end
    if kind == "number" or kind == "boolean" or kind == "string" then return value end
    local td = type_of(value)
    if td then
        local name = full_name(td)
        if BOXED[name] then
            local ok, inner = pcall(function() return value:get_field("m_value") end)
            if ok and inner ~= nil and type(inner) ~= "userdata" then return inner end
        elseif name == "System.String" then
            local ok, text = pcall(function() return value:call("ToString()") end)
            if ok and text then return text end
        end
        return "<" .. name .. ">"
    end
    return tostring(value)
end

-- Returns size and an element getter for managed arrays and generic lists.
local function collection(obj)
    local name = full_name(type_of(obj))
    if name:sub(-2) == "[]" then
        local ok, size = pcall(function() return obj:get_size() end)
        if ok and size then return size, function(i) return obj:get_element(i) end end
    elseif name:find("System.Collections.Generic.List`1", 1, true) == 1 then
        local ok, size = pcall(function() return obj:call("get_Count") end)
        if ok and size then return size, function(i) return obj:call("get_Item", i) end end
    end
    return nil
end

-- Like plain(), but small collections are expanded into their values.
local function row_value(value)
    local size, get = collection(value)
    if size and size <= PREVIEW_ITEMS then
        local items = {}
        for i = 0, size - 1 do
            local ok, item = pcall(get, i)
            items[#items + 1] = either(ok, plain(item), "<error>")
        end
        return items
    end
    return plain(value)
end

local function address(obj)
    local ok, value = pcall(function() return obj:get_address() end)
    return ok and value or nil
end

local function reflect(obj, depth, seen)
    local td = type_of(obj)
    if not td or BOXED[full_name(td)] then return plain(obj) end
    seen = seen or {}
    local addr = address(obj)
    if addr then
        if seen[addr] then return "<seen " .. full_name(td) .. ">" end
        seen[addr] = true
    end

    local node = { type = full_name(td) }
    local size, get = collection(obj)
    if size then
        node.size = size
        if depth > 0 then
            node.items = {}
            for i = 0, math.min(size, PREVIEW_ITEMS) - 1 do
                local ok, item = pcall(get, i)
                node.items[#node.items + 1] = either(ok, ok and reflect(item, depth - 1, seen), "<error>")
            end
        end
        return node
    end

    node.fields = {}
    for _, field in ipairs(instance_fields(td)) do
        local entry = { name = field:get_name(), type = full_name(field:get_type()) }
        local ok, value = pcall(field.get_data, field, obj)
        if not ok then
            entry.error = tostring(value)
        elseif depth > 0 and type_of(value) then
            entry.value = reflect(value, depth - 1, seen)
        else
            entry.value = row_value(value)
        end
        node.fields[#node.fields + 1] = entry
    end
    return node
end

local function current_save()
    local manager = assert(sdk.get_managed_singleton("app.SaveDataManager"), "SaveDataManager not ready")
    local td = sdk.find_type_definition("app.SaveDataManager")
    local getter = assert(td:get_method("getCurrentUserSaveData()"), "getCurrentUserSaveData() missing")
    return manager, assert(getter:call(manager), "no current user save (still on title screen?)")
end

-- Follows a chain of field names; nil when any step is missing.
local function walk_fields(obj, ...)
    for _, name in ipairs({ ... }) do
        if obj == nil then return nil end
        local ok, value = pcall(function() return obj:get_field(name) end)
        if not ok then return nil end
        obj = value
    end
    return obj
end

-- Plain values of a collection (up to limit), or plain(value) for anything else.
local function values_of(value, limit)
    local size, get = collection(value)
    if not size then return plain(value) end
    local items = {}
    for i = 0, math.min(size, limit or 64) - 1 do
        local ok, item = pcall(get, i)
        items[#items + 1] = either(ok, plain(item), "<error>")
    end
    return items
end

-- Full contents of every ace.Bitset field (favorite/lock flags may live in one).
local function dump_bitsets(obj)
    local result = {}
    for _, field in ipairs(instance_fields(type_of(obj))) do
        if full_name(field:get_type()) == "ace.Bitset" then
            local ok, bitset = pcall(field.get_data, field, obj)
            if ok and type_of(bitset) then
                local inner = { _type = "ace.Bitset" }
                for _, f in ipairs(instance_fields(type_of(bitset))) do
                    local value_ok, value = pcall(f.get_data, f, bitset)
                    if value_ok then inner[f:get_name()] = values_of(value, 4096) end
                end
                result[field:get_name()] = inner
            end
        end
    end
    return result
end

-- Box indices used by each saved loadout (field names from the RSZ dump).
local function dump_loadouts(equip)
    local loadouts = {}
    local size, get = collection(walk_fields(equip, "_EquipMySet"))
    for i = 0, (size or 0) - 1 do
        local ok, myset = pcall(get, i)
        if ok and myset ~= nil then
            local param = walk_fields(myset, "_MysetParam")
            loadouts[#loadouts + 1] = {
                slot = i,
                empty = plain(walk_fields(param, "IsEmpty")),
                name = plain(walk_fields(param, "MysetName")),
                index = values_of(walk_fields(param, "_EquipIndex", "Index")),
            }
        end
    end
    return loadouts
end

local function field_of_type(obj, type_name)
    for _, field in ipairs(instance_fields(type_of(obj))) do
        if full_name(field:get_type()) == type_name then
            return field:get_data(obj), field:get_name()
        end
    end
    return nil
end

local function category_of(work)
    local ok, category = pcall(function() return work:call("get_Category") end)
    return either(ok, plain(category), "?")
end

-- Compact dump of every collection in the equip param whose elements are equip works.
-- Also returns up to SAMPLE_AMULETS amulet works (category 2) with their box index.
local function dump_work_collections(equip)
    local result, amulets = {}, {}
    for _, field in ipairs(instance_fields(type_of(equip))) do
        local ok, value = pcall(field.get_data, field, equip)
        local size, get = nil, nil
        if ok and value ~= nil then size, get = collection(value) end
        if size and size > 0 then
            local first
            for i = 0, size - 1 do
                local item_ok, item = pcall(get, i)
                if item_ok and type_of(item) then
                    first = item
                    break
                end
            end
            local element_type = first and full_name(type_of(first)) or "?"
            if element_type:find("EquipWork", 1, true) then
                local fields = instance_fields(type_of(first))
                local names = {}
                for i, f in ipairs(fields) do names[i] = f:get_name() end
                local rows, categories = {}, {}
                for i = 0, size - 1 do
                    local item_ok, work = pcall(get, i)
                    if item_ok and type_of(work) then
                        local category = category_of(work)
                        local row = { i, category }
                        for j, f in ipairs(fields) do
                            local value_ok, field_value = pcall(f.get_data, f, work)
                            row[j + 2] = either(value_ok, row_value(field_value), "<error>")
                        end
                        local key = tostring(category)
                        categories[key] = (categories[key] or 0) + 1
                        rows[#rows + 1] = row
                        if category == 2 and #amulets < SAMPLE_AMULETS then
                            amulets[#amulets + 1] = { field = field:get_name(), index = i, work = work }
                        end
                    end
                end
                table.insert(names, 1, "get_Category()")
                table.insert(names, 1, "index")
                result[#result + 1] = {
                    field = field:get_name(),
                    element_type = element_type,
                    size = size,
                    columns = names,
                    categories = categories,
                    rows = rows,
                }
            end
        end
    end
    return result, amulets
end

local function looks_pure(name)
    local lower = name:lower()
    for _, prefix in ipairs({ "get", "is", "calc", "check" }) do
        if lower:sub(1, #prefix) == prefix then return true end
    end
    for _, prefix in ipairs({ "convert", "to", "create", "make" }) do
        if lower:sub(1, #prefix) == prefix then return not matches(name, IMPURE_WORDS) end
    end
    return false
end

local function signature(method)
    local params = {}
    local ok, types = pcall(method.get_param_types, method)
    if ok and types then
        for _, t in ipairs(types) do params[#params + 1] = full_name(t) end
    end
    return method:get_name() .. "(" .. table.concat(params, ", ") .. ")"
end

-- Calls side-effect-free looking methods on sample amulet works to learn how
-- skills, slots and rarity can be read: zero-argument getters on the work itself
-- and one-argument static cEquipWork methods of the decoder utilities.
local function probe_amulets(amulets)
    local decoders = {}
    for _, type_name in ipairs(DECODER_TYPES) do
        local td = sdk.find_type_definition(type_name)
        for _, method in ipairs(td and td:get_methods() or {}) do
            local ok, params = pcall(method.get_param_types, method)
            if ok and params and #params == 1 and full_name(params[1]) == "app.savedata.cEquipWork"
                and is_static(method) and full_name(method:get_return_type()) ~= "System.Void"
                and looks_pure(method:get_name()) then
                decoders[#decoders + 1] = { label = type_name .. "::" .. signature(method), method = method }
            end
        end
    end

    local samples = {}
    for _, amulet in ipairs(amulets) do
        local work = amulet.work
        local sample = { field = amulet.field, index = amulet.index, work = reflect(work, 1), getters = {}, decoders = {} }
        for _, method in ipairs(type_of(work):get_methods() or {}) do
            local name = method:get_name()
            local ok, params = pcall(method.get_param_types, method)
            if ok and params and #params == 0 and not is_static(method) and not SKIPPED_METHODS[name]
                and full_name(method:get_return_type()) ~= "System.Void" and looks_pure(name) then
                local call_ok, value = pcall(method.call, method, work)
                sample.getters[signature(method)] = either(call_ok, call_ok and reflect(value, 2), "<error " .. tostring(value) .. ">")
            end
        end
        for _, decoder in ipairs(decoders) do
            local call_ok, value = pcall(decoder.method.call, decoder.method, nil, work)
            sample.decoders[decoder.label] = either(call_ok, call_ok and reflect(value, 2), "<error " .. tostring(value) .. ">")
        end
        samples[#samples + 1] = sample
    end
    return samples
end

-- Finds money-like fields by name, and numeric fields equal to the zenny shown in game.
local function search_money(root, target)
    local hits, seen = {}, {}
    local function walk(obj, path, depth)
        local td = type_of(obj)
        local addr = address(obj)
        if not td or depth > 3 or (addr and seen[addr]) then return end
        if addr then seen[addr] = true end
        local size, get = collection(obj)
        if size then
            for i = 0, math.min(size, 16) - 1 do
                local ok, item = pcall(get, i)
                if ok then walk(item, path .. "[" .. i .. "]", depth + 1) end
            end
            return
        end
        for _, field in ipairs(instance_fields(td)) do
            local name = field:get_name()
            local ok, value = pcall(field.get_data, field, obj)
            if ok then
                local child = path .. "." .. name
                local named = matches(name, { "money", "zenny", "point" })
                local number = plain(value)
                if named or (target and type(number) == "number" and number == target) then
                    hits[#hits + 1] = { path = child, type = full_name(field:get_type()), value = number, by_value = not named }
                end
                if type_of(value) and not BOXED[full_name(type_of(value))] then walk(value, child, depth + 1) end
            end
        end
    end
    walk(root, "save", 0)
    return hits
end

local function snapshot()
    local manager, save = current_save()
    local report = {
        note = "BulkSell probe snapshot",
        manager_slot = plain(manager:get_field("CurrentUserDataIndex")),
        save = reflect(save, 1),
    }
    local equip, equip_field = field_of_type(save, "app.savedata.cEquipParam")
    report.equip_field = equip_field or "<not found>"
    if equip then
        report.equip = reflect(equip, 1)
        report.equipped_index = values_of(walk_fields(equip, "_EquipIndex", "Index"))
        report.loadouts = dump_loadouts(equip)
        report.equip_bitsets = dump_bitsets(equip)
        local amulets
        report.boxes, amulets = dump_work_collections(equip)
        report.amulet_samples = probe_amulets(amulets)
    end
    local basic = walk_fields(save, "_BasicData")
    local money_ok, money = pcall(function() return basic:call("getMoney()") end)
    report.money_api = either(money_ok, plain(money), "<error " .. tostring(money) .. ">")
    report.money = search_money(save, tonumber(state.zenny_text))
    write_json("snapshot", report)
end

local function describe_methods(td, filter)
    local list = {}
    for _, method in ipairs(td:get_methods() or {}) do
        if not filter or filter(method:get_name()) then
            local prefix = is_static(method) and "static " or ""
            list[#list + 1] = prefix .. full_name(method:get_return_type()) .. " " .. signature(method)
        end
    end
    table.sort(list)
    return list
end

local function describe_fields(td)
    local list = {}
    for _, field in ipairs(td:get_fields() or {}) do
        local prefix = field:is_static() and "static " or ""
        list[#list + 1] = prefix .. full_name(field:get_type()) .. " " .. field:get_name()
    end
    return list
end

-- app.* type names referenced by fields and method signatures of a type.
local function related_types(td)
    local names = {}
    local function add(type_name)
        for name in type_name:gmatch("app%.[%w_%.]+") do names[name] = true end
    end
    for _, field in ipairs(td:get_fields() or {}) do add(full_name(field:get_type())) end
    for _, method in ipairs(td:get_methods() or {}) do
        add(full_name(method:get_return_type()))
        local ok, types = pcall(method.get_param_types, method)
        if ok and types then
            for _, t in ipairs(types) do add(full_name(t)) end
        end
    end
    return names
end

-- GUI classes are named app.GUI + six digits (app.GUI080000 = Change Equipment,
-- app.GUI090700 = Melding Pot). Returns found names and their keyword methods.
local function scan_gui_types()
    local found, methods = {}, {}
    for category = 0, 12 do
        for sub = 0, 999 do
            local name = string.format("app.GUI%02d%04d", category, sub)
            local td = sdk.find_type_definition(name)
            if td then
                found[#found + 1] = name
                local list = describe_methods(td, listed)
                if #list > 0 then methods[name] = list end
            end
        end
    end
    return found, methods
end

local function dump_methods()
    local report = { seeds = {}, seed_fields = {}, related = {}, missing = {} }
    local queue, queued = {}, {}
    for _, name in ipairs(SEED_TYPES) do
        local td = sdk.find_type_definition(name)
        if td then
            report.seeds[name] = describe_methods(td)
            report.seed_fields[name] = describe_fields(td)
            queued[name] = true
            for related in pairs(related_types(td)) do
                if not queued[related] then
                    queued[related] = true
                    queue[#queue + 1] = related
                end
            end
        else
            report.missing[#report.missing + 1] = name
        end
    end

    -- One more hop: list keyword methods of every related app.* type.
    local index = 1
    while index <= #queue and index <= RELATED_TYPE_LIMIT do
        local td = sdk.find_type_definition(queue[index])
        if td then
            local list = describe_methods(td, listed)
            if #list > 0 then report.related[queue[index]] = list end
        end
        index = index + 1
    end
    report.related_checked = math.min(#queue, RELATED_TYPE_LIMIT)
    report.related_total = #queue

    report.gui_types, report.gui_methods = scan_gui_types()
    state.gui_methods = report.gui_methods
    write_json("methods", report)
end

local function decode(raw, td)
    if raw == nil then return "<nil>" end
    local name = full_name(td)
    if name == "System.Void" then return nil end
    local ok, result = pcall(function()
        if name == "System.Boolean" then return (sdk.to_int64(raw) & 0xFF) ~= 0 end
        local mask = INT_MASKS[name]
        if mask then
            local value = sdk.to_int64(raw) & mask[1]
            if mask[2] and value > (mask[1] >> 1) then value = value - mask[1] - 1 end
            return value
        end
        if name == "System.Int64" or name == "System.UInt64" then return sdk.to_int64(raw) end
        if name == "System.Single" then return sdk.to_float(raw) end
        if is_enum(td) then return sdk.to_int64(raw) & 0xFFFFFFFF end
        if td and td:is_value_type() then return "<struct " .. name .. ">" end
        local obj = sdk.to_managed_object(raw)
        if obj == nil then return "<null>" end
        return plain(obj)
    end)
    return either(ok, result, "<undecoded " .. name .. ">")
end

local function hook_method(td, method)
    local label = full_name(td) .. "::" .. signature(method)
    local first_param = is_static(method) and 2 or 3
    local param_types = method:get_param_types() or {}
    local return_type = method:get_return_type()

    local ok, err = pcall(sdk.hook, method, function(args)
        if not state.armed then return end
        local count = (state.counts[label] or 0) + 1
        state.counts[label] = count
        if count > TRACE_PER_METHOD or #state.trace >= TRACE_LIMIT then return end
        local record = { seq = #state.trace + 1, clock = os.clock(), method = label, args = {} }
        if first_param == 3 then record.this = plain(sdk.to_managed_object(args[2])) end
        for i, param_type in ipairs(param_types) do
            record.args[i] = decode(args[first_param + i - 1], param_type)
        end
        state.trace[#state.trace + 1] = record
        thread.get_hook_storage().bulksell_probe = record
    end, function(retval)
        if state.armed then
            local storage = thread.get_hook_storage()
            local record = storage and storage.bulksell_probe
            if record then
                record.ret = decode(retval, return_type)
                storage.bulksell_probe = nil
            end
        end
        return retval
    end)

    if ok then
        state.hooked = state.hooked + 1
    else
        state.hook_errors[#state.hook_errors + 1] = label .. ": " .. tostring(err)
    end
end

local function traceable(name)
    return not SKIPPED_METHODS[name] and name:sub(1, 4) ~= "get_"
end

local function install_trace_hooks()
    for _, type_name in ipairs(SEED_TYPES) do
        local td = sdk.find_type_definition(type_name)
        if td then
            for _, method in ipairs(td:get_methods() or {}) do
                local name = method:get_name()
                local wanted
                if KEYWORD_ONLY_TRACE[type_name] then
                    wanted = traced(name)
                elseif GUI_SEEDS[type_name] then
                    wanted = not matches(name, PER_FRAME_WORDS)
                else
                    wanted = true
                end
                if wanted and traceable(name) then hook_method(td, method) end
            end
        end
    end

    -- GUI types with any sell-related method get their decide/execute/sell methods traced.
    if not state.gui_methods then
        local _, methods = scan_gui_types()
        state.gui_methods = methods
    end
    for type_name, list in pairs(state.gui_methods) do
        local sells = false
        for _, entry in ipairs(list) do
            if entry:lower():find("sell", 1, true) then sells = true end
        end
        if sells then
            local td = sdk.find_type_definition(type_name)
            for _, method in ipairs(td:get_methods() or {}) do
                local name = method:get_name()
                if traceable(name) and traced(name) then hook_method(td, method) end
            end
        end
    end

    state.hooks_installed = true
    info(string.format("trace hooks installed=%d failed=%d", state.hooked, #state.hook_errors))
end

-- Selling rate (getEquipSellingRate / getEquipSellingRateAll) of every amulet in the box,
-- next to its raw fields, to find out what makes the rate differ between talismans.
local function dump_rates()
    local _, save = current_save()
    local box = walk_fields(save, "_Equip", "_EquipBox")
    local util = assert(sdk.find_type_definition("app.EquipUtil"), "EquipUtil missing")
    local get_set = assert(util:get_method("getEquipSet(System.Int32)"), "getEquipSet missing")
    local rate = assert(util:get_method("getEquipSellingRate(app.EquipDef.EquipSet)"), "getEquipSellingRate missing")
    local rate_all = util:get_method("getEquipSellingRateAll(app.EquipDef.EquipSet)")
    local size, get = collection(box)
    assert(size, "Equipment Box not found")
    local rows = {}
    for i = 0, size - 1 do
        local ok, row = pcall(function()
            local work = get(i)
            if category_of(work) ~= 2 then return nil end
            local set = get_set:call(nil, i)
            return {
                i,
                plain(work:get_field("FreeVal0")),
                plain(work:get_field("FreeVal1")),
                values_of(work:get_field("BowgunCustomizeId")),
                plain(set:call("get_WorkInfo"):call("get_BoxIndex")),
                plain(rate:call(nil, set)),
                rate_all and plain(rate_all:call(nil, set)) or "<missing>",
            }
        end)
        if not ok then
            rows[#rows + 1] = { i, "<error " .. tostring(row) .. ">" }
        elseif row then
            rows[#rows + 1] = row
        end
    end
    write_json("rates", {
        columns = { "index", "FreeVal0", "FreeVal1", "BowgunCustomizeId", "set_box_index", "rate", "rate_all" },
        rows = rows,
    })
end

local function start_trace()
    state.trace, state.counts = {}, {}
    state.armed = true
    info("trace started")
end

local function stop_trace()
    state.armed = false
    write_json("trace", {
        hooked = state.hooked,
        hook_errors = state.hook_errors,
        counts = state.counts,
        trace = state.trace,
    })
end

local function run(label, fn)
    state.status = label .. "..."
    local ok, err = pcall(fn)
    state.status = ok and (label .. " done") or (label .. " FAILED: " .. tostring(err))
    if not ok then info(state.status) end
end

re.on_draw_ui(function()
    if not imgui.tree_node("BulkSell Probe (dev)") then return end

    imgui.text("Status: " .. state.status)
    if state.last_file then imgui.text("Last file: reframework/data/" .. state.last_file) end

    local changed, text = imgui.input_text("Zenny shown in game (optional)", state.zenny_text)
    if changed then state.zenny_text = text end

    if imgui.button("1. Snapshot save data") then run("snapshot", snapshot) end
    if imgui.button("2. Dump methods + scan GUI types") then run("methods", dump_methods) end
    if imgui.button("6. Dump selling rates") then run("rates", dump_rates) end

    if not state.hooks_installed then
        if imgui.button("3. Install trace hooks (until Reset Scripts)") then run("hooks", install_trace_hooks) end
    else
        imgui.text(string.format("Trace hooks: %d installed, %d failed", state.hooked, #state.hook_errors))
        if not state.armed then
            if imgui.button("4. Start trace") then run("trace start", start_trace) end
        else
            imgui.text_colored("TRACE RUNNING: sell exactly ONE junk charm now", 0xFF00FFFF)
            imgui.text(string.format("Recorded calls: %d", #state.trace))
            if imgui.button("5. Stop trace and save") then run("trace stop", stop_trace) end
        end
    end

    imgui.tree_pop()
end)
