-- Test mark
test.open("ramps.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log
assertEq(lineno(), 0) assertEq(colno(), 0)
test.key('m', 'a')  -- set first mark
test.key('j', 'j', 'm', 'b')
test.key('l', 'm', 'c')
test.key('G', 'k', '$', 'm', 'd')

-- Now try jumping back to them
test.key("'", 'a')
assertEq(lineno(), 0) assertEq(colno(), 0)
test.key("'", 'b')
assertEq(lineno(), 2) assertEq(colno(), 0)
test.key("'", 'c')
assertEq(lineno(), 2) assertEq(colno(), 0)
test.key("'", 'd')
assertEq(lineno(), 11) assertEq(colno(), 0)
-- And again using `
test.key("`", 'a')
assertEq(lineno(), 0) assertEq(colno(), 0)
test.key("`", 'b')
assertEq(lineno(), 2) assertEq(colno(), 0)
test.key("`", 'c')
assertEq(lineno(), 2) assertEq(colno(), 1)
test.key("`", 'd')
assertEq(lineno(), 11) assertEq(colno(), 1)
