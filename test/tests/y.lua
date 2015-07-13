-- Test the yank command
test.open('19az.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
test.key('j')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
-- Test yanking the line
test.key('y', 'y')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
-- And pasting it
test.key('p')
--assertEq(lineno(), 1)
assertEq(colno(), 0)
assertEq(lineno(), 2)
assertEq(buffer:get_cur_line(), "0123456789\n")
test.key('k')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
test.key('3', 'l')
assertEq(colno(), 3)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
test.key('y', 'y')
assertEq(colno(), 3)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
