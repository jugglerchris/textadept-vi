-- Test :e

-- test completion in the same directory.
test.keys(':e dumm')
test.key('tab')

local buffer = ui.command_entry
test.assertEq(buffer:get_text(), 'e dummy%.txt')

buffer = _G.buffer
test.key('enter')
test.assertEq(buffer:get_text(), 'dummy\n')
