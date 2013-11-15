test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('~')
assertEq(colno(), 1)
assertEq(buffer:get_line(0), 'One two three four five\n')
test.key('$', '~')
assertEq(colno(), 22)
assertEq(buffer:get_line(0), 'One two three four fivE\n')
test.key('$', '~')
assertEq(colno(), 22)
assertEq(buffer:get_line(0), 'One two three four five\n')

test.key('G', '2', '~')
assertEq(lineno(), 2) assertEq(colno(), 2)
assertEq(buffer:get_line(2), 'SOme miscellaneous text')

test.key('w', 'w', '1', '0', '~')
assertEq(lineno(), 2) assertEq(colno(), 22)
assertEq(buffer:get_line(2), 'SOme miscellaneous TEXT')
