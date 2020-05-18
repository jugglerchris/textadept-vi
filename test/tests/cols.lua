-- Test that the column stays ok when moving up and down on different line
-- lenghts.
test.open('ramps.txt')
local assertEq = test.assertEq
local lineno = test.lineno
local colno = test.colno
assertEq(buffer.current_pos, 1)
for i=1,12 do
  test.key('j')
  assert(colno() == 0)
  assert(lineno() == i)
end
test.key('l')
test.key('l')
assert(lineno() == 12)
assert(colno() == 2)
-- Now go up; column should go down then back up to 2.
test.key('k')
assert(lineno() == 11)
assertEq(colno(), 1)
test.key('k')
assert(lineno() == 10)
assert(colno() == 0)
test.key('k')
assert(lineno() == 9)
assert(colno() == 0)
test.key('k')
assert(lineno() == 8)
assert(colno() == 0)
test.key('k')
assert(lineno() == 7)
assert(colno() == 1)
test.key('k')
assert(lineno() == 6)
assert(colno() == 2)
test.key('k')
assert(lineno() == 5)
assert(colno() == 2)
test.key('l')
assert(lineno() == 5)
assert(colno() == 3)
test.key('k')
assert(lineno() == 4)
assert(colno() == 3)
test.key('j')
assert(lineno() == 5)
assert(colno() == 3)
test.key('j')
assertEq(lineno(), 6)
assertEq(colno(), 2)
test.key('j')
assert(lineno() == 7)
assert(colno() == 1)
test.key('j')
assert(lineno() == 8)
assert(colno() == 0)
test.key('j')
assert(lineno() == 9)
assert(colno() == 0)
test.key('j')
assertEq(lineno(), 10)
assertEq(colno(), 0)
test.key('j')
assertEq(lineno(), 11)
assertEq(colno(), 1)
