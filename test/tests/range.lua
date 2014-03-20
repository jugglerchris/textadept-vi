-- Check parsing of ex ranges
local assertEq = test.assertEq
local log = test.log
local ts = test.tostring
local vi_mode_ex = require'vi_mode_ex'

-- Have a file open
test.open('1_100.txt')

local ranges = {
  -- List of address string and expected result
  --       result: { { start, end }, nextpos } (nextpos is in the string)
  { '1,4xx', { { 1, 4 }, {'xx'} } },
  { '4,8xx', { { 4, 8 }, {'xx'} } },
  { '4+4,10xx', { { 8, 10} , {'xx'} } },
  { '.,.+4xx yy', { { 1, 5}, {'xx', 'yy'} } },
  { '1,$blah', { { 1, 101 }, {'blah'}}},
}

for _, data in pairs(ranges) do
    local addrstring = data[1]
    local cmd, addr = vi_mode_ex.parse_ex_cmd(addrstring)
    assertEq(addr, data[2][1])
    assertEq(cmd, data[2][2])
end