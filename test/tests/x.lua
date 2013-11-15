test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('x')
assertEq(colno(), 0)
assertEq(buffer:get_line(0), 'ne two three four five\n')
test.key('$', 'x')
assertEq(colno(), 20)
assertEq(buffer:get_line(0), 'ne two three four fiv\n')

test.key('G', '$', 'x')
assertEq(lineno(), 2) assertEq(colno(), 21)
assertEq(buffer:get_line(2), 'some miscellaneous tex')

test.key('0', '3', 'x')
assertEq(lineno(), 2) assertEq(colno(), 0)
assertEq(buffer:get_line(2), 'e miscellaneous tex')

test.key('w', '.')
assertEq(lineno(), 2) assertEq(colno(), 2)
assertEq(buffer:get_line(2), 'e cellaneous tex')

test.key('w', 'l', '.')
assertEq(lineno(), 2) assertEq(colno(), 13)
assertEq(buffer:get_line(2), 'e cellaneous t')
