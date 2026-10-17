-- Bulk Sell Equipment for Monster Hunter Wilds (REFramework script).
--
-- Scans the Equipment Box, decides which appraised talismans are not needed
-- (duplicates, covered by a kept talisman, or - when the player chooses "Keep the
-- best N per skill" - unique talismans outside their best N) and sells them the
-- same way the game's View/Sell Equipment does. The player's own ticks (picks)
-- beat the rules. All game access runs on the game thread (UpdateBehavior),
-- spread over frames, and only while the REFramework menu is open.

local analysis = require("BulkSell.analysis")
local config = require("BulkSell.config")
local explain = require("BulkSell.explain")
local export = require("BulkSell.export")
local files = require("BulkSell.files")
local game = require("BulkSell.game")
local lang = require("BulkSell.lang")
local picks = require("BulkSell.picks")
local skills = require("BulkSell.skills")
local stars = require("BulkSell.stars")
local ui = require("BulkSell.ui")

local T = lang.T

local VERSION = "0.3.0"
local FRAME_BUDGET = 0.004       -- seconds of work per game frame
local CONFIRM_SECONDS = 20
local ANALYSE_DELAY = 0.25       -- settings and ticks are applied after this pause
local PICKS_SAVE_INTERVAL = 5    -- seconds between writes of the picks file
local RECEIPT_DIR = "BulkSell/receipts/"
local DEBUG_DIR = "BulkSell/debug/"
local MAX_KEPT_FOR = 10          -- refs listed per receipt entry
local SKILLS_CONFIRM = 10        -- "Set shown" on more skills than this asks first
local EXPORT_DIR = "BulkSell/export/"
-- Jobs that change the game finish on their own (and write their records) when the menu closes.
local STOPS_ITSELF = { sell = true, star = true }
-- Name languages for the wiki-db export: label key, via.Language value, file and site tag.
local EXPORT_LANGUAGES = {
    { "lang_game", nil, "game" }, { "lang_en", 1, "en" }, { "lang_ja", 0, "ja" }, { "lang_ko", 11, "ko" },
    { "lang_zh_hans", 13, "zh-hans" }, { "lang_zh_hant", 12, "zh-hant" },
}

local settings, migration_notice = config.load()

local state = {
    version = VERSION,
    settings = settings,
    busy = false,
    error = nil,
    scan = nil,
    skill_names = {},
    job = nil,
    job_name = nil,
    job_stats = nil,
    last_perf = nil,
    analyse_at = nil,     -- os.clock() when a pending analysis should start
    revision = 0,
    frame = 0,
    block_reason = nil,   -- why selling cannot start right now (nil = it can)
    menu_reason = nil,    -- a game menu is open or the game is saving (nil = neither)
    stale = false,        -- the box may have changed since the scan; rescan before selling
    drawing = false,
    confirm = nil,        -- pending confirmation, bound to one plan revision and its exact keys
    unique_ack = nil,     -- { hash, count } the player acknowledged this session
    notice = nil,         -- one-line message, e.g. why a confirmation was withdrawn
    notices = {},         -- messages with an OK button (migration, removed picks)
    picks = nil,          -- picks store of the current save slot
    picks_saved_at = 0,
    skills_undo = nil,    -- per-skill settings before the last change in the Skills panel
    skills_confirm = nil, -- a pending "Set shown" on many skills, or "Reset all"
    stars = nil,          -- the stars Bulk Sell added, for the current save slot
    star_confirm = nil,   -- a pending star job: { kind, keys, want, revision }
    star_run = nil,       -- progress and result of the last star job
    export_result = nil,  -- what the last export did
    clipboard = nil,      -- text the UI puts on the clipboard in its next frame
    sale = nil,           -- progress and result of the last sale
    stop_requested = false,
}
if migration_notice then state.notices[#state.notices + 1] = migration_notice end

local LIST_CHANGED = T("notice_list_changed")
local PLAN_MISMATCH = T("stop_plan_mismatch")

-- A confirmation only ever applies to the list it was shown for.
local function withdraw_confirm()
    if state.confirm then
        state.confirm = nil
        state.notice = LIST_CHANGED
    end
end

local function log_error(message)
    log.error("[BulkSell] " .. message)
end

local function log_info(message)
    log.info("[BulkSell] " .. message)
end

local function skills_label(charm)
    local parts = {}
    for _, skill in ipairs(charm.skills) do
        parts[#parts + 1] = string.format("%s %d", state.skill_names[skill.id] or T("skill_id", skill.id), skill.level)
    end
    return string.format("R%d  %s", charm.rarity, #parts > 0 and table.concat(parts, ", ") or T("no_skills"))
end

local function slots_label(charm)
    local parts = {}
    for _, slot in ipairs(charm.slots) do parts[#parts + 1] = slot.kind .. slot.level end
    return #parts > 0 and table.concat(parts, " ") or "-"
end

local function map_text(map)
    local keys = {}
    for key, value in pairs(map or {}) do keys[#keys + 1] = tostring(key) .. "=" .. tostring(value) end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Identifies the rules a unique-sale acknowledgement was given for.
local function rules_hash(options)
    return table.concat({ options.mode, options.best_n, options.max_rarity, map_text(options.keep_skills),
        map_text(options.ignore_skills), map_text(options.skill_places) }, "|")
end

local function save_picks(force)
    local store = state.picks
    if not store or not store.dirty or store.blocked or store.slot == nil then return true end
    state.picks_saved_at = os.clock()
    if picks.save(store, files.write_json, files.read_json) then return true end
    log_error("could not save the picks file for save slot " .. tostring(store.slot))
    if force then state.notice = T("notice_picks_not_saved") end
    return false
end

local function save_stars()
    local store = state.stars
    if not store or not store.dirty or store.blocked or store.slot == nil then return true end
    if stars.save(store, files.write_json, files.read_json) then return true end
    log_error("could not save the stars file for save slot " .. tostring(store.slot))
    return false
end

local function pick_notice_text(notices)
    local parts = {}
    for i, n in ipairs(notices) do
        if i > 4 then
            parts[#parts + 1] = T("and_more", #notices - 4)
            break
        end
        parts[#parts + 1] = string.format("#%d %s", n.key, n.what)
    end
    return T("notice_picks_removed", #notices, table.concat(parts, ", "))
end

-- JSON needs string keys: a Lua table like { [1] = 3 } would be written as the array [3].
local function string_keys(map, format)
    local out = { _format = format }
    for key, value in pairs(map or {}) do out[tostring(key)] = value end
    return out
end

-- Debug dump: everything needed to replay the plan offline with the reference model.
local function write_debug_dump(scan, options)
    local charms, verdicts = {}, { _format = "box -> verdict" }
    for i, c in ipairs(scan.charms) do
        charms[i] = { key = c.key, rarity = c.rarity, price = c.price, skills = c.skills, slots = c.slots,
            protected = c.protected, fingerprint = c.fingerprint }
        local v = scan.verdicts[c.key]
        verdicts[tostring(c.key)] = { action = v.action, reason = v.reason, ref = v.ref, refs = v.refs, detail = v.detail,
            unique = v.unique, drops = v.drops, shape_lost = v.shape_lost }
    end
    local preview = scan.info.preview
    local path = DEBUG_DIR .. "plan_" .. os.date("%Y%m%d_%H%M%S") .. "_r" .. scan.revision .. ".json"
    files.write_json(path, {
        version = VERSION, revision = scan.revision,
        options = { mode = options.mode, best_n = options.best_n, max_rarity = options.max_rarity,
            keep_skills = string_keys(options.keep_skills, "skill -> min level"),
            ignore_skills = string_keys(options.ignore_skills, "skill -> true"),
            skill_places = string_keys(options.skill_places, "skill -> places"),
            picks = string_keys(options.picks, "box -> pick") },
        charms = charms, verdicts = verdicts, perf = state.last_perf,
        preview = preview and { manual = preview.manual, covered = preview.covered, unlimited = preview.unlimited,
            best = string_keys(preview.best, "N -> count") },
    })
end

local function analyse(charms, stats, new_count)
    local previous = state.scan
    local store = state.picks
    local active, kept, notices = picks.reconcile(store.entries, charms)
    if #notices > 0 then
        store.entries = kept
        store.dirty = true
        state.notices[#state.notices + 1] = pick_notice_text(notices)
    end
    local options = config.plan_options(state.settings)
    options.picks = active
    options.yield = coroutine.yield
    local verdicts, info = analysis.plan(charms, options)
    options.yield = nil
    for _, p in ipairs(info.problems) do log_error("safety check: box " .. tostring(p.key) .. " " .. p.what) end

    withdraw_confirm()
    state.revision = state.revision + 1
    local by_key = {}
    for _, charm in ipairs(charms) do by_key[charm.key] = charm end
    local scan = {
        charms = charms,
        stats = stats,
        by_key = by_key,
        verdicts = verdicts,
        info = info,
        options = options,
        settings = config.validate(state.settings),   -- a copy: the texts describe this plan
        rules_hash = rules_hash(options),
        summary = analysis.summarize(charms, verdicts),
        skill_options = state.scan_skill_options,
        time = state.scan_time,
        revision = state.revision,
    }
    scan.ctx = { names = state.skill_names, by_key = by_key, info = info, settings = scan.settings, ignore = options.ignore_skills }
    if previous then
        -- What this plan changed against the one before: rule edits, ticks, or a rescan.
        local changed, keys, more, fewer = analysis.diff(previous.verdicts, verdicts), {}, 0, 0
        for _, key in ipairs(changed) do
            keys[key] = true
            if verdicts[key].action == "sell" then more = more + 1 else fewer = fewer + 1 end
        end
        scan.last_change = { what = skills.describe_change(previous.options, options), keys = keys, count = #changed,
            more = more, fewer = fewer }
    end
    scan.new_count = new_count
    if previous and previous.charms == charms then
        scan.last_of_kind, scan.new_count = previous.last_of_kind, previous.new_count
    else
        coroutine.yield()
        scan.last_of_kind = skills.last_of_kind(charms, info.entry_of)
    end
    state.scan = scan
    if state.settings.debug then
        coroutine.yield()
        local started = os.clock()
        write_debug_dump(scan, options)
        if state.job_stats then state.job_stats.dump = os.clock() - started end
    end
end

local function scan_job()
    state.stale = false
    state.analyse_at = nil   -- the scan's own analysis uses the current settings and ticks
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
    local new_count
    if state.scan then
        local before = {}
        for _, c in ipairs(state.scan.charms) do before[c.key] = c.fingerprint end
        new_count = 0
        for _, c in ipairs(charms) do
            if before[c.key] ~= c.fingerprint then new_count = new_count + 1 end
        end
    end

    -- Picks and the stars Bulk Sell added belong to one save slot and character.
    local store = state.picks
    if not store or store.slot ~= stats.save_slot or store.play_start ~= stats.play_start then
        if store then
            save_picks()
            save_stars()
        end
        local read = files.read_json
        if stats.save_slot ~= nil then
            local p, st = picks.paths(stats.save_slot), stars.paths(stats.save_slot)
            read = files.reader({ p.a, p.b, st.a, st.b })
        end
        state.picks = picks.load(stats.save_slot, stats.play_start, read)
        state.stars = stars.load(stats.save_slot, stats.play_start, read)
    end
    for _, key in ipairs(stars.stale_keys(state.stars, charms)) do stars.forget(state.stars, key) end
    save_stars()
    analyse(charms, stats, new_count)
end

local function cheapest(list)
    local best
    for _, charm in ipairs(list) do
        if not best or (charm.price or 0) < (best.price or 0)
            or ((charm.price or 0) == (best.price or 0) and (charm.rarity < best.rarity
                or (charm.rarity == best.rarity and charm.key < best.key))) then
            best = charm
        end
    end
    return best
end

-- Skill levels and slot shapes the box would lose if `selling` ({ [key] = true }) were sold.
local function confirm_losses(scan, chosen, selling)
    local any = false
    for _, charm in ipairs(chosen) do
        local v = scan.verdicts[charm.key]
        if v.drops or v.ignored_drops or v.shape_lost then any = true end
    end
    -- A part of the planned sales can only lose what the whole plan loses.
    if not any then return {}, {} end
    local drops = analysis.losses(scan.charms, selling)
    local shapes, checked = {}, {}
    local entry_of = scan.info.entry_of
    for _, charm in ipairs(chosen) do
        local e = entry_of[charm.key]
        if e.nslots > 0 and not checked[e.shape] then
            checked[e.shape] = true
            local held = false
            for _, other in ipairs(scan.charms) do
                if not selling[other.key] and analysis.holds(entry_of[other.key].slots, e.slots) then
                    held = true
                    break
                end
            end
            if not held then shapes[#shapes + 1] = { shape = e.shape, box = charm.key } end
        end
    end
    return drops, shapes
end

-- The verdict's Why text, the talismans kept for it, and what it loses: receipt fields.
local function receipt_entry(scan, charm, verdict, result)
    local why = explain.why(scan.ctx, charm, verdict)
    local entry = {
        box = charm.key, talisman = charm.skills_label, slots = charm.slots_label,
        why = verdict.reason, class = explain.class(verdict), detail = why,
        price = result.price, price_source = result.price_source,
        kept_instead = verdict.ref or verdict.covered_by or "none",
    }
    if verdict.refs then
        local kept_for = {}
        for i = 1, math.min(#verdict.refs, MAX_KEPT_FOR) do kept_for[i] = verdict.refs[i] end
        entry.kept_for, entry.kept_for_total = kept_for, #verdict.refs
    end
    if verdict.rank then entry.rank = verdict.rank.rank end
    local lost = {}
    for _, d in ipairs(verdict.drops or {}) do lost[#lost + 1] = explain.skill_name(scan.ctx, d.id) .. " " .. d.level end
    for _, d in ipairs(verdict.ignored_drops or {}) do lost[#lost + 1] = explain.skill_name(scan.ctx, d.id) .. " " .. d.level end
    if verdict.shape_lost then lost[#lost + 1] = explain.shape_label(verdict.shape_lost) end
    entry.lost = #lost > 0 and table.concat(lost, ", ") or "none"
    return entry
end

local function non_empty(map)
    return next(map or {}) and map or "none"
end

local function write_receipt(sale, scan, confirm)
    local path = RECEIPT_DIR .. "sold_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local options = scan and scan.options or {}
    local sell_picks, keep_picks = 0, 0
    for _, action in pairs(options.picks or {}) do
        if action == "sell" then sell_picks = sell_picks + 1 else keep_picks = keep_picks + 1 end
    end
    -- REFramework writes an empty Lua table as null, so empty lists become "none".
    local ok = files.write_json(path, {
        version = VERSION,
        trigger = "manual",
        started = sale.started,
        finished = sale.finished,
        sold = sale.sold,
        zenny = sale.zenny,
        money_before = sale.money_before or "unknown",
        money_after = sale.money_after or "unknown",
        stopped = sale.stopped or "no",
        plan_revision = confirm.revision,
        rules = {
            mode = options.mode, best_n = options.best_n, max_rarity = options.max_rarity,
            always_keep = non_empty(options.keep_skills), dont_care = non_empty(options.ignore_skills),
            places = non_empty(options.skill_places), decorations = "off",
        },
        acknowledged = { unique = confirm.ack_unique == true, losses = confirm.ack_loss == true },
        picks = { sell = sell_picks, keep = keep_picks },
        talismans = #sale.entries > 0 and sale.entries or "none",
        skipped = #sale.skipped > 0 and sale.skipped or "none",
    })
    if ok then return path end
    log_error("could not write receipt " .. path)
    return nil
end

-- Sells exactly the keys of a confirmation, and only while they still belong to the
-- confirmed plan revision and are planned for sale there.
local function sell_job(confirm)
    local keys = confirm.keys
    local sale = {
        total = #keys, done = 0, sold = 0, zenny = 0, entries = {}, skipped = {},
        started = os.date("%Y-%m-%d %H:%M:%S"),
    }
    state.sale = sale
    save_picks(true)
    coroutine.yield()   -- file work gets a frame of its own
    local ctx, reason = game.begin_sale()
    if not ctx then error(reason, 0) end
    sale.money_before = game.money(ctx)
    coroutine.yield()
    local scan = state.scan
    local sold, sold_keys = {}, {}

    -- Whether a kept talisman (ref) is still exactly in the box; asked once per frame.
    local memo, memo_frame = {}, -1
    local function still_there(key)
        if memo_frame ~= state.frame then memo, memo_frame = {}, state.frame end
        local result = memo[key]
        if result == nil then
            result = game.unchanged(ctx, scan.by_key[key])
            memo[key] = result
        end
        return result
    end

    -- pcall so a failure mid-run still ends with a receipt and a fresh scan.
    local ok, err = pcall(function()
        if not scan or scan.revision ~= confirm.revision then
            sale.stopped = LIST_CHANGED
            return
        end
        -- Every key must be a planned sale of this revision before anything is sold.
        for _, key in ipairs(keys) do
            local charm, verdict = scan.by_key[key], scan.verdicts[key]
            if not charm or charm.key ~= key or not verdict or verdict.action ~= "sell" then
                sale.stopped = PLAN_MISMATCH
                log_error(PLAN_MISMATCH .. " (box " .. tostring(key) .. ")")
                return
            end
        end
        for _, key in ipairs(keys) do
            if state.stop_requested then
                sale.stopped = T("stop_by_you")
                return
            end
            if not reframework:is_drawing_ui() then
                sale.stopped = T("stop_menu_closed")
                return
            end
            local blocked = game.menu_block_reason()
            if blocked then
                sale.stopped = blocked
                return
            end
            local charm, verdict = scan.by_key[key], scan.verdicts[key]
            -- Kept talismans are never sold, so a reference to one sold in this run is a bug.
            local refs = verdict.refs or {}
            local bad_ref = verdict.ref ~= nil and sold[verdict.ref]
            for _, r in ipairs(refs) do
                if sold[r] then bad_ref = true end
            end
            if bad_ref then
                sale.stopped = PLAN_MISMATCH
                log_error(PLAN_MISMATCH .. " (box " .. tostring(key) .. " refers to a talisman sold in this run)")
                return
            end
            local result
            if verdict.ref and not still_there(verdict.ref) then
                result = { sold = false, reason = T("skip_kept_instead_gone") }
            else
                for _, r in ipairs(refs) do
                    if not still_there(r) then
                        result = { sold = false, reason = T("skip_kept_for_changed", r) }
                        break
                    end
                end
            end
            result = result or game.sell_one(ctx, charm)
            sale.done = sale.done + 1
            if result.sold then
                sold[key] = true
                sold_keys[#sold_keys + 1] = key
                sale.sold = sale.sold + 1
                sale.zenny = sale.zenny + result.price
                sale.entries[#sale.entries + 1] = receipt_entry(scan, charm, verdict, result)
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
        sale.stopped = T("stop_error", tostring(err))
        log_error(sale.stopped)
    end

    if reframework:is_drawing_ui() then sale.money_after = game.money(ctx) end
    sale.finished = os.date("%Y-%m-%d %H:%M:%S")
    sale.receipt = write_receipt(sale, scan, confirm)
    if state.picks then
        picks.remove(state.picks, sold_keys)
        save_picks(true)
    end
    -- The scan no longer matches the box; it is made again as soon as the menu is open.
    state.stale = true
end

-- Sets (want = true) or removes the favorite star of exactly the keys of a confirmation.
local function star_job(job)
    local run = { kind = job.kind, want = job.want, total = #job.keys, done = 0, changed = 0, skipped = {} }
    state.star_run = run
    local ctx, reason = game.begin_star()
    if not ctx then error(reason, 0) end
    local scan = state.scan
    local ok, err = pcall(function()
        if not scan or scan.revision ~= job.revision then
            run.stopped = LIST_CHANGED
            return
        end
        for _, key in ipairs(job.keys) do
            if state.stop_requested then
                run.stopped = T("stop_by_you")
                return
            end
            if not reframework:is_drawing_ui() then
                run.stopped = T("stop_menu_closed")
                return
            end
            local blocked = game.menu_block_reason()
            if blocked then
                run.stopped = blocked
                return
            end
            local charm = scan.by_key[key]
            local result = game.set_favorite(ctx, charm, job.want)
            run.done = run.done + 1
            if result.done then
                run.changed = run.changed + 1
                if job.want then stars.add(state.stars, charm) else stars.forget(state.stars, key) end
            elseif result.already then
                if not job.want then stars.forget(state.stars, key) end
            elseif result.fatal then
                run.stopped = result.reason
                log_error(result.reason)
                return
            else
                run.skipped[#run.skipped + 1] = { box = key, reason = result.reason }
            end
            coroutine.yield()
        end
    end)
    if not ok then
        run.stopped = T("stop_error", tostring(err))
        log_error(run.stopped)
    end
    if not save_stars() then run.stopped = run.stopped or T("stars_not_saved") end
    run.finished = true
    -- Favorites are protected, so the plan changes.
    state.stale = true
end

local function write_text(path, text)
    if type(fs) ~= "table" or type(fs.write) ~= "function" then return false end
    local ok, result = pcall(fs.write, path, text)
    return ok and result ~= false
end

-- Skill names for an export: the game's language, or another one through the game's texts.
local function export_names(list, language)
    if language == nil then return state.skill_names, false end
    local names, missing = {}, false
    for _, charm in ipairs(list) do
        for _, skill in ipairs(charm.skills) do
            if names[skill.id] == nil then
                local name = game.skill_name_in(skill.id, language)
                if not name then missing = true end
                names[skill.id] = name or state.skill_names[skill.id]
            end
        end
    end
    return names, missing
end

local function export_job(job)
    local scan = state.scan
    local list = export.select(scan.charms, scan.verdicts, job.scope)
    local stamp = os.date("%Y%m%d_%H%M%S")
    local result = { kind = job.kind, count = #list }
    if job.kind == "wikidb" then
        local names, missing = export_names(list, job.language[2])
        local text = export.wikidb(list, names)
        result.missing_names = missing
        state.clipboard = text
        result.path = EXPORT_DIR .. "wikidb_" .. job.language[3] .. "_" .. stamp .. ".txt"
        if not write_text(result.path, text) then result.path = nil end
    else
        local ctx = scan.ctx
        local text = export.csv(list, scan.verdicts, state.skill_names,
            function(v) return explain.verdict_label(ctx, v) end,
            function(charm, v) return (explain.why(ctx, charm, v)) end)
        result.path = EXPORT_DIR .. "talismans_" .. stamp .. ".csv"
        if not write_text(result.path, text) then
            result.path = nil
            result.failed = true
        end
    end
    state.export_result = result
end

local function start(name, job)
    state.job = coroutine.create(job)
    state.job_name = name
    state.job_stats = { name = name, frames = 0, longest = 0, slow = 0, started = os.clock() }
    state.busy = true
    state.error = nil
end

local function cancel_job()
    state.job, state.job_name, state.job_stats, state.busy = nil, nil, nil, false
end

local function request_analysis()
    state.analyse_at = os.clock() + ANALYSE_DELAY
    withdraw_confirm()
end

local function planned_sales(list)
    local scan, out = state.scan, {}
    for _, charm in ipairs(list) do
        if scan.verdicts[charm.key].action == "sell" then out[#out + 1] = charm end
    end
    return out
end

local actions = {
    scan = function()
        if not state.job then start("scan", scan_job) end
    end,
    analyse = request_analysis,
    -- kind: "all" (every planned sale), "shown" (the planned sales in `list`, the rows the
    -- filter shows) or "one" (the cheapest planned sale in `list`).
    request_sell = function(kind, list)
        local scan = state.scan
        if not scan or state.job or state.stale or state.analyse_at then return end
        local chosen = planned_sales(kind == "all" and scan.charms or list or scan.charms)
        if kind == "one" then chosen = { cheapest(chosen) } end
        if #chosen == 0 then return end
        local keys, selling, zenny = {}, {}, 0
        local unique_rule, unique_picks, picked = 0, 0, 0
        for i, charm in ipairs(chosen) do
            keys[i] = charm.key
            selling[charm.key] = true
            zenny = zenny + (charm.price or 0)
            local v = scan.verdicts[charm.key]
            if v.reason == "picked" then picked = picked + 1 end
            if v.unique then
                if v.reason == "rule" then unique_rule = unique_rule + 1 else unique_picks = unique_picks + 1 end
            end
        end
        local drops, shapes = confirm_losses(scan, chosen, selling)
        local ack = state.unique_ack
        state.notice = nil
        state.confirm = {
            revision = scan.revision,
            keys = keys,
            count = #chosen,
            zenny = zenny,
            label = #chosen == 1 and (chosen[1].skills_label .. "  " .. chosen[1].slots_label) or nil,
            unique_rule = unique_rule,
            unique_picks = unique_picks,
            picks = picked,
            share = scan.stats.appraised > 0 and (#chosen * 100 // scan.stats.appraised) or 0,
            drops = drops,
            shapes = shapes,
            rules_hash = scan.rules_hash,
            need_unique = unique_rule > 0 and not (ack and ack.hash == scan.rules_hash and unique_rule <= ack.count),
            need_loss = #drops > 0 or #shapes > 0,
            ack_unique = false,
            ack_loss = false,
            expires = os.clock() + CONFIRM_SECONDS,
        }
    end,
    confirm_sell = function()
        local confirm = state.confirm
        state.confirm = nil
        if not confirm or os.clock() > confirm.expires or state.job or state.block_reason then return end
        if (confirm.need_unique and not confirm.ack_unique) or (confirm.need_loss and not confirm.ack_loss) then return end
        if state.stale or state.analyse_at or not state.scan or state.scan.revision ~= confirm.revision then
            state.notice = LIST_CHANGED
            return
        end
        if confirm.need_unique then state.unique_ack = { hash = confirm.rules_hash, count = confirm.unique_rule } end
        state.stop_requested = false
        start("sell", function() sell_job(confirm) end)
    end,
    cancel_sell = function()
        state.confirm = nil
    end,
    stop_sell = function()
        state.stop_requested = true
    end,
    -- A click on a row's Sell box (`shown` = what the box shows now).
    click = function(charm, shown)
        if not state.picks or state.job_name == "sell" then return end
        if picks.click(state.picks, charm, shown) then request_analysis() end
    end,
    mark = function(list, action)
        if not state.picks or state.job_name == "sell" then return end
        if picks.mark(state.picks, list, action) > 0 then request_analysis() end
    end,
    undo = function()
        if state.picks and state.job_name ~= "sell" and picks.undo(state.picks) then request_analysis() end
    end,
    continue_without_picks = function()
        if not state.picks then return end
        picks.continue_without(state.picks)
        request_analysis()
    end,
    dismiss_notice = function(i)
        table.remove(state.notices, i)
    end,

    -- Stars: kind "kept" (every kept talisman), "picks" (your Keep picks) or "remove" (the
    -- stars Bulk Sell added). Nothing happens before confirm_star.
    request_star = function(kind)
        local scan = state.scan
        if not scan or state.job or state.stale or not state.stars or state.stars.blocked then return end
        local keys, want = {}, kind ~= "remove"
        if kind == "remove" then
            for i, charm in ipairs(stars.removable(state.stars, scan.charms)) do keys[i] = charm.key end
        else
            for _, charm in ipairs(scan.charms) do
                local v = scan.verdicts[charm.key]
                if v.action == "keep" and not charm.favorite and (kind == "kept" or v.reason == "picked") then
                    keys[#keys + 1] = charm.key
                end
            end
        end
        if #keys == 0 then return end
        state.star_confirm = { kind = kind, keys = keys, want = want, revision = scan.revision }
    end,
    confirm_star = function()
        local job = state.star_confirm
        state.star_confirm = nil
        if not job or state.job or state.block_reason or state.stale or not state.scan or state.scan.revision ~= job.revision then return end
        state.stop_requested = false
        start("star", function() star_job(job) end)
    end,
    cancel_star = function()
        state.star_confirm = nil
    end,
    -- Exports: scope "all" / "stays" / "sell"; language index into EXPORT_LANGUAGES.
    export_wikidb = function(scope, language)
        if not state.scan or state.job then return end
        start("export", function() export_job({ kind = "wikidb", scope = scope, language = EXPORT_LANGUAGES[language] or EXPORT_LANGUAGES[1] }) end)
    end,
    export_csv = function(scope)
        if not state.scan or state.job then return end
        start("export", function() export_job({ kind = "csv", scope = scope }) end)
    end,
    clipboard_done = function()
        state.clipboard = nil
    end,

    -- Skills panel: one skill, the skills a Find shows, Undo and Reset all.
    set_skill = function(id, pref)
        state.skills_undo = skills.copy_prefs(state.settings)
        skills.set(state.settings, id, pref)
        request_analysis()
    end,
    set_skills = function(ids, pref)
        if #ids == 0 then return end
        if #ids > SKILLS_CONFIRM then
            state.skills_confirm = { ids = ids, pref = pref }
            return
        end
        state.skills_undo = skills.copy_prefs(state.settings)
        for _, id in ipairs(ids) do skills.set(state.settings, id, pref) end
        request_analysis()
    end,
    reset_skills = function()
        state.skills_confirm = { reset = true }
    end,
    confirm_skills = function()
        local pending = state.skills_confirm
        state.skills_confirm = nil
        if not pending then return end
        state.skills_undo = skills.copy_prefs(state.settings)
        if pending.reset then
            skills.restore_prefs(state.settings, {
                keep_skills = { _format = state.settings.keep_skills._format },
                skill_places = { _format = state.settings.skill_places._format },
                ignore_skills = { _format = state.settings.ignore_skills._format },
            })
        else
            for _, id in ipairs(pending.ids) do skills.set(state.settings, id, pending.pref) end
        end
        request_analysis()
    end,
    cancel_skills = function()
        state.skills_confirm = nil
    end,
    undo_skills = function()
        if not state.skills_undo then return end
        skills.restore_prefs(state.settings, state.skills_undo)
        state.skills_undo = nil
        request_analysis()
    end,
}

-- The REFramework menu was closed: the player can use the game again, so the box may change.
local function on_menu_closed()
    if state.scan then
        state.stale = true
        withdraw_confirm()
    end
    if state.job and not STOPS_ITSELF[state.job_name] then cancel_job() end
end

game.install_hooks()

-- Runs the current job on the game thread within the frame budget.
re.on_pre_application_entry("UpdateBehavior", function()
    state.frame = state.frame + 1
    local drawing = reframework:is_drawing_ui()
    if state.drawing and not drawing then on_menu_closed() end
    state.drawing = drawing

    -- The game is only asked about menus while the window can actually be seen.
    if drawing and state.settings.window_open then
        local reason, touched = game.menu_block_reason()
        if touched or game.take_list_opened() then
            if state.scan and not state.stale and not STOPS_ITSELF[state.job_name] then
                state.stale = true
                withdraw_confirm()
            end
        end
        state.menu_reason = reason
        state.block_reason = game.sell_unavailable()
            or (state.scan and state.scan.stats.blocked)
            or (state.picks and state.picks.blocked)
            or reason
    end
    if state.confirm and os.clock() > state.confirm.expires then state.confirm = nil end

    if not state.job then
        if drawing and state.settings.window_open and state.stale and state.scan and not state.menu_reason then
            start("scan", scan_job)
        elseif state.analyse_at and os.clock() >= state.analyse_at and state.scan then
            state.analyse_at = nil
            config.save(state.settings)
            local scan = state.scan
            start("analyse", function() analyse(scan.charms, scan.stats) end)
        elseif state.picks and state.picks.dirty and os.clock() - state.picks_saved_at >= PICKS_SAVE_INTERVAL then
            save_picks()
        end
    end
    local job = state.job
    if not job then return end
    -- A scan or analysis is only worth finishing while the player can see it.
    if not drawing and not STOPS_ITSELF[state.job_name] then return end

    local job_stats = state.job_stats
    job_stats.frames = job_stats.frames + 1
    local started = os.clock()
    repeat
        local before = os.clock()
        local ok, err = coroutine.resume(job)
        local took = os.clock() - before
        if took > job_stats.longest then job_stats.longest = took end
        if took > 0.006 then job_stats.slow = job_stats.slow + 1 end
        if not ok then
            state.error = tostring(err)
            log_error(state.error)
            break
        end
    until coroutine.status(job) == "dead" or os.clock() - started > FRAME_BUDGET

    if coroutine.status(job) == "dead" then
        job_stats.seconds = os.clock() - job_stats.started
        state.last_perf = job_stats
        if state.settings.debug then
            log_info(string.format("%s done in %d frames (%.3f s), longest resume %.1f ms, resumes over 6 ms: %d%s",
                job_stats.name, job_stats.frames, job_stats.seconds, job_stats.longest * 1000, job_stats.slow,
                job_stats.dump and string.format(" (debug dump %.1f ms)", job_stats.dump * 1000) or ""))
        end
        cancel_job()
    end
end)

re.on_draw_ui(function()
    ui.menu(state)
    ui.window(state, actions)
end)

re.on_config_save(function()
    config.save(state.settings)
    save_picks()
    save_stars()
end)

-- Offline tests set BULKSELL_TEST before loading the script to reach its state.
state.export_languages = EXPORT_LANGUAGES
if type(BULKSELL_TEST) == "table" then
    BULKSELL_TEST.state = state
    BULKSELL_TEST.actions = actions
end
