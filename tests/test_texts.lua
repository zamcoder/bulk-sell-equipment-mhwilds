-- Texts (lang.lua, explain.lua) and box capacity.

local lang = require("BulkSell.lang")
local explain = require("BulkSell.explain")
local capacity = require("BulkSell.capacity")
local support = require("analysis_support")
local eq = support.eq
local runner = support.runner()
local test = runner.test

local SOURCES = { "BulkSell.lua", "BulkSell/ui.lua", "BulkSell/explain.lua", "BulkSell/picks.lua", "BulkSell/config.lua", "BulkSell/skills.lua", "BulkSell/stars.lua" }
local DYNAMIC = {   -- keys built at run time
    "filter_to_sell", "filter_to_keep", "filter_all", "filter_picks", "filter_unique",
    "mark_sell", "mark_keep", "mark_auto", "filter_changed", "filter_last",
    "col_skill", "col_on_talismans", "col_best_level", "col_keep", "col_after",
    "star_confirm_kept", "star_confirm_picks", "star_confirm_remove", "scope_all", "scope_stays", "scope_sell",
    "lang_game", "lang_en", "lang_ja", "lang_ko", "lang_zh_hans", "lang_zh_hant",
    "col_sell", "col_box", "col_talisman", "col_slots", "col_price", "col_verdict", "col_why",
    "why_protected_equipped", "why_protected_loadout", "why_protected_favorite", "why_protected_decorations", "why_protected_bonus",
}

