test.open("cmpl1.txt")
assertEq = test.assertEq
assertFileEq = test.assertFileEq
assertAt = test.assertAt

local keys = test.keys
local key = test.key

keys('2j2l')
assertAt(2, 2)
assertEq(buffer:get_cur_line(), "seven secret selections\n")

keys('i')
key('c-p') -- ctrl-p
assertEq(buffer:get_cur_line(), "selectionsven secret selections\n")
key('c-p')
assertEq(buffer:get_cur_line(), "secretven secret selections\n")
key('c-p')
assertEq(buffer:get_cur_line(), "seven secret selections\n")
