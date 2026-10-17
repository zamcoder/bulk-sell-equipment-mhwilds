-- REFramework window for Bulk Sell. Drawn from re.on_draw_ui, so it is visible
-- while the REFramework menu is open (Insert by default). It only reads and edits
-- Lua state; every game call happens in the jobs of BulkSell.lua.

local capacity = require("BulkSell.capacity")
local explain = require("BulkSell.explain")
local export = require("BulkSell.export")
local lang = require("BulkSell.lang")
local skills = require("BulkSell.skills")
local stars = require("BulkSell.stars")
local T = lang.T

local ui = {}

local PAGE_SIZE = 50
local TABLE_FLAGS = 1 | 64 | 1920   -- ImGuiTableFlags_Resizable | RowBg | Borders
local COLUMN_FIXED, COLUMN_STRETCH = 16, 8   -- ImGuiTableColumnFlags_WidthFixed / WidthStretch
local COLUMNS = {   -- key, flags, width (fixed) or weight (stretch)
    { "col_sell", COLUMN_FIXED, 36 }, { "col_box", COLUMN_FIXED, 52 }, { "col_talisman", COLUMN_STRETCH, 2.2 },
    { "col_slots", COLUMN_FIXED, 72 }, { "col_price", COLUMN_FIXED, 72 }, { "col_verdict", COLUMN_FIXED, 130 },
    { "col_why", COLUMN_STRETCH, 2.8 },
}
local WRAP = 100   -- characters per line for long messages (ImGui does not wrap plain text)
local FIRST_USE_EVER = 4        -- ImGuiCond_FirstUseEver
local HOVER_DISABLED = 1024     -- ImGuiHoveredFlags_AllowWhenDisabled
local RED = 0xFF4040FF
local YELLOW = 0xFF40FFFF
local GREEN = 0xFF60FF60
local GREY = 0xFFA0A0A0
local FILTERS = { "filter_to_sell", "filter_to_keep", "filter_all", "filter_picks", "filter_unique", "filter_changed",
    "filter_last", "filter_new" }
local FILTER_NEW = 8
local TOAST_FLAGS = 201583   -- NoDecoration | NoMove | AlwaysAutoResize | NoSavedSettings | NoFocusOnAppearing | NoInputs
local FILTER_CHANGED = 6
local SKILLS_HEIGHT = 300   -- pixels of the Skills list
local RARITIES = { 5, 6, 7, 8 }
local MAX_LOSS_LINES = 8
local MAX_LOSS_BOXES = 3

-- Per-session view state; not saved.
local view = {
    filter = 1, page = 1, find = "", rarity = { [5] = true, [6] = true, [7] = true, [8] = true },
    rows = nil, rows_key = nil, texts = {}, texts_revision = nil, totals = nil,
    skill_find = "", skill_rows = nil, skill_rows_revision = nil,
    export_scope = 1, export_language = 1, star_counts = nil,
}

local function has(name) return type(imgui[name]) == "function" end

local function thousands(n)
    local text = tostring(math.floor(n or 0))
    local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (result:gsub("^,", ""))
end

