local test = require'test'
local assertEq = test.assertEq
local log = test.log
local pegex = require('pegex')
local compile = pegex.compile

pat = compile('|')
assertEq(pat:match("foobar"), {_start=1,_end=0})

pat = compile('()|')
assertEq(pat:match("foobar"), {_start=1,_end=0, groups={{1,0}},})

pat = compile("((a)|(ab))((c)|(bc))")
assertEq(pat:match("ac"), {_start=1,_end=2, groups={
                                               {1,1},
                                               {1,1},
                                               nil,
                                               {2,2},
                                               {2,2},
                                               nil}})
assertEq(pat:match("abc"), {_start=1,_end=3, groups={
                                               {1,1},
                                               {1,1},
                                               nil,
                                               {2,3},
                                               nil,
                                               {2,3}}})
assertEq(pat:match("abbc"), {_start=1,_end=4, groups={
                                               {1,2},
                                               nil,
                                               {1,2},
                                               {3,4},
                                               nil,
                                               {3,4}}})