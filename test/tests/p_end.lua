test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

assertEq(colno(), 0)
assertEq(lineno(), 0)
test.keys('yw') -- yanks the first line
test.key('G', 'o') -- and put at the end
test.key('escape')
test.key('p')
assertEq(colno(), 3)
assertEq(lineno(), 3)
assertEq(buffer:get_line(4), "one ")
test.key('O', 'escape')
test.key('p')
assertEq(buffer:get_text(),
    [[one two three four five
hey bee cee dee ee eff
some miscellaneous text
one 
one ]])
