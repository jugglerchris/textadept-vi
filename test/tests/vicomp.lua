-- Test vi_complete.lua
local assertEq = test.assertEq
local keys = test.keys
local vi_complete = require'vi_complete'
local t = vi_complete._test

test.open('words.txt')

-- Find the current prefix
keys('1G03l')
assertEq({t.find_prefix()}, {0, 'one'})

keys('1G02l')
assertEq({t.find_prefix()}, {0, 'on'})

keys('1G0wl')
assertEq({t.find_prefix()}, {4, 't'})

-- Get the list of matching words
keys('1G0wl')
assertEq(t.get_words(true, 4, 't'), {'three', 'text'})

keys('1G0wl')
assertEq(t.get_words(false, 4, 't'), {'three', 'text'})
