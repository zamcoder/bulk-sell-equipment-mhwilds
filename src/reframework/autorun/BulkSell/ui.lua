-- REFramework window for Bulk Sell. Drawn from re.on_draw_ui, so it is visible
-- while the REFramework menu is open (Insert by default). It only reads and edits
-- Lua state; every game call happens in the jobs of BulkSell.lua.

local capacity = require("BulkSell.capacity")
local explain = require("BulkSell.explain")
local lang = require("BulkSell.lang")
local T = lang.T

local ui = {}

local PAGE_SIZE = 50
local TABLE_FLAGS = 64 | 1920   -- ImGuiTableFlags_RowBg | ImGuiTableFlags_Borders
local FIRST_USE_EVER = 4        -- ImGuiCond_FirstUseEver
local HOVER_DISABLED = 1024     -- ImGuiHoveredFlags_AllowWhenDisabled
local RED = 0xFF4040FF
local YELLOW = 0xFF40FFFF
local GREEN = 0xFF60FF60
local GREY = 0xFFA0A0A0
local FILTERS = { "filter_to_sell", "filter_to_keep", "filter_all", "filter_picks", "filter_unique" }
local RARITIES = { 5, 6, 7, 8 }
local MAX_LOSS_LINES = 8
local MAX_LOSS_BOXES = 3

-- Per-session view state; not saved.
local view = {
    filter = 1, page = 1, find = "", rarity = { [5] = true, [6] = true, [7] = true, [8] = true },
    rows = nil, rows_key = nil, texts = {}, texts_revision = nil, totals = nil,
    skill_choice = 1, skill_level = 1,
}

local function has(name) return type(imgui[name]) == "function" end

local function thousands(n)
    local text = tostring(math.floor(n or 0))
    local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (result:gsub("^,", ""))
end

local function tooltip(text)
    if has("is_item_hovered") and has("set_tooltip") and imgui.is_item_hovered() then imgui.set_tooltip(text) end
end

-- Texts of one row, computed once per plan revision.
local function row_texts(scan, charm)
    if view.texts_revision ~= scan.revision then
        view.texts, view.texts_revision = {}, scan.revision
    end
    local t = view.texts[charm.key]
    if not t then
        local v = scan.verdicts[charm.key]
        local why, warn = explain.why(scan.ctx, charm, v)
        t = {
            verdict = explain.verdict_label(scan.ctx, v), why = why, warn = warn,
            price = charm.price and (thousands(charm.price) .. " z") or "?",
            search = (charm.skills_label .. " " .. charm.slots_label):lower(),
        }
        view.texts[charm.key] = t
    end
    return t
end

local function matches(scan, charm)
    local v = scan.verdicts[charm.key]
    local f = view.filter
    if f == 1 and v.action ~= "sell" then return false end
    if f == 2 and v.action ~= "keep" then return false end
    if f == 4 and v.reason ~= "picked" then return false end
    if f == 5 and not (v.action == "sell" and v.unique) then return false end
    if not view.rarity[charm.rarity] then return false end
    local find = view.find
    if find ~= "" then
        local box = find:match("^#(%d+)$")
        if box then return charm.key == tonumber(box) end
        return row_texts(scan, charm).search:find(find:lower(), 1, true) ~= nil
    end
    return true
end

