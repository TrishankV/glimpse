-- Glimpse X-Ray adapter: loads and normalizes character data from X-Ray sidecar files.
--
-- Pure Lua module with zero KOReader UI dependencies, isolatable and testable standalone.

local M = {}
M.VERSION = 1

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function collapse_ws(s)
    return trim((s:gsub("%s+", " ")))
end

-- Primitive JSON parser for pure Lua testability (supports basic objects/arrays/strings/numbers/booleans)
local function parse_json(str)
    if not str or str == "" then return nil end
    -- If dkjson or cjson is available in KOReader runtime, use it
    local pcall_ok, json = pcall(require, "json")
    if pcall_ok and json and json.decode then
        local ok, res = pcall(json.decode, str)
        if ok and res then return res end
    end

    -- Minimal pure-Lua JSON decoder fallback for arrays & simple key-value objects
    local i = 1
    local len = #str

    local function skip_ws()
        while i <= len do
            local c = str:sub(i, i)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                i = i + 1
            else
                break
            end
        end
    end

    local parse_val -- forward declaration

    local function parse_string()
        i = i + 1 -- skip opening quote
        local start = i
        local parts = {}
        while i <= len do
            local c = str:sub(i, i)
            if c == '\\' then
                parts[#parts + 1] = str:sub(start, i - 1)
                i = i + 2
                start = i
            elseif c == '"' then
                parts[#parts + 1] = str:sub(start, i - 1)
                i = i + 1
                return table.concat(parts)
            else
                i = i + 1
            end
        end
        return table.concat(parts)
    end

    local function parse_array()
        i = i + 1 -- skip '['
        local arr = {}
        while i <= len do
            skip_ws()
            if str:sub(i, i) == ']' then
                i = i + 1
                return arr
            end
            local val = parse_val()
            arr[#arr + 1] = val
            skip_ws()
            local c = str:sub(i, i)
            if c == ',' then
                i = i + 1
            elseif c == ']' then
                i = i + 1
                return arr
            end
        end
        return arr
    end

    local function parse_object()
        i = i + 1 -- skip '{'
        local obj = {}
        while i <= len do
            skip_ws()
            if str:sub(i, i) == '}' then
                i = i + 1
                return obj
            end
            if str:sub(i, i) ~= '"' then break end
            local key = parse_string()
            skip_ws()
            if str:sub(i, i) == ':' then i = i + 1 end
            skip_ws()
            local val = parse_val()
            obj[key] = val
            skip_ws()
            local c = str:sub(i, i)
            if c == ',' then
                i = i + 1
            elseif c == '}' then
                i = i + 1
                return obj
            end
        end
        return obj
    end

    parse_val = function()
        skip_ws()
        local c = str:sub(i, i)
        if c == '"' then
            return parse_string()
        elseif c == '[' then
            return parse_array()
        elseif c == '{' then
            return parse_object()
        elseif c == 't' and str:sub(i, i + 3) == "true" then
            i = i + 4
            return true
        elseif c == 'f' and str:sub(i, i + 4) == "false" then
            i = i + 5
            return false
        elseif c == 'n' and str:sub(i, i + 3) == "null" then
            i = i + 4
            return nil
        else
            local num_str = str:match("^%-?%d+%.?%d*", i)
            if num_str then
                i = i + #num_str
                return tonumber(num_str)
            end
        end
        i = i + 1
        return nil
    end

    skip_ws()
    return parse_val()
end

-- Candidate X-Ray file paths for a given document path
function M.candidate_paths(doc_path)
    if not doc_path or doc_path == "" then return {} end
    local sdr = doc_path:gsub("%.%w+$", "") .. ".sdr"
    local dir, filename = doc_path:match("^(.*)/([^/]+)$")
    filename = filename or doc_path
    local base = filename:gsub("%.%w+$", "")

    local paths = {
        sdr .. "/xray.json",
        sdr .. "/characters.json",
        sdr .. "/xray.lua",
    }
    if dir then
        paths[#paths + 1] = dir .. "/xray.json"
        paths[#paths + 1] = dir .. "/" .. base .. ".xray.json"
    end
    return paths
end

local function normalize_character(item)
    if not item then return nil end
    if type(item) == "string" then
        return { name = trim(item), description = "", aliases = {} }
    end
    if type(item) ~= "table" then return nil end
    local name = item.name or item.label or item.title or item.character_name
    if not name or name == "" then return nil end

    local desc = item.description or item.desc or item.summary or item.biography or item.info or ""
    local aliases = {}
    if type(item.aliases) == "table" then
        for _, a in ipairs(item.aliases) do
            if type(a) == "string" and trim(a) ~= "" then
                aliases[#aliases + 1] = trim(a)
            end
        end
    elseif type(item.aliases) == "string" and trim(item.aliases) ~= "" then
        aliases[1] = trim(item.aliases)
    end

    return {
        name = collapse_ws(name),
        description = collapse_ws(desc),
        aliases = aliases,
        loc_count = tonumber(item.loc_count or item.count or item.occurrences) or 0,
    }
end

function M.parse_data(raw_data)
    if not raw_data or raw_data == "" then return nil end

    local data = parse_json(raw_data)
    if not data then return nil end

    local items = {}
    if type(data) == "table" then
        local raw_list = data.characters or data.items or data.terms or data.people or (data[1] and data)
        if type(raw_list) == "table" then
            for _, entry in ipairs(raw_list) do
                local char = normalize_character(entry)
                if char then items[#items + 1] = char end
            end
        end
    end

    if #items == 0 then return nil end
    return { version = M.VERSION, characters = items }
end

function M.scan(doc_path, read_file_fn)
    local candidates = M.candidate_paths(doc_path)
    for _, path in ipairs(candidates) do
        local content = read_file_fn(path)
        if content and content ~= "" then
            local result = M.parse_data(content)
            if result then
                result.path = path
                return result
            end
        end
    end
    return nil, "no_xray"
end

function M.format_characters(chars)
    if not chars or #chars == 0 then return "" end
    local lines = {}
    lines[#lines + 1] = "Characters (X-Ray)"
    lines[#lines + 1] = ""
    for _, c in ipairs(chars) do
        lines[#lines + 1] = c.name
        if #c.aliases > 0 then
            lines[#lines + 1] = "Also known as: " .. table.concat(c.aliases, ", ")
        end
        if c.description and c.description ~= "" then
            lines[#lines + 1] = c.description
        end
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

-- Merge book character reference with X-Ray character reference
function M.merge(book_text, xray_chars, preference)
    preference = preference or "combine"

    if preference == "xray_only" then
        return M.format_characters(xray_chars)
    elseif preference == "book_only" then
        return book_text or ""
    end

    -- "combine" mode
    local xray_text = M.format_characters(xray_chars)
    if not book_text or book_text == "" then return xray_text end
    if not xray_text or xray_text == "" then return book_text end

    return book_text .. "\n\n" .. string.rep("—", 20) .. "\n\n" .. xray_text
end

return M
