-- Copyright (C) 2014 Chris Emerson <github@mail.nosreme.org>
-- See LICENSE for details (MIT license).
local M = {}

local regex = require'regex'

-- Replace textadept's events.FIND handler with one implementing better regex.

function M.install()
    events.connect(events.FIND, M.find, 1)
end

-- Find expression forwards from the current point.
function M.find(regex, forward)
    local pat = vi_regex.compile(regex)
    
    -- Search a subset of the buffer, and adjust the match to set the
    -- start/end pointers correctly.
    local function search(startpos, endpos)
        local m = pat:match(buffer:text_range(startpos, endpos))
        if m then
            -- Adjust result to take account of startpos
            m._start = m._start + startpos - 1
            m._end = m._end + startpos
        end
        return m
    end
    
    -- As search(), but search backwards.
    -- This isn't as efficient, as it searches forward and waits for the
    -- last match.
    local function search_rev(startpos, endpos)
        local res = nil
        while true do
            local m = search(startpos, endpos)
            if m then
                -- a later match than we'd previously had
                res = m

                -- Start searching from this point (non-overlapping)
                startpos = m._end
            else
                -- no other matches - return the last we got.
                break
            end
        end
        return res
    end
    
    local m = nil
    if forward then
        local startpos = buffer.current_pos + 1
        local endpos = buffer.length
    
        m = search(startpos, endpos) or search(0, endpos)
    else
        local startpos = 0
        local endpos = buffer.current_pos
        
        m = search_rev(startpos, endpos) or search_rev(0, buffer.length)
    end
    
    if m then
        local s, e = m._start, m._end
        buffer:set_sel(e, s)
    else
        ui.statusbar_text = "Not found"
    end
    
    return false
end

return M
