-- Support for visual mode.
local M = {}

local vi_motion = require('vi_motion')
local vi_ops = require('vi_ops')

local state  -- This will be vi_mode.state later (but import time is too early)

local function visual_update(pos)
    local s = state.visual.s
    local e = pos or state.visual.pos

    state.visual.pos = e

    -- Adjust one end to make it inclusive
--    if e < s then
--        s = s+1
--    elseif s < e then
--        e = e+1
--    end
--    e = e + 1
    cme_log(('Adjusting selection to (%d, %d)'):format(s, e))
    buffer.set_selection(s, e)
--    buffer.set_sel(s, e)
end

M.VISUAL = 'visual'

local function exit_visual()
    enter_mode(mode_command)
end

local mode_visual = {
    name = M.VISUAL,

    bindings = {
        esc = function()
            exit_visual()
        end,
        v = function()
            exit_visual()
        end,
        x = function()
            vi_ops.cut(state.visual.s, state.visual.pos, state.visual.movtype)
            exit_visual()
        end,
    },

    init = function()
        state = vi_mode.state
        local pos = buffer.current_pos
        state.visual.pos = pos  -- current location
        state.visual.s = pos    -- other end.
        state.visual.movtype = MOV_INC  -- Possible linewise support later
        visual_update()
    end,
}

setmetatable(mode_visual.bindings, {
    __index = function(t,k)
        local m = vi_motion.motions[k]
        if type(m) == 'table' and m[1] then
            local f = vi_mode.motion2key(m)
            return function()
--                buffer.clear_selections()
                cme_log(('Pre anything, pos=%d, key=%q, sel=(%d, %d)'):format(state.visual.pos, k,
                    buffer.selection_start, buffer.selection_end))
                buffer.current_pos = state.visual.pos
                cme_log(('Pre move, pos=%d (real %d)'):format(state.visual.pos, buffer.current_pos))
                f()
                cme_log(('After move, pos=%d'):format(buffer.current_pos))
                visual_update(buffer.current_pos)
            end
        elseif type(m) == 'table' then
            return vi_motion.wrap_table(m, vi_mode.motion2key)
        end
    end
    })

M.mode_visual = mode_visual

return M
