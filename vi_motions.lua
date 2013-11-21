-- Implementations of the motion functions.
local M = {}

local vi_ta_util = require 'vi_ta_util'
local line_length = vi_ta_util.line_length

-- Normal motions
function M.char_left()
  local line, pos = buffer.get_cur_line()
  if pos > 0 then buffer.char_left() end
end

function M.char_right()
    local line, pos = buffer.get_cur_line()
	local docpos = buffer.current_pos
    -- Don't include line ending characters, so we can't use buffer.line_length().
    local lineno = buffer:line_from_position(docpos)
	local length = line_length(lineno)
	if pos < (length - 1) then
	    buffer.char_right()
	end
end

-- Select motions (return start,end_)
function M.sel_line()
  local lineno = buffer:line_from_position(buffer.current_pos)
  return buffer:position_from_line(lineno), buffer.line_end_position[lineno]
end

return M