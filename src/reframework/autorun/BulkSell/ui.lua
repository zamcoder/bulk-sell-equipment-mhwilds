-- REFramework window for Bulk Sell. Drawn from re.on_draw_ui, so it is visible
-- while the REFramework menu is open (Insert by default).

local ui = {}

local PAGE_SIZE = 50
local TABLE_FLAGS = 64 | 1920   -- ImGuiTableFlags_RowBg | ImGuiTableFlags_Borders
local FIRST_USE_EVER = 4        -- ImGuiCond_FirstUseEver
local RED = 0xFF4040FF
local YELLOW = 0xFF40FFFF
local GREEN = 0xFF60FF60
local FILTERS = { "To sell", "To keep", "All" }
local PROTECTED_TEXT = {
    equipped = "equipped",
    loadout = "in a loadout",
    favorite = "favorite",
    decorations = "has decorations",
    ["special bonus"] = "RNG Charm Crafting bonus",
}

-- Per-session view state; not saved.
local view = { filter = 1, page = 1, rows = nil, rows_key = nil, skill_choice = 1, skill_level = 1 }

local function thousands(n)
    local text = tostring(math.floor(n or 0))
    local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (result:gsub("^,", ""))
end

local function verdict_text(verdict)
    if verdict.action == "keep" then
        if verdict.reason == "protected" then return "Keep: " .. (PROTECTED_TEXT[verdict.detail] or verdict.detail) end
        return "Keep"
    end
    if verdict.reason == "rule" then return "Sell: rarity rule" end
    if verdict.reason == "duplicate" then return "Sell: duplicate" end
    return "Sell: covered"
end

local function price_text(charm)
    if not charm.price then return "?" end
    return thousands(charm.price) .. " z"
end

