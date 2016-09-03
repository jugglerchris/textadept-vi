-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}
local vi_tags = require('vi_tags')
local vi_quickfix = require('vi_quickfix')
local vi_regex = require('regex.pegex')
M.use_vi_entry = true
local vi_entry
local vi_views = require('vi_views')
local lpeg = require 'lpeg'
local vi_find_files = require 'vi_find_files'
local P, R, S = lpeg.P, lpeg.R, lpeg.S
local C, Cc, Cf, Cp, Ct, Carg, Cg = lpeg.C, lpeg.Cc, lpeg.Cf, lpeg.Cp, lpeg.Ct, lpeg.Carg, lpeg.Cg

-- Support for saving state over reset
local state = {
    history = {},
    histidx = 1,
    clists = {},  -- Stack of { list=items, idx=n } for :clist etc.
    clistidx = 0,
    last_cmd = nil,
    entry_state = nil, -- vi_entry state
    cur_buf = nil,     -- The current buffer before starting the entry
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

local function relpath(path)
    local curdir = lfs.abspath(lfs.currentdir())
    
    local curlen = #curdir
    
    if path:sub(1, curlen) == curdir then
        return path:sub(curlen+2)
    else
        return path
    end
end

-- Local wrapper which handles special expansions ("%" -> current filename)
local function get_matching_files(text, doescape)
    -- Special case - a bare % becomes the current file's path.
    if text == "%" then
        local result = relpath(state.cur_buf.filename)
        if doescape then
            result = vi_find_files.luapat_escape(result)
        end
        return { result }
    end
    
    return vi_find_files.matching_files(text, doescape) 
end

local do_debug = false
local function dbg(...)
    if do_debug then ui._print("ex", ...) end
end

-- Helper functions for parsing addresses
local function _curline()
    return buffer:line_from_position(buffer.current_pos) + 1
end
local function _lastline()
    return buffer.line_count
end

local function _tolinenum(a)
    return tonumber(a)
end

local function _searchfwd(re)
    local pat = vi_regex.compile(re)
    local lineno = _curline()

    for i=lineno,_lastline() do
        local line = buffer:get_line(i-1)
        if pat:match(line) then
            return i
        end
    end
    error("Pattern '"..re.."' not found from "..tostring(buffer.filename)..":"..lineno.." (lastline=".._lastline()..")")
end

-- Take two numbers and produce a range.
local function _mk_range(a, b)
    return { a, b }
end

-- Take a single address and make a range
local function _mk_range_single(a)
    return { a, a }
end

local function neg(a) return -a end
local function add(a,b) return a+b end

-- Pattern for matching an address.  Returns a line number.
local ex_addr_num = (R"09" ^ 1) / _tolinenum
local ex_addr_here = (P".") / _curline
local ex_addr_end = (P"$") / _lastline

-- A regular expressions.
local ex_quoted_slash = (P"\\/" + (1 - P"/"))
local ex_pattern_nonempty = ex_quoted_slash ^ 1
local ex_pattern = ex_pattern_nonempty + P(0)

local ex_addr_fwd = (P"/" * C(ex_pattern_nonempty ^ 1) * P"/") / _searchfwd
local ex_addr_base = ex_addr_num + ex_addr_here + ex_addr_end + ex_addr_fwd
local addr_adder = (P"+" * ex_addr_num)
local addr_subber = (P"-" * ex_addr_num) / neg
local ex_addr = Cf(ex_addr_base * (addr_adder + addr_subber)^0, add) + Cf((P(0) / _curline) * (addr_adder + addr_subber)^1, add)

-- A range of '%' means the whole file
local ex_range_pct = P'%' / function() return _mk_range(1, _lastline()) end

-- And a range returns a pair of line numbers { start, end }
local ex_range = ((((ex_addr + P(0)/_curline) * "," * ex_addr)/_mk_range) + (ex_addr / _mk_range_single) + ex_range_pct + (P(0) * Cc(nil)))

local ex_ws = S" \t"

-- A simple command (plain words).  TODO: add quoting.
local ex_cmd_simple = (C((1 - ex_ws) ^ 1) * (ex_ws ^ 0)) ^ 1

local function unquote_slash(s)
    -- In () to lose the second return value
    return (s:gsub("\\/", "/"))
end

-- The s command
local ex_cmd_s = C(P("s")) * P("/") * (ex_pattern/unquote_slash) * P("/") * 
                                   ((ex_quoted_slash ^ 0)/unquote_slash) * P("/") * C(R("az")^0)
                                  
-- Shell command: !ls
-- Very basic word splitting - add quoting later.
local ex_cmd_shell = C(P("!")) * (C((1 - ex_ws) ^ 1) * (ex_ws ^ 0)) ^ 1

local ex_cmd = Ct(ex_cmd_s + ex_cmd_shell + ex_cmd_simple)

local ex_cmdline = ex_range * (ex_ws ^ 0) * ex_cmd

-- Parse an ex command, including optional range and command
function M.parse_ex_cmd(s)
    local range, args = ex_cmdline:match(s)

    return args, range
end

local function ex_error(msg)
    vi_mode.err(msg)
end

local find_matching_files = vi_find_files.find_matching_files

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

-- Jump to an item in a clist ({ text, path=filename, lineno=lineno, idx=idx })
-- Jump to a quickfix item
local function clist_go(item)
    -- If no file/line, don't do anything.
    if item.path and item.lineno then
        io.open_file(item.path)
        buffer.goto_line(item.lineno-1)
        state.clists[state.clistidx].idx = item.idx
    end
end

--- Expand a filename:
--    ~/foo -> $HOME/foo
local function expand_filename(s)
    if s:sub(1,2) == "~/" then
        s = os.getenv("HOME") .. s:sub(2)
    end
    local files = get_matching_files(s, false)
    if #files >= 1 then return files[1] end
    return s
end

-- Parse the replacement string
local repl_chars = C((P(1) - S'&\\')^1)
-- Relies on the table of groups being the first extra parameter to lpeg.match.
local repl_ref = P"\\" * (C(R"09") * Carg(1)) / function(ref, groups) return groups[ref] or "" end
local amp_ref = P"&" * Carg(1) /function(groups) return groups["&"] end
local repl_special = P"\\n" * Cc('\n')
local repl_quoted = P"\\" * C(P(1))
local repl_pat = Cf(Cc("")*((repl_chars + repl_ref + amp_ref + repl_special + repl_quoted) ^ 0), function(a,b) return a..b end)

local function command_substitute(args, range)
    local searchpat = args[2]
    local replace = args[3]
    local flagstring = args[4]
    local flags = {}
--    cme_log('subst: pat=[['..searchpat..']], repl=[['..replace..']], flags=[['..flagstring..']]')
    
    for i=1,#flagstring do
        flags[flagstring:sub(i,i)] = true
    end
    
    if range == nil then
        local lineno = buffer:line_from_position(buffer.current_pos)
        range = { lineno, lineno }
    else
        -- convert from 1-based to 0-based line numbers
        range = { range[1]-1, range[2]-1 }
    end
    
    local pat = vi_regex.compile(searchpat)
    if pat == nil then
        ex_error("Bad pattern.")
        return
    end
    
    buffer:begin_undo_action()
    local lineno = range[1]  -- Start or current line
    local lastline = range[2] -- Finish line (may change if newlines inserted)
    while lineno <= lastline do
        local line = buffer:get_line(lineno)
        line = line:gsub("\n", "") -- Remove any newline from the end.
        local m = pat:match(line)
        while m do
            local groups = {}
            if m.groups then
               for k,v in pairs(m.groups or {}) do
                   local grp = line:sub(v[1], v[2])
                   groups[tostring(k)] = grp
               end
            end
            groups["&"] = line:sub(m._start, m._end)
            local repl = repl_pat:match(replace, 1, groups)
            line = line:sub(1,m._start-1) .. repl .. line:sub(m._end+1)

            -- Keep looking?
            if flags.g then
                m = pat:match(line, m._start + #repl)
            else
                break
            end
        end
        -- Do the replace
        local linepos = buffer:position_from_line(lineno)
        local linelength = buffer.line_end_position[lineno] - buffer.position_from_line(lineno)
        buffer:set_selection(linepos+linelength, linepos)
        buffer:replace_sel(line)
        local _, nlcount = line:gsub("\n", "")
        -- Account for any inserted newlines.
        lineno = lineno + 1 + nlcount
        lastline = lastline + nlcount
    end
    buffer:end_undo_action()
end

-- Take a buffer with error messages, and turn it into a quickfix list,
-- which is activated.
local function choose_errors_from_buf(buf, cb)
    local results = vi_quickfix.quickfix_from_buffer(buf)
    cb = cb or clist_go
    if results then
        -- Push the results list to the stack
        state.clistidx = #state.clists+1
        state.clists[state.clistidx] = { list=results, idx=1 }
        choose_list('Errors', results, cb)
    end
end

-- Wrapper around clist_go which also annotates the destination buffer.
local function clist_go_annotate(item)
    if item.path and item.lineno then
        io.open_file(item.path)
        buffer.goto_line(item.lineno-1)
        buffer:annotation_clear_all()
        buffer.annotation_visible = buffer.ANNOTATION_STANDARD
        for _,erritem in ipairs(state.clists[state.clistidx].list) do
            if erritem.path == item.path then
                local msg = erritem.message
                local prevmsg = buffer.annotation_text[erritem.lineno-1]
                if prevmsg and #prevmsg > 0 then
                    msg = prevmsg .. "\n" .. msg
                end
                buffer.annotation_text[erritem.lineno-1] = msg
                buffer.annotation_style[erritem.lineno-1] = 8  -- error style
            end
        end
        state.clists[state.clistidx].idx = item.idx
    end
end

-- As choose_errors_from_buf, but with a callback which also annotates
-- the destination buffer with errors.
local function choose_errors_annotated_from_buf(buf)
    return choose_errors_from_buf(buf, clist_go_annotate)
end

-- Spawn a command, which will write its output to a buffer in the
-- background, and call a function when finished.
--
-- command: a table of the command line
-- workdir: The working directory the command should run in.
-- buftype: the buffer type (eg "*make*"), which will be created or cleared.
-- when_finished: a function called with the buffer when the process
--                exits.
function command_to_buffer(command, workdir, buftype, when_finished, read_only)
    local msgbuf = nil
    for n,buf in ipairs(_BUFFERS) do
        if buf._type == buftype then
            msgbuf = buf
            break
        end
    end
    if msgbuf == nil then
        msgbuf = buffer.new()
        msgbuf._type = buftype
    else
        -- Clear the buffer
        msgbuf:clear_all()
    end
    ui._print(buftype, "Running: " .. table.concat(command, " "))
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
                ui.goto_view(my_view)
            end

            msgbuf:append_text(s)
            msgbuf:goto_pos(msgbuf.length)
            msgbuf:set_save_point()

            if my_view ~= cur_view then
                ui.goto_view(cur_view)
            end
        end
    end
    local function endproc()
        msgbuf:append_text('Finished:' .. table.concat(command, " "))
        msgbuf:set_save_point()
        if read_only then
            msgbuf.read_only = true
        end
        if when_finished ~= nil then
            when_finished(msgbuf)
        end
    end
    spawn(table.concat(command, " "), workdir, getoutput, getoutput, endproc)
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
             ex_error("Too many arguments to :"..args[1])
         end
    end,
    wn = function(args)
        if #args ~= 1 then ex_error("Too many arguments to :"..args[1]); return end
        M.ex_commands.w(args)
        M.ex_commands.n(args)
    end,
    wN = function(args)
        if #args ~= 1 then ex_error("Too many arguments to :"..args[1]); return end
        M.ex_commands.w(args)
        M.ex_commands.N(args)
    end,
    wq = function(args)
        if #args ~= 1 then ex_error("Too many arguments to :"..args[1]); return end
        M.ex_commands.w(args)
        M.ex_commands.q(args)
    end,
    x = function(args)
        if #args ~= 1 then ex_error("Too many arguments to :"..args[1]); return end
        if buffer.modify then
            M.ex_commands.w(args)
        end
        M.ex_commands.q(args)
    end,
    n = function(args)
        if #args ~= 1 then ex_error("Too many arguments to :"..args[1]); return end
        view:goto_buffer(1)
    end,
    ['ne']    = function(args) M.ex_commands.n(args) end,
    ['nex']   = function(args) M.ex_commands.n(args) end,
    ['next']  = function(args) M.ex_commands.n(args) end,
    ['n!']    = function(args) M.ex_commands.n(args) end,
    ['ne!']   = function(args) M.ex_commands.n(args) end,
    ['nex!']  = function(args) M.ex_commands.n(args) end,
    ['next!'] = function(args) M.ex_commands.n(args) end,
    N = function(args)
        if #args ~= 1 then ex_error("Too many arguments to :"..args[1]); return end
        view:goto_buffer(-1)
    end,
    ['N!'] = function(args) M.ex_commands.N(args) end,
    b = function(args)
        if #args > 1 then
            local bufname = args[2]
            -- Try as a regular expression too.
            local bufpat = vi_regex.compile(bufname)
            for i, buf in ipairs(_BUFFERS) do
                if buf and buf.filename and ((bufpat and bufpat:match(buf.filename)) or buf.filename:find(bufname, 1, true)) then
                   -- TODO: handle more than one matching
                   view:goto_buffer(buf)
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
            vi_views.close_siblings_of(view)
        end
    end,
    ['q!'] = function(args)
        -- force quit
        events.connect(events.QUIT, function() return false end, 1)
        quit()
    end,
    only = function(args)
        -- Quit
        if #_VIEWS > 1 then
            view.unsplit(view)
        end
    end,
    split = function(args)
        view.split(view, false)
        if args[2] then
            local filename = expand_filename(args[2])
            io.open_file(filename)
        end
    end,
    vsplit = function(args)
        view.split(view, true)
        if args[2] then
            local filename = expand_filename(args[2])
            io.open_file(filename)
        end
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
        local command = {"make"}
        for i=2,#args do
            command[#command+1] = args[i]
        end
        -- Remove existing annotations.
        for _,b in ipairs(_BUFFERS) do
            b:annotation_clear_all()
        end
        command_to_buffer(command, "./", "*make*", choose_errors_annotated_from_buf, true)
    end,

    -- Search files
    grep = function(args)
        local pat = args[2]
        if not pat then return end
        
        local cmd = {}
        local grepprg = vi_mode.state.variables.grepprg
        
        if type(grepprg) == 'string' then
            cmd[#cmd+1] = grepprg
        else
            -- Assume a table
            for _,arg in ipairs(grepprg) do
                cmd[#cmd+1] = arg
            end
        end
        -- Append arguments
        for i = 2,#args do
            cmd[#cmd+1] = args[i]
        end

        command_to_buffer(cmd, ".", "*grep*", choose_errors_from_buf)
    end,
    
    ['!'] = function(args, range)
        local command = {}
        for i=2,#args do
            command[#command+1] = args[i]
        end
        if range == nil then
            ui.print("Running: " .. table.concat(command, " "))
            command_to_buffer(command, "./", "*shell*")
        else
            buffer:set_selection(buffer:position_from_line(range[2]),
                                 buffer:position_from_line(range[1]-1))
            textadept.editing.filter_through(table.concat(command, " "))
        end
    end,
    
    cb = function(args)
        choose_errors_from_buf(buffer)
    end,
    cn = function(args)
        local clist = state.clists[state.clistidx]
        if not clist then
            ex_error("No clist")
            return
        end
        local idx = clist.idx
        if idx >= #clist.list then
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
            vi_tags.goto_tag(tags[1])
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
    s = command_substitute,

    -- Some commands for textadept functionality.
    compile = textadept.run.compile,
    build = function()
        for _,buf in ipairs(_BUFFERS) do
            if buf._type == _L['[Message Buffer]'] then
                buf:clear_all()
                break
            end
        end
        textadept.run.build()
    end,
    run = textadept.run.run,
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
        local cmd, range = M.parse_ex_cmd(command)
        -- For now, a very simple command parser
        local handler = M.ex_commands[cmd[1]]

        ui.command_entry.entry_text = ""
        if handler ~= nil then
            handler = debugwrap(handler)

            state.last_cmd = command
            result = handler(cmd, range)
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
    local pat = vi_regex.compile(text)

    for k,buf in ipairs(_BUFFERS) do
        if buf.filename and pat and pat:match(buf.filename) then
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

local function matching_commands(text)
    local commands = {}
    local tlen = #text

    for k,_ in pairs(M.ex_commands) do
        if k:sub(1, tlen) == text then
          commands[#commands+1] = k
        end
    end
    return commands
end

local function complete_commands(pos, text)
    local commands = matching_commands(text)
    if #buffers == 1 then
        ui_ce.entry_text = string.sub(ui_ce.entry_text, 1, pos-1) .. buffers[1]
    else
        ui_ce.show_completions(commands)
    end
end

local function complete_files(pos, text)
    local files = get_matching_files(text)
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
    wq = complete_files,
    x = complete_files,
    tag = complete_tags,
    tsel = complete_tags,
    find = complete_paths,
    grep = complete_files,  -- for the search root
}

-- Completers for the new entry method
M.completions_word = {
    b = matching_buffers,
    e = function(text) return get_matching_files(text, true) end,
    w = vi_find_files.matching_files_nopat,
    wq = vi_find_files.matching_files_nopat,
    x = vi_find_files.matching_files_nopat,
    split = get_matching_files,
    vsplit = get_matching_files,
    tag = vi_tags.match_tag,
    tsel = vi_tags.match_tag,
    find = find_matching_files,
    grep = get_matching_files,  -- for the search root
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
            debugwrap(complete_commands(1, lastword))
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
    elseif cmd == word then
        return matching_commands(cmd)
    else
        return {}
    end
end

if M.use_vi_entry then
    vi_entry = require('vi_ce_entry')
    state.entry_state = vi_entry.new(':', handle_ex_command, do_complete)
end

function M.start(exitfunc)
    state.exitfunc = exitfunc
    state.histidx = #state.history + 1  -- new command is after the end of the history

    -- If using vi_entry, the current buffer won't be easily available.
    state.cur_buf = buffer
    if M.use_vi_entry then
        state.entry_state:start()
    else
        ui.command_entry.entry_text = ""
        ui.command_entry.enter_mode('vi_ex_command')
    end
end

--- Run an ex command that may not have come directly from the command line.
function M.run_ex_command(text)
    handle_ex_command(text)
end

-- Repeat the previous command, if any.
function M.repeat_last_command()
    if state.last_cmd then
        handle_ex_command(state.last_cmd)
    end
end

--- Add a new custom ex command.
function M.add_ex_command(name, handler, completer)
    M.ex_commands[name] = handler
    M.completions[name] = completer
end

return M
