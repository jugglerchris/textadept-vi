-- Turn on coverage analysis if available
pcall(require, 'luacov')

_NOCOMPAT = true

-- Used to be in properties.lua
buffer.margin_width_n[1] = 0
buffer.margin_width_n[2] = 0
buffer.margin_width_n[3] = 1
buffer.margin_width_n[4] = 1
buffer.margin_width_n[5] = 0
buffer.use_tabs = false
buffer.indent = 2

local function remove_line_number_margin()
    buffer.margin_width_n[1] = 0
end
events.connect(events.BUFFER_NEW, remove_line_number_margin)
events.connect(events.VIEW_NEW, remove_line_number_margin)
events.connect(events.FILE_OPENED, remove_line_number_margin)

ok, msg = xpcall(function()
-- Make textadept-vi available
package.path = _USERHOME .. "/../../?.lua;".._USERHOME .. "/../scripts/?.lua;" .. package.path
package.cpath = _USERHOME .. "/../../extension/?.so;"..package.cpath
local lfs = require'lfs'

function _G.cme_log(...) test.log(...) test.log('\n') end

test = require 'test'

vi_mode = require 'textadept-vi.vi_mode'

-- Get the list of tests to run
local testfiles = {}
do
    local iter, dir_obj=lfs.dir(_USERHOME.."/../tests/")
    while true do
        local name = iter(dir_obj)
        if name == nil then break end
        local basename= name:match("(.+)%.lua$")
--        test.log('name='..name..', base='..tostring(basename) .. "\n")
        if basename ~= nil then
            testfiles[#testfiles+1] = basename
        end
    end
    table.sort(testfiles)
end

test.queue(function()
    for _,basename in ipairs(testfiles) do
        test.run(basename)
    end
end)


end, function(msg)
    local f = io.open("output/test_init_error.txt", "w")
    f:write(debug.traceback(msg))
    f:flush()
    f:close()
    return msg
end)

if not ok then error(msg) end
