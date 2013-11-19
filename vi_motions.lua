-- Implementations of the motion functions.
local M = {}

function M.char_left()
  local line, pos = buffer.get_cur_line()
  if pos > 0 then buffer.char_left() end
end

return M