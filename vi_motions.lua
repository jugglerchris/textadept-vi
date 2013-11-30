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

function M.line_start(rep)
    buffer:home()
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

function M.goto_line(lineno)
    if lineno > 0 then
        -- Textadept does zero-based line numbers.
        buffer.goto_line(lineno-1)
    else
        -- With no arg, go to last line.
        buffer.document_end()
        buffer.home()
    end
end

function M.match_brace()
   local orig_pos = buffer.current_pos
   -- Simple case: match on current character
   local pos = buffer:brace_match(buffer.current_pos)
   if pos >= 0 then
       buffer:goto_pos(pos)
       return
   end
   
   -- Get the current line and position, as we'll need it for
   -- the next tests.
   local line, idx = buffer:get_cur_line()
   
   -- Are we on a C conditional?
   do
       -- TODO: cache the pattern
       local P = lpeg.P
       local S = lpeg.S
       local C = lpeg.C
       local R = lpeg.R
       
       local ws = S' \t'
      
       local cpppat = (ws ^ 0) * P"#" * (ws ^ 0) * 
                  (C(P"if" + P"elif" + P"else"+ P"ifdef" + P"endif") + -R("az", "AZ", "09"))
       
       local cppcond = cpppat:match(line)
       
       -- How each operation adjusts the nesting level
       local nestop = {
           ['if'] = 1,
           ['ifdef'] = 1,
           ['else'] = 0,
           ['elif'] = 0,
           ['endif'] = -1,
       }
       
       local lineno = buffer.line_from_position(buffer.current_pos)
       local level = 0
       if cppcond == 'endif' then
           -- Search backwards for the original if/ifdef
           while lineno > 0 do
               lineno = lineno - 1
               line = buffer:get_line(lineno)
               cppcond = cpppat:match(line)
               if nestop[cppcond] == 1 and level == 0 then
                   -- found!
                   buffer.goto_line(lineno)
                   return
               elseif cppcond then
                   level = level + nestop[cppcond]
               end
           end
       elseif cppcond then
           -- Search forwards for matching level
           local lines = buffer.line_count
           while lineno < lines do
               lineno = lineno + 1
               line = buffer:get_line(lineno)
               cppcond = cpppat:match(line)
               if cppcond and level == 0 and nestop[cppcond] < 1 then
                   -- found!
                   buffer.goto_line(lineno)
                   return
               elseif cppcond then
                   level = level + nestop[cppcond]
               end
           end
       end
   end
   
   -- Try searching forwards on the line
   local bracketpat =  "[%(%)<>%[%]{}]"
   
   local newidx, _, c = line:find(bracketpat, idx+1)
   if newidx then
       pos = buffer:brace_match(orig_pos + newidx - idx - 1)
       if pos >= 0 then
           buffer:goto_pos(pos)
       end
       return
   end
     
end

return M