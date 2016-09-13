-- Check that running :commands works.
-- Add a dummy command
local assertEq = test.assertEq

local myvar = nil
local vi_mode = require 'vi_mode'
local cmd_errors = {}

local function save_errors(f)
    return function(...)
               ok, err = pcall(f, ...)
               if ok then return err end
               cmd_errors[#cmd_errors+1] = err
           end
end
vi_mode.ex_mode.add_ex_command('tester', save_errors(function(args, range)
      assertEq(args, {'tester', 'arg1', 'arg2'})
      assertEq(range, {1, 4})
      myvar = range
   end), nil) -- no completer

-- test.key doesn't currently work from the command entry, so we instead
-- need to use physkey, with one final key at the end (which will wait for
-- the keypress to have been handled).
test.keys(':1,4tester arg1 arg2')
test.key('enter')

assertEq(cmd_errors, {})
assertEq(myvar,{1,4})

-- remove the test command
assert(vi_mode.ex_mode.ex_commands['tester'])
vi_mode.ex_mode.ex_commands['tester'] = nil
