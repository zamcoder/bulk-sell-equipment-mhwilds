-- One-time compensation, development only, never shipped.
--
-- v0.2.0 paid 6,400 z instead of 8,000 z for box 923 (receipt sold_20261016_004431.json).
-- This adds the missing 1,600 z exactly once, on the game thread, and writes a receipt.
-- A marker file makes a second payment impossible:
--   pending  written (and read back) before addMoney
--   done     written after zenny rose by exactly the amount
-- A pending marker found later is only finalized when zenny already shows the payment.

local files = require("BulkSell.files")

local AMOUNT = 1600
local MARKER = "BulkSell/compensation/v020-box923.json"
local V020_RECEIPT = "BulkSell/receipts/sold_20261016_004431.json"
local FRAME_BUDGET = 0.004

local state = { status = "idle", job = nil }

local function method(type_name, signature)
    local td = sdk.find_type_definition(type_name)
    return td and td:get_method(signature)
end

local function number(value)
    if type(value) ~= "number" then return nil end
    return math.tointeger(value) or value
end

local function basic_param()
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local getter = method("app.SaveDataManager", "getCurrentUserSaveData()")
    assert(manager and getter, "save data manager not ready")
    local save = assert(getter:call(manager), "no save loaded")
    return assert(save:get_field("_BasicData"), "no basic data")
end

local function money(basic)
    local getter = assert(method("app.savedata.cBasicParam", "getMoney()"), "getMoney missing")
    return assert(number(getter:call(basic)), "zenny unreadable")
end

-- Writes and reads back; returns true only when the file round-trips.
local function write_checked(path, value)
    if not files.write_json(path, value) then return false end
    local status, loaded = files.read_json(path)
    return status == "ok" and loaded.state == value.state and loaded.money_before == value.money_before
end

local function busy_reason()
    local gui = sdk.get_managed_singleton("app.GUIManager")
    local open = method("app.GUIManager", "isOpenFullScreenUI()")
    if not gui or not open then return "game menus not ready" end
    local ok, is_open = pcall(open.call, open, gui)
    if not ok or is_open ~= false then return "close the game menu first" end
    local save_manager = sdk.get_managed_singleton("app.SaveDataManager")
    for _, signature in ipairs({ "get_IsSaveLoadFlowRunning()", "get_IsShowSaving()" }) do
        local getter = method("app.SaveDataManager", signature)
        if getter then
            local saving_ok, saving = pcall(getter.call, getter, save_manager)
            if not saving_ok or saving ~= false then return "the game is saving; try again in a moment" end
        end
    end
    return nil
end

local function finish(basic, marker, after)
    local receipt = {
        kind = "compensation",
        reason = "v0.2.0 paid 6,400 z instead of 8,000 z for box 923",
        amount = AMOUNT,
        money_before = marker.money_before,
        money_after = after,
        at = os.date("%Y-%m-%d %H:%M:%S"),
    }
    assert(files.write_json("BulkSell/receipts/compensation_" .. os.date("%Y%m%d_%H%M%S") .. ".json", receipt),
        "could not write the compensation receipt (the zenny was added)")
    local done = { state = "done", amount = AMOUNT, money_before = marker.money_before, money_after = after, at = receipt.at }
    assert(write_checked(MARKER, done), "could not write the done marker (the zenny was added)")
    state.status = string.format("OK: +%s exact (%d -> %d)", "1,600", marker.money_before, after)
end

local function compensate()
    local busy = busy_reason()
    if busy then error("not now: " .. busy, 0) end
    local basic = basic_param()

    local status, marker = files.read_json(MARKER)
    if status == "corrupt" then error("the marker file is unreadable; nothing was paid", 0) end
    if status == "ok" then
        if marker.state == "done" then
            state.status = "Already done; nothing paid."
            return
        end
        if marker.state == "pending" and number(marker.money_before) then
            local now = money(basic)
            if now == marker.money_before + AMOUNT then
                finish(basic, marker, now)
                return
            end
            error(string.format("a pending marker exists and zenny is %d (before: %d); nothing paid. Please report this.",
                now, marker.money_before), 0)
        end
        error("the marker file has an unknown state; nothing paid", 0)
    end
    -- A receipt without a marker means the marker was removed by hand: never pay again.
    if type(fs) == "table" and type(fs.glob) == "function" then
        local ok, found = pcall(fs.glob, "^BulkSell[\\\\/]receipts[\\\\/]compensation_.*\\.json$")
        if not ok or type(found) ~= "table" or #found > 0 then
            error("a compensation receipt already exists; nothing paid", 0)
        end
    end

    local v020_status, v020 = files.read_json(V020_RECEIPT)
    local first = v020_status == "ok" and type(v020.talismans) == "table" and v020.talismans[1]
    if not first or first.box ~= 923 or first.price ~= 6400 then
        error("the v0.2.0 receipt does not show box 923 paid 6,400 z; nothing paid", 0)
    end

    local before = money(basic)
    local pending = { state = "pending", amount = AMOUNT, money_before = before, at = os.date("%Y-%m-%d %H:%M:%S") }
    if not write_checked(MARKER, pending) then error("could not write the pending marker; nothing paid", 0) end

    local add = assert(method("app.savedata.cBasicParam", "addMoney(System.Int32, System.Boolean)"), "addMoney missing")
    add:call(basic, AMOUNT, true)
    local after = money(basic)
    if after - before ~= AMOUNT then
        error(string.format("zenny changed by %d instead of %d; the pending marker stays. Please report this.", after - before, AMOUNT), 0)
    end
    finish(basic, pending, after)
end

re.on_pre_application_entry("UpdateBehavior", function()
    local job = state.job
    if not job then return end
    local started = os.clock()
    repeat
        local ok, err = coroutine.resume(job)
        if not ok then
            state.job = nil
            state.status = "FAILED: " .. tostring(err)
            log.error("[BulkSellCompensate] " .. state.status)
            return
        end
    until coroutine.status(job) == "dead" or os.clock() - started > FRAME_BUDGET
    if coroutine.status(job) == "dead" then state.job = nil end
end)

re.on_draw_ui(function()
    if imgui.tree_node("BulkSell Compensation (dev)") then
        imgui.text("Status: " .. state.status)
        if not state.job and imgui.button("Compensate +1,600 z") then
            state.status = "running..."
            state.job = coroutine.create(compensate)
        end
        imgui.tree_pop()
    end
end)
