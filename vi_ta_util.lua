-- Utilities for dealing with textadept objects.
local M = {}

-- Return the number of characters on this line, without
-- line endings.
function M.line_length(lineno)
	return buffer.line_end_position[lineno] - buffer.position_from_line(lineno)
end

--- Return the buffer-specific vi state.
function M.buf_state(buf)
    if not buf._vi then
        buf._vi = {}
    end
    return buf._vi
end

return M