-- JSON files under reframework/data, read without REFramework's "[JSON] Failed to load
-- file" log line for files that do not exist, and with missing told apart from corrupt.
--
-- fs.read returns "" both for a missing and for an empty file. Only then does fs.glob
-- decide whether the file exists. fs.glob matches a std::regex against every path under
-- reframework/data, which takes about 9 ms in game, so it is used as little as possible:
-- never for a file that has content, and once for several files (files.reader).
-- Windows paths use backslashes, so "/" matches either one.

local files = {}

local function has(lib, name)
    return type(lib) == "table" and type(lib[name]) == "function"
end

local function escape(path)
    return (path:gsub("%.", "\\."):gsub("/", "[\\\\/]"))
end

function files.pattern(path)
    return "^" .. escape(path) .. "$"
end

-- true or false, or nil when fs.glob is not available.
function files.exists(path)
    if not has(fs, "glob") then return nil end
    local ok, matches = pcall(fs.glob, files.pattern(path))
    if not ok or type(matches) ~= "table" then return nil end
    return #matches > 0
end

local function normalized(path)
    return (path:gsub("\\", "/"):lower())
end

-- Which of `paths` exist, with one fs.glob: { [path] = true/false }, or nil without fs.glob.
function files.existing(paths)
    if not has(fs, "glob") then return nil end
    local parts = {}
    for i, path in ipairs(paths) do parts[i] = escape(path) end
    local ok, matches = pcall(fs.glob, "^(?:" .. table.concat(parts, "|") .. ")$")
    if not ok or type(matches) ~= "table" then return nil end
    local found = {}
    for _, match in ipairs(matches) do found[normalized(match)] = true end
    local result = {}
    for _, path in ipairs(paths) do result[path] = found[normalized(path)] == true end
    return result
end

local function decode(text)
    local parsed, value = pcall(json.load_string, text)
    if not parsed or type(value) ~= "table" then return "corrupt" end
    return "ok", value
end

-- Returns "ok" plus the decoded value, "missing", or "corrupt". `exists` (optional) is
-- what an earlier fs.glob found out, so no new glob is needed.
-- Without fs.read/json.load_string (older REFramework) it falls back to json.load_file,
-- which cannot tell a corrupt file from a missing one.
function files.read_json(path, exists)
    if not has(fs, "read") or not has(json, "load_string") then
        local ok, value = pcall(json.load_file, path)
        if ok and value ~= nil then return "ok", value end
        return "missing"
    end
    local ok, text = pcall(fs.read, path)
    if ok and type(text) == "string" and text ~= "" then return decode(text) end
    if exists == nil then exists = files.exists(path) end
    return exists and "corrupt" or "missing"
end

-- A read_json for a known set of files that uses at most one fs.glob for all of them.
-- Other paths are read with files.read_json.
function files.reader(paths)
    local results = {}
    if has(fs, "read") and has(json, "load_string") then
        local unknown = {}
        for _, path in ipairs(paths) do
            local ok, text = pcall(fs.read, path)
            if ok and type(text) == "string" and text ~= "" then
                results[path] = { decode(text) }
            else
                unknown[#unknown + 1] = path
            end
        end
        if #unknown > 0 then
            local present = files.existing(unknown) or {}
            for _, path in ipairs(unknown) do results[path] = { present[path] and "corrupt" or "missing" } end
        end
    end
    return function(path)
        local result = results[path]
        if result then return result[1], result[2] end
        return files.read_json(path)
    end
end

-- REFramework writes an empty Lua table as JSON null; callers keep a placeholder key.
function files.write_json(path, value)
    local ok, result = pcall(json.dump_file, path, value, 2)
    return ok and result ~= false
end

return files
