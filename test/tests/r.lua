test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('r', 'x')
assertEq(colno(), 1)
assertEq(buffer:get_line(1), 'xne two three four five\n')
test.key('$', 'r', 'z')
assertEq(colno(), 22)
assertEq(buffer:get_line(1), 'xne two three four fivz\n')
test.key('G', '$', 'r', 'P')
assertEq(lineno(), 2) assertEq(colno(), 22)
assertEq(buffer:get_line(3), 'some miscellaneous texP')

-- Tests with repeats
test.key('2', 'G', '4', 'r', 'K')
assertEq(lineno(), 1) assertEq(colno(), 4)
assertEq(buffer:get_line(2), 'KKKKbee cee dee ee eff\n')

test.key('l', 'l', '.')
assertEq(lineno(), 1) assertEq(colno(), 10)
assertEq(buffer:get_line(2), 'KKKKbeKKKKe dee ee eff\n')

test.key('$', 'h', 'h', '.')  -- should error, as goes over the end of line
assertEq(buffer:get_line(2), 'KKKKbeKKKKe dee ee eff\n')
assertEq(lineno(), 1) assertEq(colno(), 19)

test.keys('0r*')
assertEq(buffer:get_line(2), '*KKKbeKKKKe dee ee eff\n')
