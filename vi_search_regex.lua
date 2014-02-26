local M = {}

local vi_regex = require'vi_regex'

M.search_hl_indic = _SCINTILLA.next_indic_number()

-- Set up our indicator style.
local function set_colours()
    buffer.indic_fore[M.search_hl_indic] = 0x0000FF
    buffer.indic_style[M.search_hl_indic] = _SCINTILLA.constants.INDIC_ROUNDBOX
    buffer.indic_alpha[M.search_hl_indic] = 100
    -- Find all occurrences to highlight.
    buffer.indicator_current = M.search_hl_indic
    buffer:indicator_clear_range(0, buffer.length)
end

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
        set_colours()
        local s, e = m._start, m._end
        --ui.print(s, e)
        buffer:indicator_fill_range(s, e-s)
        buffer:goto_pos(s)
    else
        ui.print("Not found")
    end
    
    return false
end

return M
