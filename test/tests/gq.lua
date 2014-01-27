-- Test the re-indent (=<motion>)
-- For now test with XML - add others as needed!
test.open('wrap.txt')
local assertEq = test.assertEq
local colno, lineno = test.colno, test.lineno

assertEq(buffer.current_pos, 0)

-- Wrap the first line.
test.keys('gql')
assertEq(buffer:get_line(0), 'this\n')
assertEq(colno(), 0) assertEq(lineno(), 0)

-- Wrap the first two lines
test.keys('gqj')
assertEq(buffer:get_line(0), 'this is\n')
assertEq(colno(), 0) assertEq(lineno(), 0)
test.keys('u1G')

-- Wrap the first four lines
test.keys('gq3j')
assertEq(buffer:get_line(0), 'this is a paragraph\n')
assertEq(colno(), 0) assertEq(lineno(), 0)
assertEq(buffer:get_line(1), '\n')

-- Undo, then wrap the whole file
test.keys('u')
assertEq(buffer:get_line(0), 'this\n')
test.keys('1GgqG')
assertEq(buffer:get_text(), [[
this is a paragraph

this is a paragraph with a long line.  There are sentence breaks inside the
line, and it goes on and on and on.  For at least three lines.  This should be
wrapped to separate lines.

this is a paragraph with a long line.  There are sentence breaks inside the
line, and it goes on and on and on.  For at least three lines.  This should be
wrapped to separate lines.  This paragraph also has a second line.

And this third is a separate paragraph.]])

-- Undo, then wrap one paragraph and check we're left on the last line.
test.keys('u6Ggql')
assertEq(buffer:get_line(5), "this is a paragraph with a long line.  There are sentence breaks inside the\n")
assertEq(buffer:get_line(6), "line, and it goes on and on and on.  For at least three lines.  This should be\n")
assertEq(buffer:get_line(7), "wrapped to separate lines.\n")
assertEq(lineno(), 7)
