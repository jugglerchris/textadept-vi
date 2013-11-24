-- Implementations of the motion functions.
local M = {}

local vi_ta_util = require 'vi_ta_util'
local line_length = vi_ta_util.line_length
local buf_state = vi_ta_util.buf_state

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

---  Move the cursor down one line.
-- 
function M.line_down()
    local bufstate = buf_state(buffer)
    
    local lineno = buffer.line_from_position(buffer.current_pos)
    local linestart = buffer.position_from_line(lineno)
    if lineno < buffer.line_count then
        local ln = lineno + 1
        local col = bufstate.col or (buffer.current_pos - linestart)
        bufstate.col = col  -- Try to stay in the same column
        if col >= line_length(ln) then
            col = line_length(ln) - 1
        end
        if col < 0 then col = 0 end
        buffer:goto_pos(buffer.position_from_line(ln) + col)
    end
end

---  Move the cursor up one line.
-- 
function M.line_up()
    local bufstate = buf_state(buffer)
    local lineno = buffer.line_from_position(buffer.current_pos)
    local linestart = buffer.position_from_line(lineno)
    if lineno >= 1 then
        local ln = lineno - 1
        local col = bufstate.col or buffer.current_pos - linestart
        bufstate.col = col
        if col >= line_length(ln) then
            col = line_length(ln) - 1
        end
        if col < 0 then col = 0 end
        buffer:goto_pos(buffer.position_from_line(ln) + col)
    end
end

-- Move to the start of the next word
function M.word_right()
    buffer.word_right()
    local lineno = buffer.line_from_position(buffer.current_pos)
    local col = buffer.current_pos - buffer.position_from_line(lineno)
    -- Textadept sticks at the end of the line.
    if col >= line_length(lineno) then
        if lineno == buffer.line_count-1 then
            buffer:char_left()
        else
            buffer:word_right()
        end
    end
end

-- Move to the start of the previous word
function M.word_left()
    buffer.word_left()
    local lineno = buffer.line_from_position(buffer.current_pos)
    local col = buffer.current_pos - buffer.position_from_line(lineno)
    -- Textadept sticks at the end of the line.
    if col >= line_length(lineno) then
        buffer:word_left()
    end
end

-- Move to the end of the next word
 function M.word_end()
     buffer.char_right()
     buffer.word_right_end() 
     local lineno = buffer:line_from_position(buffer.current_pos)
     local col = buffer.current_pos - buffer.position_from_line(lineno)
     if col == 0 then
         -- word_right_end sticks at start of
         -- line.
         buffer:word_right_end()
     end
     buffer.char_left()
end

-- Move to the end of the line
function M.line_end(rep)
    if rep and rep > 1 then
        for i=1,rep-1 do
            buffer:line_down()
        end
    end
    buffer:line_end()
    local line, pos = buffer.get_cur_line()
    if pos > 0 then buffer:char_left() end
end

-- Select motions (return start,end_)
function M.sel_line(numlines)
  if not numlines or numlines < 1 then numlines = 1 end
  local lineno = buffer:line_from_position(buffer.current_pos)
  return buffer:position_from_line(lineno), buffer.line_end_position[lineno + numlines - 1]
end

return M