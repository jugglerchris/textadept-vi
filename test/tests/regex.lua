local assertEq = test.assertEq
local function log(x) test.log(tostring(x) .. "\n") end
local vi_regex = require('regex.regex')
local compile = vi_regex.compile

local pat = compile('fo+[ab]ar')

assertEq(pat:match("foobar"), {_start=1,_end=6})
assertEq(pat:match("foooobar"), {_start=1,_end=8})
assertEq(pat:match("foblahfoobar"), {_start=7, _end=12})
assertEq(pat:match("foblahfooaar"), {_start=7, _end=12})
assertEq(pat:match("fbar"), nil)

local pat = compile('(foo|bar)+')

assertEq(pat:match("asdfoo"), { _start=4, _end=6 })
assertEq(pat:match("asdfobar"), { _start=6, _end=8 })
assertEq(pat:match("asdfoofoobarjkl;"), { _start=4, _end=12 })
assertEq(pat:match("asdfabulous", nil))

local pat = compile('^.foo')

assertEq(pat:match('afoo'), { _start=1, _end=4 })
assertEq(pat:match('jfoo'), { _start=1, _end=4 })
assertEq(pat:match('jjfoo'), nil)
assertEq(pat:match('foo'), nil)
assertEq(pat:match('foo then foo'), nil)

local pat = compile('a.?b')

assertEq(pat:match('abooo'), { _start=1,_end=2 })
assertEq(pat:match('axbooo'), { _start=1,_end=3 })
assertEq(pat:match('axxbooo'), nil)

local pat = compile('a.*b')
lpeg.print(pat._pat)

assertEq(pat:match('axbcdef'), { _start=1,_end=3 })
assertEq(pat:match('axxbcdef'), { _start=1,_end=4 })
assertEq(pat:match('abcdef'), { _start=1,_end=2 })
assertEq(pat:match('abcdebf'), { _start=1,_end=6 })
assertEq(pat:match('ababab'), { _start=1, _end=6 })
