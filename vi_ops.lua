-- Functions implementing operators, ie commands to be followed by a motion.
local M = {}

-- Implements c{motion}
function M.change(movement)
  local mtype = movement.movtype
  M.cut(movement)
  if mtype == 'linewise' then
      -- If linewise, should be editing in a new empty line
      if buffer.current_pos == 0 then
         -- start of buffer
         buffer.new_line()
         buffer.char_left()  -- position cursor at start of the inserted
                             -- line
      else
         buffer.char_left()
         buffer.new_line()
      end
  end
end

--- Delete a range from this buffer, and save in a register.
--  If the register is not specified, use the unnamed register ("").
function M.cut(movement, register)
    local linewise = movement.movtype == 'linewise'
    local start, end_ = movement.s, movement.e
    if not linewise then
        -- If start/end_ are on different lines and there would only be
        -- whitespace left after the delete, then change to linewise.
        local sline = buffer:line_from_position(start)
        local eline = buffer:line_from_position(end_)
        if sline ~= eline then
            local sline_start = buffer:position_from_line(sline)
            local prestart = buffer:get_line(sline):sub(1, start-sline_start)

            local eline_start = buffer:position_from_line(eline)
            local postend = buffer:get_line(eline):sub(end_-eline_start+1)

            if prestart:match('^%s*$') and postend:match('^%s*$') then
                -- Switch to linewise
                linewise = true
                start = sline_start
                end_ = eline_start + buffer:line_length(eline)
            end
        end
    end
    buffer:set_selection(start, end_)
    local text = buffer:get_sel_text()
    buffer:cut()
    state.registers[register or '"'] = {text=text, line=linewise}
end

--- yank a range from this buffer, and save in a register.
--  If the register is not specified, use the unnamed register ("").
function M.yank(movement, register)
    local linewise = movement.movtype == 'linewise'
    local orig_pos = buffer.current_pos
    local start, end_ = movement.s, movement.e
    buffer:set_sel(start, end_)
    local text = buffer:get_sel_text()
    buffer:clear_selections()
    if linewise then
        local raws, rawe = movement.raws, movement.rawe
        buffer:goto_pos(raws < rawe and raws or rawe)
    else
        buffer:goto_pos(start < end_ and start or end_)
    end
    state.registers[register or '"'] = {text=text, line=linewise}
end

function M.indent(movement)
    local start, end_ = movement.s, movement.e
    -- Scintilla decides between replacing the selection with a tab,
    -- or indenting the selection, based on whether it's more than
    -- one line or not.  Unfortunately that means that if there's no
    -- newline on the last line, and we try to indent the last line,
    -- the selection doesn't appear to be multiline as the end of the
    -- selection is still on the same line.
    local startline = buffer:line_from_position(start)
    local endline = buffer:line_from_position(end_)
    local curpos = buffer.current_pos
    local temp_eol = false
    if startline == endline and end_ == buffer.length then
        buffer:insert_text(buffer.length, '\n')
        assert(buffer.length == end_ + 1)
        end_ = end_ + 1
        temp_eol = true
    end
    buffer:set_sel(start, end_)
    buffer:tab()
    buffer:clear_selections()
    if temp_eol then
        -- Remove the dummy EOL we added.
        buffer:set_sel(buffer.length-1, buffer.length)
        assert(buffer:get_sel_text() == "\n")
        buffer:clear()
        buffer:clear_selections()
    end
    buffer:goto_pos(buffer.line_indent_position[buffer:line_from_position(start)])
end

function M.undent(movement)
    local start, end_ = movement.s, movement.e
    buffer:set_sel(start, end_)
    buffer:back_tab()
    buffer:clear_selections()
    buffer:goto_pos(buffer.line_indent_position[buffer:line_from_position(start)])
end

function M.revcase(movement)
    local start, end_ = movement.s, movement.e
    local pos = start
    buffer:begin_undo_action()
    while pos < end_ do
        buffer:set_sel(pos, pos+1)
        local c = buffer:get_sel_text()
        local newc = string.upper(c)
        if newc == c then newc = string.lower(c) end
        buffer:replace_sel(newc)
        buffer.current_pos = pos+1
        pos = pos + 1
    end
    buffer:end_undo_action()
end

function M.lowercase(movement)
    local start, end_ = movement.s, movement.e
    buffer:set_sel(start, end_)
    buffer:lower_case()
    buffer:clear_selections()
    buffer:goto_pos(start)
end
function M.uppercase(movement)
    local start, end_ = movement.s, movement.e
    buffer:set_sel(start, end_)
    buffer:upper_case()
    buffer:clear_selections()
    buffer:goto_pos(start)
end

function M.replace_char(sym, movement)
    local start, end_ = movement.s, movement.e
    local here = start
    buffer:begin_undo_action()
    while here < end_ do
       local nextpos = buffer:position_relative(here, 1)
       buffer:set_sel(here, nextpos)
       buffer:replace_sel(sym)
       -- Recalculate nextpos as the new character may
       -- not be the same length.
       nextpos = buffer:position_relative(here, 1)
       buffer.current_pos = nextpos

       here = nextpos
    end
    buffer:end_undo_action()
