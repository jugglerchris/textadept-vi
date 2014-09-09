test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.keys('dG')
assertEq(buffer:get_text(), '')
-- TODO: remove the 1G - undo places at the wrong place
test.keys('u1Gw2dw')
assertEq(colno(), 4)
assertEq(lineno(), 0)
assertEq(buffer:get_cur_line(), 'one four five\n')

-- Check that the redo gets the right count
test.keys('^.')
assertEq(colno(), 0)
assertEq(lineno(), 0)
assertEq(buffer:get_cur_line(), 'five\n')

test.keys('j$bbd^')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), 'ee eff\n')

test.keys('j0wlD')
assertEq(colno(), 6)
assertEq(lineno(), 2)
assertEq(buffer:get_cur_line(), 'some m')
