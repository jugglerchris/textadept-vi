test.open('words.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log

-- Tests inspired by:
-- http://vim.wikia.com/wiki/Swapping_characters,_words_and_lines 
test.key('w') -- go to second word

test.keys('hdeep')
assertEq(buffer:get_cur_line(), 'one three two four five\n')

test.keys('^wxp')
assertEq(buffer:get_cur_line(), 'one htree two four five\n')

-- swap line with next
test.keys('ddp')
assertEq(buffer:get_line(0), 'hey bee cee dee ee eff\n')
assertEq(buffer:get_line(1), 'one htree two four five\n')

-- swap line with previous
test.keys('2GddkP')
assertEq(buffer:get_line(1), 'hey bee cee dee ee eff\n')
assertEq(buffer:get_line(0), 'one htree two four five\n')

-- TODO: add dawbP (swap word with previous) and dawwP/dawelp (with next)
-- when implemented.