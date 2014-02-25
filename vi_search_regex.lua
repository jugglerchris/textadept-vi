local M = {}

local vi_regex = require'vi_regex'

-- Replace textadept's events.FIND handler with one implementing better regex.

function M.install()
    events.connect(events.FIND, M.find, 1)
end

M.search_hl_indic = _SCINTILLA.next_indic_number()

local function set_colours()
    buffer.indic_fore[M.search_hl_indic] = 0x00FFFF
    buffer.indic_style[M.search_hl_indic] = _SCINTILLA.constants.INDIC_ROUNDBOX
    buffer.indic_alpha[M.search_hl_indic] = 100
    -- Find all occurrences to highlight.
    buffer.indicator_current = M.search_hl_indic
    buffer:indicator_clear_range(0, buffer.length)
end

-- Find expression forwards from the current point.
function M.find(regex, forward)
    local pat = vi_regex.compile(regex)
    
    local startpos = buffer.current_pos + 1
    local endpos = buffer.length
    
    local text = buffer:text_range(startpos, endpos)
    
    local m = pat:match(text)
    
    if m and m._start and m._end then
        local s, e = m._start, m._end
        s = s + startpos - 1
        e = e + startpos
        --ui.print(s, e)
        set_colours()
        buffer:indicator_fill_range(s, e-s)
        buffer:goto_pos(s)
    else
        ui.print("Not found")
    end
    
    return false
end

return M
