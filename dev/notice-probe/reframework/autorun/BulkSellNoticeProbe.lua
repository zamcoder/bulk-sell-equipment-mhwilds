-- Notice probe, development only, never shipped, read-only.
--
-- Looks for the game's own on-screen notices (chat log, system messages, info pop-ups), so a
-- later version can show Bulk Sell's messages in the game's style. It only reads type and
-- method names from the type database; it never calls a game method.
-- Result: BulkSellProbe/notice_candidates_<time>.json.

local files = require("BulkSell.files")

local TYPE_PATTERNS = { "[Cc]hat", "[Nn]otice", "[Nn]otif", "[Ss]ystemMessage", "[Ss]ysMsg", "[Mm]sgLog", "[Ll]ogManager",
    "[Mm]essageLog", "[Ii]nfoLog", "[Tt]oast", "[Aa]nnounce", "[Pp]opup" }
local METHOD_PATTERN_A = { "[Rr]eq", "[Aa]dd", "[Pp]ush", "[Oo]pen", "[Ss]how", "[Nn]otify", "[Ss]et", "[Ss]tart", "[Rr]egister" }
local METHOD_PATTERN_B = { "[Mm]sg", "[Mm]essage", "[Ll]og", "[Nn]otice", "[Cc]hat", "[Ii]nfo", "[Tt]ext", "[Ss]ystem" }
local MAX_TYPES = 400
local FRAME_BUDGET = 0.004

local state = { status = "idle", job = nil, last_file = nil }

local function matches_any(text, patterns)
    for _, p in ipairs(patterns) do
        if text:find(p) then return true end
    end
    return false
end

local function menu_open()
    local gui = sdk.get_managed_singleton("app.GUIManager")
    local td = sdk.find_type_definition("app.GUIManager")
    local open = td and td:get_method("isOpenFullScreenUI()")
    if not gui or not open then return false end
    local ok, value = pcall(open.call, open, gui)
    return ok and value == true
end

local function signature(m)
    local ok, text = pcall(function()
        local params = {}
        for i, t in ipairs(m:get_param_types() or {}) do params[i] = t:get_full_name() end
        local ret = m:get_return_type()
        return (ret and ret:get_full_name() or "?") .. " " .. m:get_name() .. "(" .. table.concat(params, ", ") .. ")"
            .. (m:is_static() and " static" or "")
    end)
    return ok and text or "?"
end

local function scan_types()
    if type(sdk.get_tdb) ~= "function" then error("sdk.get_tdb is not available in this REFramework build", 0) end
    local tdb = sdk.get_tdb()
    local count = tdb:get_num_types()
    local found, types_seen = {}, 0
    for i = 0, count - 1 do
        local ok, td = pcall(tdb.get_type, tdb, i)
        local name = ok and td and td:get_full_name()
        if name and name:find("^app%.") and matches_any(name, TYPE_PATTERNS) and #found < MAX_TYPES then
            local entry = { type = name, singleton = sdk.get_managed_singleton(name) ~= nil, methods = {} }
            for _, m in ipairs(td:get_methods() or {}) do
                local mname = m:get_name()
                if matches_any(mname, METHOD_PATTERN_A) and matches_any(mname, METHOD_PATTERN_B) then
                    entry.methods[#entry.methods + 1] = signature(m)
                end
            end
            if #entry.methods > 0 or entry.singleton then found[#found + 1] = entry end
        end
        types_seen = i + 1
        if i % 512 == 511 then
            if menu_open() then error("stopped: a game menu is open. Close it and press the button again.", 0) end
            coroutine.yield()
        end
    end
    local path = "BulkSellProbe/notice_candidates_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    assert(files.write_json(path, { types_seen = types_seen, total = count, found = #found > 0 and found or "none" }),
        "could not write " .. path)
    state.last_file = path
    state.status = string.format("done: %d types read, %d candidates", types_seen, #found)
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
            log.error("[BulkSellNoticeProbe] " .. state.status)
            return
        end
    until coroutine.status(job) == "dead" or os.clock() - started > FRAME_BUDGET
    if coroutine.status(job) == "dead" then state.job = nil end
end)

re.on_draw_ui(function()
    if imgui.tree_node("BulkSell Notice probe (dev)") then
        imgui.text("Status: " .. state.status)
        if state.last_file then imgui.text("Last file: reframework/data/" .. state.last_file) end
        if not state.job and imgui.button("List game notice methods (read-only)") then
            state.status = "running..."
            state.job = coroutine.create(scan_types)
        end
        imgui.tree_pop()
    end
end)
