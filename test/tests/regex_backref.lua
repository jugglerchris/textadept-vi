local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local vi_regex = require('textadept-vi.regex.pegex')
local compile = vi_regex.compile

local pat

pat = compile('([A-Z]+)[a-z]*\\1')

assertEq(pat:match('ABCfooDEF'), nil)
assertEq(pat:match('ABCfooABC'), {_start=1, _end=9, groups={{1,3}}})
assertEq(pat:match('ABCfooBCD'), {_start=2, _end=8, groups={{2,3}}})
