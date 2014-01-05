test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local assertAt = test.assertAt

-- *, #

-- basic search
test.physkeys('/cee')
test.key('\n')
assertAt(1, 8)

-- Backwards search
test.physkeys('?fi')
test.key('enter')
assertAt(0, 19)

-- Repeat forward search
test.physkeys('/ee')
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