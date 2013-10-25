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
assertEq(colno(), 9)
test.key('d', 'd')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
test.key('u', '0', '2', 'G')  -- undo
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "0123456789\n")
-- Make the virtual column larger than the current column
test.key('$', 'j', 'l', 'l', 'k')
assertEq(colno(), 9)
assertEq(lineno(), 1)
test.key('d', 'd')
assertEq(buffer:get_text(),[[
abcdefghijklmnopqrstuvwxyz
ABCDEFGHIJKLMNOPQRSTUVWXYZ]])
test.key('u')
assertEq(buffer:get_text(),[[
abcdefghijklmnopqrstuvwxyz
0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZ]])