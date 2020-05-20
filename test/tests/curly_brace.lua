-- Test the { and } motions
test.open('wrap.txt')

local vi_ta_util = require 'vi_ta_util'

local assertEq = test.assertEq
local lineno = test.lineno
local line_length = vi_ta_util.line_length

assertEq(lineno(), 0)

-- Down a paragraph
test.key('}')
assertEq(lineno(), 4)

-- Up a paragraph
test.key('{')
assertEq(lineno(), 0)

-- Down 2 paragraphs
test.key('2', '}')
assertEq(lineno(), 6)

-- Delete first 2 paragraphs
test.key('d', '2', '{')
assertEq(lineno(), 0)
assertEq(line_length(lineno()+1), 0)
assertEq(buffer.line_count, 5)
assertEq(state.registers['"'],{line=true, text=[[
this
is
a
paragraph

this is a paragraph with a long line.  There are sentence breaks inside the line, and it goes on and on and on.  For at least three lines.  This should be wrapped to separate lines.
]]})