local function filtered_rows(scan)
    local key = tostring(scan.revision) .. ":" .. view.filter
    if view.rows_key ~= key then
        local rows = {}
        for _, charm in ipairs(scan.charms) do
            local action = scan.verdicts[charm.key].action
            if view.filter == 3 or (view.filter == 1 and action == "sell") or (view.filter == 2 and action == "keep") then
                rows[#rows + 1] = charm
            end
        end
        view.rows, view.rows_key = rows, key
    end
    return view.rows
end

local function draw_table(scan)
    local changed, filter = imgui.combo("Show##BulkSellFilter", view.filter, FILTERS)
    if changed then
        view.filter = filter
        view.page = 1
    end

    local rows = filtered_rows(scan)
    local pages = math.max(1, (#rows + PAGE_SIZE - 1) // PAGE_SIZE)
    view.page = math.min(view.page, pages)
    if imgui.button("<##BulkSellPrev") and view.page > 1 then view.page = view.page - 1 end
    imgui.same_line()
    imgui.text(string.format("Page %d / %d  (%d talismans)", view.page, pages, #rows))
    imgui.same_line()
    if imgui.button(">##BulkSellNext") and view.page < pages then view.page = view.page + 1 end

    if not imgui.begin_table("BulkSellTable", 5, TABLE_FLAGS) then return end
    -- end_table must run even if a row fails, or ImGui's stack is left unbalanced.
    local ok, err = pcall(function()
        imgui.table_setup_column("Talisman")
        imgui.table_setup_column("Slots")
        imgui.table_setup_column("Price")
        imgui.table_setup_column("Verdict")
        imgui.table_setup_column("Kept instead")
        imgui.table_headers_row()
        local by_key = scan.by_key
        for i = (view.page - 1) * PAGE_SIZE + 1, math.min(#rows, view.page * PAGE_SIZE) do
            local charm = rows[i]
            local verdict = scan.verdicts[charm.key]
            imgui.table_next_row()
            imgui.table_set_column_index(0)
            imgui.text(charm.skills_label)
            imgui.table_set_column_index(1)
            imgui.text(charm.slots_label)
            imgui.table_set_column_index(2)
            imgui.text(price_text(charm))
            imgui.table_set_column_index(3)
            imgui.text(verdict_text(verdict))
            imgui.table_set_column_index(4)
            local kept = verdict.ref and by_key[verdict.ref]
            imgui.text(kept and (kept.skills_label .. "  " .. kept.slots_label) or "")
        end
    end)
    imgui.end_table()
    if not ok then error(err, 0) end
end

local function draw_keep_skills(state, actions)
    local settings = state.settings
    imgui.text("Never sell by rarity when a talisman has:")
    local remove
    for id, level in pairs(settings.keep_skills) do
        if id ~= "_format" then
            imgui.text(string.format("  %s %d+", state.skill_names[tonumber(id)] or ("Skill #" .. id), level))
            imgui.same_line()
            if imgui.button("Remove##BulkSellKeep" .. id) then remove = id end
        end
    end
    if remove then
        settings.keep_skills[remove] = nil
        actions.analyse()
    end

    local options = state.scan.skill_options
    if #options.names == 0 then return end
    local _, choice = imgui.combo("Skill##BulkSellKeepSkill", view.skill_choice, options.names)
    view.skill_choice = math.min(choice, #options.names)
    local _, level = imgui.slider_int("Min level##BulkSellKeepLevel", view.skill_level, 1, 5)
    view.skill_level = level
    if imgui.button("Add kept skill##BulkSellKeepAdd") then
        settings.keep_skills[tostring(options.ids[view.skill_choice])] = view.skill_level
        actions.analyse()
    end
end

local function draw_rules(state, actions)
    local settings = state.settings
    local any = false
    local changed, value = imgui.checkbox("Sell talismans that a kept talisman fully covers (and extra duplicates)", settings.sell_dominated)
    if changed then
        settings.sell_dominated = value
        any = true
    end
    changed, value = imgui.checkbox("Also sell by rarity", settings.rule_enabled)
    if changed then
        settings.rule_enabled = value
        any = true
    end
    if settings.rule_enabled then
        changed, value = imgui.slider_int("Sell rarity up to##BulkSellRule", settings.rule_max_rarity, 5, 8)
        if changed then
            settings.rule_max_rarity = value
            any = true
        end
        draw_keep_skills(state, actions)
    end
    if any then actions.analyse() end
end

local function draw_sale_result(sale)
    if not sale.finished then return end
    imgui.text_colored(string.format("Sold %d talismans for %s z.", sale.sold, thousands(sale.zenny)), GREEN)
    if #sale.skipped > 0 then
        imgui.text(string.format("%d were kept after a last check (changed, equipped, favorite...).", #sale.skipped))
    end
    if sale.stopped then imgui.text_colored("Stopped: " .. sale.stopped, YELLOW) end
    if sale.receipt then imgui.text("Receipt: reframework/data/" .. sale.receipt) end
end

local function draw_sell_controls(state, actions)
    local sale = state.sale
    if state.busy and sale and not sale.finished then
        imgui.text(string.format("Selling... %d / %d  (%s z)", sale.done, sale.total, thousands(sale.zenny)))
        if imgui.button("Stop##BulkSellStop") then actions.stop_sell() end
        return
    end
    if sale then draw_sale_result(sale) end
    if state.busy then return end

    if state.block_reason then
        imgui.text_colored(state.block_reason, YELLOW)
        return
    end
    local confirm = state.confirm
    if confirm then
        local what = confirm.label and ("1 talisman (" .. confirm.label .. ")") or (confirm.count .. " talismans")
        imgui.text_colored(string.format("Sell %s for %s z? This cannot be undone.", what, thousands(confirm.zenny)), YELLOW)
        if imgui.button("Yes, sell##BulkSellConfirm") then actions.confirm_sell() end
        imgui.same_line()
        if imgui.button("Cancel##BulkSellCancel") then actions.cancel_sell() end
        return
    end
    local count = state.scan.summary.sell
    if count == 0 then
        imgui.text("Nothing to sell with the current rules.")
        return
    end
    if imgui.button(string.format("Sell %d talismans##BulkSellAll", count)) then actions.request_sell(nil) end
    imgui.same_line()
    if imgui.button("Sell just 1 (test)##BulkSellOne") then actions.request_sell(1) end
end

local function draw_body(state, actions)
    if state.error then imgui.text_colored("Error: " .. state.error, RED) end

    if state.busy then
        imgui.text("Working...")
    elseif imgui.button("Scan Equipment Box") then
        actions.scan()
    end

    local scan = state.scan
    if not scan then
        imgui.text("Scan reads your talismans. Nothing is sold until you confirm.")
        return
    end
    local stats = scan.stats
    imgui.same_line()
    imgui.text(string.format("Scanned %s: %d appraised talismans (%d protected), %d of %d box slots used",
        scan.time, stats.appraised, stats.protected, stats.used, stats.slots))

    imgui.separator()
    draw_rules(state, actions)

    imgui.separator()
    local summary = scan.summary
    local reasons = summary.by_reason
    imgui.text(string.format("Sell %d, keep %d, for about %s z.", summary.sell, summary.keep, thousands(summary.zenny)))
    imgui.text(string.format("Covered %d, duplicates %d, rarity rule %d, protected %d",
        reasons.dominated or 0, reasons.duplicate or 0, reasons.rule or 0, reasons.protected or 0))
    draw_sell_controls(state, actions)

    imgui.separator()
    draw_table(scan)
end

function ui.menu(state)
    if imgui.tree_node("Bulk Sell Talismans") then
        local ok, err = pcall(function()
            imgui.text("Version " .. state.version)
            if imgui.button(state.settings.window_open and "Hide window##BulkSell" or "Show window##BulkSell") then
                state.settings.window_open = not state.settings.window_open
            end
        end)
        imgui.tree_pop()
        if not ok then error(err, 0) end
    end
end

function ui.window(state, actions)
    if not state.settings.window_open or not reframework:is_drawing_ui() then return end
    pcall(function() imgui.set_next_window_size(Vector2f.new(1000, 720), FIRST_USE_EVER) end)
    state.settings.window_open = imgui.begin_window("Bulk Sell Talismans##BulkSellWindow", true, 0)
    local ok, err = pcall(draw_body, state, actions)
    if not ok then imgui.text_colored("UI error: " .. tostring(err), RED) end
    imgui.end_window()
end

-- Exposed for tests.
ui._thousands = thousands
ui._verdict_text = verdict_text

return ui
