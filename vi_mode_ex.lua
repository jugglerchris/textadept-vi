-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}
local vi_tags = require('vi_tags')

M.state = {
    history = {},  -- command history
    histidx = 1,   -- current index
}
local state = M.state
local gui_ce = gui.command_entry

local do_debug = false
local function dbg(...)
    if do_debug then gui._print("ex", ...) end
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
    _M.vi_mode.err(msg)
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

-- Find files matching a Lua pattern
local function find_matching_files(pattern)
    local results = {}
    local function f(filename)
        if filename:match(pattern) then
            results[#results+1] = filename
        end
    end
    lfs.dir_foreach('.', f, { folders = { "build"}}, true)
    return results
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
    find = function(args)
        local files = find_matching_files(args[2])
        if #files == 1 then
            io.open_file(files[1])
        elseif #files == 0 then
            ex_error("No files found: " .. #files)
        else
            ex_error("Multiple files found: " .. #files)
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
    b = function(args)
        if #args > 1 then
            local bufname = args[2]
            for i, buf in ipairs(_BUFFERS) do
                if buf and buf.filename and buf.filename:match(bufname) then
                   -- TODO: handle more than one matching
                   view:goto_buffer(i)
                   return
                end
            end
        end
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

    reset = function(args)
        reset()
    end,

    -- Build things
    make = function(args)
        -- modelled after run.lua:command
        local command = "make " .. table.concat(args, " ", 2) .. " 2>&1"
        local output= io.popen(command)
        local lexer = buffer:get_lexer()
        for line in output:lines() do
            events.emit(events.COMPILE_OUTPUT, lexer, line)
        end
    end,

    -- Tags
    tag = function(args)
        local tname = args[2]
        loc = vi_tags.find_tag_exact(tname)
        gui.print("Got tag: ", table.concat(loc, ","))
    end,
}

local function errhandler(msg)
    local fullmsg = debug.traceback(msg)
    return fullmsg
end

local function debugwrap(f)
  local function wrapped(...)
    ok, rest = xpcall(f, errhandler, ...)
    if ok then
      return rest
    else
      gui._print("lua errors", rest)
    end
  end
  return wrapped
end

local function handle_ex_command(command)
    if in_ex_mode then
      gui.statusbar_text = "Ex: "..command
        state.history[#(state.history)+1] = command
        state.histidx = #(state.history)
        local cmd = split(command)
        -- For now, a very simple command parser
        local handler = M.ex_commands[cmd[1]]
        local result

        in_ex_mode = false

        gui.command_entry.entry_text = ""

        if handler ~= nil then
            handler = debugwrap(handler)

            result = handler(cmd)
        else
            ex_error("Bad command <" .. tostring(cmd[1]) .. ">")
        end

        if result ~= nil then
            return result
        else
            return false  -- make sure this isn't handled again
        end
    end
end

local function matching_buffers(text)
    local buffers = {}
    if text == nil or text == '' then
        -- Match any filename if no pattern given.
        text = "."
    end

    for k,buf in ipairs(_BUFFERS) do
        if buf.filename and buf.filename:match(text) then
          buffers[#buffers+1] = buf.filename
        end
    end
    return buffers
end

local function complete_buffers(pos, text)
    local buffers = matching_buffers(text)
    if #buffers == 1 then
        gui_ce.entry_text = string.sub(gui_ce.entry_text, 1, pos-1) .. buffers[1]
    else
        gui_ce.show_completions(buffers)
    end
end

local ignore_complete_files = { ['.'] = 1, ['..'] = 1 }
local function complete_files(pos, text)
    local dir, filepat, dirlen
    if text then
        dir, filepat = text:match("^(.-)([^/]*)$")
        -- save the length of the directory portion (that we're not going to
        -- modify).
        dirlen = dir:len()
    else
        dir = '.'
        filepat = ''
        dirlen = 0
    end
    local files = { }

    -- Default to current directory, but save the original length
    if dir == '' then dir = '.' end

    -- Assume this is a prefix.
    filepat = '^' .. filepat

    for fname in lfs.dir(dir) do
        if (not ignore_complete_files[fname]) and fname:match(filepat) then
          local fullpath = dir .. "/" .. fname
          if lfs.attributes(fullpath, 'mode') == 'directory' then
              fname = fname .. "/"
          end
          files[#files+1] = fname
        end
    end
    if #files == 0 then
        ex_error("No completions")
    elseif #files == 1 then
        -- Substitute directly
        gui_ce.entry_text = string.sub(gui_ce.entry_text, 1, pos+dirlen-1) .. files[1]
    else
        -- Several completions
        gui_ce.show_completions(files)
    end
end

M.completions = {
    b = complete_buffers,
    e = complete_files,
}

-- Register our command_entry keybindings
keys.vi_ex_command = {
    ['\n'] = function ()
    	       local exit = state.exitfunc
     	       state.exitfunc = nil
	       return gui_ce.finish_mode(function(text)
                                              handle_ex_command(text)
                                              exit()
                                      end)
	     end,
    ['\t'] = function ()
        local cmd = gui_ce.entry_text:match("^(%S+)%s")
        local lastpos, lastword = gui_ce.entry_text:match("%s()(%S+)$")
        if cmd and M.completions[cmd] then
            debugwrap(M.completions[cmd])(lastpos, lastword)
        else
            -- complete commands here
        end
    end,
    up = function ()
        if state.histidx > 1 then
            state.histidx = state.histidx - 1
            gui_ce.entry_text = state.history[state.histidx]
        end
    end,
    down= function ()
        if state.histidx < #state.history then
            state.histidx = state.histidx + 1
            gui_ce.entry_text = state.history[state.histidx]
        end
    end,
}

function M.start(exitfunc)
    in_ex_mode = true
    state.exitfunc = exitfunc
    gui.command_entry.entry_text = ""
    gui.command_entry.enter_mode('vi_ex_command')
end

return M
