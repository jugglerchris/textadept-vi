test.open("cmpl1.txt")
assertEq = test.assertEq
assertFileEq = test.assertFileEq
assertAt = test.assertAt

local keys = test.keys
local key = test.key

keys('3j')
assertAt(3, 0)
assertEq(buffer:get_cur_line(), "\n")

keys('ise')
key('c-n') -- ctrl-n
assertEq(buffer:get_cur_line(), "seven\n")
key('c-n')
assertEq(buffer:get_cur_line(), "secret\n")
key('c-n')
assertEq(buffer:get_cur_line(), "selections\n")
key('c-n')
assertEq(buffer:get_cur_line(), "se\n")
key('c-n') -- looping around
assertEq(buffer:get_cur_line(), "seven\n")
key('c-p')
assertEq(buffer:get_cur_line(), "se\n")
key('c-p')
assertEq(buffer:get_cur_line(), "selections\n")
key('c-p')
assertEq(buffer:get_cur_line(), "secret\n")
