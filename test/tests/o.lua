test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('o', 'x', 'y', 'z', 'escape')
assertEq(lineno(), 1) assertEq(colno(), 2)
assertEq(buffer:get_line(0), 'one two three four five\n')
assertEq(buffer:get_line(1), 'xyz\n')
assertEq(buffer:get_line(2), 'hey bee cee dee ee eff\n')
test.key('j', '$', 'o', 'z', 'y', 'x', 'escape')
assert(lineno(), 3) assertEq(colno(), 2)
assertEq(buffer:get_line(1), 'xyz\n')
assertEq(buffer:get_line(2), 'hey bee cee dee ee eff\n')
assertEq(buffer:get_line(3), 'zyx\n')
assertEq(buffer:get_line(4), 'some miscellaneous text')

test.key('G', 'o', 'a', 'b', 'c', 'escape')
assert(lineno(), 5) assertEq(colno(), 2)
assertEq(buffer:get_line(4), 'some miscellaneous text\n')
assertEq(buffer:get_line(5), 'abc')
