local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local vi_regex = require('regex.regex')
local compile = vi_regex.compile

local pat

pat = compile('a(.*)b')

assertEq(pat:match("axyzb"), {_start=1,_end=5, groups={{2,4}},})
assertEq(pat:match("axyzbb"), {_start=1,_end=6, groups={{2,5}},})

pat = compile('a(foo|bar)*b')

assertEq(pat:match("ab"), {_start=1,_end=2, groups={},})
assertEq(pat:match("afoob"), {_start=1,_end=5, groups={{2,4}},})
assertEq(pat:match("afoobarb"), {_start=1,_end=8, groups={{5,7}},})
