local test = require'test'
local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local regex = require('regex')
local compile = regex.compile

pat = compile('foo')
assertEq(pat.numgroups, 0)

pat = compile('f(o)o')
assertEq(pat.numgroups, 1)

pat = compile('f((o))o')
assertEq(pat.numgroups, 2)

pat = compile('f(o)((a)o)')
assertEq(pat.numgroups, 3)