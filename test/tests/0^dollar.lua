-- Test 0,^,$
test.open("indents.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('$')
assertEq(colno(), 15)
test.key('0')
assertEq(colno(), 1)
test.key('^')
assertEq(colno(), 3)
