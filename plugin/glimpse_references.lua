-- Glimpse reference scanner: finds publisher-provided reference pages in EPUBs.
--
-- This module deliberately returns only small metadata and a short preview.
-- The caller reads a page's full text only when the reader opens it, keeping
-- Glimpse's normal image-first flow and memory footprint unchanged.

local M = {}
M.VERSION = 1

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function collapse_ws(s)
    return trim((s:gsub("%s+", " ")))
end

local function clean_text(s)
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    s = s:gsub("[ \t]+", " ")
    s = s:gsub(" *\n *", "\n")
    s = s:gsub("\n\n\n+", "\n\n")
    return trim(s)
end

local function unescape(s)
    return (s:gsub("&#x(%x+);", function(h)
        local n = tonumber(h, 16)
        return n and n < 128 and string.char(n) or ""
    end):gsub("&#(%d+);", function(d)
        local n = tonumber(d)
        return n and n < 128 and string.char(n) or ""
    end):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
      :gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&nbsp;", " ")
      :gsub("&mdash;", "—"):gsub("&ndash;", "–"):gsub("&hellip;", "…")
      :gsub("&lsquo;", "‘"):gsub("&rsquo;", "’"):gsub("&ldquo;", "“"):gsub("&rdquo;", "”"))
end

local function dir_of(path)
    return path:match("^(.*)/[^/]*$") or ""
end

local function resolve_path(base, href)
    local p = href:gsub("#.*$", ""):gsub("%?.*$", "")
    if not p:match("^/") and base ~= "" then p = base .. "/" .. p end
    local out = {}
    for part in p:gsub("^/+", ""):gmatch("[^/]+") do
        if part == ".." then table.remove(out)
        elseif part ~= "." then out[#out + 1] = part end
    end
    return table.concat(out, "/")
end

local function attr(tag, name)
    local n = name:gsub("(%a)", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)
    return tag:match(n .. '%s*=%s*"([^"]*)"')
        or tag:match(n .. "%s*=%s*'([^']*)'")
        or tag:match(n .. "%s*=%s*([^%s>]+)")
end

local function plain(html)
    html = html:gsub("<!--.-!-->", " ")
    html = html:gsub("<[sS][cC][rR][iI][pP][tT].-</[sS][cC][rR][iI][pP][tT]%s*>", " ")
    html = html:gsub("<[sS][tT][yY][lL][eE].-</[sS][tT][yY][lL][eE]%s*>", " ")
    html = html:gsub("<[bB][rR]%s*/?>", "\n")
    html = html:gsub("</[pP]>", "\n\n")
    html = html:gsub("</[hH][1-6]>", "\n\n")
    html = html:gsub("</[dD][tT]>", "\n")
    html = html:gsub("</[dD][dD]>", "\n\n")
    html = html:gsub("</[lL][iI]>", "\n")
    html = html:gsub("</[tT][rR]>", "\n")
    html = html:gsub("</[dD][iI][vV]>", "\n")
    html = html:gsub("</[sS][eE][cC][tT][iI][oO][nN]>", "\n")
    html = html:gsub("</[aA][rR][tT][iI][cC][lL][eE]>", "\n")
    html = html:gsub("<[^>]->", " ")
    return unescape(html)
end

local LABELS = {
    characters = { "characters", "character list", "cast of characters", "cast", "dramatis personae", "persons of the tale", "dramatis personæ", "list of characters", "people" },
    glossary = { "glossary", "vocabulary", "terms", "lexicon", "dictionary" },
    places = { "places", "locations", "gazetteer", "map", "maps" },
    timeline = { "timeline", "chronology", "chronicle", "history" },
    reference = { "appendix", "appendices", "pronunciation", "pronunciation guide", "family tree", "genealogy", "notes", "bibliography" },
}

local function kind_for(label)
    label = collapse_ws(label or ""):lower()
    for kind, words in pairs(LABELS) do
        for _, word in ipairs(words) do
            if label == word or label:find("^" .. word .. "[%s:%-—]") then
                return kind
            end
        end
    end
end

local function title_of(html)
    local heading = html:match("<[hH]1[^>]*>(.-)</[hH]1>")
        or html:match("<[hH]2[^>]*>(.-)</[hH]2>")
    local title = html:match("<[tT][iI][tT][lL][eE][^>]*>(.-)</[tT][iI][tT][lL][eE]>")
    local raw = heading or title or ""
    return collapse_ws(unescape(raw:gsub("<[^>]->", " ")))
end

local function parse_opf(opf, opf_path)
    local base = dir_of(opf_path)
    local manifest, spine = {}, {}
    for tag in opf:gmatch("<item%s+[^>]->") do
        local id, href, media, props = attr(tag, "id"), attr(tag, "href"), attr(tag, "media-type"), attr(tag, "properties")
        if id and href then
            manifest[id] = {
                path = resolve_path(base, href),
                media = media,
                props = props,
            }
        end
    end
    for tag in opf:gmatch("<itemref%s+[^>]->") do
        local idref = attr(tag, "idref")
        if idref and manifest[idref] then spine[#spine + 1] = manifest[idref] end
    end
    return spine
end

local function is_html(item)
    return item and ((item.media or ""):find("html", 1, true) or item.path:match("%.x?html?$"))
end

-- Return small candidate records. Full text remains in the EPUB until opened.
function M.scan(read_file)
    local container = read_file("META-INF/container.xml")
    local opf_path = container and container:match('full%-path%s*=%s*"([^"]+)"')
        or container and container:match("full%-path%s*=%s*'([^']+)'")
    if not opf_path then return nil, "no_opf" end
    local opf = read_file(opf_path)
    if not opf then return nil, "no_opf" end
    local out = {}
    for i, item in ipairs(parse_opf(opf, opf_path)) do
        if is_html(item) then
            local html = read_file(item.path)
            if html then
                local title = title_of(html)
                local kind = kind_for(title)
                if not kind and item.props then
                    kind = kind_for(item.props)
                end
                if kind then
                    local body = clean_text(plain(html))
                    out[#out + 1] = {
                        kind = kind,
                        title = title ~= "" and title or "Reference",
                        path = item.path,
                        spine_index = i,
                        preview = collapse_ws(body):sub(1, 280),
                    }
                end
            end
        end
    end
    return { version = M.VERSION, references = out }
end

function M.read_text(read_file, record)
    if not record or not record.path then return nil end
    local html = read_file(record.path)
    return html and clean_text(plain(html)) or nil
end

return M
