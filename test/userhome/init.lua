-- Turn on coverage analysis if available
pcall(require, 'luacov')

-- Used to be in properties.lua
buffer.margin_width_n[0] = 0
buffer.margin_width_n[1] = 0
buffer.margin_width_n[2] = 1
buffer.margin_width_n[3] = 1
buffer.use_tabs = false
buffer.indent = 2

ok, msg = xpcall(function()
-- Make textadept-vi available
package.path = _USERHOME .. "/../../?.lua;".._USERHOME .. "/../scripts/?.lua;" .. package.path
package.cpath = _USERHOME .. "/../../extension/?.so;"..package.cpath
local lfs = require'lfs'

function _G.cme_log(...) test.log(...) test.log('\n') end

test = require 'test'

vi_mode = require 'vi_mode'

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
