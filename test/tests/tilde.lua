test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('~')
assertEq(colno(), 1)
assertEq(buffer:get_line(1), 'One two three four five\n')
test.key('$', '~')
assertEq(colno(), 22)
assertEq(buffer:get_line(1), 'One two three four fivE\n')
test.key('$', '~')
assertEq(colno(), 22)
assertEq(buffer:get_line(1), 'One two three four five\n')

-- Test repeating it
test.key('^', '2', '~')
assertEq(colno(), 2)
assertEq(buffer:get_line(1), 'oNe two three four five\n')
test.key('.')
assertEq(colno(), 4)
assertEq(buffer:get_line(1), 'oNE two three four five\n')
test.key('3', '.')
assertEq(colno(), 7)
assertEq(buffer:get_line(1), 'oNE TWO three four five\n')
test.key('l', '~')
assertEq(colno(), 9)
assertEq(buffer:get_line(1), 'oNE TWO Three four five\n')
test.key('.')
assertEq(colno(), 10)
assertEq(buffer:get_line(1), 'oNE TWO THree four five\n')

test.key('G', '2', '~')
assertEq(lineno(), 2) assertEq(colno(), 2)
assertEq(buffer:get_line(3), 'SOme miscellaneous text')

test.key('w', 'w', '1', '0', '~')
assertEq(lineno(), 2) assertEq(colno(), 22)
assertEq(buffer:get_line(3), 'SOme miscellaneous TEXT')
