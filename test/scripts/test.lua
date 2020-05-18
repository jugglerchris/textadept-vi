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
events.connect(events.ERROR, function(...)
    log(M.tostring(...).."\n")
    if M.debug then log(debug.traceback()) end
end, 1)

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
    -- First, get a list of the buffers; if we close them during the
    -- iteration, the table is modified and indices change, so we just
    -- make a note and do it afterwards.
    local toclose = {}
    for i,buf in ipairs(_G._BUFFERS) do
        if buf.filename then
            toclose[#toclose+1] = buf
        end
    end
    -- now actually close.
    for k, buf in ipairs(toclose) do
        -- convert back from buffer to index using _G._BUFFERS.
        view:goto_buffer(buf)
        buffer:set_save_point()  -- assert not dirty
        if not buf:close() then
            log('Error closing buffer ' .. tostring(buffer.filename))
        end
    end
    -- Close any splits
    while #_VIEWS > 1 do
        view:unsplit()
    end

    -- Exit the command entry mode if needed
    M.key('escape')

    -- Clear up some leftover state
    vi_mode.state.numarg = 0
end

-- Give the test summary
function M.report()
    if failures > 0 then
      log("End of tests: "..
          green(passes.." pass ("..(100.0 * passes/(passes+failures)).."%)")..
          ", "..red(failures.." FAIL ("..(100.0 * failures/(passes+failures)).."%)\n"))
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
        M.physkey('c-q') -- return control after the end.
        return rest
    end
    local testrun = coroutine.create(xpwrapped)
    local function doquit(arg)
        logd('doquit()\narg=' .. tostring(arg) .. '\n')
        quit()
    end
    local function continuetest()
        logd('continuetest()\n')
        if coroutine.status(testrun) == "dead" then
            logd("Disconnecting continuetest\n")
--            events.disconnect(events.KEYPRESS, doquit)
--            events.disconnect(events.QUIT, continuetest)
            M.report()
            -- signal the end of the test
            log("Finished")
            io.open("output/sem.fifo", "w"):write("Finished\n"):flush()
            -- kill the textadept instance
            os.exit()
            return false
        else
            logd("Continuing testrun\n")
            coroutine.resume(testrun)
            return true
        end
    end
    local function fakekeys(...)
        -- First disconnect this handler...
        events.disconnect(events.KEYPRESS, fakekeys)
        -- ... then retrigger the event
        local result = events.emit(events.KEYPRESS, ...)
        -- ... and then reconnect and return the result.
        events.connect(events.KEYPRESS, fakekeys, 1)
        return continuetest()
    end
    -- and start if off on initialisation
    events.connect(events.INITIALIZED, function()
        logd("initialising, testrun\n")
        coroutine.resume(testrun)
        logd("end of INITIALIZED\n")
        -- Run the queued function a bit on every keypress
        --events.connect(events.QUIT, continuetest, 1)
        events.connect(events.KEYPRESS, fakekeys, 1)
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
    if type(a) == "string" then
        return '"' .. a .. '"'
    elseif type(a) ~= 'table' then return tostring(a) end
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
--  and values are equal.  Returns true or calls error().
function M.assertEq(a, b)
    return assertEqLevel(a, b, 2)
end

-- Placeholder value which matches anything
M.STAR = {}

-- Metatable for fuzzy match tables
local fuzzy_mt = {}

function M.T(tab)
    return setmetatable(tab, fuzzy_mt)
end

local filename_mt = {}
function M.F(filename)
    return setmetatable({filename}, filename_mt)
end

-- Compare two tables, treating them as the same if they key pairs
-- match
function tableMatches(a, b)
  -- First, check that every key in a matches one in b.
  for k,v in pairs(a) do
      local ok, err = matches(v, b[k])
      if not ok then return false, k.."->"..err end
  end

  -- Second, check that every key in b exists in a.
  -- We don't need to compare - if the key is in a then we've already
  -- checked.
  for k,_ in pairs(b) do
    if a[k] == nil then return false, k.."==nil" end
  end

  -- They must be equal
  return true
end

-- Do a fuzzy match of two tables.  Keys in a must appear and match in
-- table b, but the reverse isn't true.
function fuzzyMatches(a, b)
    for k,va in pairs(a) do
        local vb = b[k]
        local ok, err = matches(va, vb)
        if not ok then return false, err end
    end
    return true
end

local function matchesFilename(a, b)
    local path1 = lfs.abspath(a)
    local path2 = lfs.abspath(b)

    if path1 == path2 then
        return true
    else
        return false, "Filename mismatch: "..a..", "..b
    end
end

-- Return:
--  true if two value match (including wildcards and fuzzy matches)
--  false and a string describing the mismatch otherwise
function matches(a, b)
    -- Easy case: builtin equal works for most cases.
    if a == b then return true end

    -- If one is a wildcard, then this matches.
    if a == M.STAR or b == M.STAR then return true end

    -- Check for a filename match
    if getmetatable(a) == filename_mt then
        return matchesFilename(a[1], b)
    elseif getmetatable(b) == filename_mt then
        return matchesFilename(a, b[1])
    end


    if type(a) ~= 'table' or type(b) ~= 'table' then
        -- If not both tables, then not equal.
        return false, "Type mismatch"
    end

    -- Check for fuzzy maches
    if getmetatable(a) == fuzzy_mt then
        return fuzzyMatches(a, b)
    elseif getmetatable(b) == fuzzy_mt then
        return fuzzyMatches(b, a)
    end
    return tableMatches(a, b)
end

--- Assert that a and b "match".  This means that they may be equal, but
--  with some fuzziness:
--  test.STAR matches anything
--  test.T{...} matches a table with a superset of the keys, such that any
--  keys present match.
function M.assertMatches(a, b)
    local ok, info = matches(a, b)
    if not ok then
        if info then
            error("Failed assertion: [["..info.."]]\n", 2)
        else
            error("Failed assertion: [["..M.tostring(a).."]] doesn't match [["..M.tostring(b).."]]\n", 2)
        end
    end
end

--- Assert that two filenames are equivalent (compared using lfs.abspath).
function M.assertFileEq(a, b)
    assertEqLevel(lfs.abspath(a), lfs.abspath(b), 3)
end

function M.assert(a)
    return assertEqLevel(not a, false, 2)
end

-- Open a test file in the current view
function M.open(filebase)
    local filename = "files/"..filebase
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

-- convenience function to enter an ex command
function M.colon(s)
    test.keys(':' .. s)
    test.key('enter')
end

-- Send an arbitrary tmux command
function M.tmux(s)
    tmux:write(s .. '\n')
    tmux:flush()
end

-- Read the current screen contents (defaulting to the whole screen).
function M.getscreen(first, last)
    first = first or 0
    last = last or 23

    local tmux = io.popen("TMUX= tmux -q -S ./output/tmux-socket -C capture-pane -S "..first.." -E "..last.." -p", "r")

    local parts = {}
    for line in tmux:lines("*L") do
        if line:match('^%%begin') or line:match('^%%end') then
           -- skip this line
        else
            parts[#parts+1] = line
        end
    end
    tmux:close()
    local data = table.concat(parts)
    return data
end

-- Return the current line number
-- The tests were written before the Great Renumbering in textadept 11,
-- so for now we'll return the old number.
function M.lineno() return buffer:line_from_position(buffer.current_pos)-1 end

-- The tests were written before the Great Renumbering in textadept 11,
-- so for now we'll return the old number.
function M.colno() return buffer.column[buffer.current_pos]-1 end

-- Assert an absolute position
function M.assertAt(line, col)
    assertEqLevel(line, M.lineno(), 3)
    assertEqLevel(col, M.colno(), 3)
end

-- Run some keys in a vim session and compare the results
function M.run_in_vim(init_data, keylist)
    local vimfilename = 'vimfile.txt'
    local vimpath = './output/' .. vimfilename
    local vimfile = io.open(vimpath,'wb')
    vimfile:write(init_data)
    vimfile:close()
    do
    local vimfile = io.open(vimpath .. '_','wb')
    vimfile:write(init_data)
    vimfile:close()
    end

    -- -c: directory to start in
    -- -k: destroy target window if needed
    -- -t: target widnow
    tmux:write([[new-window -c ./output 'vim -N -u ./userhome/vimrc ]]..vimfilename.."'\n")
    tmux:flush()

    -- Assume it's switched to the new window
    for _,key in ipairs(keylist) do
        M.physkey(key)
    end

    M.physkey('escape')
    M.physkey('escape')
    M.physkey(':')
    M.physkey('w')
    M.physkey('q')
    M.physkey('enter')
    tmux:flush()

    -- TODO: work out why this is necessary
    os.execute('sleep 1')

    vimfile, err = io.open(vimpath, 'r')
    local result = vimfile:read("*a")
    vimfile:close()
    return result
end

--
-- Run the same key sequence (keys is a { 'a', 'b' } sequence of keypresses)
-- in both the current textadept-vi and in a separately-spawned vim and
-- check that both leave the buffer contents the same.
-- filename is the name of one of the test files (as used with test.open())
function M.cosim(filename, keys)
    local unpack = unpack or table.unpack

    M.open(filename)
    local init_data = buffer:get_text()

    test.key(unpack(keys))
    local fini_data = buffer:get_text()

    M.assertEq(test.run_in_vim(init_data, keys), fini_data)
end

return M
