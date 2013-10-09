--[[
Utilities for running textadept tests.
--]]

local M = {}

local results = io.open('results.txt','w')

local function log(msg)
    results:write(msg)
    results:flush()
end
M.log = log
M.debug = false
local function logd(msg)
    if M.debug then log(msg) end
end

log("Running tests...\n")

local tmux_trace = ""
if M.debug then
    tmux_trace = " strace -o "
end

local tmux = io.popen("TMUX="..tmux_trace.."tmux.strace tmux -S ./output/tmux-socket -C attach > tmux.output 2>&1", "w")
events.connect(events.QUIT, function() tmux:close() return true end)

function M.dbg(msg)
  if M.debug then
    log(msg)
  end
end

local numtests = 0
local passes = 0
local failures = 0

local fail_immediate = false

-- Run test <testname>, from tests/<testname>.lua
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
    local res = nil
    
    local test_coro = coroutine.create(testfunc)
    
    while true do
        logd("Resuming test_coro: ")
        local co_res, co_results = coroutine.resume(test_coro)
        logd("returned: <"..tostring(co_res) .. ">, <" .. tostring(co_results)..">")
        logd("  status="..coroutine.status(test_coro).."\n")
        if not co_res then
            -- An error
            res = false
            msg = co_results
            break
        else
            logd("No error in test: <"..tostring(co_results)..">")
            if coroutine.status(test_coro) == "dead" then
                -- It succeeded
                res = true
                break
            else
                -- Try again later
                logd("yielding from test.run\n")
                coroutine.yield()
                logd("Resumed from test.run\n")
            end
        end
    end
    if res then 
        passes = passes + 1
        log('OK\n')
    else
        failures = failures + 1
        log('Fail: '..tostring(msg)..'\n')
        if  fail_immediate then error(msg) end
        
    end
end

-- Start running a test function.  It will be run in a coroutine, as it may
-- need to wait for events to happen.
function M.queue(f)
    local testrun = coroutine.create(f)
    local function doquit()
        logd('doquit()\n')
        quit()
    end
    local function continuetest()
        logd('continuetest()\n')
        if coroutine.status(testrun) == "dead" then
            logd("Disconnecting continuetest\n")
            events.disconnect(events.KEYPRESS, doquit)
            events.disconnect(events.QUIT, continuetest)
            M.physkey("c-q")
            return false
        else
            logd("Continuing testrun\n")
            coroutine.resume(testrun)
            return false
        end
    end
    -- and start if off on initialisation
    events.connect(events.INITIALIZED, function()
        logd("initialising, testrun\n")
        coroutine.resume(testrun)
        logd("end of INITIALIZED\n")
        -- Run the queued function a bit on every keypress
        events.connect(events.QUIT, continuetest, 1)
        events.connect(events.KEYPRESS, doquit, 1)
    end)
end

-- Open a test file in the current view
function M.open(filebase)
    local filename = _USERHOME .. "/../files/"..filebase
    io.open_file(filename)
end

-- Simulate a keypress
function M.key(key)
    logd("Sending key " .. key .. "\n")
    M.physkey(key)
    logd("yielding after sending key\n")
    coroutine.yield()
    logd("Resumed after key "..tostring(key).."\n")
end

function M.physkey(key)
    tmux:write('send-keys ' .. key .. '\n')
    tmux:flush()
end

-- Return the current line number
function M.lineno() return buffer:line_from_position(buffer.current_pos) end

function M.colno() return buffer.column[buffer.current_pos] end

return M