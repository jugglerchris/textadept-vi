-- Test the re-indent (=<motion>)
-- For now test with XML - add others as needed!
test.open('foo.xml')
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
assertEq(get_indents(), {0, 2, 2, 4, 4, 4, 4, 0, 4, 4, 2, 4, 2, 0})
test.key('u')
assertEq(get_indents(), {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
test.keys('2G==')
assertEq(get_indents(), {0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
-- Regression test: this was returning ...,2,1,0.
test.keys('u11G==12G==')
assertEq(get_indents(), {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0})

--
test.keys('uu1G=G') -- undo and re-indent all
assertEq(get_indents(), {0, 2, 2, 4, 4, 4, 4, 0, 4, 4, 2, 4, 2, 0})
-- Try indenting each line individually to check it doesn't move (ie doesn't
-- give a different result from reindenting the whole thing)
local text = buffer:get_text()
for i = 1,buffer.line_count do
    test.keys(tostring(i).."G==")
    assertEq(buffer:get_text(), text)
end
