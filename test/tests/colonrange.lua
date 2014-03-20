-- Check that running :commands works.
-- Add a dummy command
local assertEq = test.assertEq

local myvar = nil
local vi_mode = require 'vi_mode'
vi_mode.ex_mode.add_ex_command('tester', function(args, range)
      assertEq(args, {'tester', 'arg1', 'arg2'})
      assertEq(range, {1, 4})
      myvar = range
   end, nil) -- no completer
   
-- test.key doesn't currently work from the command entry, so we instead
-- need to use physkey, with one final key at the end (which will wait for
-- the keypress to have been handled).
test.keys(':1,4tester arg1 arg2')
test.key('enter')

assertEq(myvar,{1,4})

-- remove the test command
assert(vi_mode.ex_mode.ex_commands['tester'])
vi_mode.ex_mode.ex_commands['tester'] = nil