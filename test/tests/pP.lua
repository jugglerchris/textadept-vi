test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

test.keys('ddp') -- swap current and next lines.
assertEq(buffer:get_line(1), 'hey bee cee dee ee eff\n')
assertEq(buffer:get_line(2), 'one two three four five\n')
assertEq(colno(), 0)
assertEq(lineno(), 1)

test.keys('ddp') -- swap current and next lines.
assertEq(buffer:get_line(2), 'some miscellaneous text\n')
assertEq(buffer:get_line(3), 'one two three four five\n')
assertEq(colno(), 0)
assertEq(lineno(), 2)

-- TODO: test non-linewise, and P
