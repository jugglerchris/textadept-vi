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
for i=1,9 do
  test.key('l')
  col = col + 1
  assert(colno() == col)
  assert(lineno() == 1)
end
test.key('l')
assert(lineno() == 1)
assert(colno() == 9)
test.key('l')
assert(lineno() == 1)
assert(colno() == 9)
for i=9,1,-1 do
  test.key('h')
  col = col - 1
  assert(lineno() == 1)
  assert(colno() == col)
end
test.key('h')
assert(lineno() == 1)
assert(colno() == 0)
test.key('3')
test.key('l')
assert(lineno() == 1)
assert(colno() == 3)
test.key('9')
test.key('l')
assert(lineno() == 1)
assert(colno() == 9)
test.key('3')
test.key('h')
assert(lineno() == 1)
assert(colno() == 6)
test.key('9')
test.key('h')
assert(lineno() == 1)
assert(colno() == 0)
