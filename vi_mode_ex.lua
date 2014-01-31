-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}
local vi_tags = require('vi_tags')
M.use_vi_entry = true
local vi_entry
if M.use_vi_entry then
    vi_entry = require('vi_entry')
end

-- Support for saving state over reset
local state = {
    history = {},
    histidx = 1,
    clists = {},  -- Stack of { list=items, idx=n } for :clist etc.
    clistidx = 0,
}

M.state = state

-- Save over a reset
events.connect(events.RESET_BEFORE, function()
  -- stash state in the arg table.  arg isn't available during reset,
  -- but is restored afterwards.
  _G.arg.vi_saved_state_ex = state
end)
events.connect(events.RESET_AFTER, function()
  -- Restore saved state
  local saved = _G.arg.vi_saved_state_ex
  if saved then
      state.history = saved.history
      state.histidx = saved.histidx
      state.clists = saved.clists or {}
      state.clistidx = saved.clistidx or 0
      _G.arg.vi_saved_state_ex = nil
  end
end)

local ui_ce = ui.command_entry

local do_debug = false
local function dbg(...)
    if do_debug then ui._print("ex", ...) end
end

local function split(s)
    local ret = {}
    --dbg("split(" .. s ..")")
    for word in string.gmatch(s, "%S+") do
        ret[#ret+1] = word
    end
    return ret
end

local function ex_error(msg)
    vi_mode.err(msg)
end

local function unsplit_other(ts)
    if ts.vertical == nil then
        -- Ensure this view is focused (so we don't delete the focused view)
        for k,v in ipairs(_G._VIEWS) do
            if ts == v then
                ui.goto_view(k)
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
    local ts = ts or ui.get_split_table()

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

-- Find files matching a Lua pattern (or a string match)
local function find_matching_files(pattern)
    local results = {}
    local function f(filename)
        if filename:match(pattern) or filename:find(pattern, 1, true) then
            results[#results+1] = filename
        end
    end
    lfs.dir_foreach('.', f, { folders = { "build"}}, false)
    return results
end

-- Given a list of items, prompt the user to choose one.
local function choose_list(title, items, cb)
    local list = textredux.core.list.new(title)
    list.items = items
    list.on_selection = function(l, item, shift, ctrl, alt, meta)
       cb(item)
    end
    list.keys.esc = function() list:close() end
    list:show()
end

-- Jump to an item in a clist ({ filename, lineno, text })
local function clist_go(item)
    io.open_file(item[1])
    buffer.goto_line(item[2]-1)
    state.clists[state.clistidx].idx = item.idx
end

--- Expand a filename:
--    ~/foo -> $HOME/foo
local function expand_filename(s)
    if s:sub(1,2) == "~/" then
        s = os.getenv("HOME") .. s:sub(2)
    end
    return s
end

M.ex_commands = {
    e = function(args)
        dbg("In e handler")
        if args[2] ~= nil then
            local filename = expand_filename(args[2])
            io.open_file(filename)
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
            choose_list('Choose file', files, io.open_file)
        end
    end,
    w = function(args)
         --dbg("Fn:" .. tostring(_G.buffer.filename))
         if #args == 2 then
	     io.save_file_as(args[2])
         elseif #args == 1 then
	     io.save_file()
         else
             ex_error("Too many arguments to :w")
         end
    end,
    wq = function(args)
        io.save_file()
        M.ex_commands.q()
    end,
    n = function(args)
         view:goto_buffer(1, true)
    end,
    p = function(args)
         view:goto_buffer(-1, true)
    end,
    b = function(args)
        if #args > 1 then
            local bufname = args[2]
            for i, buf in ipairs(_BUFFERS) do
                if buf and buf.filename and (buf.filename:match(bufname) or buf.filename:find(bufname, 1, true)) then
                   -- TODO: handle more than one matching
                   view:goto_buffer(i)
                   return
                end
            end
        end
    end,
    bdelete = function(args)
        if #args > 1 then
            ex_error("Arguments to bdelete not supported yet.")
        else
            io.close_buffer()
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
        local st = ui.get_split_table()
        local function dumpsplit(t, indent)
          if t.split then
            ui.print(indent.."View:", tostring(t))
          else
            ui.print(indent.."Split: ver=".. tostring(t.vertical))
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
        local command = {"make"}
        for i=2,#args do
            command[#command+1] = args[i]
        end
        textadept.run.cwd = './'  -- So that the run module can take care of finding errors.
        local lexer = buffer:get_lexer()
        ui.print("Running: " .. table.concat(command, " "))
        local msgbuf = buffer
        local function getoutput(s)
            local cur_view = view
            local cur_buf
            local my_view
            -- Search for a view with this buffer
            for i,v in ipairs(_VIEWS) do
                if v.buffer == msgbuf then
                    my_view = v
                    break
                end
            end
            if my_view then
                if cur_view ~= my_view then
                    ui.goto_view(_VIEWS[my_view])
                end
                    
                msgbuf:append_text(s)
                msgbuf:goto_pos(msgbuf.length)
                
                if my_view ~= cur_view then
                    ui.goto_view(_VIEWS[cur_view])
                end
            end
        end
        os.spawn(nil, command, nil, nil, getoutput, getoutput)
    end,
    
    -- Search files
    lgrep = function(args)
        local pat = args[2]
        if not pat then return end
        
        local root = args[3] or '.'
        
        local results = {}
        
        local function search(filename)
            local f, err = io.open(filename)
            if not f then
                ex_error(err..":"..filename)
            end
            local lineno = 0
            for line in f:lines() do
                lineno = lineno + 1
                if line:match(pat) then
                    local idx = #results+1
                    results[idx] = { filename, lineno, line, idx=idx }
                end
            end
            f:close()
        end
        lfs.dir_foreach(root, search, _G.vifilter, false)
        if #results == 0 then
            ex_error("No matches found.")
        else
            -- Push the results list to the stack
            state.clistidx = #state.clists+1
            state.clists[state.clistidx] = { list=results, idx=1 }
            choose_list('Matches found', results, clist_go)
        end
    end,
    cn = function(args)
        local clist = state.clists[state.clistidx]
        if not clist then
            ex_error("No clist")
            return
        end
        local idx = clist.idx
        if idx > #clist.list then
            ex_error("End of list")
        else
            clist_go(clist.list[idx+1])
        end
    end,
    cp = function(args)
        local clist = state.clists[state.clistidx]
        if not clist then
            ex_error("No clist")
            return
        end
        local idx = clist.idx
        if idx <= 1 then
            ex_error("Start of list")
        else
            clist_go(clist.list[idx-1])
        end
    end,
    clist = function(args)
        local clist = state.clists[state.clistidx]
        if not clist then
            ex_error("No clist")
            return
        end
        choose_list('Matches found', clist.list, clist_go)
    end,

    -- Tags
    tag = function(args)
        local tname = args[2]
        local loc = vi_tags.find_tag_exact(tname)
        if loc then
            vi_tags.goto_tag(loc)
        else
            ex_error("Tag not found")
        end
    end,
    tn = function(args)
        local loc = vi_tags.tag_next()
        if loc then
            vi_tags.goto_tag(loc)
        else
            ex_error("No more tags")
        end
    end,
    tp = function(args)
        local loc = vi_tags.tag_prev()
        if loc then
            vi_tags.goto_tag(loc)
        else
            ex_error("No more tags")
        end
    end,
    tsel = function(args)
        local tname = args[2]
        local loc1
        if tname then
            loc1 = vi_tags.find_tag_exact(tname)
            if not loc1 then
                ex_error("Tag not found")
                return
            end
        end
        -- We know there's at least one match
        local tags = vi_tags.get_all()
        if not tags then
            ex_error("No tags")
            return
        end

        if #tags == 1 then
            -- Only one, just jump to it.
            vi_tags.goto_tag(loc1)
        else
            local items = {}
            for i,t in ipairs(tags) do
                items[#items+1] = { t.filename, t.excmd, tag=t }
            end
            choose_list('Choose tag', items, function(item)
                vi_tags.goto_tag(item.tag)
            end)
        end
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
      ui._print("lua errors", rest)
    end
  end
  return wrapped
end

local function handle_ex_command(command)
      local result
      if not command:match("^%s*$") then
        ui.statusbar_text = "Ex: "..command
        state.history[state.histidx] = command
        local cmd = split(command)
        -- For now, a very simple command parser
        local handler = M.ex_commands[cmd[1]]
        
        ui.command_entry.entry_text = ""
        if handler ~= nil then
            handler = debugwrap(handler)

            result = handler(cmd)
        else
            ex_error("Bad command <" .. tostring(cmd[1]) .. ">")
        end

      end

      if result ~= nil then
          return result
      else
          return false  -- make sure this isn't handled again
      end
end

-- Handle a completion.
-- Given a list of completions, and a function to get the string to complete,
-- do the right thing:
--  if nil or empty, give error
--  if one option, substitute it in directly
--  otherwise, prompt with the list.
local function do_complete_simple(pos, names)
    if (not names) or #names == 0 then
        ex_error("No completions")
    elseif #names == 1 then
        -- Substitute directly
        ui_ce.entry_text = string.sub(ui_ce.entry_text, 1, pos-1) .. names[1]
    else
        -- Several completions
        ui_ce.show_completions(names)
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
        ui_ce.entry_text = string.sub(ui_ce.entry_text, 1, pos-1) .. buffers[1]
    else
        ui_ce.show_completions(buffers)
    end
end

local ignore_complete_files = { ['.'] = 1, ['..'] = 1 }
local function matching_files(text)
    local origdir, dir, filepat, dirlen
    -- Special case - a bare % becomes the current file's path.
    if text == "%" then
        return { buffer.filename }
    end
    if text then
        origdir, filepat = text:match("^(.-)([^/]*)$")
        -- save the length of the directory portion (that we're not going to
        -- modify).
        dirlen = origdir:len()
        
        -- Expand ~/
        dir = expand_filename(origdir)
    else
        dir = '.'
        origdir = ''
        filepat = ''
        dirlen = 0
    end
    local files = { }

    -- Default to current directory, but save the original length
    if dir == '' then dir = '.' end

    -- Assume this is a prefix.
    filepat = '^' .. filepat

    local mode = lfs.attributes(dir, 'mode')
    if mode and mode == 'directory' then
      for fname in lfs.dir(dir) do
        if (not ignore_complete_files[fname]) and fname:match(filepat) then
          local fullpath = dir .. "/" .. fname
          if lfs.attributes(fullpath, 'mode') == 'directory' then
              fname = fname .. "/"
          end
          files[#files+1] = fname
        end
      end
    else
      ex_error('Bad dir: '..dir)
    end
    files.skip_prefix = dirlen
    return files
end

local function complete_files(pos, text)
    local files = matching_files(text)
    if #files == 0 then
        ex_error("No completions")
    elseif #files == 1 then
        -- Substitute directly
        ui_ce.entry_text = string.sub(ui_ce.entry_text, 1, pos+dirlen-1) .. files[1]
    else
        -- Several completions
        ui_ce.show_completions(files)
    end
end

local function complete_tags(pos, text)
    local tagnames = vi_tags.match_tag(text)
    do_complete_simple(pos, tagnames)
end

local function complete_paths(pos, text)
    local files = find_matching_files(text)
    do_complete_simple(pos, files)
end

M.completions = {
    b = complete_buffers,
    e = complete_files,
    w = complete_files,
    tag = complete_tags,
    tsel = complete_tags,
    find = complete_paths,
}

-- Completers for the new entry method
M.completions_word = {
    b = matching_buffers, 
    e = function(text) return matching_files(text) end,
    w = function(text) return matching_files(text) end,
    tag = vi_tags.match_tag,
    tsel = vi_tags.match_tag,
    find = find_matching_files,
}

-- Register our command_entry keybindings
keys.vi_ex_command = {
    ['\n'] = function ()
    	       local exit = state.exitfunc
     	       state.exitfunc = nil
	       return ui_ce.finish_mode(function(text)
                                              handle_ex_command(text)
                                              exit()
                                      end)
	     end,
    ['\t'] = function ()
        local cmd = ui_ce.entry_text:match("^(%S+)%s")
        local lastpos, lastword = ui_ce.entry_text:match("%s()(%S+)$")
        if not lastpos then lastpos = ui_ce.entry_text:len() end
        if cmd and M.completions[cmd] then
            debugwrap(M.completions[cmd])(lastpos, lastword)
        else
            -- complete commands here
        end
    end,
    up = function ()
        if state.histidx > 1 then
            -- Save current text
            state.history[state.histidx] = ui_ce.entry_text
            
            state.histidx = state.histidx - 1
            ui_ce.entry_text = state.history[state.histidx]
        end
    end,
    down= function ()
        if state.histidx < #state.history then
            -- Save current text
            state.history[state.histidx] = ui_ce.entry_text
            
            state.histidx = state.histidx + 1
            ui_ce.entry_text = state.history[state.histidx]
        end
    end,
}

local function do_complete(word, cmd)
    if cmd and M.completions_word[cmd] then
        return M.completions_word[cmd](word)
    else
        return {}
    end
end

function M.start(exitfunc)
    state.exitfunc = exitfunc
    state.histidx = #state.history + 1  -- new command is after the end of the history
    if M.use_vi_entry then
        vi_entry.enter_mode(':', handle_ex_command, do_complete)
    else
        ui.command_entry.entry_text = ""
        ui.command_entry.enter_mode('vi_ex_command')
    end
end

--- Run an ex command that may not have come directly from the command line.
function M.run_ex_command(text)
    handle_ex_command(text)
end

--- Add a new custom ex command.
function M.add_ex_command(name, handler, completer)
    M.ex_commands[name] = handler
    M.completions[name] = completer
end

return M
