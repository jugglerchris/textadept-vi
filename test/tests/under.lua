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
assertEq(lineno(), 1)
assertEq(colno(), 2)
test.key('1', 'G')
test.key('4', '_')
assertEq(lineno(), 3)
assertEq(colno(), 0)

-- Check as a (linewise) motion
test.key('2', 'G')
test.key('c', '3', '_', 'a', 's', 'd', 'f', 'escape')
assertEq(lineno(), 1)
assertEq(colno(), 3)
assertEq(buffer:get_line(1), 'blah blah\n')
assertEq(buffer:get_line(2), 'asdf\n')
assertEq(buffer:get_line(3), '\n')
assertEq(buffer:get_line(4), 'This is a sentence.\n')
