local test = require'test'
local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local regex = require('regex')
local compile = regex.compile

pat = compile('foo')
assertEq(pat.patternProps.numGroups, 0)

pat = compile('f(o)o')
assertEq(pat.patternProps.numGroups, 1)

pat = compile('f((o))o')
assertEq(pat.patternProps.numGroups, 2)

pat = compile('f(o)((a)o)')
assertEq(pat.patternProps.numGroups, 3)