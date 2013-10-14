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
    test.physkey('c-q')
end)