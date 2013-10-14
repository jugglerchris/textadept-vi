-- Test the re-indent (=<motion>)
-- For now test with XML - add others as needed!
test.open('foo.xml')
local assertEq = test.assertEq
assertEq(buffer.current_pos, 0)
-- indent the whole file
test.key('=')
test.key('G')
-- Get the indentation of each line
indents = {}
for i=1,buffer.line_count do
    -- line numbers 0-based
    indents[i] = buffer:get_line(i-1):match("^ *()") - 1
end
assertEq(indents, {0, 2, 2, 4, 4, 4, 4, 4, 2, 2, 4, 2, 0})