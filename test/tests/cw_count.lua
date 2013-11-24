-- Test the change word command
test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
test.key('j')
assertEq(colno(), 0)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "hey bee cee dee ee eff\n")
-- Test changing the first word
test.key('c', 'w', 'f', 'o', 'o', 'escape', 'c-l')
assertEq(colno(), 2)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "foo bee cee dee ee eff\n")
-- Move forward a couple of words (to the cee), then repeat
test.key('w', 'w', '.')
assertEq(buffer:get_cur_line(), "foo bee foo dee ee eff\n")
-- undo and check it's been reverted
test.key('u', 'u')
assertEq(buffer:get_cur_line(), "hey bee cee dee ee eff\n")
-- Try again with a prefix
test.key('0') -- ensure start of line
test.key('3', '.')
-- Prefix should repeat the movement, not the change.
assertEq(buffer:get_cur_line(), "foo dee ee eff\n")
test.key('u')
assertEq(buffer:get_cur_line(), "hey bee cee dee ee eff\n")
-- Try existing count
test.key('2', 'c', 'w', 'r', 's', 't', 'space', 'escape')
assertEq(buffer:get_cur_line(), "rst cee dee ee eff\n")
test.key('u')
assertEq(buffer:get_cur_line(), "hey bee cee dee ee eff\n")
-- Try replacing the count, should change the number of words changed.
test.key('0')
test.key('3', '.')
assertEq(buffer:get_cur_line(), "rst dee ee eff\n")
