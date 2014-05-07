local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local vi_regex = require('regex.regex')
local compile = vi_regex.compile

local pat
-- Check \s, \S, \w, \W, \d, \D
pat = compile('x\\s')

assertEq(pat:match("xxx j"), {_start=3,_end=4})
assertEq(pat:match("xxx\tj"), {_start=3,_end=4})

pat = compile('\\w\\s')
assertEq(pat:match("x j"), {_start=1,_end=2})
assertEq(pat:match("Z_ j"), {_start=2, _end=3})
assertEq(pat:match("Z; j"), nil)

pat = compile('\\W\\w')
assertEq(pat:match(";2 177_x j"), {_start=6,_end=7})

pat = compile('\\S\\s\\S')
assertEq(pat:match(";2 177_x j"), {_start=2,_end=4})

pat = compile('\\d+')
assertEq(pat:match("askdfj1317 jlj"), {_start=7, _end=10})

pat = compile('\\D+')
assertEq(pat:match("1230 _abc;_ 8"), {_start=5, _end=12})