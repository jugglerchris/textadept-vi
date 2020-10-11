local assertEq = test.assertEq
local ex = vi_mode.ex_mode.run_ex_command
local key = test.key
local keys = test.keys

test.open('1_10.txt')

local function checkOrig()
  return assertEq(buffer:get_text(), [[1
2
3
4
5
6
7
8
9
10
]])
end

checkOrig()

-- Set some marks
keys('4Gma')
keys('7Gmb')
keys('1G')

checkOrig()

ex("'a,'bs/^/__/")
assertEq(buffer:get_text(), [[1
2
3
__4
__5
__6
__7
8
9
10
]])
key('u')

checkOrig()
