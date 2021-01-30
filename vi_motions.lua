local M = {}

local vi_ta_util = require 'textadept-vi.vi_ta_util'
local line_length = vi_ta_util.line_length
local buf_state = vi_ta_util.buf_state

-- Normal motions
function M.char_left()
  local line, pos = buffer.get_cur_line()
  if pos > 1 then buffer.char_left() end
end

function M.char_right()
    local line, pos = buffer.get_cur_line()
    local docpos = buffer.current_pos
    -- Don't include line ending characters, so we can't use buffer.line_length().
    local lineno = buffer:line_from_position(docpos)
    local length = line_length(lineno)
    if pos < length then
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

        -- Find a visible line (skip over folds)
        while not buffer.line_visible[ln] do
            ln = ln + 1
            if ln >= buffer.line_count then
                return
            end
        end
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
        -- Find a visible line (skip over folds)
        while not buffer.line_visible[ln] do
            ln = ln - 1
            if ln < 0 then
                return
            end
        end
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
        if lineno == buffer.line_count then
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

-- Go to column 0
function M.line_start(rep)
    buffer:home()
end

-- Go to first non-blank on line, or if there to first column.
function M.line_beg(rep)
    buffer.home()    -- Go to beginning of line
    buffer.vc_home()  -- swaps between beginning/first visible
end

-- go (rep-1) visible lines down (ie. jump over folds), then go
-- to the first non-blank character of the current line
function M.line_down_then_line_beg(rep)
    for _=2,rep do M.line_down() end -- go rep-1 lines down
    M.line_beg()
end

-- Move paragraphs at a time
local function paragraph_move(forward, rep)
    local step = forward and 1 or -1
    local endAt = forward and buffer.line_count or 0

    for i=1,rep do
        -- Go until blank line on an open fold
        for lineno=buffer:line_from_position(buffer.current_pos)+step,endAt,step do
            if lineno == endAt or (buffer.line_visible[lineno] and
                                   line_length(lineno) == 0) then
                buffer:goto_line(lineno)
                break
            end
        end
    end
end

function M.paragraph_backward(rep)
    paragraph_move(false, rep)
end
function M.paragraph_forward(rep)
    paragraph_move(true, rep)
end

-- Move to the end of the line
function M.line_end(rep)
    if rep and rep > 1 then
        for i=1,rep-1 do
            buffer:line_down()
        end
    end
    buffer:line_end()
    local line, pos = buffer:get_cur_line()
    if pos > 1 then buffer:char_left() end
end

-- Select motions (return start,end_)
function M.sel_line(numlines)
  if not numlines or numlines < 1 then numlines = 1 end
  local lineno = buffer:line_from_position(buffer.current_pos)
  return buffer.current_pos, buffer.line_end_position[lineno + numlines - 1]
end

-- Helpers for classifying characters for words:
-- A word is a sequence of (_,digits,letters) or (other non-blanks).
local function w_isblank(c)
  return c:match("%s")
end
local function w_isword(c)
  return c:match("[%a%d_]")
end
local function w_isother(c)
  return c:match("[^%s%a%d_]")
end

function M.sel_word(numwords)
  if not numwords or numwords < 1 then numwords = 1 end

  local buflen = buffer.length
  local pos = buffer.current_pos

  -- Simple case: off the end of the buffer.
  if pos > buflen then
      return buflen, buflen
  end

  -- Now find the current character.
  local nextpos = buffer:position_after(pos)
  local c = buffer:text_range(pos, nextpos)

  if c:match("%s") then
    -- If on whitespace, behave just like 'w'.
    for i=1,numwords do
      M.word_right()
      return pos, buffer.current_pos
    end
  else
    -- Otherwise, behave as "change word".
    local p = pos
    for i=1,numwords do
        -- Skip over whitespace
        while p <= buflen and w_isblank(c) do
          p = nextpos
          nextpos = buffer:position_after(nextpos)
          c = buffer:text_range(p, nextpos)
        end
        -- And now find the end of the word or nonblank-sequence
        if p <= buflen and w_isword(c) then
          while p <= buflen and w_isword(c) do
            p = nextpos
            nextpos = buffer:position_after(nextpos)
            c = buffer:text_range(p, nextpos)
          end
        else
          while p <= buflen and w_isother(c) do
            p = nextpos
            nextpos = buffer:position_after(nextpos)
            c = buffer:text_range(p, nextpos)
          end
        end
    end
    return pos, p
  end
end

function M.goto_line(lineno)
    if lineno > 0 then
        -- Textadept does zero-based line numbers.
        buffer:goto_line(lineno)
    else
        -- With no arg, go to last line.
        buffer:document_end()
        buffer:home()
    end
end

-- Same a goto_line but with a different default.
function M.goto_line_0(lineno)
    if lineno > 0 then
        -- Textadept does zero-based line numbers.
        buffer:goto_line(lineno)
    else
        -- With no arg, or 0, go to last line.
        buffer:goto_line(1)
        buffer:home()
    end
end

function M.match_brace()
   local orig_pos = buffer.current_pos
   -- Simple case: match on current character
   local pos = buffer:brace_match(buffer.current_pos, 0)
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
       pos = buffer:brace_match(orig_pos + newidx - idx - 1, 0)
       if pos >= 0 then
           buffer:goto_pos(pos)
       end
       return
   end
end

--- Redo the previous search
function M.search_next()
    vi_mode.search_mode.restart()
end

-- Redo the previous search in the opposite direction.
function M.search_prev()
    vi_mode.search_mode.restart_rev()
end

--- Search forward for the word under the cursor
function M.search_word_next()
    vi_mode.search_mode.search_word()
end

--- Search backwards for the word under the cursor
function M.search_word_prev()
    vi_mode.search_mode.search_word_rev()
end

--- Begin search mode (entering a pattern).
--  cb will be called later with or a movement description.
function M.search_fwd(cb)
    vi_mode.search_mode.start(function(movf)
        cb({ 'exclusive', movf, 1 })
    end)
end

--- Begin search mode backwards (entering a pattern).
--  cb will be called later with or a movement description.
function M.search_back(cb)
    vi_mode.search_mode.start_rev(function(movf)
        cb({ 'exclusive', movf, 1 })
    end)
end

-- Return the position (if any) of the next occurance of character c
-- on the current line.
function M.next_char_of(c)
    local orig_pos = buffer.current_pos
    local lineno = buffer:line_from_position(buffer.current_pos)
    buffer.target_start = buffer.current_pos + 1
    buffer.target_end = buffer.line_end_position[lineno]

    local orig_flags = buffer.search_flags
    buffer.search_flags = buffer.FIND_MATCHCASE
    local pos = buffer:search_in_target(c)
    buffer.search_flags = orig_flags

    if pos >= 0 then
        buffer:goto_pos(pos)
    else
        buffer:goto_pos(orig_pos)
    end
end

return M
