-- Support for visual mode.
local M = {}

local vi_motion = require('vi_motion')

local state  -- This will be vi_mode.state later (but import time is too early)

local function visual_update(s, e)
    s = s or state.visual_pos.s
    e = e or state.visual_pos.e

    state.visual_pos.s = s
    state.visual_pos.e = e

    buffer.set_selection(s, e)
end

M.VISUAL = 'visual'

local mode_visual = {
    name = M.VISUAL,

    bindings = {
        esc = function()
            enter_mode(mode_command)
        end,
    },

    init = function()
        state = vi_mode.state
        local pos = buffer.current_pos
        state.visual_pos.pos = pos
        state.visual_pos.s = pos
        state.visual_pos.e = pos+1
        if pos == buffer.length - 1 then
            state.visual_pos.s = pos-1
            state.visual_pos.e = pos
        end
        visual_update()
    end,
}

setmetatable(mode_visual.bindings, {
    __index = function(t,k)
        local m = vi_motion.motions[k]
        if type(m) == 'table' and m[1] then
            local f = vi_mode.motion2key(m)
            return function()
                buffer.current_pos = state.visual_pos.pos
                f()
                state.visual_pos.pos = buffer.current_pos
                state.visual_pos.e = buffer.current_pos
                visual_update()
            end
        elseif type(m) == 'table' then
            return vi_motion.wrap_table(m, vi_mode.motion2key)
        end
    end
    })

M.mode_visual = mode_visual

return M
