-- Check parsing of ex ranges
local assertEq = test.assertEq
local log = test.log
local ts = test.tostring
local vi_mode_ex = require'vi_mode_ex'

test.open('1_100.txt')

local commands = {
  -- List of address string and expected result
  --       result: { { start, end }, nextpos } (nextpos is in the string)
  { 'xx yy zz', { nil, {'xx', 'yy', 'zz'} } },
  { '.s/asdf/ghjk/', { {7, 7}, {'s', 'asdf', 'ghjk', ''} } },
  { '.s/x\\/y/asdf/', { {7, 7}, {'s', 'x/y', 'asdf', ''} } },
  { '.s/xy/as\\/df/', { {7, 7}, {'s', 'xy', 'as/df', ''} } },
}

-- Start from line 7
buffer:goto_line(6)

for _, data in pairs(commands) do
    local addrstring = data[1]
    local cmd, addr = vi_mode_ex.parse_ex_cmd(addrstring)
    assertEq(cmd, data[2][2])
    assertEq(addr, data[2][1])
end