test.open('words_unicode.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(lineno(), 0) assertEq(colno(), 0)

-- Check that removing a multibyte character works properly.
test.keys('7l')
assertEq(colno(), 7)
assertEq(buffer:get_line(1), 'Arrow: ─>\n')
test.key('x')
assertEq(colno(), 7)
assertEq(buffer:get_line(1), 'Arrow: >\n')
