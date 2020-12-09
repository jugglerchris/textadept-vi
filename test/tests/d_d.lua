-- Test the delete command
test.open('blanklines.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
test.key('j', 'j', 'j')
assertEq(colno(), 0)
assertEq(lineno(), 3)
assertEq(buffer:get_cur_line(), "three\n")
test.key('d', 'd')
assertEq(buffer:get_text(),[[
one
two

four

five
six
]])
assertEq(lineno(), 3)
test.key('d', 'd')
assertEq(buffer:get_text(),[[
one
two


five
six
]])
assertEq(lineno(), 3)
test.key('d', 'd')
assertEq(buffer:get_text(),[[
one
two

five
six
]])
assertEq(lineno(), 3)
test.key('u', 'u', 'u', '4', 'G') -- Shouldn't need the 3G, but...
assertEq(lineno(), 3)
assertEq(buffer:get_text(),[[
one
two

three
four

five
six
]])
test.key('d', 'd')
assertEq(lineno(), 3)
assertEq(buffer:get_text(),[[
one
two

four

five
six
]])
test.key('.')
assertEq(buffer:get_text(),[[
one
two


five
six
]])
assertEq(lineno(), 3)
