-- Utilities for dealing with textadept objects.
local M = {}

-- Return the number of characters on this line, without
-- line endings.
function M.line_length(lineno)
	return buffer.line_end_position[lineno] - buffer.position_from_line(lineno)
end

return M