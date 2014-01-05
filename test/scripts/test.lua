--[[
Utilities for running textadept tests.
--]]

local M = {}

local results = io.open('./output/results.txt','w')

local function log(msg)
    results:write(msg)
    results:flush()
end
M.log = log
M.debug = false

-- Catch any errors that happen.
events.connect(events.ERROR, log, 1)

local function logd(msg)
    if M.debug then log(msg) end
end

log("Running tests...\n")

local tmux_trace = ""
if M.debug then
    tmux_trace = " strace -o "
end

local tmux = io.popen("TMUX="..tmux_trace.."./output/tmux.strace tmux -S ./output/tmux-socket -C attach > ./output/tmux.output 2>&1", "w")
events.connect(events.QUIT, function() tmux:close() return true end)

function M.dbg(msg)
  if M.debug then
    log(msg)
  end
end

-- Colour codes
CSI = "\x1B["
local function SGR(...)
  return CSI .. table.concat({...},';') .. "m"
end
NORMAL = SGR(0)
RED = SGR(31,1)
GREEN = SGR(32,1)

-- Wrap text in colours
local function green(text) return GREEN .. text .. NORMAL end
local function red(text) return RED .. text .. NORMAL end

local numtests = 0
local passes = 0
local failures = 0

local fail_immediate = false
do
    local failenv = os.getenv("FAILHARD")
    if failenv == "1" then fail_immediate = true end
end

local testenv = os.getenv("TESTS")
local test_enabled = nil
if testenv and testenv:len() > 0 then
    test_enabled = {}
    for t in testenv:gmatch("(%S+)") do
        test_enabled[t] = true
    end
else
    -- enable all
    test_enabled = setmetatable({}, {
      __index = function(t, key) return true end
    })
end

-- Run test <testname>, from tests/<testname>.lua
function M.run(testname)
    if not test_enabled[testname] then return end
    
    log("  "..testname.."...")
    numtests = numtests + 1
    local testfile =  _USERHOME .. "/../tests/" .. testname .. ".lua"
    local testfunc, msg = loadfile(testfile, "t")
    if not testfunc then
        log(red(" ERROR\n"))
        logd(" ERROR loading: " .. msg .. "\n")
        failures = failures + 1
        --error("Error loading test script " .. testfile)
        return
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
                
                -- But has the view split (eg for an error buffer)?
                if #_VIEWS ~= 1 then res = false end
                
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
        log(green('OK'..'\n'))
    else
        failures = failures + 1
        -- Strip trailing newlines to keep things tidy.
        log(red('Fail: '..tostring(msg):gsub("^(.-)(\n*)$", "%1")..'\n'))
        -- log the display when it failed
        tmux:write('display-message "Test '..testname..' failed."\n')
        tmux:write('capture-pane\n')
        tmux:flush()
        if  fail_immediate then error(msg) end
        
    end
    -- Close any buffers opened for the test.
    for i,buf in ipairs(_G._BUFFERS) do
        if buf._vitest_owned then
            view:goto_buffer(i)
            buffer:set_save_point()  -- assert not dirty
            if not io.close_buffer(buf) then
                log('Error closing buffer ' .. tostring(buffer.filename))
            end
        end
    end
    -- Close any splits
    while #_VIEWS > 1 do
        view:unsplit()
    end
    
    -- Clear up some leftover state
    vi_mode.state.numarg = 0
end

-- Give the test summary
function M.report()
    if failures > 0 then
      log("End of tests: "..
          green(passes.." pass ("..(100.0 * passes/(passes+failures)).."%)")..
          ", "..red(failures.." FAIL ("..(100.0 * failures/(passes+failures))..")\n"))
    else
      log("End of tests: all "..green(passes.." passed\n"))
    end
end

-- Start running a test function.  It will be run in a coroutine, as it may
-- need to wait for events to happen.
function M.queue(f)
--    io.open_file('files/dummy.txt')
    local function xpwrapped()
        local res, rest = xpcall(f, debug.traceback)
        if not res then 
            log(rest)
            error(rest)
        end
        return rest
    end
    local testrun = coroutine.create(xpwrapped)
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
            M.report()
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
        logd("Connected QUIT and KEYPRESS events\n")
    end)
