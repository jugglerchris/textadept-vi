test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.keys('cGfoo') test.key('escape')
assertEq(buffer:get_text(), 'foo')
-- TODO: remove the 1G - undo places at the wrong place
test.keys('u1Gw2cwbar') test.key('escape')
assertEq(colno(), 6)
assertEq(lineno(), 0)
assertEq(buffer:get_cur_line(), 'one bar four five\n')

test.keys('j$bbc^jjj') test.key('escape')
assertEq(colno(), 2)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), 'jjjee eff\n')

test.keys('j0wlCbob') test.key('escape')
assertEq(colno(), 8)
assertEq(lineno(), 2)
assertEq(buffer:get_cur_line(), 'some mbob')
