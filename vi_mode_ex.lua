-- Handle the ex buffer emulation
-- Modeled on textadept's command_entry.lua
local M = {}
local vi_tags = require('vi_tags')
local vi_quickfix = require('vi_quickfix')
local vi_regex = require('regex.regex')
M.use_vi_entry = true
local vi_entry
local lpeg = require 'lpeg'
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

local matching_files

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
local ex_addr = Cf(ex_addr_base * (addr_adder + addr_subber)^0, add)

-- And a range returns a pair of line numbers { start, end }
local ex_range = ((((ex_addr + P(0)/_curline) * "," * ex_addr)/_mk_range) + (ex_addr / _mk_range_single) + (P(0) * Cc(nil)))

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

local ex_cmd = Ct(ex_cmd_s + ex_cmd_simple)

local ex_cmdline = ex_range * (ex_ws ^ 0) * ex_cmd

-- Parse an ex command, including optional range and command
function M.parse_ex_cmd(s)
    local range, args = ex_cmdline:match(s)

    return args, range
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

-- Find files matching a Regex pattern (or a string match)
local function find_matching_files(pattern)
    local results = {}
    local pat = vi_regex.compile(pattern)
    local function f(filename)
        if (pat and pat:match(filename)) or filename:find(pattern, 1, true) then
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

-- Jump to an item in a clist ({ text, path=filename, lineno=lineno, idx=idx })
-- Jump to a quickfix item
local function clist_go(item)
    io.open_file(item.path)
    buffer.goto_line(item.lineno-1)
    state.clists[state.clistidx].idx = item.idx
end

--- Expand a filename:
--    ~/foo -> $HOME/foo
local function expand_filename(s)
    if s:sub(1,2) == "~/" then
        s = os.getenv("HOME") .. s:sub(2)
    end
    local files = matching_files(s, false)
    if #files >= 1 then return files[1] end
    return s
end

-- Parse the replacement string
local repl_chars = C((P(1) - S'&\\')^1)
-- Relies on the table of groups being the first extra parameter to lpeg.match.
local repl_ref = P"\\" * (C(R"09") * Carg(1)) / function(ref, groups) return groups[ref] or "" end
local amp_ref = P"&" * Carg(1) /function(groups) return groups["&"] end
local repl_quoted = P"\\" * C(P(1))
local repl_pat = Cf((repl_chars + repl_ref + amp_ref + repl_quoted) ^ 0, function(a,b) return a..b end)

