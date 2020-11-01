-- Handle the vim search emulation
-- Modeled on textadept's command_entry.lua
local M = {}

M.search_hl_indic = _SCINTILLA.next_indic_number()

local function set_colours()
    buffer.indic_fore[M.search_hl_indic] = 0xFF0000
    buffer.indic_style[M.search_hl_indic] = _SCINTILLA.constants.INDIC_ROUNDBOX
    buffer.indic_alpha[M.search_hl_indic] = 100
    -- Find all occurrences to highlight.
    buffer.indicator_current = M.search_hl_indic
    buffer:indicator_clear_range(0, buffer.length)
end

M.state = {
    in_search_mode = false,
    backwards = false,
    pattern = "",
}
local state = M.state

local function do_search(backwards)
    if state.pattern == "" then return end
    ui.statusbar_text = "Search: "..state.pattern
    local saved_pos = buffer.current_pos
    buffer:search_anchor()

    local search_flags = _SCINTILLA.constants.FIND_REGEXP

    local searcher = function(...) return buffer:search_next(...) end

    -- Search from the end.  We'll jump to the first one "after" the current pos.
    buffer.current_pos = 0
    buffer:search_anchor()
    pos = searcher(search_flags, state.pattern)

    set_colours()

    if pos >= 0 then
        local saved_flags = buffer.search_flags
        buffer.search_flags = search_flags

        local new_pos = nil

        -- Need to use search_in_target to find the actual search extents.
        buffer.target_start = 0
        buffer.target_end = buffer.length
        local occurences = 0
        local first_pos = nil
        local last_pos = nil
        while buffer:search_in_target(state.pattern) >= 0 do
            local match_len = buffer.target_end - buffer.target_start
            last_pos = buffer.target_start
            if first_pos == nil then
                first_pos = buffer.target_start
            end

            -- Work out the current pos, ie first hit after the saved position.
            if backwards then
                if buffer.target_start < saved_pos then
                    new_pos = buffer.target_start
                end
            else
                -- Forwards - take the first one after saved_pos
                if new_pos == nil and buffer.target_start > saved_pos then
                    new_pos = buffer.target_start
                end
            end
            buffer:indicator_fill_range(buffer.target_start, match_len)
            if buffer.target_end == buffer.target_start then
                -- Zero length match - not useful, abort here.
                buffer.current_pos = saved_pos
                ui.statusbar_text = "Not found"
                return
            end
            -- Ensure we make some progress
            if buffer.target_end == buffer.target_start then
                buffer.target_start = buffer.target_end + 1
            else
                    buffer.target_start = buffer.target_end
            end
            buffer.target_end = buffer.length
            if buffer.target_start >= buffer.length then
                break
            end

            occurences = occurences + 1
        end
        -- Handle wrapping search
        if new_pos == nil then
            if backwards then
                new_pos = last_pos
            else
                new_pos = first_pos
            end
            ui.statusbar_text = "WRAPPED SEARCH"
        else
            ui.statusbar_text = "Found " .. tostring(occurences)
        end
        -- Restore global search flags
        buffer.search_flags = saved_flags
        buffer:ensure_visible(buffer:line_from_position(new_pos))
        buffer:goto_pos(new_pos)
        buffer.selection_start = new_pos
    else
        buffer.current_pos = saved_pos
        vi_mode.err("Not found")
    end
end

local function handle_search_command(command)
    if state.in_search_mode then
        state.pattern = command
        do_search(state.backwards)
        state.in_search_mode = false
        return false  -- make sure this isn't handled again
    end
end

-- Register our key bindings for the command entry
local ui_ce = ui.command_entry
local function finish_search(text)
    local exitfunc = state.exitfunc
    state.exitfunc = nil
    if string.len(text) == 0 then
        text = state.pattern
    end
    exitfunc(function()
        state.pattern = text
        do_search(state.backwards)
    end)
end
keys.vi_search_command = {
    ['ctrl+v'] = {
        ['\t'] = function()
            return keys.vi_search_command['\t']()
        end,
    },
    ['\t'] = function() -- insert the string '\t' instead of tab
        -- FIXME: insert at correct position ???
        local text = ui.command_entry:get_text()
        --ui_ce.enter_mode(nil)
        ui.command_entry:set_text(text .. "\\t")
        --ui_ce.enter_mode("vi_search_command")
    end,
    ['esc'] = function()
              ui_ce.enter_mode(nil)  -- Exit command_entry mode
              keys.mode = "vi_command"
          end,
    ['\b'] = function()
        if ui.command_entry:get_text() == "" then
            return keys.vi_search_command['esc']() -- exit
        end
        return false -- propagate the key
     end,
}

local function start_common(exitfunc)
    state.in_search_mode = true
    state.exitfunc = exitfunc
    ui.command_entry.run(finish_search)
end

function M.start(exitfunc)
    state.backwards = false
    return start_common(exitfunc)
end

function M.start_rev(exitfunc)
    state.backwards = true
    return start_common(exitfunc)
end

function M.restart()
    do_search(state.backwards)
end

function M.restart_rev()
    do_search(not state.backwards)
end

local function search_word_common(backwards)
    -- Search for the word under the cursor
    -- TODO: quote properly, or better don't use regex'
    -- Uses ideas from editing.lua
    local pos = buffer.current_pos
    local s, e = buffer:word_start_position(pos, true), buffer:word_end_position(pos)
    local word = buffer:text_range(s, e)
    if word == "" then return end
    state.pattern = '\\b' .. word .. '\\b'
    ui.command_entry.append_history(finish_search, state.pattern)
    state.backwards = backwards
    if backwards then
        -- Avoid hitting the current word again if the cursor isn't at the
        -- start.
        buffer.current_pos = s
    end
    do_search(backwards)
end

function M.search_word()
    search_word_common(false)
end

function M.search_word_rev()
    search_word_common(true)
end

return M
