test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('c', 'j', 'x', 'y', 'z', 'escape')
assertEq(lineno(), 0)
assertEq(colno(), 2)
assertEq(buffer:get_line(1), 'xyz\n')
assertEq(buffer:get_line(2), 'some miscellaneous text')
