-- Minimal fake of the REFramework Lua API for offline smoke tests.
-- It proves code paths run without Lua errors; real game behaviour can only be checked in game.

local M = {}

local real_type = type
local MOCK = {}
M.real_type = real_type

-- Game objects are userdata in REFramework; mock objects are tables flagged with MOCK.
type = function(value)
    if real_type(value) == "table" and rawget(value, MOCK) then return "userdata" end
    return real_type(value)
end

M.types = {}
local next_address = 0x1000

function M.new_type(name, spec)
    spec = spec or {}
    local td = { name = name, fields = {}, methods = {}, parent = spec.parent, value_type = spec.value_type }
    function td:get_full_name() return self.name end
    function td:get_fields() return self.fields end
    function td:get_methods() return self.methods end
    function td:get_parent_type() return self.parent and M.types[self.parent] end
    function td:is_value_type() return self.value_type == true end
    function td:get_method(sig)
        for _, m in ipairs(self.methods) do
            if m.sig == sig or m.name == sig then return m end
        end
    end
    M.types[name] = td
    return td
end

function M.add_field(td, name, type_name, static)
    local field = { name = name, type_name = type_name, static = static == true }
    function field:get_name() return self.name end
    function field:get_type() return M.types[self.type_name] end
    function field:is_static() return self.static end
    function field:get_data(obj) return obj.values[self.name] end
    td.fields[#td.fields + 1] = field
end

function M.add_method(td, name, return_type, params, impl, static)
    local method = { name = name, return_type = return_type, params = params or {}, impl = impl, static = static == true }
    method.sig = name .. "(" .. table.concat(method.params, ", ") .. ")"
    function method:get_name() return self.name end
    function method:get_return_type() return M.types[self.return_type] end
    function method:get_param_types()
        local list = {}
        for i, p in ipairs(self.params) do list[i] = M.types[p] end
        return list
    end
    function method:is_static() return self.static end
    function method:call(obj, ...) return self.impl(obj, ...) end
    td.methods[#td.methods + 1] = method
    return method
end

function M.new_object(type_name, values)
    next_address = next_address + 0x10
    local obj = { [MOCK] = true, td = assert(M.types[type_name], type_name), values = values or {}, address = next_address }
    function obj:get_type_definition() return self.td end
    function obj:get_address() return self.address end
    function obj:get_field(name) return self.values[name] end
    function obj:call(sig, ...)
        local current = self.td
        while current do
            local method = current:get_method(sig)
            if method then return method.impl(self, ...) end
            current = current:get_parent_type()
        end
        error("mock method missing: " .. sig)
    end
    return obj
end

function M.new_array(element_type, items)
    if not M.types[element_type .. "[]"] then M.new_type(element_type .. "[]", { parent = "System.Object" }) end
    local obj = M.new_object(element_type .. "[]")
    obj.items = items
    function obj:get_size() return #self.items end
    function obj:get_element(i) return self.items[i + 1] end
    return obj
end

-- Array of boxed integers, the way REFramework returns primitive array elements.
function M.boxed_array(type_name, values)
    local items = {}
    for i, v in ipairs(values) do items[i] = M.new_object(type_name, { m_value = v }) end
    return M.new_array(type_name, items)
end

function M.string(text)
    local obj = M.new_object("System.String")
    obj.text = text
    return obj
end

for _, name in ipairs({ "System.Object", "System.Void", "System.Int16", "System.Int32", "System.UInt32",
    "System.Boolean", "System.String", "System.Enum", "System.Guid" }) do
    M.new_type(name)
end
M.new_type("System.ValueType", { parent = "System.Object" })
M.add_method(M.types["System.String"], "ToString", "System.String", {}, function(self) return self.text end)

-- Installs fake REFramework globals and returns the recorder used by tests.
function M.install()
    local env = {
        written = {}, files = {}, hooks = {}, pressed = {}, inputs = {}, texts = {},
        callbacks = {}, entries = {}, singletons = {}, logs = {}, storage = {},
    }

    local function input(label, value)
        local new_value = env.inputs[label]
        if new_value ~= nil then
            env.inputs[label] = nil
            return true, new_value
        end
        return false, value
    end

    sdk = {
        find_type_definition = function(name) return M.types[name] end,
        get_managed_singleton = function(name) return env.singletons[name] end,
        hook = function(method, pre, post) env.hooks[#env.hooks + 1] = { method = method, pre = pre, post = post } end,
        to_int64 = function(raw) return raw end,
        to_float = function(raw) return raw end,
        to_managed_object = function(raw) if real_type(raw) == "table" then return raw end end,
        PreHookResult = { CALL_ORIGINAL = 0, SKIP_ORIGINAL = 1 },
    }
    re = {
        on_draw_ui = function(fn) env.callbacks.draw_ui = fn end,
        on_frame = function(fn) env.callbacks.frame = fn end,
        on_config_save = function(fn) env.callbacks.config_save = fn end,
        on_script_reset = function(fn) env.callbacks.script_reset = fn end,
        on_pre_application_entry = function(name, fn) env.entries[name] = fn end,
        on_application_entry = function(name, fn) env.entries["post:" .. name] = fn end,
    }
    reframework = { is_drawing_ui = function() return true end }
    imgui = setmetatable({
        tree_node = function() return true end,
        begin_window = function(_, open) return open end,
        begin_table = function() return true end,
        button = function(label)
            if env.pressed[label] then
                env.pressed[label] = nil
                return true
            end
            return false
        end,
        checkbox = input,
        slider_int = input,
        combo = input,
        input_text = input,
        text = function(text) env.texts[#env.texts + 1] = text end,
        text_colored = function(text) env.texts[#env.texts + 1] = text end,
    }, { __index = function() return function() end end })
    json = {
        load_file = function(path) return env.files[path] end,
        dump_file = function(path, data)
            env.written[#env.written + 1] = { path = path, data = data }
            env.files[path] = data
            return true
        end,
    }
    log = {}
    for _, level in ipairs({ "info", "warn", "error", "debug" }) do
        log[level] = function(message) env.logs[#env.logs + 1] = level .. ": " .. tostring(message) end
    end
    thread = { get_hook_storage = function() return env.storage end }

    -- Presses a button (or sets an input) and draws one REFramework UI frame.
    function env.draw(pressed, inputs)
        for _, label in ipairs(pressed or {}) do env.pressed[label] = true end
        for label, value in pairs(inputs or {}) do env.inputs[label] = value end
        env.texts = {}
        env.callbacks.draw_ui()
        for label in pairs(env.pressed) do error("button not drawn: " .. label, 2) end
        for label in pairs(env.inputs) do error("input not drawn: " .. label, 2) end
    end

    function env.has_text(pattern)
        for _, text in ipairs(env.texts) do
            if tostring(text):find(pattern) then return true end
        end
        return false
    end

    return env
end

function M.eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

return M
