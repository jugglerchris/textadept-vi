-- Test the delete command
test.open('19az.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
test.key('j')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
-- Test deleting the line
test.key('d', 'd')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
test.key('u')  -- undo
assertEq(colno(), 0)
--assertEq(lineno(), 1)
test.key('2', 'G')  -- go to the second line again
assertEq(buffer:get_cur_line(), "0123456789\n")
-- Try at the end of the line too
test.key('$')
assertEq(colno(), 10)
test.key('d', 'd')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