local function filtered_rows(scan)
    local mask = {}
    for _, r in ipairs(RARITIES) do mask[#mask + 1] = view.rarity[r] and "1" or "0" end
    local key = table.concat({ scan.revision, view.filter, view.find, table.concat(mask) }, "|")
    if view.rows_key ~= key then
        local rows, sell, zenny = {}, 0, 0
        for _, charm in ipairs(scan.charms) do
            if matches(scan, charm) then
                rows[#rows + 1] = charm
                if scan.verdicts[charm.key].action == "sell" then
                    sell = sell + 1
                    zenny = zenny + (charm.price or 0)
                end
            end
        end
        view.rows, view.rows_key = rows, key
        view.rows_sell, view.rows_zenny = sell, zenny
    end
    return view.rows
end

-- Plan-wide counts the summary needs, once per revision.
local function plan_totals(scan)
    if view.totals and view.totals.revision == scan.revision then return view.totals end
    local t = { revision = scan.revision, losses = 0, pick_sell = 0, pick_keep = 0 }
    for _, charm in ipairs(scan.charms) do
        local v = scan.verdicts[charm.key]
        if v.action == "sell" and (v.drops or v.ignored_drops or v.shape_lost) then t.losses = t.losses + 1 end
        if v.reason == "picked" then
            if v.action == "sell" then t.pick_sell = t.pick_sell + 1 else t.pick_keep = t.pick_keep + 1 end
        end
    end
    view.totals = t
    return t
end

-- Keep combo -------------------------------------------------------------------

local function keep_entries(scan, settings)
    local preview = scan.info.preview or { best = {} }
    local entries = {}
    local function add(mode, n, label, count)
        local text = label
        if count then text = text .. "  -  " .. T("keep_count", count.sell, thousands(count.zenny)) end
        entries[#entries + 1] = { mode = mode, n = n, label = text }
    end
    add("manual", nil, T("keep_manual"), preview.manual)
    add("covered", nil, T("keep_covered"), preview.covered)
    local listed = {}
    for _, n in ipairs({ 10, 5, 3, 2, 1 }) do
        add("best", n, T("keep_best_n", n), preview.best[n])
        listed[n] = true
    end
    if settings.mode == "best" and not listed[settings.best_n] then
        add("best", settings.best_n, T("keep_best_n", settings.best_n), preview.best[settings.best_n])
    end
    return entries
end

local function draw_keep_skills(state, actions)
    local settings = state.settings
    imgui.text(T("always_keep_title"))
    local remove
    local ids = {}
    for id in pairs(settings.keep_skills) do
        if id ~= "_format" then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
    for _, id in ipairs(ids) do
        imgui.text(string.format("  %s %d+", state.skill_names[tonumber(id)] or T("skill_id", id), settings.keep_skills[id]))
        imgui.same_line()
        if imgui.button(T("remove") .. "##BulkSellKeep" .. id) then remove = id end
    end
    if remove then
        settings.keep_skills[remove] = nil
        actions.analyse()
    end
    local options = state.scan.skill_options
    if not options or #options.names == 0 then return end
    local _, choice = imgui.combo(T("skill") .. "##BulkSellKeepSkill", view.skill_choice, options.names)
    view.skill_choice = math.max(1, math.min(choice, #options.names))
    local _, level = imgui.slider_int(T("min_level") .. "##BulkSellKeepLevel", view.skill_level, 1, 5)
    view.skill_level = level
    if imgui.button(T("always_keep_add") .. "##BulkSellKeepAdd") then
        local key = tostring(options.ids[view.skill_choice])
        settings.keep_skills[key] = view.skill_level
        settings.skill_places[key] = nil
        settings.ignore_skills[key] = nil
        actions.analyse()
    end
end

local function draw_rules(state, actions)
    local settings = state.settings
    local scan = state.scan
    local entries = keep_entries(scan, settings)
    local labels, current = {}, 1
    for i, e in ipairs(entries) do
        labels[i] = e.label
        if e.mode == settings.mode and (e.mode ~= "best" or e.n == settings.best_n) then current = i end
    end
    local changed, choice = imgui.combo(T("keep") .. "##BulkSellKeepMode", current, labels)
    if changed and entries[choice] then
        settings.mode = entries[choice].mode
        if entries[choice].n then settings.best_n = entries[choice].n end
        actions.analyse()
    end
    imgui.same_line()
    imgui.text("(?)")
    tooltip(T("keep_help"))
    if settings.mode == "best" then
        local r_changed, rarity = imgui.slider_int(T("rarity_limit") .. "##BulkSellRarity", settings.max_rarity, 5, 8)
        if r_changed then
            settings.max_rarity = rarity
            actions.analyse()
        end
        local unlimited = scan.info.preview and scan.info.preview.unlimited
        if settings.max_rarity < 8 and unlimited then
            imgui.text_colored(T("rarity_hint", settings.max_rarity, settings.best_n, unlimited.sell, thousands(unlimited.zenny)), GREY)
        end
        draw_keep_skills(state, actions)
    end
end

-- Summary and selling -------------------------------------------------------------

local function draw_sale_result(sale)
    if not sale.finished then return end
    imgui.text_colored(T("sold_result", sale.sold, thousands(sale.zenny)), GREEN)
    if #sale.skipped > 0 then imgui.text(T("sold_skipped", #sale.skipped)) end
    if sale.stopped then imgui.text_colored(T("stopped", sale.stopped), YELLOW) end
    if sale.receipt then imgui.text(T("receipt", sale.receipt)) end
end

-- "Fire Resistance 3 (best left 2) #2292" for an analysis.losses entry.
local function drop_line(state, drop)
    local name = state.skill_names[drop.id] or T("skill_id", drop.id)
    local shown = {}
    for i = 1, math.min(#drop.boxes, MAX_LOSS_BOXES) do shown[i] = "#" .. drop.boxes[i] end
    local boxes = table.concat(shown, ", ")
    if #drop.boxes > MAX_LOSS_BOXES then boxes = boxes .. string.format(" +%d", #drop.boxes - MAX_LOSS_BOXES) end
    if drop.to == 0 then return T("loss_skill_gone", name, drop.from, boxes) end
    return T("loss_skill_lower", name, drop.from, drop.to, boxes)
end

local function draw_losses(state, confirm)
    imgui.text_colored(T("loss_title"), RED)
    local lines = 0
    for _, drop in ipairs(confirm.drops) do
        lines = lines + 1
        if lines > MAX_LOSS_LINES then break end
        imgui.text_colored("  " .. drop_line(state, drop), RED)
    end
    for _, shape in ipairs(confirm.shapes) do
        lines = lines + 1
        if lines > MAX_LOSS_LINES then break end
        imgui.text_colored("  " .. T("loss_shape", explain.shape_label(shape.shape), shape.box), RED)
    end
    local total = #confirm.drops + #confirm.shapes
    if total > MAX_LOSS_LINES then imgui.text_colored("  " .. T("and_more", total - MAX_LOSS_LINES), RED) end
    local changed, value = imgui.checkbox(T("ack_loss") .. "##BulkSellAckLoss", confirm.ack_loss)
    if changed then confirm.ack_loss = value end
end

local function draw_confirm(state, actions, confirm)
    local what = confirm.label and T("confirm_one", confirm.label) or T("confirm_many", confirm.count)
    imgui.text_colored(T("confirm_question", what, thousands(confirm.zenny)), YELLOW)
    if confirm.unique_rule > 0 then imgui.text(T("confirm_unique", confirm.unique_rule, state.scan.settings.best_n)) end
    if confirm.picks > 0 then imgui.text(T("confirm_picks", confirm.picks)) end
    if confirm.share > 50 then imgui.text(T("confirm_share", confirm.share)) end
    if confirm.need_unique then
        local changed, value = imgui.checkbox(T("ack_unique") .. "##BulkSellAckUnique", confirm.ack_unique)
        if changed then confirm.ack_unique = value end
    end
    if confirm.need_loss then draw_losses(state, confirm) end
    local ready = (not confirm.need_unique or confirm.ack_unique) and (not confirm.need_loss or confirm.ack_loss)
    -- "Yes, sell" only exists once every required box is ticked (works without begin_disabled).
    if ready then
        if imgui.button(T("yes_sell") .. "##BulkSellConfirm") then actions.confirm_sell() end
        imgui.same_line()
    end
    if imgui.button(T("cancel") .. "##BulkSellCancel") then actions.cancel_sell() end
end

local function empty_text(settings)
    if settings.mode == "covered" then return T("empty_covered") end
    if settings.mode == "manual" then return T("empty_manual") end
    return T("empty_best")
end

local function draw_sell_controls(state, actions, rows)
    local sale = state.sale
    if state.busy and state.job_name == "sell" and sale and not sale.finished then
        imgui.text(T("selling_progress", sale.done, sale.total, thousands(sale.zenny)))
        if imgui.button(T("stop") .. "##BulkSellStop") then actions.stop_sell() end
        return
    end
    if sale then draw_sale_result(sale) end
    if state.notice then imgui.text_colored(state.notice, YELLOW) end
    if state.busy then return end

    if state.picks and state.picks.blocked then
        imgui.text_colored(state.picks.blocked, YELLOW)
        if imgui.button(T("continue_without_picks") .. "##BulkSellNoPicks") then actions.continue_without_picks() end
        return
    end
    if state.stale then
        imgui.text_colored(T("rescanning"), YELLOW)
        return
    end
    if state.block_reason then
        imgui.text_colored(state.block_reason, YELLOW)
        return
    end
    if state.confirm then
        draw_confirm(state, actions, state.confirm)
        return
    end
    if state.analyse_at then
        imgui.text(T("updating"))
        return
    end
    local count = state.scan.summary.sell
    if count == 0 then
        imgui.text(empty_text(state.scan.settings))
        return
    end
    if imgui.button(T("sell_all", count) .. "##BulkSellAll") then actions.request_sell("all") end
    local shown = view.rows_sell or 0
    if shown > 0 and shown < count then
        imgui.same_line()
        if imgui.button(T("sell_shown", shown) .. "##BulkSellShown") then actions.request_sell("shown", rows) end
    end
    if shown > 0 then
        imgui.same_line()
        if imgui.button(T("sell_one") .. "##BulkSellOne") then actions.request_sell("one", rows) end
    end
end

local function draw_summary(state)
    local scan = state.scan
    local summary, reasons = scan.summary, scan.summary.by_reason
    local totals = plan_totals(scan)
    local cap = capacity.of(scan.stats.used, scan.stats.slots, summary.sell)
    imgui.text(T("summary_line", summary.sell, summary.keep, thousands(summary.zenny),
        cap and cap.used_after_sale or "?", cap and cap.total or "?"))
    local r = summary.by_rarity
    imgui.text(T("summary_detail", reasons.duplicate or 0, reasons.dominated or 0, summary.unique_rule,
        totals.pick_sell + totals.pick_keep, totals.pick_sell, totals.pick_keep, reasons.protected or 0,
        r[5] or 0, r[6] or 0, r[7] or 0, r[8] or 0))
    local settings = scan.settings
    if totals.losses > 0 then
        imgui.text_colored(T("warn_losses", totals.losses), YELLOW)
    elseif summary.sell > 0 and settings.mode == "best" then
        imgui.text_colored(T("promise_best", settings.best_n), GREEN)
    elseif summary.sell > 0 and settings.mode == "covered" then
        imgui.text_colored(T("promise_covered"), GREEN)
    end
end

-- Table ------------------------------------------------------------------------------

local function draw_pick_box(state, actions, charm, verdict)
    local label = "##BulkSellPick" .. charm.key
    if charm.protected then
        if has("begin_disabled") and has("end_disabled") then
            imgui.begin_disabled(true)
            imgui.checkbox(label, false)
            imgui.end_disabled()
            if has("is_item_hovered") and has("set_tooltip") and imgui.is_item_hovered(HOVER_DISABLED) then
                imgui.set_tooltip(explain.protected_text(charm.protected))
            end
        else
            imgui.text("(-)")
        end
        return
    end
    local entry = state.picks and state.picks.entries[charm.key]
    local shown = entry and entry.action or verdict.action
    local changed = imgui.checkbox(label, shown == "sell")
    if changed then actions.click(charm, shown) end
end

local function draw_table(state, actions, scan, rows)
    local changed, filter = imgui.combo(T("show") .. "##BulkSellFilter", view.filter, (function()
        local names = {}
        for i, key in ipairs(FILTERS) do names[i] = T(key) end
        return names
    end)())
    if changed then
        view.filter = filter
        view.page = 1
    end
    imgui.same_line()
    local find_changed, find = imgui.input_text(T("find") .. "##BulkSellFind", view.find)
    if find_changed then
        view.find = find or ""
        view.page = 1
    end
    for _, r in ipairs(RARITIES) do
        imgui.same_line()
        local r_changed, on = imgui.checkbox("R" .. r .. "##BulkSellR" .. r, view.rarity[r])
        if r_changed then
            view.rarity[r] = on
            view.page = 1
        end
    end
    rows = filtered_rows(scan)

    imgui.text(T("shown_line", #rows, view.rows_sell, thousands(view.rows_zenny)))
    imgui.same_line()
    imgui.text(T("mark_shown"))
    for _, mark in ipairs({ { "sell", "mark_sell" }, { "keep", "mark_keep" }, { "auto", "mark_auto" } }) do
        imgui.same_line()
        if imgui.button(T(mark[2]) .. "##BulkSellMark" .. mark[1]) then actions.mark(rows, mark[1]) end
    end
    if state.picks and state.picks.undo then
        imgui.same_line()
        if imgui.button(T("undo") .. "##BulkSellUndo") then actions.undo() end
    end

    local pages = math.max(1, (#rows + PAGE_SIZE - 1) // PAGE_SIZE)
    view.page = math.min(view.page, pages)
    if imgui.button("<##BulkSellPrev") and view.page > 1 then view.page = view.page - 1 end
    imgui.same_line()
    imgui.text(T("page", view.page, pages))
    imgui.same_line()
    if imgui.button(">##BulkSellNext") and view.page < pages then view.page = view.page + 1 end

    if not imgui.begin_table("BulkSellTable", 7, TABLE_FLAGS) then return end
    -- end_table must run even if a row fails, or ImGui's stack is left unbalanced.
    local ok, err = pcall(function()
        for _, column in ipairs({ "col_sell", "col_box", "col_talisman", "col_slots", "col_price", "col_verdict", "col_why" }) do
            imgui.table_setup_column(T(column))
        end
        imgui.table_headers_row()
        for i = (view.page - 1) * PAGE_SIZE + 1, math.min(#rows, view.page * PAGE_SIZE) do
            local charm = rows[i]
            local verdict = scan.verdicts[charm.key]
            local t = row_texts(scan, charm)
            imgui.table_next_row()
            imgui.table_set_column_index(0)
            draw_pick_box(state, actions, charm, verdict)
            imgui.table_set_column_index(1)
            local picked = state.picks and state.picks.entries[charm.key]
            imgui.text(tostring(charm.key) .. (picked and "*" or ""))
            imgui.table_set_column_index(2)
            imgui.text(charm.skills_label)
            imgui.table_set_column_index(3)
            imgui.text(charm.slots_label)
            imgui.table_set_column_index(4)
            imgui.text(t.price)
            imgui.table_set_column_index(5)
            imgui.text(t.verdict)
            imgui.table_set_column_index(6)
            if t.warn then imgui.text_colored(t.why, RED) else imgui.text(t.why) end
        end
    end)
    imgui.end_table()
    if not ok then error(err, 0) end
end

local function draw_notices(state, actions)
    for i, text in ipairs(state.notices) do
        imgui.text_colored(text, YELLOW)
        imgui.same_line()
        if imgui.button(T("ok") .. "##BulkSellNotice" .. i) then
            actions.dismiss_notice(i)
            return
        end
    end
end

local function draw_body(state, actions)
    if state.error then imgui.text_colored(T("error", state.error), RED) end

    if state.busy then
        imgui.text(T("working"))
    elseif imgui.button(T("scan") .. "##BulkSellScan") then
        actions.scan()
    end
    draw_notices(state, actions)

    local scan = state.scan
    if not scan then
        imgui.text(T("intro"))
        return
    end
    local stats = scan.stats
    local cap = capacity.of(stats.used, stats.slots, 0)
    imgui.same_line()
    local line = T("scanned", scan.time, stats.appraised, stats.protected, stats.used, stats.slots, cap and cap.free or 0)
    if cap and cap.level == "critical" then
        imgui.text_colored(line, RED)
    elseif cap and cap.level == "warn" then
        imgui.text_colored(line, YELLOW)
    else
        imgui.text(line)
    end

    imgui.separator()
    draw_rules(state, actions)

    imgui.separator()
    draw_summary(state)
    local rows = filtered_rows(scan)
    draw_sell_controls(state, actions, rows)

    imgui.separator()
    draw_table(state, actions, scan, rows)
end

function ui.menu(state)
    if imgui.tree_node("Bulk Sell Equipment") then
        local ok, err = pcall(function()
            imgui.text(T("version", state.version))
            if imgui.button((state.settings.window_open and T("hide_window") or T("show_window")) .. "##BulkSell") then
                state.settings.window_open = not state.settings.window_open
            end
            local changed, debug = imgui.checkbox(T("debug_files") .. "##BulkSellDebug", state.settings.debug)
            if changed then state.settings.debug = debug end
            if state.settings.debug and state.last_perf then
                imgui.text(T("debug_perf", state.last_perf.name, state.last_perf.frames, state.last_perf.longest * 1000))
            end
        end)
        imgui.tree_pop()
        if not ok then error(err, 0) end
    end
end

function ui.window(state, actions)
    if not state.settings.window_open or not reframework:is_drawing_ui() then return end
    pcall(function() imgui.set_next_window_size(Vector2f.new(1100, 760), FIRST_USE_EVER) end)
    -- "###" keeps the window ID fixed when the title changes (translations).
    state.settings.window_open = imgui.begin_window(T("window_title") .. "###BulkSellWindow", true, 0)
    local ok, err = pcall(draw_body, state, actions)
    if not ok then imgui.text_colored(T("ui_error", tostring(err)), RED) end
    imgui.end_window()
end

-- Exposed for tests.
ui._thousands = thousands
ui._drop_line = drop_line
ui._view = view

return ui
