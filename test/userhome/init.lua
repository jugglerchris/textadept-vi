-- Make textadept-vi available
package.path = _USERHOME .. "/../../?.lua;".._USERHOME .. "/../scripts/?.lua;" .. package.path

test = require 'test'

vi_mode = require 'vi_mode'

events.connect(events.INITIALIZED, function()
    test.run('empty')
    test.run('jk')
    test.run('hl')
    quit()
    test.physkey('esc')
end)