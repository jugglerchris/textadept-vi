local M = {}

local vi_regex = require'vi_regex'

-- Replace textadept's events.FIND handler with one implementing better regex.

function M.install()
    events.connect(events.FIND, M.find, 1)
end

-- Find expression forwards from the current point.
function M.find(regex, forward)
    local pat = vi_regex.compile(regex)
    
    local startpos = buffer.current_pos + 1
    local endpos = buffer.length
    
    local function search(startpos, endpos)
        local m = pat:match(buffer:text_range(startpos, endpos))
        if m then
            -- Adjust result to take account of startpos
            m._start = m._start + startpos - 1
            m._end = m._end + startpos
        end
        return m
    end
    
    local m = search(startpos, endpos) or search(0, endpos)
    
    if m then
        local s, e = m._start, m._end
        buffer:set_sel(e, s)
    else
        ui.print("Not found")
    end
    
    return false
end

return M
