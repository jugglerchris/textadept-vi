-- Test indenting.
test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
buffer.indent = 4
test.keys('>>')
assertEq(colno(), 4)
assertEq(lineno(), 0)
assertEq(buffer:get_cur_line(), "    one two three four five\n")
test.keys('3>>')
assertEq(colno(), 8)
assertEq(lineno(), 0)
assertEq(buffer:get_text(), [[
        one two three four five
    hey bee cee dee ee eff
    some miscellaneous text]])
test.keys('3G>2k')
assertEq(colno(), 12)
assertEq(lineno(), 0)
assertEq(buffer:get_text(), [[
            one two three four five
        hey bee cee dee ee eff
        some miscellaneous text]])
test.keys('2G<k')
assertEq(colno(), 8)
assertEq(lineno(), 0)
assertEq(buffer:get_text(), [[
        one two three four five
    hey bee cee dee ee eff
        some miscellaneous text]])
test.keys('2<<')
assertEq(buffer:get_text(), [[
    one two three four five
hey bee cee dee ee eff
        some miscellaneous text]])
test.keys('1G<2j')
assertEq(buffer:get_text(), [[
one two three four five
hey bee cee dee ee eff
    some miscellaneous text]])

test.keys('G>>')
assertEq(buffer:get_text(), [[
one two three four five
hey bee cee dee ee eff
        some miscellaneous text]])
