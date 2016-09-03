-- Test gg
test.open("1_100.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('G')
assertEq(lineno(), 100)
test.key('gg')
assertEq(lineno(), 0)
