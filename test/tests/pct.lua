-- Test brace/bracket (and #if etc.) matching
test.open('bracket.txt')
local lineno = test.lineno
local colno = test.colno
local assertEq = test.assertEq
local log = test.log
assertEq(lineno(), 0) assertEq(colno(), 0)
test.key('%')
assertEq(lineno(), 0) assertEq(colno(), 7)
test.key('%', 'l')
assertEq(lineno(), 0) assertEq(colno(), 1)
test.key('%')
assertEq(lineno(), 0) assertEq(colno(), 6)
test.key('%', 'l')
assertEq(lineno(), 0) assertEq(colno(), 2)
test.key('%')
assertEq(lineno(), 0) assertEq(colno(), 5)
test.key('%', 'l')
assertEq(lineno(), 0) assertEq(colno(), 3)
test.key('%')
assertEq(lineno(), 0) assertEq(colno(), 4)
test.key('%')
assertEq(lineno(), 0) assertEq(colno(), 3)
test.key('5', 'l')
assertEq(lineno(), 0) assertEq(colno(), 8)
local startcol = 8
local endcol = 24
-- Loop through the matching pairs
while startcol < (endcol-2) do
  test.key('%')
  assertEq(lineno(), 0) assertEq(colno(), endcol)
  test.key('%', 'l')
  assertEq(lineno(), 0) assertEq(colno(), startcol+1)
  startcol = startcol + 1
  endcol = endcol - 1
end
test.key('j')
  assertEq(lineno(), 1) assertEq(colno(), 0)

-- And the same on different lines
local startline = 1
local endline = 9
-- Loop through the matching pairs on different lines
while startline < (endline-2) do
  test.key('%')
  assertEq(lineno(), endline) assertEq(colno(), 0)
  test.key('%', 'j')
  assertEq(lineno(), startline+1) assertEq(colno(), 0)
  startline = startline + 1
  endline = endline - 1
end

-- Test C preprocessor matching

local matches = {
  -- sequences of line numbers (% should rotate in order)
  { 11, 14, 17, 18 },
  { 12, 13 },
  { 15, 16 },
}
local function goto_line(n)
  local ui_lineno = n + 1
  local keystring = tostring(ui_lineno) .. "G"
  for i=1, keystring:len() do
    test.key(keystring:sub(i, i))
  end
end

for _,v in ipairs(matches) do
    for i,lno in ipairs(v) do
        goto_line(lno)
        assertEq(lineno(), lno)
        test.key('%')
        if i < #v then
            assertEq(lineno(), v[i+1])
        else
            assertEq(lineno(), v[1])
        end
    end
end