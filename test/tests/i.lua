test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('i', 'x', 'y', 'z', 'escape')
assertEq(colno(), 2)
assertEq(buffer:get_line(1), 'xyzone two three four five\n')
test.key('j', 'i', 'z', 'y', 'x', 'escape')
assert(lineno(), 1) assertEq(colno(), 4)
assertEq(buffer:get_line(2), 'hezyxy bee cee dee ee eff\n')

test.key('j', '0', '.')
assertEq(buffer:get_line(3), 'zyxsome miscellaneous text')
assertEq(lineno(), 2) assertEq(colno(), 3)

test.keys('1G0i_')
test.key('escape')
test.keys('j0.')
assertEq(buffer:get_line(1), '_xyzone two three four five\n')
assertEq(buffer:get_line(2), '_hezyxy bee cee dee ee eff\n')
