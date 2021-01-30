-- Check parsing of ex ranges
local assertEq = test.assertEq
local log = test.log
local ts = test.tostring
local vi_mode_ex = require'textadept-vi.vi_mode_ex'

-- Have a file open
test.open('1_100.txt')

local ranges = {
  -- List of address string and expected result
  --       result: { { start, end }, nextpos } (nextpos is in the string)
  { '1,4xx', { { 1, 4 }, {'xx'} } },
  { '4,8xx', { { 4, 8 }, {'xx'} } },
  { '4+4,10xx', { { 8, 10}, {'xx'} } },
  { '.,.+4xx yy', { { 7, 11 }, {'xx', 'yy'} } },
  { '1,$blah', { { 1, 101 }, {'blah'}}},
  { '/10/,3xx', { { 10, 3 }, {'xx'}}},
  { '4,/10/xx', { { 4, 10 }, {'xx'}}},
  { '4,/33/xx', { { 4, 33 }, {'xx'}}},
  { ',$xx',     { { 7, 101 }, {'xx'}}},
  { ',17xx',    { { 7, 17 }, {'xx'}}},
  { '.xx',      { { 7, 7 }, {'xx'}}},
  { '55xx',     { { 55, 55, }, {'xx'}}},
  { '/66/xx',   { { 66, 66, }, {'xx'}}},
}

-- Start from line 7
buffer:goto_line(7)

for _, data in pairs(ranges) do
    local addrstring = data[1]
    local cmd, addr = vi_mode_ex.parse_ex_cmd(addrstring)
    assertEq(cmd, data[2][2])
    assertEq(addr, data[2][1])
end