end

local eq
local tableEq

function eq(a, b)
    -- Easy case: builtin equal works for most cases.
    if a == b then return true end
    
    if type(a) ~= 'table' or type(b) ~= 'table' then
        -- If not both tables, then not equal.
        return false
    end
    return tableEq(a, b)
end

-- Compare two tables, treating them as the same if they key pairs
-- are equal.
function tableEq(a, b)
  -- First, check that every key in a matches one in b.
  for k,v in pairs(a) do
      if not eq(v, b[k]) then return false end
  end
  
  -- Second, check that every key in b exists in a.
  -- We don't need to compare - if the key is in a then we've already
  -- checked.
  for k,_ in pairs(b) do
    if a[k] == nil then return false end
  end
  
  -- They must be equal
  return true
end

-- Pretty-print tables
function M.tostring(a)
    if type(a) ~= 'table' then return tostring(a) end
    local maxn = 0
    local sbits = {'{'}
    for i,v in ipairs(a) do
        table.insert(sbits, M.tostring(v) .. ", ")
        maxn = i
    end
    for k,v in pairs(a) do
        -- Do the non-contiguous-integer keys
        if type(k) == 'number' and k == math.ceil(k) and k <= maxn and k >= 1 then 
           -- Ignore an integer key we've already seen
        else
            table.insert(sbits, '['..M.tostring(k)..'] = '..M.tostring(v)..', ')
        end
    end
    table.insert(sbits, '}')
    return table.concat(sbits)
end

--- Assert that a and b are equal.  Tables are equal if their keys
--  and values are equal.  Calls error() with level to report an error.
local function assertEqLevel(a, b, level)
    if not eq(a,b) then
        error("Failed assertion: [["..M.tostring(a).."]] != [["..M.tostring(b).."]]\n", level)
    end
end

--- Assert that a and b are equal.  Tables are equal if their keys
--  and values are equal.  REturns true or calls error().  
function M.assertEq(a, b)
    return assertEqLevel(a, b, 3)
end

-- Open a test file in the current view
function M.open(filebase)
    local filename = _USERHOME .. "/../files/"..filebase
    io.open_file(filename)
    buffer._vitest_owned = true
end

-- Simulate a keypress
function M.key(...)
    for _, key in ipairs({...}) do
      logd("Sending key " .. key .. "\n")
      M.physkey(key)
      logd("yielding after sending key\n")
      coroutine.yield()
      logd("Resumed after key "..tostring(key).."\n")
    end
end

-- Convenience to send a string of characters rather than a table.
function M.keys(s)
    local keys = {}
    for i=1,s:len() do
       M.key(s:sub(i,i))
    end
end

function M.physkey(key)
    if key:len() == 1 then
       -- escape single characters if necessary
       local c = key:byte(1)
       key = string.format('0x%02x', c)
    end
    tmux:write('send-keys ' .. key .. '\n')
    tmux:flush()
end

-- Send a string of characters to physkey (without the coroutine processing).
function M.physkeys(s)
    local keys = {}
    for i=1,s:len() do
       M.physkey(s:sub(i,i))
    end
end

-- Read the current screen contents (defaulting to the whole screen).
function M.getscreen(first, last)
    first = first or 0
    last = last or 23
    
    local tmux = io.popen("TMUX= tmux -S ./output/tmux-socket -C capture-pane -S "..first.." -E "..last.." -p", "r")
    
    data = tmux:read("*a")
    tmux:close()
    return data
end

-- Return the current line number
function M.lineno() return buffer:line_from_position(buffer.current_pos) end

function M.colno() return buffer.column[buffer.current_pos] end

-- Assert an absolute position
function M.assertAt(line, col)
    assertEqLevel(line, M.lineno(), 3)
    assertEqLevel(col, M.colno(), 3)
end

return M
