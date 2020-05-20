test.open('indents2.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

test.key('J')
assertEq(colno(), 9)
assertEq(buffer:get_line(1), 'blah blah woo woo\n')
test.key('J')
assertEq(colno(), 17)
assertEq(buffer:get_line(1), 'blah blah woo woo erg  -- trailing spaces    \n')
test.key('J')
assertEq(colno(), 45)
assertEq(buffer:get_line(1), 'blah blah woo woo erg  -- trailing spaces     sponge\n')

test.key('j', 'j', '0')
assertEq(lineno(), 2) assertEq(colno(), 0)
assertEq(buffer:get_line(3), 'This is a sentence.\n')

test.key('J')
assertEq(lineno(), 2) assertEq(colno(), 19)
assertEq(buffer:get_line(3), 'This is a sentence.  And another.\n')