-- Draws a long message on several lines, broken at spaces.
local function wrap_at(text, width)
    local lines, rest = {}, tostring(text)
    while #rest > width do
        local cut = rest:sub(1, width + 1):match("^.*() ")   -- the last space that keeps the line short enough
        if not cut or cut <= 1 then break end
        lines[#lines + 1] = rest:sub(1, cut - 1)
        rest = rest:sub(cut + 1)
    end
    lines[#lines + 1] = rest
    return lines
end

local function wrap(text) return wrap_at(text, WRAP) end

local function say(text, color)
    for _, l in ipairs(wrap(text)) do
        if color then imgui.text_colored(l, color) else imgui.text(l) end
    end
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
    if f == 6 and not (scan.last_change and scan.last_change.keys[charm.key]) then return false end
    if f == 7 and not (scan.last_of_kind and scan.last_of_kind[charm.key]) then return false end
    if f == FILTER_NEW and not view.arrivals[charm.key] then return false end
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
    local key = table.concat({ scan.revision, view.filter, view.find, table.concat(mask), view.arrivals_count or 0 }, "|")
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
    local t = { revision = scan.revision, losses = 0, dont_care = 0, pick_sell = 0, pick_keep = 0 }
    local dont_care = {}
    for _, charm in ipairs(scan.charms) do
        local v = scan.verdicts[charm.key]
        if v.action == "sell" and (v.drops or v.shape_lost) then t.losses = t.losses + 1 end
        for _, d in ipairs(v.action == "sell" and v.ignored_drops or {}) do
            if not dont_care[d.id] then
                dont_care[d.id] = true
                t.dont_care = t.dont_care + 1
            end
        end
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

-- Skills panel -------------------------------------------------------------------

local function skill_rows(scan, settings)
    if view.skill_rows_revision ~= scan.revision then
        view.skill_rows = skills.rows(scan.charms, scan.verdicts, settings, scan.ctx.names)
        view.skill_rows_revision = scan.revision
    end
    return view.skill_rows
end

-- Combo choices and labels for a best level and a preference, built once instead of every frame.
local choice_cache = {}
local function skill_choices(best, pref)
    local key = table.concat({ best, pref.kind, pref.n or pref.min or "" }, ":")
    local entry = choice_cache[key]
    if not entry then
        local choices, current = skills.choices(best, pref)
        local labels = {}
        for i, choice in ipairs(choices) do labels[i] = skills.label(choice) end
        entry = { choices, current, labels }
        choice_cache[key] = entry
    end
    return entry[1], entry[2], entry[3]
end

local function draw_skill_row(state, actions, row)
    local pref = skills.pref_of(state.settings, row.id)
    local ignored = pref.kind == "ignore"
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    if ignored then imgui.text_colored(row.name, GREY) else imgui.text(row.name) end
    imgui.table_set_column_index(1)
    imgui.text(tostring(row.count))
    imgui.table_set_column_index(2)
    imgui.text(tostring(row.best))
    imgui.table_set_column_index(3)
    local choices, current, labels = skill_choices(row.best, pref)
    local changed, index = imgui.combo("##BulkSellSkillPref" .. row.id, current, labels)
    if changed and choices[index] and not skills.same(choices[index], pref) then actions.set_skill(row.id, choices[index]) end
    imgui.table_set_column_index(4)
    row.after = row.after or (row.kept > 0 and T("after_kept", row.kept, row.kept_best) or T("after_none"))
    local after = row.after
    if row.loss then
        imgui.text_colored(after .. (ignored and T("after_dont_care") or ""), RED)
    elseif ignored then
        imgui.text_colored(after, GREY)
    else
        imgui.text(after)
    end
end

local SET_SHOWN = { { "default", { kind = "default" } }, { "keep", { kind = "keep", min = 1 } }, { "ignore", { kind = "ignore" } } }
local SKILL_COLUMNS = { { "col_skill", COLUMN_STRETCH, 2 }, { "col_on_talismans", COLUMN_FIXED, 90 },
    { "col_best_level", COLUMN_FIXED, 60 }, { "col_keep", COLUMN_FIXED, 170 }, { "col_after", COLUMN_STRETCH, 2 } }

local function draw_skill_table(state, actions, shown)
    if not imgui.begin_table("BulkSellSkillsTable", 5, TABLE_FLAGS) then return end
    local ok, err = pcall(function()
        for _, column in ipairs(SKILL_COLUMNS) do
            if not pcall(imgui.table_setup_column, T(column[1]), column[2], column[3]) then imgui.table_setup_column(T(column[1])) end
        end
        imgui.table_headers_row()
        for _, row in ipairs(shown) do draw_skill_row(state, actions, row) end
    end)
    imgui.end_table()
    if not ok then error(err, 0) end
end

local function draw_skills(state, actions)
    local scan, settings = state.scan, state.settings
    local c = skills.counts(settings)
    local header = T("skills_header", c.keep, c.custom, c.ignore) .. "###BulkSellSkills"
    if not has("collapsing_header") or not imgui.collapsing_header(header) then return end
    local pending = state.skills_confirm
    if pending then
        local text = pending.reset and T("skills_confirm_reset") or T("skills_confirm_set", #pending.ids, skills.label(pending.pref))
        say(text, YELLOW)
        if imgui.button(T("yes") .. "##BulkSellSkillsYes") then actions.confirm_skills() end
        imgui.same_line()
        if imgui.button(T("cancel") .. "##BulkSellSkillsNo") then actions.cancel_skills() end
        return
    end
    local find_changed, find = imgui.input_text(T("find_skill") .. "##BulkSellSkillFind", view.skill_find)
    if find_changed then view.skill_find = find or "" end
    local shown = {}
    local needle = view.skill_find:lower()
    for _, row in ipairs(skill_rows(scan, settings)) do
        if needle == "" or row.name:lower():find(needle, 1, true) then shown[#shown + 1] = row end
    end
    -- "Set shown" changes many skills at once, so it needs a Find term first.
    if needle ~= "" then
        local ids = {}
        for i, row in ipairs(shown) do ids[i] = row.id end
        imgui.text(T("set_shown", #shown))
        for _, choice in ipairs(SET_SHOWN) do
            imgui.same_line()
            if imgui.button(skills.label(choice[2]) .. "##BulkSellSetShown" .. choice[1]) then actions.set_skills(ids, choice[2]) end
        end
    end
    if state.skills_undo then
        if imgui.button(T("undo") .. "##BulkSellSkillsUndo") then actions.undo_skills() end
        imgui.same_line()
    end
    if imgui.button(T("reset_all") .. "##BulkSellSkillsReset") then actions.reset_skills() end

    -- The list scrolls inside a child window when the binding is there.
    local child = has("begin_child_window") and has("end_child_window") and Vector2f ~= nil
        and pcall(imgui.begin_child_window, "BulkSellSkillsList", Vector2f.new(0, SKILLS_HEIGHT), true)
    local ok, err = pcall(draw_skill_table, state, actions, shown)
    if child then imgui.end_child_window() end
    if not ok then error(err, 0) end
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
    end
    draw_skills(state, actions)
end

-- Summary and selling -------------------------------------------------------------

local function draw_sale_result(sale)
    if not sale.finished then return end
    imgui.text_colored(lang.N("sold_result", sale.sold, thousands(sale.zenny)), GREEN)
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
    local ignored = state.scan and state.scan.options.ignore_skills[drop.id] and T("loss_dont_care") or ""
    if drop.to == 0 then return T("loss_skill_gone", name, drop.from, boxes) .. ignored end
    return T("loss_skill_lower", name, drop.from, drop.to, boxes) .. ignored
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
    local what = confirm.label and T("confirm_single", confirm.label) or T("confirm_many", confirm.count)
    say(T("confirm_question", what, thousands(confirm.zenny)), YELLOW)
    if confirm.unique_rule > 0 then say(T("confirm_unique", confirm.unique_rule, state.scan.settings.best_n)) end
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
    if state.notice then say(state.notice, YELLOW) end
    if state.busy then return end

    if state.picks and state.picks.blocked then
        say(state.picks.blocked, YELLOW)
        if imgui.button(T("continue_without_picks") .. "##BulkSellNoPicks") then actions.continue_without_picks() end
        return
    end
    if state.stale then
        imgui.text_colored(T("rescanning"), YELLOW)
        return
    end
    if state.block_reason then
        say(state.block_reason, YELLOW)
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
    if imgui.button(lang.N("sell_all", count) .. "##BulkSellAll") then actions.request_sell("all") end
    local shown = view.rows_sell or 0
    if shown > 0 and shown < count then
        imgui.same_line()
        if imgui.button(T("sell_shown", shown) .. "##BulkSellShown") then
            actions.request_sell("shown", rows, view.filter == FILTER_NEW and "auto-clean" or nil)
        end
    end
    if shown > 0 then
        imgui.same_line()
        if imgui.button(T("sell_test") .. "##BulkSellOne") then
            actions.request_sell("one", rows, view.filter == FILTER_NEW and "auto-clean" or nil)
        end
    end
end

local function draw_summary(state, actions)
    local scan = state.scan
    local summary, reasons = scan.summary, scan.summary.by_reason
    local totals = plan_totals(scan)
    local cap = capacity.of(scan.stats.used, scan.stats.slots, summary.sell)
    imgui.text(T("summary_line", summary.sell, summary.keep, thousands(summary.zenny),
        cap and cap.used_after_sale or "?", cap and cap.total or "?"))
    local r = summary.by_rarity
    say(T("summary_detail", reasons.duplicate or 0, reasons.dominated or 0, summary.unique_rule,
        totals.pick_sell + totals.pick_keep, totals.pick_sell, totals.pick_keep, reasons.protected or 0))
    if summary.sell > 0 then imgui.text(T("summary_rarity", r[5] or 0, r[6] or 0, r[7] or 0, r[8] or 0)) end
    local settings = scan.settings
    if totals.losses > 0 then say(T("warn_losses", totals.losses), YELLOW) end
    if totals.dont_care > 0 then say(T("warn_dont_care", totals.dont_care), YELLOW) end
    if totals.losses > 0 or totals.dont_care > 0 then
        -- a loss is listed instead of the promise
    elseif summary.sell > 0 and settings.mode == "best" then
        imgui.text_colored(T("promise_best", settings.best_n), GREEN)
    elseif summary.sell > 0 and settings.mode == "covered" then
        imgui.text_colored(T("promise_covered"), GREEN)
    end
    if summary.sell > 0 then
        local points = 0
        for rarity, n in pairs(summary.by_rarity) do points = points + n * (export.MELD_POINTS[rarity] or 0) end
        say(T("planner", thousands(summary.zenny), thousands(points)), GREY)
    end
    if (view.arrivals_count or 0) > 0 then
        imgui.text_colored(lang.N("arrivals_line", view.arrivals_count), YELLOW)
        imgui.same_line()
        if imgui.button(T("arrivals_show") .. "##BulkSellShowNew") then view.filter, view.page = FILTER_NEW, 1 end
        imgui.same_line()
        if imgui.button(T("arrivals_clear") .. "##BulkSellClearNew") then
            actions.clear_arrivals()
            view.arrivals, view.arrivals_count = {}, 0
        end
    end
    local change = scan.last_change
    if change and change.count > 0 then
        say(T("last_change", change.what, change.more, change.fewer))
        imgui.same_line()
        if imgui.button(T("show_changed") .. "##BulkSellShowChanged") then view.filter, view.page = FILTER_CHANGED, 1 end
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
        for _, column in ipairs(COLUMNS) do
            -- Older bindings may not take the width arguments.
            if not pcall(imgui.table_setup_column, T(column[1]), column[2], column[3]) then imgui.table_setup_column(T(column[1])) end
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

-- Tools: stars and export ------------------------------------------------------------

local function star_counts(state, scan)
    local c = view.star_counts
    if c and c.revision == scan.revision then return c end
    c = { revision = scan.revision, kept = 0, picks = 0, remove = 0 }
    for _, charm in ipairs(scan.charms) do
        local v = scan.verdicts[charm.key]
        if v.action == "keep" and not charm.favorite then
            c.kept = c.kept + 1
            if v.reason == "picked" then c.picks = c.picks + 1 end
        end
    end
    if state.stars then c.remove = #stars.removable(state.stars, scan.charms) end
    view.star_counts = c
    return c
end

local function draw_star_result(run)
    if not run or not run.finished then return end
    imgui.text_colored(lang.N(run.want and "star_result_add" or "star_result_remove", run.changed), GREEN)
    if #run.skipped > 0 then imgui.text(T("star_skipped", #run.skipped)) end
    if run.stopped then say(T("stopped", run.stopped), YELLOW) end
end

local function draw_stars(state, actions, scan)
    local run = state.star_run
    if state.busy and state.job_name == "star" and run and not run.finished then
        imgui.text(T("star_progress", run.done, run.total))
        if imgui.button(T("stop") .. "##BulkSellStarStop") then actions.stop_sell() end
        return
    end
    draw_star_result(run)
    local ledger = state.stars
    if ledger and ledger.blocked then
        say(ledger.blocked, YELLOW)
        return
    end
    local pending = state.star_confirm
    if pending then
        say(T("star_confirm_" .. pending.kind, #pending.keys), YELLOW)
        if imgui.button(T("yes") .. "##BulkSellStarYes") then actions.confirm_star() end
        imgui.same_line()
        if imgui.button(T("cancel") .. "##BulkSellStarNo") then actions.cancel_star() end
        return
    end
    if state.busy or state.stale or state.block_reason then return end
    local c = star_counts(state, scan)
    local drawn = false
    for _, entry in ipairs({ { "kept", "star_kept_button", c.kept }, { "picks", "star_picks_button", c.picks },
        { "remove", "star_remove_button", c.remove } }) do
        if entry[3] > 0 then
            if drawn then imgui.same_line() end
            if imgui.button(T(entry[2], entry[3]) .. "##BulkSellStar" .. entry[1]) then actions.request_star(entry[1]) end
            drawn = true
        end
    end
    if not drawn then imgui.text(T("star_nothing")) end
end

local function draw_export(state, actions)
    local scopes, languages = {}, {}
    for i, scope in ipairs(export.SCOPES) do scopes[i] = T("scope_" .. scope) end
    for i, language in ipairs(state.export_languages or {}) do languages[i] = T(language[1]) end
    local changed, scope = imgui.combo(T("export_scope") .. "##BulkSellExportScope", view.export_scope, scopes)
    if changed then view.export_scope = scope end
    changed, scope = imgui.combo(T("export_names") .. "##BulkSellExportNames", view.export_language, languages)
    if changed then view.export_language = scope end
    if not state.busy then
        if imgui.button(T("export_wikidb") .. "##BulkSellWikiDb") then
            actions.export_wikidb(export.SCOPES[view.export_scope], view.export_language)
        end
        imgui.same_line()
        if imgui.button(T("export_csv") .. "##BulkSellCsv") then actions.export_csv(export.SCOPES[view.export_scope]) end
    end
    local language = (state.export_languages or {})[view.export_language]
    local site = language and language[3] ~= "game" and language[3] or "en"
    imgui.text(T("wikidb_step_1", site))
    imgui.text(T("wikidb_step_2"))
    imgui.text_colored(T("wikidb_warning"), YELLOW)
    local result = state.export_result
    if result then
        if result.kind == "wikidb" then
            imgui.text_colored(lang.N("export_copied", result.count), GREEN)
            say(result.path and T("export_saved", result.path) or T("export_not_saved"))
            if result.missing_names then say(T("export_some_names"), YELLOW) end
        elseif result.path then
            say(T("export_csv_saved", result.count, result.path), GREEN)
        else
            say(T("export_csv_failed"), YELLOW)
        end
    end
end

local function draw_tools(state, actions, scan)
    if not has("collapsing_header") or not imgui.collapsing_header(T("tools_header") .. "###BulkSellTools") then return end
    draw_stars(state, actions, scan)
    imgui.separator()
    draw_export(state, actions)
end

local function draw_notices(state, actions)
    for i, text in ipairs(state.notices) do
        say(text, YELLOW)
        imgui.same_line()
        if imgui.button(T("ok") .. "##BulkSellNotice" .. i) then
            actions.dismiss_notice(i)
            return
        end
    end
end

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function draw_body(state, actions)
    view.arrivals = state.arrivals or {}
    view.arrivals_count = count_keys(view.arrivals)
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
    if scan.new_count and scan.new_count > 0 then line = line .. T("new_since_scan", scan.new_count) end
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
    draw_summary(state, actions)
    local rows = filtered_rows(scan)
    draw_sell_controls(state, actions, rows)

    imgui.separator()
    draw_tools(state, actions, scan)

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
            local auto_changed, auto = imgui.checkbox(T("auto_clean") .. "##BulkSellAutoClean", state.settings.auto_clean)
            if auto_changed then state.settings.auto_clean = auto end
            if state.settings.auto_clean then
                local cap_changed, cap = imgui.checkbox(T("capacity_toast") .. "##BulkSellCapacityToast", state.settings.capacity_toast)
                if cap_changed then state.settings.capacity_toast = cap end
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
    -- An export put its text here; ImGui can only set the clipboard while it draws.
    if state.clipboard then
        if has("set_clipboard") then pcall(imgui.set_clipboard, state.clipboard) end
        actions.clipboard_done()
    end
    if not state.settings.window_open or not reframework:is_drawing_ui() then return end
    pcall(function() imgui.set_next_window_size(Vector2f.new(1100, 760), FIRST_USE_EVER) end)
    -- "###" keeps the window ID fixed when the title changes (translations).
    state.settings.window_open = imgui.begin_window(T("window_title") .. "###BulkSellWindow", true, 0)
    local ok, err = pcall(draw_body, state, actions)
    if not ok then imgui.text_colored(T("ui_error", tostring(err)), RED) end
    imgui.end_window()
end

-- A short message in a corner while the REFramework menu is closed. It takes no input and
-- only reads Lua state (it is drawn from re.on_frame).
local TOAST_WRAP = 60
local TOAST_STYLE = {   -- ImGuiCol index, RGBA: a dark panel with a gold edge, like the game's own notices
    { 2, 0.06, 0.05, 0.04, 0.88 },   -- WindowBg
    { 5, 0.84, 0.69, 0.35, 0.90 },   -- Border
}
local TOAST_GOLD = 0xFF6CC8E8

-- Where the message goes: the right side of the screen, a third of the way down, when the
-- screen size is known; otherwise the top left.
local function place_toast()
    local size = has("get_display_size") and imgui.get_display_size()
    if size and size.x and size.x > 0 then
        imgui.set_next_window_pos(Vector2f.new(size.x - 24, size.y * 0.30), 1, Vector2f.new(1, 0))   -- top right corner there
    else
        imgui.set_next_window_pos(Vector2f.new(40, 140), 1)
    end
end

function ui.toast(state)
    local toast = state.toast
    if not toast then return end
    if os.clock() > toast.until_at then
        state.toast = nil
        return
    end
    if reframework:is_drawing_ui() then return end
    pcall(place_toast)
    -- Colours are pushed one by one and popped exactly as often, or ImGui would break.
    local pushed = 0
    if has("push_style_color") and has("pop_style_color") and Vector4f then
        for _, c in ipairs(TOAST_STYLE) do
            if pcall(imgui.push_style_color, c[1], Vector4f.new(c[2], c[3], c[4], c[5])) then pushed = pushed + 1 end
        end
    end
    imgui.begin_window("Bulk Sell###BulkSellToast", nil, TOAST_FLAGS)
    pcall(function()
        imgui.text_colored(T("toast_title"), TOAST_GOLD)
        for _, line in ipairs(wrap_at(toast.text, TOAST_WRAP)) do imgui.text(line) end
    end)
    imgui.end_window()
    if pushed > 0 then imgui.pop_style_color(pushed) end
end

-- Exposed for tests.
ui._thousands = thousands
ui._drop_line = drop_line
ui._view = view
ui._wrap = wrap

return ui
