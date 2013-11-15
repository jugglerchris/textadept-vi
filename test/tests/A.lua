test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('A', 'x', 'y', 'z', 'escape')
assertEq(colno(), 25)
assertEq(buffer:get_line(0), 'one two three four fivexyz\n')
test.key('j', 'A', 'z', 'y', 'x', 'escape')
assert(lineno(), 1) assertEq(colno(), 24)
assertEq(buffer:get_line(1), 'hey bee cee dee ee effzyx\n')

test.key('j', '0', '.')
assertEq(buffer:get_line(2), 'some miscellaneous textzyx')
assertEq(lineno(), 2) assertEq(colno(), 25)
