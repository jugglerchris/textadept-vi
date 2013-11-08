-- Test G
test.open("ramps.txt")
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq

test.key('G')
assertEq(lineno(), 12)
test.key('1', 'G')
assertEq(lineno(), 0)
for i=1,12,3 do
   local cmd = i .. "G"
   for j=1,cmd:len() do
     test.key(cmd:sub(j,j))
   end
   assertEq(lineno(), i-1)
end