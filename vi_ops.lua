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

return M