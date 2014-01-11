test.open("tags/bar.c")
assertEq = test.assertEq
assertAt = test.assertAt
ex = vi_mode.ex_mode.run_ex_command
keys = test.keys
key = test.key

keys('jj0w')
test.key('c-]')

assertEq(buffer.filename, 'files/tags/foo.c')
assertAt(5, 0)
ex('tn')
assertEq(buffer.filename, 'files/tags/foo.c')
assertAt(1, 0)
key('ct')
assertEq(buffer.filename, 'files/tags/bar.c')
assertAt(2,4)
key('j') key('c]')

assertEq(buffer.filename, 'files/tags/foo.h')
assertAt(0, 0)
