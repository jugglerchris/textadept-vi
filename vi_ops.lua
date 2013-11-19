-- Functions implementing operators, ie commands to be followed by a motion.
local M = {}

-- Implements c{motion}
function M.change(start, end_, mtype)
  local linewise = mtype == 'linewise'
  buffer.begin_undo_action()
  vi_mode.vi_cut(start, end_, linewise)
  vi_mode.enter_insert_then_end_undo(vi_mode.post_insert(function()
    local start = buffer.current_pos
    move()
    local end_ = buffer.current_pos
    vi_mode.vi_cut(start, end_, linewise)
  end))
end

return M