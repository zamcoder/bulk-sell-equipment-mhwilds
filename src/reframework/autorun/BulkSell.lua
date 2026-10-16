-- Bulk Sell Talismans for Monster Hunter Wilds (REFramework script).
--
-- Scans the Equipment Box, decides which appraised talismans are not needed
-- (covered by a kept talisman, duplicates, or the optional rarity rule) and
-- sells them the same way the game's View/Sell Equipment does. All game access
-- runs on the game thread (UpdateBehavior), spread over frames.

local analysis = require("BulkSell.analysis")
local config = require("BulkSell.config")
local game = require("BulkSell.game")
local ui = require("BulkSell.ui")

local VERSION = "0.2.2"
local FRAME_BUDGET = 0.004   -- seconds of work per game frame
local CONFIRM_SECONDS = 20
local RECEIPT_DIR = "BulkSell/receipts/"

local state = {
    version = VERSION,
    settings = config.load(),
    busy = false,
    error = nil,
    scan = nil,
    skill_names = {},
    job = nil,
    analyse_requested = false,
    revision = 0,
    block_reason = nil,   -- why selling cannot start right now (nil = it can)
    confirm = nil,        -- pending confirmation { count, zenny, label, limit, expires }
    sale = nil,           -- progress and result of the last sale
    stop_requested = false,
}

local function log_error(message)
    log.error("[BulkSell] " .. message)
end

