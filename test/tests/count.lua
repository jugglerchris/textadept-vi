test.open('1_100.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
assertEq(lineno(), 0) assertEq(colno(), 0)
test.keys('3j')
assertEq(lineno(), 3) assertEq(colno(), 0)
test.keys('10j')
assertEq(lineno(), 13) assertEq(colno(), 0)
test.keys('1G11j')
assertEq(lineno(), 11) assertEq(colno(), 0)
-- counts for modifications
assertEq(buffer.line_count, 101)
test.keys('1Gdd')
assertEq(buffer.line_count, 100)
test.keys('1Gud2j')
assertEq(buffer.line_count, 98)
test.keys('d10j')
assertEq(buffer.line_count, 87)
test.keys('d12j')
assertEq(buffer.line_count, 74)
