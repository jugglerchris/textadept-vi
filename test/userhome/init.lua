ok, msg = xpcall(function()
-- Make textadept-vi available
package.path = _USERHOME .. "/../../?.lua;".._USERHOME .. "/../scripts/?.lua;" .. package.path
package.cpath = _USERHOME .. "/../../extension/?.so;"..package.cpath

function _G.cme_log(...) end

test = require 'test'

vi_mode = require 'vi_mode'

test.queue(function()
    test.run('empty')
    test.run('count')
    test.run('jk')
    test.run('hl')
    test.run('cols')
    test.run('eq')
    test.run('eq2')
    test.run('d')
    test.run('cw')
    test.run('cw_count')
    test.run('wbe')
    test.run('HML')
    test.run('pct')
    test.run('m_quot_bquot')
    test.run('0^dollar')  -- 0, ^, $
    test.run('dollar2')
    test.run('G')
    test.run('i')
    test.run('a')
    test.run('A')
    test.run('o')
    test.run('O')
    test.run('r')
    test.run('R')
    test.run('tilde')
    test.run('J')
    test.run('gq')
    test.run('dD')
    test.run('cC')
    test.run('x')
    test.run('indent')
    test.run('pP')
    test.run('undo_redo')
    test.run('colon')
    test.run('search') -- /, ?, *, #, n, N
    test.run('tags')   -- c], ct
    test.run('c_hat')  -- c^, switch to last buffer
    test.run('fold')
    -- test.run('cz')     -- suspend; tricky to test in this framework.
    test.run('swap')
    test.run('ai')  -- aw, iw, etc.
    -- signal the end of the test
    io.open("output/results.txt", "a"):write("Finished\n"):flush()
    io.open("output/sem.fifo", "w"):write("Finished\n"):flush()
    
    test.log('killing myself')
    
    test.tmux('kill-pane')
end)


end, function(msg)
    local f = io.open("output/test_init_error.txt", "w")
    f:write(debug.traceback(msg))
    f:flush()
    f:close()
    return msg
end)

if not ok then error(msg) end