local function command_substitute(args, range)
    local searchpat = args[2]
    local replace = args[3]
    local flagstring = args[4]
    local flags = {}
    cme_log('subst: pat=[['..searchpat..']], repl=[['..replace..']], flags=[['..flagstring..']]')
    
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
    for lineno = range[1], range[2] do
        local line = buffer:get_line(lineno)
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
--            local repl = replace:gsub("\\(%d)", function(ref)
--                      return groups[ref] or "<<<"..ref..":"..tostring(groups[ref])..">>>"
--                   end)
            line = line:sub(1,m._start-1) .. repl .. line:sub(m._end+1)
            -- Do the replace
            local linepos = buffer:position_from_line(lineno)
            buffer:set_selection(linepos+buffer:line_length(lineno), linepos)
            buffer:replace_sel(line)
            
            -- Keep looking?
            if flags.g then
                m = pat:match(line, m._start + #repl)
            else
                break
            end
        end
    end
    buffer:end_undo_action()
end

-- Take a buffer with error messages, and turn it into a quickfix list,
-- which is activated.
local function choose_errors_from_buf(buf)
    local results = vi_quickfix.quickfix_from_buffer(buf)
    if results then
        -- Push the results list to the stack
        state.clistidx = #state.clists+1
        state.clists[state.clistidx] = { list=results, idx=1 }
        choose_list('Errors', results, clist_go)
    end
end

function run_command_to_buf(command, workdir, buftype, on_finish)
    ui.print("Running: " .. table.concat(command, " "))
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
        msgbuf.clear_all()
    end
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
    local function doend()
        on_finish(msgbuf)
    end
    spawn(table.concat(command, " "), workdir, getoutput, getoutput, doend)
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
            -- Try as a regular expression too.
            local bufpat = vi_regex.compile(bufname)
            for i, buf in ipairs(_BUFFERS) do
                if buf and buf.filename and ((bufpat and bufpat:match(buf.filename)) or buf.filename:find(bufname, 1, true)) then
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
        run_command_to_buf(command, './', '*** make output ***', choose_errors_from_buf)
    end,

    -- Search files
    grep = function(args)
        local pat = args[2]
        if not pat then return end
        
        local re = vi_regex.compile(pat)

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
                if re:match(line) then
                    local idx = #results+1
                    local text = filename .. ":" .. lineno .. ":" .. line
                    results[idx] = { text, path=filename, lineno=lineno, idx=idx }
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

-- Escape a Lua pattern to make it an exact match.
-- TODO: find a more general place for this.
local function luapat_escape(s)
    -- replace metacharacters
    s = s:gsub("[%(%)%%%.%[%]%*%+%-%?]", function (s) return "%"..s end)

    -- ^ and $ only apply at the start/end
    if s:sub(1,1) == "^" then s = "%" .. s end
    if s:sub(-1,-1) == "$" then s = s:sub(1,-2) .. "%$" end
    return s
end

local ignore_complete_files = { ['.'] = 1 }
function do_matching_files(text, mk_matcher, escape)
    local patparts = {} -- the pieces of the pattern
    -- Split the pattern into parts separated by /
    if text then
        for part in text:gmatch('[^/]+') do
            table.insert(patparts, part)
        end
        -- If tab on trailing /, then will want to complete on files in the
        -- directory.
        if text:sub(-1) == '/' then
            table.insert(patparts, '')
        end
    end
    -- partmatches[n] is a list of matches for patparts[n] at that level
    local parts = { }
    -- Set of directories to look in
    local dirs = { }

    -- The start depends on whether the path is absolute or relative
    if text and text:sub(1, 1) == '/' then
        table.insert(dirs, '/')
    elseif patparts[1] == '~' then
        -- Handle ~/...
        table.insert(dirs, os.getenv("HOME") .. "/")
        -- Remove the initial ~
        table.remove(patparts, 1)
    else
        table.insert(dirs, './')
    end

    -- For each path section
    for level, patpart in ipairs(patparts) do
      local last = (level == #patparts)

      -- If the last part, then allow trailing parts
      -- TODO: if we complete from a middle-part, then
      -- this test should be for where the cursor is.
      local allow_wild_end = last

      -- The set of paths for the following loop
      local newdirs = {}
      local matcher = mk_matcher(patpart, allow_wild_end)

      -- For each possible directory at this level
      for _,dir in ipairs(dirs) do
        for fname in lfs.dir(dir) do
          if not ignore_complete_files[fname] and matcher(fname) then
            local fullpath
            if dir == "./" then
                fullpath = fname
            else
                fullpath = dir .. fname
            end
            local isdir = lfs.attributes(fullpath, 'mode') == 'directory'

            -- Record this path if it's not a non-directory with more path
            -- parts to go.
            if lfs.attributes(fullpath, 'mode') == 'directory' then
                table.insert(newdirs, fullpath .. '/')
            elseif last then
                table.insert(newdirs, fullpath)
            end
          end
        end
      end
      -- Switch to the next level of items
      dirs = newdirs
    end  -- loop through pattern parts

    -- Find out the set of components at each level
    -- parts[level] is a table { fname=1,fname2=1, fname,fname2}
    local parts = {}
    for _,res in ipairs(dirs) do
        local level = 1
        for piece in res:gmatch('[^/]*') do
            ps = parts[level] or {}
            parts[level] = ps

            if ps[piece] == nil then
              ps[piece] = 1
              table.insert(ps, piece)
            end
        end
    end

    -- Now rebuild the pattern, with some ambiguities removed
    local narrowed = false  -- whether we've added more unambiguous info
    local newparts = {}
    -- keep absolute or relative
    if text:sub(1,1) == '/' then
        table.insert(newparts,  '/')
    end
    for level,matches in ipairs(parts) do
        local last = (level == #parts)
        if #matches == 1 then
            -- Only one thing, so use that.
            local newpart = escape(matches[1])
            if newpart ~= patparts[level] then
                narrowed = true
            end
            table.insert(newparts, newpart)
            -- matches[fname] is true if all options are directories
            if last and matches[matches[1]] then
                table.insert(newparts, '/')
            end
        else
            table.insert(newparts, patparts[level])
        end
        if not last then table.insert(newparts, '/') end
    end
    local files
    if narrowed then
        files = { table.concat(newparts) }
    else
        files = {}
        table.sort(dirs)
        for i,d  in ipairs(dirs) do
            files[i] = escape(d)
        end
    end
    return files
end

local function mkmatch_luapat(pat, allow_wild_end)
    local fullpat = '^' .. pat
    if allow_wild_end then
        fullpat = fullpat .. '.*'
    end
    fullpat = fullpat .. '$'
    return function(text) 
        local result = text:match(fullpat)
        return result
    end
end

-- Find files with patterns
function matching_files(text, doescape)
    -- Escape by default
    local escape
    if doescape == nil or doescape then
        escape = luapat_escape
    else
        escape = function(s) return s end
    end
    -- Special case - a bare % becomes the current file's path.
    if text == "%" then
        return { escape(state.cur_buf.filename) }
    end

    return do_matching_files(text, mkmatch_luapat, escape)
end

local function mkmatch_null(pat, allow_wild_end)
    local escaped_pat = '^' .. luapat_escape(pat)
    if allow_wild_end then
        escaped_pat = escaped_pat .. '.*'
    end
    escaped_pat = escaped_pat .. '$'
    return function(text)
        local result = text:match(escaped_pat)
        return result
    end
end

-- Match filename exactly, with no escaping or wildcards etc.
function matching_files_nopat(text)
    local escape = function(s) return s end
    return do_matching_files(text, mkmatch_null, escape)
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
    grep = complete_files,  -- for the search root
}

-- Completers for the new entry method
M.completions_word = {
    b = matching_buffers,
    e = function(text) return matching_files(text) end,
    w = matching_files_nopat,
    split = matching_files,
    vsplit = matching_files,
    tag = vi_tags.match_tag,
    tsel = vi_tags.match_tag,
    find = find_matching_files,
    grep = matching_files,  -- for the search root
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

if M.use_vi_entry then
    vi_entry = require('vi_entry')
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
