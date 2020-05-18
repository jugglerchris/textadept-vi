test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('a', 'x', 'y', 'z', 'escape')
assertEq(colno(), 3)
assertEq(buffer:get_line(1), 'oxyzne two three four five\n')
test.key('j', 'a', 'z', 'y', 'x', 'escape')
assert(lineno(), 1) assertEq(colno(), 6)
assertEq(buffer:get_line(2), 'hey zyxbee cee dee ee eff\n')

test.key('j', '0', '.')
assertEq(buffer:get_line(3), 'szyxome miscellaneous text')
assertEq(lineno(), 2) assertEq(colno(), 4)
