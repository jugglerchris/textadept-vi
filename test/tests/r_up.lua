test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('R', 'A', 'B', 'C', 'escape')
assertEq(colno(), 2)
assertEq(buffer:get_line(0), 'ABC two three four five\n')
test.key('$', 'R', 'Z', 'Y', 'X', 'escape')
assertEq(colno(), 24)
assertEq(buffer:get_line(0), 'ABC two three four fivZYX\n')
test.key('G', '$', 'R', 'J', 'K', 'L', 'escape')
assertEq(lineno(), 2) assertEq(colno(), 24)
assertEq(buffer:get_line(2), 'some miscellaneous texJKL')
-- repeat action
test.keys('^.')
assertEq(lineno(), 2) assertEq(colno(), 2)
assertEq(buffer:get_line(2), 'JKLe miscellaneous texJKL')

-- Test with repeats
test.keys('1G0')
test.key('3', 'R', '1', '2', '3', 'escape')
assertEq(buffer:get_line(0), '123123123hree four fivZYX\n')
test.keys('j2.')
assertEq(lineno(), 1) assertEq(colno(), 13)
assertEq(buffer:get_line(1), 'hey bee 123123e ee eff\n')