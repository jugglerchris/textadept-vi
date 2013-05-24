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

local function unsplit_other(ts)
    if ts.vertical == nil then
        -- Ensure this view is focused (so we don't delete the focused view)
        for k,v in ipairs(_G._VIEWS) do
            if ts == v then
                gui.goto_view(k)
                break
            end
        end
        view.unsplit(ts)
    else
        unsplit_other(ts[1])
    end
end

local function close_siblings_of(v, ts)
    local v = view
    local ts = ts or gui.get_split_table()

    if ts.vertical == nil then
        -- This is just a view
        return false
    else
        if ts[1] == v then
            -- We can't quite just close the current view.  Pick the first
            -- on the other side.
            return unsplit_other(ts[2])
        else if ts[2] == v then
            return unsplit_other(ts[1])
        else
            return close_siblings_of(v, ts[1]) or close_siblings_of(v, ts[2])
        end end
    end
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
    wq = function(args)
        buffer.save(_G.buffer)
        M.ex_commands.q()
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
        if #_VIEWS == 1 then
            -- Only one view, so quit.
            quit()
        else
            -- there are split views.  view.unsplit closes the *other*
            -- splits to leave the current view; we want :q to do the
            -- opposite and close this one.
            close_siblings_of(view)
        end
    end,
    only = function(args)
        -- Quit
        if #_VIEWS > 1 then
            view.unsplit(view)
        end
    end,
    split = function(args)
        view.split(view, false)
    end,
    vsplit = function(args)
        view.split(view, true)
    end,
    ds = function(args)
        local st = gui.get_split_table()
        local function dumpsplit(t, indent)
          if t.split then
            gui.print(indent.."View:", tostring(t))
          else
            gui.print(indent.."Split: ver=".. tostring(t.vertical))
            dumpsplit(t[1], indent.."  ")
            dumpsplit(t[2], indent.."  ")
          end
        end
        dumpsplit(st, "")
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
