-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}

local debug = false
local function dbg(...)
    if debug then gui._print("ex", ...) end
end

local function split(s)
    local ret = {}
    --dbg("split(" .. s ..")")
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
    q = function(args)
        -- Quit
        dbg("in q")
        quit()
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

M.state = {}
local state = M.state

-- Register our command_entry keybindings
local gui_ce = gui.command_entry
keys.vi_ex_command = {
    ['\n'] = function ()
    	       local exit = state.exitfunc
     	       state.exitfunc = nil
	       return gui_ce.finish_mode(function(text)
                                              handle_ex_command(text)
                                              exit()
                                      end)
	     end,
}

function M.start(exitfunc)
    in_ex_mode = true
    state.exitfunc = exitfunc
    gui.command_entry.entry_text = ""
    gui.command_entry.enter_mode('vi_ex_command')
end

return M
