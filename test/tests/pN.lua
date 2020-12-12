test.open('1_10.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

test.keys('j') -- Start at line 2
test.keys('3yy') -- copy 3 lines
test.keys('5G') -- go to line 5
test.keys('3p') -- paste three times

assertEq(buffer:get_text(), [[1
2
3
4
5
2
3
4
2
3
4
2
3
4
6
7
8
9
10
]])