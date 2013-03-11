-- Handle the vim search emulation
-- Modeled on textadept's command_entry.lua
local M = {}

local search_hl_indic = _SCINTILLA.next_indic_number()

local function set_colours()
    buffer.indic_fore[search_hl_indic] = "0x00FFFF"
    buffer.indic_style[search_hl_indic] = _SCINTILLA.constants.INDIC_ROUNDBOX
end

local in_search_mode = false
local function handle_search_command(command)
    if in_search_mode then
	gui.statusbar_text = "Search: "..command
        buffer:search_anchor()

        local search_flags = (_SCINTILLA.constants.SCFIND_REGEXP +
                              _SCINTILLA.constants.SCFIND_POSIX)

        pos = buffer:search_next(search_flags, command)

        if pos >= 0 then
            local saved_flags = buffer.search_flags
            buffer.search_flags = search_flags
            buffer.goto_pos(pos)
            -- Find all occurrences to highlight.
            buffer.indicator_current = search_hl_indic
            buffer:indicator_clear_range(0, buffer.length)

            -- Need to use search_in_target to find the actual search extents.
            buffer.target_start = 0
            buffer.target_end = buffer.length
            local occurences = 0
            local addsel = buffer.set_selection
            while buffer.search_in_target(command) >= 0 do
                addsel(buffer.target_end-1, buffer.target_start)
                addsel = buffer.add_selection
                --[[  In the terminal, indicators currently don't work.  :-(
                local match_len = buffer.target_end - buffer.target_start
                buffer:indicator_fill_range(buffer.target_start, match_len)
                -- Set the search range from the end of this match to the
                -- end of the buffer.
                ]]
                buffer.target_start = buffer.target_end
                buffer.target_end = buffer.length

                occurences = occurences + 1
            end
            gui.statusbar_text = "Found " .. tostring(occurences) .. " : <" .. tostring(search_hl_indic) .. ">"
            -- Restore global search flags
            buffer.search_flags = saved_flags
        else
            gui.statusbar_text = "Not found"
        end
	--in_search_mode = false
	return true  -- make sure this isn't handled again
    end
end

local function handle_search_key(code)
    if in_search_mode and keys.KEYSYMS[code] == 'esc' then
        -- Make sure we cancel the search flag.

        in_search_mode = false
    end
end

events.connect(events.COMMAND_ENTRY_COMMAND, handle_search_command, 1)
events.connect(events.COMMAND_ENTRY_KEYPRESS, handle_search_key, 1)

function M.start()
    in_search_mode = true
    gui.command_entry.entry_text = ""
    gui.command_entry.focus()
end

return M
