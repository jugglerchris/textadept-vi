local assertEq = test.assertEq
local assertFileEq = test.assertFileEq
local assertMatches = test.assertMatches
local T = test.T
local F = test.F
local STAR = test.STAR

local function dumpsplit(t, indent)
  indent = indent or ""
  if not t[1] then
    test.log(indent.."View: " ..tostring(t).." ".. test.tostring(t.buffer.filename).. '\n')
  else
    test.log(indent.."Split: ver=".. tostring(t.vertical)..', size='..t.size.. '\n')
    dumpsplit(t[1], indent.."  ")
    dumpsplit(t[2], indent.."  ")
  end
end
_G.dumpsplit = dumpsplit

local function assertSplitMatches(a, b)
    local ok, err = pcall(assertMatches, a, b)
    if not ok then
        test.log("Split not as expected:\n")
        dumpsplit(a)
        dumpsplit(b)
        error(err, 2)
    end
end

test.open('a.txt')

assertSplitMatches(ui.get_split_table(), T{buffer=T{filename=F'files/a.txt'}})

test.colon('vsplit')
test.open('b.txt')

assertSplitMatches(ui.get_split_table(),
              {
                T{buffer=T{filename=F'files/a.txt'}},
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=40,
              })
              
test.key('c-w', 'c-w')
test.colon('split')
test.open('c.txt')

assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/c.txt'}},
                   vertical=false,
                   size=10,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=40,
              })
              
assertFileEq(buffer.filename, 'files/c.txt')
test.colon('e files/d.txt')
assertFileEq(buffer.filename, 'files/d.txt')
              
assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/d.txt'}},
                   vertical=false,
                   size=10,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=40,
              })
              
assertFileEq(buffer.filename, 'files/d.txt')
test.colon('b c.txt')
assertFileEq(buffer.filename, 'files/c.txt')
              
assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/c.txt'}},
                   vertical=false,
                   size=10,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=40,
              })

test.key('c-w', '+')
assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/c.txt'}},
                   vertical=false,
                   size=9,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=40,
              })

test.key('5', 'c-w', '-')
assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/c.txt'}},
                   vertical=false,
                   size=14,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=40,
              })

test.key('3', 'c-w', '<')
assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/c.txt'}},
                   vertical=false,
                   size=14,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=37,
              })

test.key('6', 'c-w', '>')
assertSplitMatches(ui.get_split_table(),
              {
                {
                   T{buffer=T{filename=F'files/a.txt'}},
                   T{buffer=T{filename=F'files/c.txt'}},
                   vertical=false,
                   size=14,
                },
                T{buffer=T{filename=F'files/b.txt'}},
                vertical=true,
                size=43,
              })

-- Tidy up.
view:unsplit()
view:unsplit()