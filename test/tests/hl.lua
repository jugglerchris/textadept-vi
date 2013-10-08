-- Test the left/right keys
test.open('19az.txt')
local lineno = test.lineno
local colno = test.colno
test.key('j')
assert(colno() == 0)
assert(lineno() == 1)
test.key('h')
assert(colno() == 0)
assert(lineno() == 1)
local col = 0
for i=1,10 do
  test.key('l')
  col = col + 1
  assert(colno() == col)
  assert(lineno() == 1)
end
test.key('l')
assert(lineno() == 1)
assert(colno() == 11)
test.key('l')
assert(lineno() == 1)
assert(colno() == 11)