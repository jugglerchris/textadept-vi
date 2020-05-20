local assertEq = test.assertEq
local ex = vi_mode.ex_mode.run_ex_command
local key = test.key

test.open('words.txt')

local function checkOrig()
  return assertEq(buffer:get_text(), [[
one two three four five
hey bee cee dee ee eff
some miscellaneous text]])
end

checkOrig()

ex('2s/f/_/')
assertEq(buffer:get_line(2), [[hey bee cee dee ee e_f
]])
key('u')

checkOrig()

ex('2s/f/_/g')
assertEq(buffer:get_line(2), [[hey bee cee dee ee e__
]])
key('u')

checkOrig()

-- no g flag
ex('1,$s/\\<([a-df-z]*)e\\>/J\\1J/')
assertEq(buffer:get_text(), [[
JonJ two three four five
hey bee cee dee ee eff
JsomJ miscellaneous text]])

key('u')
checkOrig()

ex('1,$s/\\<([a-z]*)e\\>/J\\1J/g')

assertEq(buffer:get_text(), [[
JonJ two JthreJ four JfivJ
hey JbeJ JceJ JdeJ JeJ eff
JsomJ miscellaneous text]])

-- undo
key('u')

checkOrig()

ex('1,$s/ .* /{&}/')
assertEq(buffer:get_text(), [[
one{ two three four }five
hey{ bee cee dee ee }eff
some{ miscellaneous }text]])

ex('1,$s/[^ ]*$/___/')
assertEq(buffer:get_text(), [[
one{ two three four ___
hey{ bee cee dee ee ___
some{ miscellaneous ___]])
key('u')

-- Note the \\ is escaped in the string.
ex('1,$s/ /\\n/g')
assertEq(buffer:get_text(), [[
one{
two
three
four
}five
hey{
bee
cee
dee
ee
}eff
some{
miscellaneous
}text]])
