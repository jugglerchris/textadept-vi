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
    if s < e then
        e = e+1
    end
    buffer.set_selection(s, e)
end

M.VISUAL = 'visual'

local function exit_visual()
    enter_mode(mode_command)
end

local function visual_range()
    local s, e = state.visual.s, state.visual.pos
    if s>e then
        s, e = e, s
    end
    return s, e+1
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
            local s, e = visual_range()
            vi_ops.cut(s, e, state.visual.movtype)
            exit_visual()
        end,
        ['~'] = function()
            local s, e = visual_range()
            vi_ops.revcase(s, e, state.visual.movtype)
            exit_visual()
        end,
        --[[ Vim operators not yet implemented here:
        ~, d, c, y, <, >, !, =, gq
        other commands:
        :, r, s, C, S, R, D, X, Y, p, J, U, u, ^], I, A
        ]]
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
--                buffer.current_pos = state.visual.pos
                buffer.goto_pos(state.visual.pos)
                f()
                visual_update(buffer.current_pos)
            end
        elseif type(m) == 'table' then
            return vi_motion.wrap_table(m, vi_mode.motion2key)
        end
    end
    })

M.mode_visual = mode_visual

return M
