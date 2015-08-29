local assertEq=test.assertEq
local unpack = unpack or table.unpack

test.open('wordsnl.txt')
local init_data = buffer:get_text()
local keys = {'j', 'l', 'v', 'l', 'l', 'l', '~'}

test.key(unpack(keys))
local fini_data = buffer:get_text()

assertEq(test.run_in_vim(init_data, keys), fini_data)

