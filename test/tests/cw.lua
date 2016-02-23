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
test.key('c', 'w', 'f', 'o', 'o', 'escape')
assertEq(colno(), 2)
assertEq(lineno(), 1)
assertEq(buffer:get_cur_line(), "foo bee cee dee ee eff\n")
-- Move forward a couple of words (to the cee), then repeat
test.key('w', 'w', '.')
assertEq(buffer:get_cur_line(), "foo bee foo dee ee eff\n")
-- undo and check it's been reverted
test.key('u', 'u')
assertEq(buffer:get_cur_line(), "hey bee cee dee ee eff\n")
-- Try on the last word of the line
test.key('^', '5', 'w')
assertEq(colno(), 19)
test.key('c', 'w', 'X', 'escape')
assertEq(buffer:get_cur_line(), "hey bee cee dee ee X\n")
-- Try at the end of a line.
test.key('u', '$', 'c', 'w', 'Y', 'escape')
assertEq(buffer:get_cur_line(), "hey bee cee dee ee efY\n")
-- The last word of the last line (with no newline, as in words.txt)
test.key('u', 'G', '$', 'b', 'c', 'w', 'a', 'b', 'escape')
assertEq(buffer:get_cur_line(), "some miscellaneous ab")

-- Some other cases
test.open('punc1.txt')
test.key('c', 'w', '_', 'escape')
assertEq(buffer:get_cur_line(), "_.bar.baz\n")
test.key('u', '^', '2', 'c', 'w', '_', 'escape')
assertEq(buffer:get_cur_line(), "_bar.baz\n")
test.key('u', '^', 'c', '2', 'w', '=', 'escape')
assertEq(buffer:get_cur_line(), "=bar.baz\n")
