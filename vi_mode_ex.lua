-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}

local in_ex_mode = false
local function handle_ex_command(command)
    if in_ex_mode then
	gui.statusbar_text = "Ex: "..command
	in_ex_mode = false
	return true  -- make sure this isn't handled again
    end
end

local function handle_ex_key(code)
    if in_ex_mode and keys.KEYSYMS[code] == 'esc' then
        -- Make sure we cancel the ex flag.
        in_ex_mode = false
    end
end

events.connect(events.COMMAND_ENTRY_COMMAND, handle_ex_command, 1)
events.connect(events.COMMAND_ENTRY_KEYPRESS, handle_ex_key, 1)

function M.start()
    in_ex_mode = true
    gui.command_entry.focus()
end

return M
