test.open('words.txt')
local assertEq = test.assertEq
local key = test.key
assertEq(buffer.filename, 'files/words.txt')
test.open('foo.xml')
assertEq(buffer.filename, 'files/foo.xml')
key('c-^')
assertEq(buffer.filename, 'files/words.txt')
key('c-^')
assertEq(buffer.filename, 'files/foo.xml')