test("every text key used by the code exists", function()
    local missing = {}
    for _, name in ipairs(SOURCES) do
        local file = assert(io.open(PROJECT_ROOT .. "/src/reframework/autorun/" .. name, "r"))
        local text = file:read("a")
        file:close()
        for key in text:gmatch('T%("([%w_]+)"%s*[,)]') do
            if not lang.EN[key] then missing[#missing + 1] = name .. ": " .. key end
        end
    end
    for _, key in ipairs(DYNAMIC) do
        if not lang.EN[key] then missing[#missing + 1] = "dynamic: " .. key end
    end
    eq(#missing, 0, "missing keys: " .. table.concat(missing, ", "))
end)

test("T formats and never fails", function()
    eq(lang.T("sell_all", 3), "Sell 3 talismans")
    eq(lang.T("no_such_key"), "no_such_key", "unknown key")
    eq(lang.T("sell_all", "x"), "Sell %d talismans", "bad argument keeps the template")
    eq(lang.T("ok"), "OK", "no arguments")
end)

test("every text is ASCII except the middle dot", function()
    for key, text in pairs(lang.EN) do
        local rest = text:gsub("\194\183", "")
        eq(rest:find("[\128-\255]") == nil, true, "key " .. key)
    end
end)

test("slot shapes and protected reasons read well", function()
    eq(explain.shape_label("W1|A2,1"), "W1 A2 A1")
    eq(explain.shape_label("W|A3"), "A3")
    eq(explain.shape_label("W|A"), "-")
    eq(explain.protected_text("favorite"), "Favorite: remove the star in game to sell it")
    eq(explain.protected_text("special bonus"), "RNG Charm Crafting bonus")
    eq(explain.protected_text("other"), "other")
end)

test("Why texts", function()
    local ctx = {
        names = { [10] = "Attack Boost", [20] = "Ambush" },
        by_key = { [5] = { skills_label = "R8  Attack Boost 3", skills = { { id = 10, level = 3 } } } },
        info = { lists = { [10] = { 1, 2, 3, 4 }, [20] = { 1 } }, shape_lists = { ["W|A3"] = { 1, 2 } } },
        settings = { best_n = 3, max_rarity = 7, keep_skills = { ["20"] = 2 } },
        ignore = {},
    }
    local charm = { key = 9, skills = { { id = 10, level = 1 } } }
    eq(explain.why(ctx, charm, { action = "sell", reason = "duplicate", ref = 5 }), "Same as #5 (kept)")
    eq(explain.why(ctx, charm, { action = "sell", reason = "dominated", ref = 5 }), "Covered by #5 R8  Attack Boost 3")
    eq(explain.why(ctx, charm, { action = "sell", reason = "rule", rank = { skill = 10, rank = 4 } }),
        "Not in your best 3 · closest Attack Boost #4 of 4")
    eq(explain.why(ctx, charm, { action = "sell", reason = "rule", rank = { skill = "shape:W|A3", rank = 2 } }),
        "Not in your best 3 · closest Slot shape A3 #2 of 2")
    eq(explain.why(ctx, charm, { action = "sell", reason = "rule" }), "Not in your best 3 · beaten by a talisman that is also sold")
    local text, warn = explain.why(ctx, charm, { action = "sell", reason = "picked", drops = { { id = 10, level = 1, kept = 0 } } })
    eq(text, "Your pick · LAST Attack Boost 1")
    eq(warn, true, "a loss is a warning")
    eq(explain.why(ctx, charm, { action = "sell", reason = "picked", covered_by = 5 }), "Your pick (covered by #5)")
    eq(explain.why(ctx, charm, { action = "keep", reason = "top_n", detail = { skill = 10, rank = 1 } }), "Attack Boost #1 of 4")
    eq(explain.why(ctx, charm, { action = "keep", reason = "top_n", detail = { shape = "W|A3", rank = 2 } }), "Slot shape A3 #2 of 2")
    eq(explain.why(ctx, charm, { action = "keep", reason = "exempt", detail = 20 }), "Keep all Ambush 2+")
    eq(explain.why(ctx, charm, { action = "keep", reason = "rarity" }), "Unique; you sell up to R7")
    eq(explain.why(ctx, charm, { action = "keep", reason = "protected", detail = "loadout" }), "In a loadout")
    local held, held_warn = explain.why(ctx, charm, { action = "keep", reason = "best", detail = "safety_check" })
    eq(held, "Held back by a safety check - please report")
    eq(held_warn, true, "held back is a warning")
    ctx.ignore = { [20] = true }
    local ignored = { key = 9, skills = { { id = 10, level = 1 }, { id = 20, level = 2 } } }
    eq(explain.why(ctx, ignored, { action = "sell", reason = "duplicate", ref = 5 }), "Same as #5 (kept) (ignoring Ambush 2)")
    eq(explain.verdict_label(ctx, { action = "keep", reason = "top_n" }), "Keep · best 3")
    eq(explain.verdict_label(ctx, { action = "sell", reason = "rule" }), "Sell · unique")
    eq(explain.class({ action = "sell", reason = "dominated" }), "safe")
    eq(explain.class({ action = "sell", reason = "picked" }), "pick")
end)

test("long messages are wrapped at spaces, keeping the spacing", function()
    imgui = setmetatable({}, { __index = function() return function() end end })
    local ui = require("BulkSell.ui")
    local text = lang.T("confirm_unique", 727, 3) .. " Sell 1 talisman (R5  Skill1 1  W1)."
    local lines = ui._wrap(text)
    eq(#lines > 1, true, "several lines")
    for _, line in ipairs(lines) do eq(#line <= 100, true, "line length") end
    eq(table.concat(lines, " "), text, "nothing lost")
    eq(#ui._wrap("short"), 1, "short text stays one line")
    eq(#ui._wrap(string.rep("x", 150)), 1, "a word longer than a line is not cut")
end)

test("capacity levels", function()
    local c = capacity.of(2087, 2400, 735)
    eq(c.free, 313, "free")
    eq(c.level, "ok", "ok")
    eq(c.used_after_sale, 1352, "after the sale")
    eq(c.free_after_sale, 1048, "free after the sale")
    eq(capacity.of(2360, 2400).level, "warn", "warn at 40 free")
    eq(capacity.of(2395, 2400).level, "critical", "critical at 5 free")
    eq(capacity.of(nil, 2400), nil, "unknown")
    eq(capacity.of(10, 20, 50).used_after_sale, 0, "never below zero")
end)

runner.run()
