test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('O', 'x', 'y', 'z', 'escape')
assertEq(lineno(), 0) assertEq(colno(), 2)
assertEq(buffer:get_line(1), 'xyz\n')
assertEq(buffer:get_line(2), 'one two three four five\n')
assertEq(buffer:get_line(3), 'hey bee cee dee ee eff\n')
test.key('j', '$', 'O', 'z', 'y', 'x', 'escape')
assert(lineno(), 1) assertEq(colno(), 2)
assertEq(buffer:get_line(1), 'xyz\n')
assertEq(buffer:get_line(2), 'zyx\n')
assertEq(buffer:get_line(3), 'one two three four five\n')

test.key('G', 'O', 'a', 'b', 'c', 'escape')
assert(lineno(), 4) assertEq(colno(), 2)
assertEq(buffer:get_line(5), 'abc\n')
assertEq(buffer:get_line(6), 'some miscellaneous text')
