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
-- { type, f, count }
-- where f is a function to do the movement, type is one of
-- MOV_LINE, MOV_EXC, MOV_INC for linewise, exclusive or inclusive,
-- and count is the prefix count.  This may be modified when wrapped.
local motions = {
  h = { MOV_EXC, vi_motions.char_left, 1 },
  l = { MOV_EXC, vi_motions.char_right, 1 },
  j = { MOV_LINE, vi_motions.line_down, 1 },
  k = { MOV_LINE, vi_motions.line_up, 1 },
}
local MOTION_ZERO = { MOV_EXC, vi_motions.line_start, 1 }
local digits = {}
for i=0,9 do
    digits[i..''] = true
end
local PREFIX_COUNT = {} -- unique table key
local function index_digits(t, k)
    -- Intercept numbers to return an wrapped version.
    if digits[k] then
        local precount = t[PREFIX_COUNT]
        if precount ~= nil and k == '0' then
            return MOTION_ZERO -- special case - 0 is a motion by itself.
        end
        
        -- Rely on the master table never having PREFIX_COUNT.
        if precount == nil then
            -- If this is the first digit, return a wrapped table
            local newtab = setmetatable({}, {
                __index=function(t, k)
                    local res = motions[k]
                    if type(res)=='table' and res[1] then
                      -- This is a motion, so apply the multiple
                      res = { res[1], res[2], t[PREFIX_COUNT] }
                    end
                    return res or index_digits(t, k)
                end })
            t = newtab
            precount = 0
        end
            
        -- Update the count in the (possibly new) wrapper table
        precount = (precount * 10) + (k+0)
        t[PREFIX_COUNT] = precount
        
        -- Return the wrapper
        return t
    else
        -- not found
        return nil
    end
end

setmetatable(motions, {
  __index = index_digits,
})
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
                                local movtype, mov_f, rep = table.unpack(movedesc)
                                -- Convert simple movement into a range
                                return { movtype, function(rep)
                                  local pos1 = buffer.current_pos
                                  for i=1,rep do
                                    mov_f()
                                  end
                                  local pos2 = buffer.current_pos
                                  if pos1 > pos2 then
                                    pos1, pos2 = pos2, pos1
                                  end
                                  return pos1, pos2
                                end, rep }
                              end)
})
  
M.sel_motions = sel_motions

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
    return wrap_table(actions, function(movdesc) 
        return function()
            local movtype, movf, rep = table.unpack(movdesc)
            local start, end_ = movf(rep)
            handler(start, end_, movtype)
        end
    end)
end

return M