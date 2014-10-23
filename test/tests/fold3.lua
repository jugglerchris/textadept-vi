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

local function lines_visible()
    local result = {}
    local i = 0
    for i=0,buffer.line_count-1 do
        result[#result+1] = buffer.line_visible[i]
    end
    return result
end

test.keys('zM')
assertEq(lines_visible(), {true, false, false, false, true, false, false, false})
test.keys('zR')
assertEq(lines_visible(), {true, true, true, true, true, true, true, true})
test.keys('zM')
assertEq(lines_visible(), {true, false, false, false, true, false, false, false})
-- Check that lines become visible when searching
test.keys('/retur') test.key('enter')
assertAt(6, 3)
assertEq(lines_visible(), {true, false, false, false, true, true, true, true})
