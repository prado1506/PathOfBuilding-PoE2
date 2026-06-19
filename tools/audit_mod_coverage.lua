#!/usr/bin/env luajit
-- Standalone audit script. Run from repo root: luajit tools/audit_mod_coverage.lua

package.path = "tools/?.lua;" .. package.path
local lib = require("mod_coverage_lib")

local manifest = lib.generate("src/Data/ModCache.lua")

local out_path = "audit/mod-coverage.txt"
local f, err = io.open(out_path, "w")
if not f then
    io.stderr:write("Failed to open " .. out_path .. " for writing: " .. tostring(err) .. "\n")
    os.exit(1)
end
f:write(manifest)
f:write("\n")
f:close()

io.stdout:write("Wrote " .. out_path .. "\n")
