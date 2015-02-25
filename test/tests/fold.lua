test.open('simple.lua')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local getscreen = test.getscreen

-- Make sure the screen updates after opening.
test.key('c-l')

local origScreen = [[
⊟ function f()
│    -- blah
└ end

]]
local foldedScreen = "⊞ function f()\n\n\n\n"

assertEq(getscreen(1, 4), origScreen)
-- Now try folding
-- TODO: work out why c-l is needed before the screen updates.
test.key('z', 'c', 'c-l')
assertEq(getscreen(1, 4), foldedScreen)

test.key('z', 'o', 'c-l')
assertEq(getscreen(1, 4), origScreen)
