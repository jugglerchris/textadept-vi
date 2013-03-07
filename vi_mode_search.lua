-- Handle the vim search emulation
-- Modeled on textadept's command_entry.lua
local M = {}

local in_search_mode = false
local function handle_search_command(command)
    if in_search_mode then
	gui.statusbar_text = "Search: "..command
	in_search_mode = false
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
    gui.command_entry.focus()
end

return M
