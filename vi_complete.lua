-- Implement word completion (with ctrl-p/ctrl-n) in insert mode.
local M = {}
local vi_tags = require('vi_tags')

-- update the display from the current word after moving.
local function update_word()
    local pos = M.state.pos
    local listpos = M.state.listpos
    local sel_start = M.state.wordstart
    local sel_end = M.state.current_end
    local word = (listpos == 0) and M.state.prefix or M.state.words[listpos][pos]
    buffer:set_selection(sel_end, sel_start)
    buffer:replace_sel(word)
    M.state.current_end = buffer.selection_end
    return true
end

-- Advance to the next word list
local function next_list()
    local state = M.state
    local listpos = state.listpos
    local pos = state.pos
    while true do
        listpos = listpos + 1
        pos = 1
        if listpos > #M.search_types then
            -- list 0 always has the initial prefix.
            listpos = 0
            break
        end
        if state.words[listpos] == nil then
            state.words[listpos] = M.search_types[listpos].finder(state.forwards, state.here, state.prefix)
        end
        if state.words[listpos] and #state.words[listpos] > 0 then
            -- If no words available, try the next list.
            break
        end
    end
    state.pos = pos
    state.listpos = listpos
end

-- Go to the previous word list
local function prev_list()
    local state = M.state
    local pos = state.pos
    local listpos = state.listpos
    while true do
        listpos = listpos - 1
        if listpos < 0 then
            listpos = #M.search_types
        end
        if listpos == 0 then
            -- List 0 is just the original word prefix.
            pos = 1
            break
        end
        if state.words[listpos] == nil then
            state.words[listpos] = M.search_types[listpos].finder(state.forwards, state.here, state.prefix)
        end
        if state.words and #state.words[listpos] > 0 then
            -- Found some words
            pos = #state.words[listpos]
            break
        end
    end
    state.listpos = listpos
    state.pos = pos
end

local function next_backwards()
    local state = M.state
    local pos = state.pos
    local listpos = state.listpos
    if pos <= 1 then
        if state.forwards then
            prev_list()
        else
            next_list()
        end
        state.pos = #state.words[state.listpos]
    else
        pos = pos - 1
        state.pos = pos
    end
    update_word()
end

local function next_forwards()
    local state = M.state
    local pos = state.pos
    local listpos = state.listpos
    if pos >= #state.words[listpos] then
        if state.forwards then
            next_list()
        else
            prev_list()
        end
        state.pos = 1
    else
        pos = pos + 1
        state.pos = pos
    end
    update_word()
end

local function exit_complete()
    local pos = buffer.current_pos
    buffer:clear_selections()
    buffer:goto_pos(pos)
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
                   exit_complete()
                   if f then
                       return f()
                   end
                end,
    })
end

M.wordchars = 'a-zA-Z0-9_'

function get_words(forwards, here, prefix)
    local words = {}  -- ordered list of words

    local wordstart = here - #prefix

    local search = buffer.search_next

    -- Avoid finding the current word
    buffer.current_pos = here+1
    buffer:search_anchor()

    local endpos = here

    local pat = '\\b'..prefix..'['..M.wordchars..']*\\b'

    local wrapped = false
    while true do
        local nextpos = search(buffer, buffer.FIND_REGEXP + buffer.FIND_MATCHCASE, pat)
        if nextpos < 0 then
            if wrapped then break end

            -- Start from the end
            wrapped = true
            buffer.current_pos = 0
            buffer:search_anchor()
            --buffer.anchor = forwards and 0 or buffer.length
        elseif wrapped and nextpos >= wordstart then
            break
        else
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

-- Complete on tags
function get_tags(forwards, here, prefix)
    local matching_tags = vi_tags.match_tag("^"..prefix)
    return matching_tags or {}
end

-- The word completion types, in order.
local search_types = {
    {
        name='buffer',
        finder = get_words,
    },
    {
        name='tags',
        finder = get_tags,
    },
}
M.search_types = search_types

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
        forwards = forwards, -- initial direction
        words = {[0]={} },  -- list of word lists (in the order of search_types, with a dummy zeroth list.)
        listpos = 0, -- current word list (0 is empty)
        pos = 0,  -- current entry in words[listpos]
        current_end = here,
        wordstart = wordstart,
        prefix = prefix,
        here = here,
    }

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
