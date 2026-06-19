-- Shared module for mod coverage audit. Used by both the standalone
-- audit script and the Busted regression-guard spec.

local M = {}

-- Pattern: [%+%-]?%d+%.?%d*
local function normalise(line)
    return (line:gsub("[%+%-]?%d+%.?%d*", "#"))
end

local function has_leftover(extra)
    if extra == nil then
        return false
    end
    return extra:match("^%s*(.-)%s*$") ~= ""
end

--- Load ModCache.lua and classify every entry.
-- @param mod_cache_path string|nil  Path to ModCache.lua (default: "src/Data/ModCache.lua").
-- @return table  { supported, partial, unsupported, total, unsupported_forms, partial_forms }
function M.analyse(mod_cache_path)
    mod_cache_path = mod_cache_path or "src/Data/ModCache.lua"

    local chunk, err = loadfile(mod_cache_path)
    if not chunk then
        error("Failed to load ModCache.lua: " .. tostring(err))
    end
    local cache = {}
    chunk(cache)

    local supported = 0
    local partial   = 0
    local unsupported = 0

    local unsupported_set = {}
    local part_set  = {}

    for line, entry in pairs(cache) do
        local modList = entry[1]
        local extra   = entry[2]

        if modList == nil then
            unsupported = unsupported + 1
            unsupported_set[normalise(line)] = true
        elseif has_leftover(extra) then
            partial = partial + 1
            local form = normalise(line)
            local norm_extra = normalise(extra:match("^%s*(.-)%s*$") or extra)
            if not part_set[form] then
                part_set[form] = norm_extra
            end
        else
            supported = supported + 1
        end
    end

    local unsupported_forms = {}
    for form in pairs(unsupported_set) do
        unsupported_forms[#unsupported_forms + 1] = form
    end
    table.sort(unsupported_forms)

    local partial_forms = {}
    for form, extra in pairs(part_set) do
        partial_forms[#partial_forms + 1] = { form, extra }
    end
    table.sort(partial_forms, function(a, b) return a[1] < b[1] end)

    return {
        supported   = supported,
        partial     = partial,
        unsupported = unsupported,
        total       = supported + partial + unsupported,
        unsupported_forms = unsupported_forms,
        partial_forms     = partial_forms,
    }
end

--- Produce the manifest string from an analysis result.
-- @param result table  Return value from M.analyse().
-- @return string
function M.render(result)
    local lines = {}

    -- Note: the counts in the header are raw cache entry counts (before
    -- number-normalisation de-duplication), while the manifest body lists
    -- de-duped normalised forms. The line counts in the body will therefore
    -- be <= the header counts for partial/unsupported categories.
    lines[#lines + 1] = string.format(
        "# total=%d supported=%d partial=%d unsupported=%d",
        result.total, result.supported, result.partial, result.unsupported
    )

    for _, form in ipairs(result.unsupported_forms) do
        lines[#lines + 1] = "unsupported\t" .. form
    end

    for _, entry in ipairs(result.partial_forms) do
        lines[#lines + 1] = "partial\t" .. entry[1] .. "\t" .. entry[2]
    end

    return table.concat(lines, "\n")
end

--- Convenience: analyse + render in one call.
-- @param mod_cache_path string|nil
-- @return string
function M.generate(mod_cache_path)
    return M.render(M.analyse(mod_cache_path))
end

return M
