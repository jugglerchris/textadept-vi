local test = require'test'
local assertEq = test.assertEq
local log = test.log
local regex = require('regex')
local compile = regex.compile

pat = compile('|')
assertEq(pat:match("foobar"), {_start=1,_end=0})

pat = compile('()|')
assertEq(pat:match("foobar"), {_start=1,_end=0, groups={{1,0}},})
