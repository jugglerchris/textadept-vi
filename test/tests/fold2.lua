test.open('mid.lua')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local assertAt = test.assertAt

assertAt(0,0)

-- Now try folding
test.keys('zc')
assertAt(0,0)
-- Try moving over folded function
test.key('j')
assertAt(4,0) -- should have skipped the body

test.key('k')
assertAt(0,0) -- should have skipped the body
