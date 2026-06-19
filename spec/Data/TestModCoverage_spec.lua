package.path = "../tools/?.lua;" .. package.path
local lib = require("mod_coverage_lib")

describe("ModCoverage #data", function()
    it("manifest matches committed audit/mod-coverage.txt", function()
        local actual = lib.generate("../src/Data/ModCache.lua")

        local f, err = io.open("../audit/mod-coverage.txt", "r")
        assert(f, "audit/mod-coverage.txt not found: " .. tostring(err))
        local expected = f:read("*a")
        f:close()

        -- Normalise trailing newlines so a lone trailing newline in the
        -- committed file does not count as a content difference.
        local norm_expected = expected:gsub("\n+$", "")
        local norm_actual   = actual:gsub("\n+$", "")

        if norm_expected == norm_actual then
            return
        end

        -- Build sets for a set-based diff (avoids positional false-positives
        -- when a single inserted line would otherwise flood the output).
        local expected_set = {}
        for line in (norm_expected .. "\n"):gmatch("([^\n]*)\n") do
            expected_set[line] = true
        end
        local actual_set = {}
        for line in (norm_actual .. "\n"):gmatch("([^\n]*)\n") do
            actual_set[line] = true
        end

        local removed, added = {}, {}
        for line in pairs(expected_set) do
            if not actual_set[line] then
                removed[#removed + 1] = "- " .. line
            end
        end
        for line in pairs(actual_set) do
            if not expected_set[line] then
                added[#added + 1] = "+ " .. line
            end
        end
        table.sort(removed)
        table.sort(added)

        local diff = table.concat(removed, "\n") .. "\n" .. table.concat(added, "\n")
        fail("audit/mod-coverage.txt is stale. Re-run: luajit tools/audit_mod_coverage.lua\nDiff:\n" .. diff)
    end)
end)
