-- Test $ with counts
test.open("ramps.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('$')
assertEq(colno(), 0) assertEq(lineno(), 0)
test.keys('j3$')
assertEq(colno(), 2) assertEq(lineno(), 3)
