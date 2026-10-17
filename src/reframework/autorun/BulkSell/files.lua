-- JSON files under reframework/data, read without REFramework's "[JSON] Failed to load
-- file" log line for files that do not exist, and with missing told apart from corrupt.
--
-- fs.read returns "" both for a missing and for an empty file, so fs.glob decides
-- whether the file exists. fs.glob matches a std::regex against paths relative to
-- reframework/data, and Windows paths use backslashes, so "/" matches either one.

local files = {}

local function has(lib, name)
    return type(lib) == "table" and type(lib[name]) == "function"
end

function files.pattern(path)
    local escaped = path:gsub("%.", "\\."):gsub("/", "[\\\\/]")
    return "^" .. escaped .. "$"
end

-- true or false, or nil when fs.glob is not available.
function files.exists(path)
    if not has(fs, "glob") then return nil end
    local ok, matches = pcall(fs.glob, files.pattern(path))
    if not ok or type(matches) ~= "table" then return nil end
    return #matches > 0
end

-- Returns "ok" plus the decoded value, "missing", or "corrupt".
-- Without fs.read/json.load_string (older REFramework) it falls back to json.load_file,
-- which cannot tell a corrupt file from a missing one.
function files.read_json(path)
    if not has(fs, "read") or not has(json, "load_string") then
        local ok, value = pcall(json.load_file, path)
        if ok and value ~= nil then return "ok", value end
        return "missing"
    end
    local exists = files.exists(path)
    local ok, text = pcall(fs.read, path)
    if not ok or type(text) ~= "string" then return exists and "corrupt" or "missing" end
    if text == "" then return exists and "corrupt" or "missing" end
    local parsed, value = pcall(json.load_string, text)
    if not parsed or type(value) ~= "table" then return "corrupt" end
    return "ok", value
end

-- REFramework writes an empty Lua table as JSON null; callers keep a placeholder key.
function files.write_json(path, value)
    local ok, result = pcall(json.dump_file, path, value, 2)
    return ok and result ~= false
end

return files
