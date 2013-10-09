-- Test the up/down arrows
test.open('1_10.txt')
local lineno = test.lineno
assert(buffer.current_pos == 0)
assert(lineno() == 0)
test.key('k')
assert(lineno() == 0)
test.key('j')
assert(lineno() == 1)
test.key('j')
assert(lineno() == 2)
test.key('k')
assert(lineno() == 1)
test.key('j')
assert(lineno() == 2)
for i=1,10 do
  test.key('j')
end
assert(lineno() == 10)
test.key('k')
assert(lineno() == 9)
test.key('k')
assert(lineno() == 8)
for i=1,10 do
  test.key('k')
end
assert(lineno() == 0)
