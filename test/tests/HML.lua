-- Test the left/right keys
test.open('1_100.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log
test.key('j', 'l')
assertEq(colno(), 0) assertEq(lineno(), 1)
test.key('H')
assertEq(colno(), 0) assertEq(lineno(), 0)
test.key('M')
assertEq(colno(), 0) assertEq(lineno(), 10)
test.key('L')
assertEq(colno(), 0) assertEq(lineno(), 20)
test.key('H')
assertEq(colno(), 0) assertEq(lineno(), 0)
test.key('M')
assertEq(colno(), 0) assertEq(lineno(), 10)
test.key('L')
assertEq(colno(), 0) assertEq(lineno(), 20)
