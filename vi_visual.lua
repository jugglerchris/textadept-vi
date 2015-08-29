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

-- Take an operator function (which takes startpos, endpos, movtype)
-- and return a key sym for visual mode.
local function wrap_op(opfunc)
    return function()
            local s, e = visual_range()
            opfunc(s, e, state.visual.movtype)
            exit_visual()
        end
end
local function wrap_op_linewise(opfunc)
    return function()
            local s, e = visual_range()
            opfunc(s, e, 'linewise')
            exit_visual()
        end
end

local handle_v_r = setmetatable({}, {
    __index = function(t, sym)
                 if string.match(sym, "^.$") then
                   return wrap_op(function(s, e, t) vi_ops.replace_char(sym, s, e, t) end)
                 end
             end,
})


local mode_visual = {
    name = M.VISUAL,

    bindings = {
        esc = function()
            exit_visual()
        end,
        v = function()
            exit_visual()
        end,
        x = wrap_op(vi_ops.cut),
        d = wrap_op(vi_ops.cut),
        ['~'] = wrap_op(vi_ops.revcase),
        u = wrap_op(vi_ops.lowercase),
        U = wrap_op(vi_ops.uppercase),
        y = wrap_op(vi_ops.yank),
        r = handle_v_r,
        g = {
            q = wrap_op(vi_ops.wrap),
        },
        --[[ Vim operators not yet implemented here:
        c, <, >, !, =
        other commands:
        :, s, C, S, R, D, X, Y, p, J, ^], I, A
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
local function motion2visualkey(m)
    return function()
        local f = vi_mode.motion2key(m)
        buffer.goto_pos(state.visual.pos)
        f()
        visual_update(buffer.current_pos)
    end
end

setmetatable(mode_visual.bindings, {
    __index = function(t,k)
        local m = vi_motion.motions[k]
        if type(m) == 'table' and m[1] then
            return motion2visualkey(m)
        elseif type(m) == 'table' then
            return vi_motion.wrap_table(m, motion2visualkey)
        end
    end
    })

local function set_default_visual_key(k)
    if mode_visual.bindings[k] == nil then
        mode_visual.bindings[k] = function()
            vi_mode.err("Unbound visual key: <" .. tostring(k) .. ">")
        end
    end
end

for i = 0,25 do
    k = string.char(i + string.byte("a"))
    set_default_visual_key(k)
    set_default_visual_key(string.upper(k))
end

M.mode_visual = mode_visual

return M
