ok, msg = xpcall(function()
-- Make textadept-vi available
package.path = _USERHOME .. "/../../?.lua;".._USERHOME .. "/../scripts/?.lua;" .. package.path

test = require 'test'

vi_mode = require 'vi_mode'

test.queue(function()
    test.run('empty')
    test.run('jk')
    test.run('hl')
    test.run('cols')
    test.run('eq')
    test.run('d')
    test.run('cw')
    test.run('cw_count')
    test.physkey('c-q')
end)


end, function(msg)
    local f = io.open("output/test_init_error.txt", "w")
    f:write(debug.traceback(msg))
    f:flush()
    f:close()
    return msg
end)

if not ok then error(msg) end
