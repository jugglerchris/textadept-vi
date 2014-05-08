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

-- Check C-style escapes
pat = compile('\\t+')
assertEq(pat:match("abc\t\t foo"), {_start=4, _end=5})

pat = compile('\\n+')
assertEq(pat:match("abc\n\n foo"), {_start=4, _end=5})

pat = compile('\\r+')
assertEq(pat:match("abc\r\r foo"), {_start=4, _end=5})

pat = compile('\\f+')
assertEq(pat:match("abc\f\f foo"), {_start=4, _end=5})

pat = compile('\\a+')
assertEq(pat:match("abc\a\a foo"), {_start=4, _end=5})

pat = compile('\\e+')
assertEq(pat:match("abc\027\027 foo"), {_start=4, _end=5})

-- Check them inside charsets
pat = compile('[ \\t]+')
assertEq(pat:match("abc\t\t tfoo"), {_start=4, _end=6})
