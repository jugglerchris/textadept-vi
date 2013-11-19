-- Support for motion key sequences
local M = {}

-- Implementations of the movements
local vi_motions = require 'vi_motions'

-- Wrap a possibly nested table, returning a proxy which modifies any value
-- which isn't a nested table.  A nested table is considered one with no
-- integer keys (so #t == 0, or t[1] == nil).  This allows storing values
-- such as { 1,2,3 }.
-- Parameters:
--   tab: the table to wrap
--   f:   function to modify the value from tab.
local function wrap_table(tab, f)
    return setmetatable({}, {
        __index = function(t, k)
            local m = tab[k]
            
            if m == nil then
                return nil
            elseif type(m) == 'table' and m[1] == nil then
                -- TODO: will this work and save a table creation?:
                --   tab = m
                --   return t
                return wrap_table(m, f)
            else
                -- Return a (possibly modified) value.
                return f(m)
            end
        end,
    })
end

-- Valid movement types
MOV_LINE = 'linewise'
MOV_INC = 'inclusive'
MOV_EXC = 'exclusive'

-- Table of basic motion commands.  Each is a list:
-- { type, f }
-- where f is a function to do the movement and type is one of
-- MOV_LINE, MOV_EXC, MOV_INC for linewise, exclusive or inclusive.
local motions = {
  h = { MOV_EXC, vi_motions.char_left },
}
M.motions = motions

-- Table of select (range) motions, used after some commands (eg d{motion}).
-- Each entry is a function returning (start, end) positions.
local sel_motions = setmetatable({
  a = {
    w = function() return 'word' end,
    W = function() return 'WORD' end,
  },
}, {
  __index=wrap_table(motions, function(movedesc)
                                local movtype, mov_f = table.unpack(movedesc)
                                -- Convert simple movement into a range
                                return function()
                                  local pos1 = buffer.current_pos
                                  mov_f()
                                  local pos2 = buffer.current_pos
                                  if pos1 > pos2 then
                                    pos1, pos2 = pos2, pos1
                                  end
                                  return pos1, pos2
                                end
                              end)
})
  
M.sel_motions = sel_motions

-- Return a proxy for a key binding table which calls handler when eventually
-- getting to a complete motion.
local function wrap_bindings(tab, handler)
    return setmetatable({}, {
        __index = function(t, k)
            local m = tab[k]
            
            if type(m) == 'function' then
                return function() handler(m) end
            end
            if type(m) == 'table' then
                return wrap_bindings(m, handler)
            end
            
            -- implicitly return nil
        end,
    })
end

-- Return an entry suitable for the keys table which implements the vi motion
-- commands.
-- actions: a table of overrides (subcommands which aren't motions), eg for
-- a 'd' handler, this would include 'd' (for 'dd', which deletes the current
-- line).
-- handler: When a motion command is finished, this will be called with the
-- start and end of the range selected.
function M.bind_motions(actions, handler)
    local keyseq = {}
    setmetatable(actions, { __index=sel_motions })
    return wrap_table(actions, function(mov) 
        return function()
            local start, end_ = mov()
            handler(start, end_)
        end
    end)
end

return M