test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local assertAt = test.assertAt

-- basic search
test.keys('/cee')
test.key('enter')
--test.key('enter')
assertAt(1, 8)

-- Backwards search
test.keys('?fi')
test.key('enter')
assertAt(0, 19)

-- Repeat forward search
test.keys('/ee')
test.key('enter')
assertAt(1, 5)
test.keys('n')
assertAt(1, 9)
-- with repeat
test.keys('2n')
assertAt(1, 16)
-- wrap
test.key('n')
assertAt(0, 11)
-- prev
test.key('N')
assertAt(1, 16)
test.key('N')
assertAt(1, 13)

-- *, #
-- Create some words to use with * and #.
test.keys('1GOee bee')
test.key('escape')
test.keys('1G0*')
assertAt(2, 16)
test.keys('n')
assertAt(0, 0)
test.keys('w#')
assertAt(2, 4)

-- And test with an action
test.keys('1Gd')
test.keys('/some')
test.key('enter')
assertEq(buffer:get_text(), 'some miscellaneous text')