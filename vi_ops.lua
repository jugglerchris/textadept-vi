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
    local line_end = buffer.line_from_position(end_)
    local pat = vi_mode.lang.indents.xml.indent
    local dpat = vi_mode.lang.indents.xml.dedent

    local indent_inc = buffer.indent
    local next_indent = nil
    -- If this isn't the first line, then get the indent
    -- from the previous line
    if line_start > 1 then
        local prev_line = buffer:get_line(line_start-1)
        local prev_indent = prev_line:match(" *()")
        next_indent = prev_indent + pat:match(prev_line)
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

return M