--[[
Utilities for running textadept tests.
--]]

local M = {}

local results = io.open('results.txt','w')
results:write("Running tests...\n")
results:flush()

local numtests = 0
local passes = 0
local failures = 0

local fail_immediate = false

-- Run test <testname>, from tests/jk.lua
function M.run(testname)
    results:write("  "..testname.."...")
    results:flush()
    numtests = numtests + 1
    local testfile =  _USERHOME .. "/../tests/" .. testname .. ".lua"
    local testfunc, msg = loadfile(testfile, "t")
    if not testfunc then
        results:write(" error loading: " .. msg .. "\n")
        failures = failures + 1
        error("Error loading test script " .. testfile)
    end
    res, msg = pcall(testfunc)
    if res then 
        passes = passes + 1
        results:write('OK\n')
    else
        failures = failures + 1
        results:write('Fail: '..tostring(msg)..'\n')
        if  fail_immediate then error(msg) end
        
    end
    results:flush()
end

-- Open a test file in the current view
function M.open(filebase)
    local filename = _USERHOME .. "/../files/"..filebase
    io.open_file(filename)
end

-- Simulate a keypress
function M.key(key)
    events.emit(events.KEYPRESS, key:byte(1))
end

return M