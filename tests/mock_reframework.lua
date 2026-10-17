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

-- Every call into fake game objects is counted, so tests can prove that nothing
-- touches the game (for example while the REFramework menu is closed). With
-- env.guard_draw set, any game call while env.draw runs a UI frame is an error: the
-- mod's UI must only read Lua state (the old dev probe does not follow that rule).
M.game_calls = 0
M.in_draw = false
local function game_call()
    if M.in_draw then error("game call while drawing the UI", 3) end
    M.game_calls = M.game_calls + 1
end

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
    function td:get_field(name) return self.field_by_name and self.field_by_name[name] end
    M.types[name] = td
    return td
end

-- Static fields read their value from `static_value` (get_data(nil)).
function M.add_field(td, name, type_name, static, static_value)
    local field = { name = name, type_name = type_name, static = static == true, static_value = static_value }
    function field:get_name() return self.name end
    function field:get_type() return M.types[self.type_name] end
    function field:is_static() return self.static end
    function field:get_data(obj)
        game_call()
        if self.static then return self.static_value end
        return obj.values[self.name]
    end
    td.fields[#td.fields + 1] = field
    td.field_by_name = td.field_by_name or {}
    td.field_by_name[name] = field
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
    function method:call(obj, ...)
        game_call()
        return self.impl(obj, ...)
    end
    td.methods[#td.methods + 1] = method
    return method
end

function M.new_object(type_name, values)
    next_address = next_address + 0x10
    local obj = { [MOCK] = true, td = assert(M.types[type_name], type_name), values = values or {}, address = next_address }
    function obj:get_type_definition() return self.td end
    function obj:get_address() return self.address end
    function obj:get_field(name)
        game_call()
        return self.values[name]
    end
    function obj:call(sig, ...)
        game_call()
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
    function obj:get_size()
        game_call()
        return #self.items
    end
    function obj:get_element(i)
        game_call()
        return self.items[i + 1]
    end
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

local function eq_depth(env)
    if env.disabled ~= 0 then error("begin_disabled / end_disabled not balanced", 3) end
end

-- Installs fake REFramework globals and returns the recorder used by tests.
function M.install()
    local env = {
        written = {}, files = {}, hooks = {}, pressed = {}, inputs = {}, texts = {},
        callbacks = {}, entries = {}, singletons = {}, logs = {}, storage = {},
        drawing_ui = true, load_file_calls = 0, glob_calls = 0,
        raw = {}, parsed = {},   -- files as text for fs.read, and what json.load_string makes of a text
        disabled = 0,            -- begin_disabled depth: buttons and checkboxes do nothing inside
        hover = false,           -- what is_item_hovered answers
        tooltips = {},
        buttons = {}, combos = {},   -- what the last env.draw drew
    }
    fs = nil

    local function input(label, value)
        local new_value = env.inputs[label]
        if new_value ~= nil then
            env.inputs[label] = nil
            if env.disabled > 0 then return false, value end
            return true, new_value
        end
        return false, value
    end

    sdk = {
        find_type_definition = function(name)
            game_call()
            return M.types[name]
        end,
        get_managed_singleton = function(name)
            game_call()
            return env.singletons[name]
        end,
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
    reframework = { is_drawing_ui = function() return env.drawing_ui end }
    imgui = setmetatable({
        tree_node = function() return true end,
        -- env.close_window = "<title>" makes that window report one close click.
        begin_window = function(title, open)
            if env.close_window == title then
                env.close_window = nil
                return false
            end
            return open
        end,
        begin_table = function() return true end,
        button = function(label)
            env.buttons[label] = true
            if env.pressed[label] then
                env.pressed[label] = nil
                return env.disabled == 0
            end
            return false
        end,
        begin_disabled = function() env.disabled = env.disabled + 1 end,
        end_disabled = function() env.disabled = env.disabled - 1 end,
        collapsing_header = function() return true end,
        is_item_hovered = function() return env.hover end,
        set_tooltip = function(text) env.tooltips[#env.tooltips + 1] = text end,
        checkbox = input,
        slider_int = input,
        combo = function(label, value, items)
            env.combos[label] = items
            return input(label, value)
        end,
        input_text = input,
        text = function(text) env.texts[#env.texts + 1] = text end,
        text_colored = function(text) env.texts[#env.texts + 1] = text end,
    }, { __index = function() return function() end end })
    json = {
        load_file = function(path)
            env.load_file_calls = env.load_file_calls + 1
            return env.files[path]
        end,
        dump_file = function(path, data)
            env.written[#env.written + 1] = { path = path, data = data }
            env.files[path] = data
            if fs then env.put_raw(path, "json:" .. path .. ":" .. #env.written, data) end
            return true
        end,
    }

    -- Stores a file as text. `value` is what json.load_string returns for that text
    -- (nil = the text is not valid JSON).
    function env.put_raw(path, text, value)
        env.raw[path] = text
        if value ~= nil then env.parsed[text] = value end
    end

    -- Turns on fs.read/fs.glob/json.load_string, as in current REFramework builds.
    -- fs.glob answers with backslash paths, like it does on Windows.
    -- Enough of std::regex for the patterns the mod uses: "\." , "[\\/]" , ".*", "^", "$".
    local function regex_to_lua(regex)
        return (regex:gsub("%-", "%%-"):gsub("\\%.", "%%."):gsub("%[\\\\/%]", "[\\/]"))
    end

    function env.enable_fs()
        fs = {
            read = function(path) return env.raw[path] or "" end,
            glob = function(pattern)
                env.glob_calls = env.glob_calls + 1
                -- "^(?:a|b)$" is tried as "^a$" and "^b$".
                local alternatives = {}
                local inner = pattern:match("^%^%(%?:(.*)%)%$$")
                if inner then
                    for part in (inner .. "|"):gmatch("(.-)|") do alternatives[#alternatives + 1] = regex_to_lua("^" .. part .. "$") end
                else
                    alternatives[1] = regex_to_lua(pattern)
                end
                local matches = {}
                for path in pairs(env.raw) do
                    for _, lua_pattern in ipairs(alternatives) do
                        if path:find(lua_pattern) then
                            matches[#matches + 1] = (path:gsub("/", "\\"))
                            break
                        end
                    end
                end
                return matches
            end,
        }
        json.load_string = function(text) return env.parsed[text] end
        for path, data in pairs(env.files) do
            if not env.raw[path] then env.put_raw(path, "json:" .. path, data) end
        end
    end

    function env.game_calls() return M.game_calls end
    log = {}
    for _, level in ipairs({ "info", "warn", "error", "debug" }) do
        log[level] = function(message) env.logs[#env.logs + 1] = level .. ": " .. tostring(message) end
    end
    thread = { get_hook_storage = function() return env.storage end }

    -- Presses a button (or sets an input) and draws one REFramework UI frame.
    function env.draw(pressed, inputs)
        for _, label in ipairs(pressed or {}) do env.pressed[label] = true end
        for label, value in pairs(inputs or {}) do env.inputs[label] = value end
        env.texts, env.tooltips, env.buttons, env.combos = {}, {}, {}, {}
        M.in_draw = env.guard_draw == true
        local ok, err = pcall(env.callbacks.draw_ui)
        M.in_draw = false
        if not ok then error(err, 2) end
        eq_depth(env)
        for label in pairs(env.pressed) do error("button not drawn: " .. label, 2) end
        for label in pairs(env.inputs) do error("input not drawn: " .. label, 2) end
    end

    -- A fake os.clock: env.advance(seconds) moves it, so delays and timeouts can be tested.
    function env.use_fake_clock()
        env.now = 1000
        os.clock = function() return env.now end
        function env.advance(seconds) env.now = env.now + seconds end
    end

    -- Plain-text search (no Lua patterns).
    function env.has(text)
        for _, line in ipairs(env.texts) do
            if tostring(line):find(text, 1, true) then return true end
        end
        return false
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
