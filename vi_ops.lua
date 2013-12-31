-- Functions implementing operators, ie commands to be followed by a motion.
local M = {}

-- Implements c{motion}
function M.change(start, end_, mtype)
  M.cut(start, end_, mtype)
end

--- Delete a range from this buffer, and save in a register.
--  If the register is not specified, use the unnamed register ("").
function M.cut(start, end_, mtype, register)
    local linewise = mtype == 'linewise'
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
    buffer:set_sel(start, end_)
    local text = buffer.get_sel_text()
    buffer.cut()
    state.registers[register or '"'] = {text=text, line=linewise}
end

function M.indent(start, end_, mtype)
    buffer:set_sel(start, end_)
    buffer:tab()
    buffer:clear_selections()
    buffer:goto_pos(buffer.line_indent_position[buffer:line_from_position(start)])
end

function M.undent(start, end_, mtype)
    buffer:set_sel(start, end_)
    buffer:back_tab()
    buffer:clear_selections()
    buffer:goto_pos(buffer.line_indent_position[buffer:line_from_position(start)])
end

-- Auto indent
function M.reindent(start, end_, mtype)
    local line_start = buffer.line_from_position(start)
    local line_end = buffer.line_from_position(end_-1)
    local pat = vi_mode.lang.indents.xml.indent
    local dpat = vi_mode.lang.indents.xml.dedent

    local indent_inc = buffer.indent
    local next_indent = nil
    -- If this isn't the first line, then get the indent
    -- from the previous line
    if line_start > 0 then
        local prev_line = buffer:get_line(line_start-1)
        local prev_indent = prev_line:match(" *()") - 1
        next_indent = prev_indent + indent_inc * pat:match(prev_line)
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
            line = line:gsub("^%s*", (" "):rep(this_indent))
            buffer:set_selection(buffer:position_from_line(lineno+1),
                                 buffer:position_from_line(lineno))
            buffer:replace_sel(line)
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

function M.wrap(start, end_)
    local width = 78 -- FIXME: configurable
    local line_start = buffer.line_from_position(start)
    local line_end = buffer.line_from_position(end_)
    local pos_start = buffer.position_from_line(line_start)
    local pos_end = buffer.position_from_line(line_end) +
                    buffer.line_length(line_end)

    local prefix = nil
    local lines_to_wrap = {}

    while line_start <= (line_end+1) do
        local line, new_prefix
        if line_start <= line_end then
            line = buffer.get_line(line_start)
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
    buffer.goto_pos(start)
end

return M