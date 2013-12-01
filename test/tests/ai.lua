test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('jwl')
-- aw
test.keys('daw')
assertEq(buffer:get_cur_line(), 'hey cee dee ee eff\n')
assertEq(colno(), 4)

-- iw
test.keys('ediw')
assertEq(colno(), 4)
assertEq(buffer:get_cur_line(), 'hey  dee ee eff\n')
