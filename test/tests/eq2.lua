-- Test the re-indent (=<motion>)
test.open('foo2.xml')
local assertEq = test.assertEq
assertEq(buffer.current_pos, 0)
-- indent the whole file
test.key('=')
test.key('G')
-- Get the indentation of each line
local function get_indents()
  local indents = {}
  for i=1,buffer.line_count do
    -- line numbers 0-based
    indents[i] = buffer:get_line(i-1):match("^ *()") - 1
  end
  return indents
end
assertEq(get_indents(), {0, 0, 2, 0, 0})
