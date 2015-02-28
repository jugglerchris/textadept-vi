test.open("cmpl1.txt")
assertEq = test.assertEq
assertFileEq = test.assertFileEq
assertAt = test.assertAt

local keys = test.keys
local key = test.key

keys('3j')
assertAt(3, 0)
assertEq(buffer:get_cur_line(), "\n")

keys('if')
key('c-n') -- ctrl-n
assertEq(buffer:get_cur_line(), "four\n")
key('c-n')
assertEq(buffer:get_cur_line(), "five\n")
key('c-n') -- Start picking up tags
assertEq(buffer:get_cur_line(), "foo\n")
key('c-n') -- looping around
assertEq(buffer:get_cur_line(), "f\n")
key('c-n')
assertEq(buffer:get_cur_line(), "four\n")
key('c-p')
assertEq(buffer:get_cur_line(), "f\n")
key('c-p')
assertEq(buffer:get_cur_line(), "foo\n")
key('c-p')
assertEq(buffer:get_cur_line(), "five\n")
