local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local vi_regex = require('vi_regex')
local compile = vi_regex.compile

local pat = compile('fo+[ab]ar')

assertEq(pat:match("foobar"), {_start=1,_end=6})
assertEq(pat:match("foooobar"), {_start=1,_end=8})
assertEq(pat:match("foblahfoobar"), {_start=7, _end=12})
assertEq(pat:match("foblahfooaar"), {_start=7, _end=12})
assertEq(pat:match("fbar"), nil)
