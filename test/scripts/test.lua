--[[
Utilities for running textadept tests.
--]]

local M = {}

local results = io.open('results.txt','w')
results:write("Running tests...\n")
results:flush()

function M.log(msg)
    results:write(msg)
    results:flush()
end
local log = M.log

M.debug = false
function M.dbg(msg)
  if debug then
    log(msg)
  end
end

local numtests = 0
local passes = 0
local failures = 0

local fail_immediate = false

-- Run test <testname>, from tests/jk.lua
function M.run(testname)
    log("  "..testname.."...")
    numtests = numtests + 1
    local testfile =  _USERHOME .. "/../tests/" .. testname .. ".lua"
    local testfunc, msg = loadfile(testfile, "t")
    if not testfunc then
        log(" error loading: " .. msg .. "\n")
        failures = failures + 1
        error("Error loading test script " .. testfile)
    end
    res, msg = pcall(testfunc)
    if res then 
        passes = passes + 1
        log('OK\n')
    else
        failures = failures + 1
        log('Fail: '..tostring(msg)..'\n')
        if  fail_immediate then error(msg) end
        
    end
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

function M.physkey(key)
    os.execute("(echo send-key "..key.." ; echo detach) | TMUX= tmux -S ./output/tmux-socket -C attach")
end

-- Return the current line number
function M.lineno() return buffer:line_from_position(buffer.current_pos) end

function M.colno() return buffer.column[buffer.current_pos] end

return M