end

-- Auto indent
function M.reindent(movement)
    local start, end_ = movement.s, movement.e
    local line_start = buffer.line_from_position(start)
    local line_end = buffer.line_from_position(end_-1)
    local pat = vi_mode.lang.indents.xml.indent
    local dpat = vi_mode.lang.indents.xml.dedent

    local indent_inc = buffer.indent
    local next_indent = nil
    -- If this isn't the first line, then get the indent
    -- from the previous non-blank line
    local prev_lineno = line_start-1
    while prev_lineno >= 0 do
        local prev_line = buffer:get_line(prev_lineno)
        if not prev_line:match('^%s*$') then
            local prev_indent = buffer.line_indentation[prev_lineno]
            next_indent = prev_indent + indent_inc * pat:match(prev_line)
            -- disregard any dedent we would have applied to the previous line
            next_indent = next_indent - indent_inc * dpat:match(prev_line)

            -- found a non-blank line, so stop.
            break
        end
        prev_lineno = prev_lineno-1
        break
    end
    for lineno=line_start,line_end do
        local line = buffer:get_line(lineno)
        local indent_delta = pat:match(line)
        -- re-indent this line
        if next_indent then
            local this_indent = next_indent
            -- Special case - looking at this line may
            -- make us want to dedent (eg closing brace/tag)
            this_indent = this_indent + indent_inc * dpat:match(line)

            -- If a line is all blanks, remove any whitespace.
            buffer.line_indentation[lineno] = line:match('^%s*$') and 0 or this_indent
        else
            next_indent = 0
        end
        next_indent = next_indent + indent_inc * indent_delta
    end
end

local function wrap_lines(lines, width)
  local alltext = table.concat(lines, " ")
  local result = {}

  local linelen = 0 -- length of this line
  local line = {} -- parts of this line
  local sentence_end = false

  for word in string.gmatch(alltext, "[^%s]+") do
      local newlen = linelen + string.len(word) + 1
      if linelen > 0 and newlen > width then
          -- Doesn't fit, so start a new line
          table.insert(result, table.concat(line, " "))
          line = {}
          linelen = 0
          newlen = string.len(word)
      end

      -- double space after sentence endings, if not at end of line.
      if linelen > 0 and sentence_end then
          word = ' '..word
          newlen = newlen + 1
      end
      table.insert(line, word)
      sentence_end = (word:sub(-1) == '.')
      linelen = newlen
  end
  if linelen > 0 then
    table.insert(result, table.concat(line, " "))
  end
  return result
end

function M.wrap(movement)
    local width = 78 -- FIXME: configurable
    local line_start = buffer:line_from_position(movement.s)
    local line_end = buffer:line_from_position(movement.e)
    -- Linewise motions stop at the position at the start of the next line.
    if movement.movtype == 'linewise' and line_end >= 0 then
        line_end = line_end - 1
    end
    local pos_start = buffer:position_from_line(line_start)
    local pos_end = buffer.line_end_position[line_end]

    local prefix = nil
    local lines_to_wrap = {}

    while line_start <= (line_end+1) do
        local line, new_prefix
        if line_start <= line_end then
            line = buffer:get_line(line_start)
            new_prefix = string.match(line, "^[>| ]*")
        else
            -- A dummy end iteration to output the result
            line = "dummy line"
            new_prefix = "invalid prefix"
        end
        if prefix == nil then prefix = new_prefix end
        local is_blank = line:sub(prefix:len()):match("^%s*$")
        if new_prefix ~= prefix or is_blank then
            -- New prefix; Emit previous wrapped lines and
            -- start again
            local endpos = buffer.position_from_line(line_start)
            local new_lines = wrap_lines(lines_to_wrap, width-string.len(prefix))
            local new_parts = {}
            for _,l in ipairs(new_lines) do
                table.insert(new_parts,prefix)
                table.insert(new_parts,l)
                table.insert(new_parts,"\n")
            end
            buffer.set_selection(pos_start, endpos)
            local orig_end_line = buffer.line_from_position(endpos)
            local new_text = table.concat(new_parts)
            buffer.replace_sel(new_text)
            pos_start = buffer.selection_end
            local new_end_line = buffer.line_from_position(pos_start)
                                 buffer.clear_selections()

            -- Adjust line counts after wrapping text
            line_start = line_start + (new_end_line - orig_end_line)
            line_end= line_end + (new_end_line - orig_end_line)

            prefix = new_prefix
            lines_to_wrap = {}
            buffer.goto_pos(pos_start)
            buffer.line_up()
        end
        line_start = line_start + 1
        -- If we're on a blank, then skip to the next line
        if is_blank then
            pos_start = buffer:position_from_line(line_start)
        else
          -- Otherwise add the line and keep looking
          table.insert(lines_to_wrap,
                       string.sub(line, string.len(prefix)))
        end
    end
    buffer.goto_pos(buffer:position_from_line(line_end))
end

return M
