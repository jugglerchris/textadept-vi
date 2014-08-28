test.open("tags/bar.c")
assertEq = test.assertEq
assertFileEq = test.assertFileEq
assertAt = test.assertAt
ex = vi_mode.ex_mode.run_ex_command
local keys = test.keys
key = test.key

keys('jj0w')
test.key('c-]')

assertFileEq(buffer.filename, 'files/tags/foo.c')
assertAt(1, 0)
ex('tn')
assertFileEq(buffer.filename, 'files/tags/foo.c')
assertAt(5, 0)
key('c-t')
assertFileEq(buffer.filename, 'files/tags/bar.c')
assertAt(2,4)
key('j') key('c-]')

assertFileEq(buffer.filename, 'files/tags/foo.h')
assertAt(0, 0)

ex('tag baz')
assertFileEq(buffer.filename, 'files/tags/baz.c')
assertAt(0, 0)
key('c-t')
assertFileEq(buffer.filename, 'files/tags/foo.h')
ex('tsel baz')
assertFileEq(buffer.filename, 'files/tags/baz.c')
assertAt(0, 0)
