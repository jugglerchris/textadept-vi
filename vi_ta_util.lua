-- Utilities for dealing with textadept objects.
local M = {}

local lpeg = require 'lpeg'

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

-- Return the "word" under the cursor,
-- where word characters can be
-- specified, eg to search for filenames.
--
-- Parameters:
--    pos:   the position in the current buffer.
--    chars: a string containing the characters to include.
--
-- Returns:
--    start, end, word: start and end positions, and the word found
--    or nothing.
function M.find_word_at(pos, chars)
    local chartab = {}
    for i=1,#chars do
        chartab[chars:byte(i,i)] = true
    end
    local startpos, endpos

    local p = pos

    while chartab[buffer.char_at[p]] do
        startpos = p
        p = p - 1
    end
    -- No characters of the right class
    if not startpos then return end

    p = pos
    while chartab[buffer.char_at[p]] do
        endpos = p
        p = p + 1
    end
    endpos = endpos + 1

    return startpos, endpos, buffer:text_range(startpos, endpos)
end

return M
