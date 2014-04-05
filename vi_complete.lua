-- Implement word completion (with ctrl-p/ctrl-n) in insert mode.
local M = {}

local function next_backwards()
    local pos = M.state.pos
    if pos <= 1 then
        pos = #M.state.words
    else
        pos = pos - 1
    end
    M.state.pos = pos
    buffer:replace_sel(M.state.words[pos])
end

local function next_forwards()
    local pos = M.state.pos
    if pos >= #M.state.words then
        pos = 1
    else
        pos = pos + 1
    end
    M.state.pos = pos
    buffer:replace_sel(M.state.words[pos])
end

local function exit_complete()
    keys.MODE = vi_mode.INSERT
end

-- Wrap the insert-mode keys for the complete mode.
-- Ctrl-P/Ctrl-N will be overridden, and most keys will
-- exit this mode.
function M.get_keys(insert_keys)
    return setmetatable({
      cp = next_backwards,
      cn = next_forwards,
      esc = exit_complete,
    }, {
      __index = function(t,k)
                   local f = insert_keys[k]
                   if f then
                       exit_complete()
                       return f()
                   end
                end,
    })
end

M.wordchars = 'a-zA-Z0-9_'

local function get_words(forwards, here, prefix)
    local words = {}  -- ordered list of words
    
    local wordstart = here - #prefix
    
    search = buffer.search_next
    
    -- Avoid finding the current word
    buffer.current_pos = here+1
    buffer.search_anchor()
    
    local endpos = here
    
    local pat = '\\<'..prefix..'['..M.wordchars..']*\\>'
    
cme_log('Searching for: <<'..pat..'>>, wordstart='..wordstart..', cur='..endpos)
    local wrapped = false
    while true do
        nextpos = search(buffer, buffer.FIND_REGEXP + buffer.FIND_MATCHCASE, pat) 
        cme_log('Anextpos='..nextpos)
        if nextpos < 0 then
            if wrapped then break end
            
            -- Start from the end
            wrapped = true
            buffer.current_pos = 0
            cme_log("Wrapping to "..buffer.current_pos)
            buffer:search_anchor()
            --buffer.anchor = forwards and 0 or buffer.length
        elseif wrapped and nextpos >= wordstart then
            break
        else
          cme_log('nextpos='..nextpos)
          if nextpos == wordstart or nextpos < 0 then break end
          local word = buffer:get_sel_text()
          words[#words+1] = word
          
          buffer.current_pos = nextpos+1
          buffer:search_anchor()
        end
    end
    -- Remove duplicates in the appropriate direction
    local result = {}
    local seen = {}
    
    local s, e, step = 1, #words, 1
    if not forwards then
        -- Start from the end
        s, e = e, s
        step = -1
    end
    for i=s,e,step do
        local w = words[i]
        if not seen[w] then
            seen[w] = true
            result[#result+1] = w
        end
    end
    if not forwards then
        -- Need to reverse the order
        local newwords = {}
        for i=#result,1,-1 do
            newwords[#newwords+1] = result[i]
        end
        result = newwords
    end
    return result
end

-- Return position of first character, and the prefix string.
local function find_prefix()
    local curpos = buffer.current_pos
    local pos = buffer:word_start_position(curpos-1, true)
    
    return pos, buffer:text_range(pos, curpos)
end

-- Set up the completion state.
local function enter_complete(forwards)
    keys.MODE = vi_mode.INSERT_CNP
    local here = buffer.current_pos
    
    local wordstart, prefix = find_prefix()
    
    -- Set up state
    M.state = {
        words = get_words(forwards, here, prefix),
        pos = 0,  -- current entry
        current_pos = here,
        wordstart = wordstart,
        prefix = prefix
    }
    cme_log('Words: ' .. table.concat(M.state.words, '/'))
    -- And select the current word
    buffer:set_selection(here, wordstart)
end

-- Enter completion mode, backwards
function M.complete_backwards()
    enter_complete(false)
    next_backwards()
end

-- Enter completion mode, forwards
function M.complete_forwards()
    enter_complete(true)
    next_forwards()
end

-- Make functions visible for testing.
M._test = {
    find_prefix = find_prefix,
    get_words = get_words,
}

return M