local function skills_label(charm)
    local parts = {}
    for _, skill in ipairs(charm.skills) do
        parts[#parts + 1] = string.format("%s %d", state.skill_names[skill.id] or ("Skill #" .. skill.id), skill.level)
    end
    return string.format("R%d  %s", charm.rarity, #parts > 0 and table.concat(parts, ", ") or "(no skills)")
end

local function slots_label(charm)
    local parts = {}
    for _, slot in ipairs(charm.slots) do parts[#parts + 1] = slot.kind .. slot.level end
    return #parts > 0 and table.concat(parts, " ") or "-"
end

local function plan_options(yield)
    local settings = state.settings
    return {
        sell_dominated = settings.sell_dominated,
        rules = settings.rule_enabled and { max_rarity = settings.rule_max_rarity } or nil,
        keep_skills = config.keep_skills(settings),
        yield = yield,
    }
end

local function analyse(charms, stats)
    local verdicts = analysis.plan(charms, plan_options(coroutine.yield))
    state.revision = state.revision + 1
    local by_key = {}
    for _, charm in ipairs(charms) do by_key[charm.key] = charm end
    state.scan = {
        charms = charms,
        stats = stats,
        by_key = by_key,
        verdicts = verdicts,
        summary = analysis.summarize(charms, verdicts),
        skill_options = state.scan_skill_options,
        time = state.scan_time,
        revision = state.revision,
    }
end

local function scan_job()
    local charms, stats = game.read_talismans(coroutine.yield)
    if not charms then error(stats, 0) end

    -- Names are resolved here, on the game thread, and only read by the UI.
    local ids = {}
    for _, charm in ipairs(charms) do
        for _, skill in ipairs(charm.skills) do
            if not state.skill_names[skill.id] then state.skill_names[skill.id] = game.skill_name(skill.id) end
            ids[skill.id] = true
        end
        charm.skills_label = skills_label(charm)
        charm.slots_label = slots_label(charm)
    end
    local options = {}
    for id in pairs(ids) do options[#options + 1] = { id = id, name = state.skill_names[id] } end
    table.sort(options, function(a, b) return a.name < b.name end)
    state.scan_skill_options = { ids = {}, names = {} }
    for i, option in ipairs(options) do
        state.scan_skill_options.ids[i] = option.id
        state.scan_skill_options.names[i] = option.name
    end
    state.scan_time = os.date("%H:%M:%S")

    analyse(charms, stats)
end

-- Talismans the current scan would sell, in box order; `limit` caps the count.
local function sell_list(limit)
    local list = {}
    local scan = state.scan
    if not scan then return list end
    for _, charm in ipairs(scan.charms) do
        if scan.verdicts[charm.key].action == "sell" then
            list[#list + 1] = charm
            if limit and #list >= limit then break end
        end
    end
    return list
end

local function write_receipt(sale)
    local path = RECEIPT_DIR .. "sold_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    -- REFramework writes an empty Lua table as null, so empty lists become "none".
    local ok, result = pcall(json.dump_file, path, {
        version = VERSION,
        started = sale.started,
        finished = sale.finished,
        sold = sale.sold,
        zenny = sale.zenny,
        money_before = sale.money_before or "unknown",
        money_after = sale.money_after or "unknown",
        stopped = sale.stopped or "no",
        talismans = #sale.entries > 0 and sale.entries or "none",
        skipped = #sale.skipped > 0 and sale.skipped or "none",
    }, 2)
    if ok and result ~= false then return path end
    log_error("could not write receipt " .. path)
    return nil
end

local function sell_job(list)
    local sale = {
        total = #list, done = 0, sold = 0, zenny = 0, entries = {}, skipped = {},
        started = os.date("%Y-%m-%d %H:%M:%S"),
    }
    state.sale = sale
    local ctx, reason = game.begin_sale()
    if not ctx then error(reason, 0) end
    sale.money_before = game.money(ctx)
    local scan = state.scan

    -- pcall so a failure mid-run still ends with a receipt and a fresh scan.
    local ok, err = pcall(function()
        for _, charm in ipairs(list) do
            if state.stop_requested then
                sale.stopped = "Stopped by you."
                return
            end
            local blocked = game.menu_block_reason()
            if blocked then
                sale.stopped = blocked
                return
            end
            local verdict = scan.verdicts[charm.key]
            -- A covered or duplicate talisman is only sold while the one kept instead is still there.
            local keeper = verdict.ref and scan.by_key[verdict.ref]
            local result
            if keeper and not game.unchanged(ctx, keeper) then
                result = { sold = false, reason = "the talisman kept instead is gone" }
            else
                result = game.sell_one(ctx, charm)
            end
            sale.done = sale.done + 1
            if result.sold then
                sale.sold = sale.sold + 1
                sale.zenny = sale.zenny + result.price
                sale.entries[#sale.entries + 1] = {
                    box = charm.key, talisman = charm.skills_label, slots = charm.slots_label,
                    why = verdict.reason, price = result.price,
                }
            else
                sale.skipped[#sale.skipped + 1] = { box = charm.key, talisman = charm.skills_label, reason = result.reason }
            end
            if result.fatal then
                sale.stopped = result.reason
                log_error(result.reason)
                return
            end
            coroutine.yield()
        end
    end)
    if not ok then
        sale.stopped = "Error: " .. tostring(err)
        log_error(sale.stopped)
    end

    sale.money_after = game.money(ctx)
    sale.finished = os.date("%Y-%m-%d %H:%M:%S")
    sale.receipt = write_receipt(sale)
    -- The scan no longer matches the box.
    scan_job()
end

local function start(job)
    state.job = coroutine.create(job)
    state.busy = true
    state.error = nil
end

local actions = {
    scan = function()
        if not state.job then start(scan_job) end
    end,
    analyse = function()
        state.analyse_requested = true
    end,
    request_sell = function(limit)
        local list = sell_list(limit)
        if #list == 0 or state.job then return end
        local zenny = 0
        for _, charm in ipairs(list) do zenny = zenny + (charm.price or 0) end
        state.confirm = {
            count = #list,
            zenny = zenny,
            label = #list == 1 and (list[1].skills_label .. "  " .. list[1].slots_label) or nil,
            limit = limit,
            expires = os.clock() + CONFIRM_SECONDS,
        }
    end,
    confirm_sell = function()
        local confirm = state.confirm
        state.confirm = nil
        if not confirm or os.clock() > confirm.expires or state.job or state.block_reason then return end
        local list = sell_list(confirm.limit)
        state.stop_requested = false
        start(function() sell_job(list) end)
    end,
    cancel_sell = function()
        state.confirm = nil
    end,
    stop_sell = function()
        state.stop_requested = true
    end,
}

game.install_hooks()

-- Runs the current job on the game thread within the frame budget.
re.on_pre_application_entry("UpdateBehavior", function()
    if state.settings.window_open then
        state.block_reason = game.sell_unavailable() or game.menu_block_reason()
    end
    if state.confirm and os.clock() > state.confirm.expires then state.confirm = nil end

    if not state.job and state.analyse_requested and state.scan then
        state.analyse_requested = false
        config.save(state.settings)
        local scan = state.scan
        start(function() analyse(scan.charms, scan.stats) end)
    end
    local job = state.job
    if not job then return end

    local started = os.clock()
    repeat
        local ok, err = coroutine.resume(job)
        if not ok then
            state.error = tostring(err)
            log_error(state.error)
            break
        end
    until coroutine.status(job) == "dead" or os.clock() - started > FRAME_BUDGET

    if coroutine.status(job) == "dead" then
        state.job = nil
        state.busy = false
    end
end)

re.on_draw_ui(function()
    ui.menu(state)
    ui.window(state, actions)
end)

re.on_config_save(function()
    config.save(state.settings)
end)
