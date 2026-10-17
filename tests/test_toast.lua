-- The message shown while the REFramework menu is closed (ui.toast): game-style drawing with
-- REFramework's draw API, and the small window when that API is missing.

local support = require("analysis_support")
local eq = support.eq
local runner = support.runner()
local test = runner.test

local now = 0
os.clock = function() return now end

local calls, pushes, pops, windows = {}, 0, 0, 0
local drawing_ui = false
reframework = { is_drawing_ui = function() return drawing_ui end }
Vector2f = { new = function(x, y) return { x = x, y = y } end }
imgui = setmetatable({
    load_font = function() return 3 end,
    push_font = function(font) eq(font, 3, "the loaded font") pushes = pushes + 1 end,
    pop_font = function() pops = pops + 1 end,
    get_display_size = function() return { x = 1920, y = 1080 } end,
    calc_text_size = function() return { x = 10, y = 18 } end,
    begin_window = function() windows = windows + 1 return true end,
}, { __index = function() return function() end end })
local function fake_draw()
    draw = {}
    for _, name in ipairs({ "text", "line", "filled_quad", "filled_rect" }) do
        draw[name] = function(...) calls[#calls + 1] = { name, ... } end
    end
end
fake_draw()

local ui = require("BulkSell.ui")

local function texts()
    local out = {}
    for _, c in ipairs(calls) do
        if c[1] == "text" then out[c[2]] = c[5] end   -- text -> its colour (last one drawn)
    end
    return out
end

local function count(name)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
    return n
end

local MESSAGE = "1 new item in your Equipment Box since your last scan. Open Bulk Sell (Insert) to check."

test("drawn like the game's notices, on the right", function()
    calls, now = {}, 1
    local state = { toast = { text = MESSAGE, shown_at = 0, until_at = 12 } }
    ui.toast(state)
    local t = texts()
    assert(t["Bulk Sell"], "title")
    local body, seen = {}, {}
    for _, c in ipairs(calls) do
        if c[1] == "text" and c[2] ~= "Bulk Sell" and not seen[c[2]] then
            seen[c[2]] = true
            body[#body + 1] = c[2]
            assert(#c[2] <= 44, "short lines")
        end
    end
    eq(table.concat(body, " "), MESSAGE, "the whole message, wrapped")
    assert(#body >= 2, "on two lines or more")
    eq(t["Bulk Sell"], 0xFFFFFFFF, "full white once faded in")
    eq(count("line"), 2, "a line above and below")
    eq(count("filled_quad"), 3, "two line ends and the icon")
    eq(count("filled_rect"), 1, "a faint band behind the text")
    for _, c in ipairs(calls) do
        if c[1] == "line" then
            assert(c[2] > 1400 and c[4] > 1800, "on the right side")
        end
    end
    eq(pushes, pops, "font pushed and popped alike")
    eq(windows, 0, "no window")
    assert(state.toast, "still shown")
end)

test("fades out at the end and then goes away", function()
    calls, now = {}, 11.7
    local state = { toast = { text = MESSAGE, shown_at = 0, until_at = 12 } }
    ui.toast(state)
    local color = texts()["Bulk Sell"]
    assert(((color >> 24) & 0xFF) < 0xFF, "fading")
    now = 12.5
    ui.toast(state)
    eq(state.toast, nil, "gone")
end)

test("nothing while the REFramework menu is open", function()
    calls, now, drawing_ui = {}, 1, true
    ui.toast({ toast = { text = MESSAGE, shown_at = 0, until_at = 12 } })
    eq(#calls, 0, "not drawn")
    drawing_ui = false
end)

test("the small window when the draw API is missing", function()
    calls, now, windows = {}, 1, 0
    draw = nil
    ui.toast({ toast = { text = MESSAGE, shown_at = 0, until_at = 12 } })
    eq(windows, 1, "window instead")
    fake_draw()
end)

runner.run()
