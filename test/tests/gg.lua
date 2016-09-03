-- Test gg
test.open("1_100.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('G')
assertEq(lineno(), 100)
test.key('g', 'g')
assertEq(lineno(), 0)

test.keys('7gg')
assertEq(lineno(), 6)

test.keys('1gg')
assertEq(lineno(), 0)
