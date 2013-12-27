test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.keys('dd')
assertEq(buffer:get_line(0), 'hey bee cee dee ee eff\n')
test.keys('u')
assertEq(buffer:get_line(0), 'one two three four five\n')
test.key('c-r')
assertEq(buffer:get_line(0), 'hey bee cee dee ee eff\n')
