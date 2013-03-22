-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}

local debug = false
local function dbg(...)
    if debug then gui._print("ex", ...) end
end

local function split(s)
    local ret = {}
    -- dbg("split(" .. s ..")")
    for word in string.gmatch(s, "%S+") do
        ret[#ret+1] = word
    end
    return ret
end

local in_ex_mode = false
local function ex_error(msg)
    gui.statusbar_text = "Error: " .. msg
end

M.ex_commands = {
    e = function(args)
         dbg("In e handler")
         if args[2] ~= nil then
             io.open_file(args[2])
         else
             ex_error("No filename to open")
         end
    end,
    w = function(args)
         --dbg("Fn:" .. tostring(_G.buffer.filename))
         if #args ~= 1 then
             ex_error(":w doesn't yet accept an arg")
         else
              buffer.save(_G.buffer)
         end
    end,
    n = function(args)
         view:goto_buffer(1, true)
    end,
    p = function(args)
         view:goto_buffer(-1, true)
    end,
    c = function(args)
        -- Leave the command entry open
        gui.command_entry.focus()
        return true
    end,
}

local function handle_ex_command(command)
    if in_ex_mode then
      gui.statusbar_text = "Ex: "..command
        local cmd = split(command)
        -- For now, a very simple command parser
        local handler = M.ex_commands[cmd[1]]
        local result

        gui.command_entry.entry_text = ""

        if handler ~= nil then
            result = handler(cmd)
        else
            gui.statusbar_text = "Bad command <" .. cmd[1] .. ">"
        end

        in_ex_mode = false

        if result ~= nil then
            return result
        else
            return false  -- make sure this isn't handled again
        end
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
    gui.command_entry.entry_text = ""
    gui.command_entry.focus()
end

return M
