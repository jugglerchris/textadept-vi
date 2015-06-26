-- Test _
test.open("indents2.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('l', 'l')
assertEq(colno(), 2)
assertEq(lineno(), 0)
test.key('_')
assertEq(colno(), 0)
assertEq(lineno(), 0)
test.key('1', '_')
assertEq(colno(), 0)
assertEq(lineno(), 0)
test.key('2', '_')
assertEq(lineno(), 0)
assertEq(colno(), 2)
test.key('1', 'G')
test.key('4', '_')
assertEq(lineno(), 3)
assertEq(colno(), 0)
