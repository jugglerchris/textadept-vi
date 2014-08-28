test.open('words.txt')
local assertFileEq = test.assertFileEq
local key = test.key
assertFileEq(buffer.filename, 'files/words.txt')
test.open('foo.xml')
assertFileEq(buffer.filename, 'files/foo.xml')
key('c-^')
assertFileEq(buffer.filename, 'files/words.txt')
key('c-^')
assertFileEq(buffer.filename, 'files/foo.xml')
