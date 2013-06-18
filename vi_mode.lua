local M = {}

M.ex_mode = require 'vi_mode_ex'
M.search_mode = require 'vi_mode_search'
res, M.kill = pcall(require,'kill')
if not res then
    -- The extension module may not be available.
    M.kill = { kill=function() end }
end
--[[
Make textadept behave a bit like vim.
--]]

-- The current mode (command, insert, etc.)
COMMAND = "vi_command"
INSERT = "vi_insert"
mode = nil  -- initialised below

local debug = false
-- If true, then convert alt-x or meta-x into ESC x (NCURSES only)
M.strip_alt = false

function dbg(...)
    --if debug then print(...) end
    if debug then
        gui._print("vimode", ...)
    end
end

function enter_mode(m)
    mode = m

    dbg("Enter mode:" .. m.name)
    keys.MODE = m.name

    if m.restart then
        local restart = m.restart
        m.restart = nil
        restart()
    end

    update_status()
end

function do_keys(...)
    local result = nil
    for _,sym in ipairs({...}) do
        handler = mode.bindings[sym]
        if handler then result = handler(sym) end
    end
    return result
end

function key_handler_common(code, shift, ctrl, alt, meta)
    if M.strip_alt and NCURSES and (meta or alt) then
        -- Inject an ESC followed by the un-alt/meta key.
        events.emit(events.KEYPRESS, 7, false, false, false, false)
        events.emit(events.KEYPRESS, code, shift, ctrl, false, false)
        return true
    end

    -- This logic borrowed from core/keys.lua from textadept.
    local sym = code < 256 and (not CURSES or code ~= 7) and string.char(code) or
                                                           keys.KEYSYMS[code]

    if not sym then return end -- ignore unknown keys

    -- dbg("Code:", code)
    if alt then sym = 'a' .. sym end
    if ctrl then sym = 'c' .. sym end
    if shift then sym = 's' .. sym end -- Need to change for alphabetic

    if state.pending_keyhandler ~= nil then
        -- Call this instead
        state.pending_keyhandler(sym)
        state.pending_keyhandler = nil
	return true
    end
end
events.connect(events.KEYPRESS, key_handler_common, 1)

function update_status()
    if mode.name == COMMAND then
        gui.statusbar_text = "(command)"
    else
        gui.statusbar_text = "-- INSERT --"
    end
end
events.connect(events.UPDATE_UI)

-- Various state we modify
state = {
    numarg = 0,  -- The numeric prefix (eg for 10j to go down 10 times)
    last_numarg = 0,  -- The last numeric argument used (for repeating previous)

    pending_action = nil,  -- An action waiting for a movement
    pending_command = nil, -- The name of the editing command pending

    pending_keyhandler = nil, -- A function to call on the next keypress
    last_action = no_action,

    command_cut = nil,   -- Whether the last cut was char or line oriented

    marks = {},

    last_insert_string = nil, -- Last inserted text
    insert_pos = nil,
}
-- Make state visible.
M.state = state

local self_insert_mt = {
    __index = function(tab, key)
        if type(key) == "string" then
            if string.len(key) == 1 then
                return function() buffer.add_text(key) end
            end
        end
    end,
}
local self_insert_tab = setmetatable({}, self_insert_mt)


--- Mark the start of some potential text entry.
local function insert_start_edit()
    state.insert_pos = buffer.current_pos
end

--- Mark the end of an edit (either exiting insert mode, or moving the
--  cursor).
local function insert_end_edit()
    -- If the cursor moved, then assume we've inserted text.
    if state.insert_pos < buffer.current_pos then
        local curpos = buffer.current_pos
        buffer.set_selection(state.insert_pos, curpos+1)
        state.last_insert_string = buffer.get_sel_text()
        buffer.clear_selections()
        buffer.current_pos = curpos
        buffer.goto_pos(curpos)
    end
end

--- Return a function which does the same as its argument, but also
--  restarts the undo action.
local function break_edit(f)
    return function()
        buffer.end_undo_action()
        insert_end_edit()
        f()
        insert_start_edit()
        buffer.begin_undo_action()
    end
end

mode_insert = {
    name = INSERT,

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_insert.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        esc = function()
            insert_end_edit()
	        local line, pos = buffer.get_cur_line()
            if pos > 0 then buffer.char_left() end
            enter_mode(mode_command)
        end,

        up    = break_edit(buffer.line_up),
        down  = break_edit(buffer.line_down),
        left  = break_edit(buffer.char_left),
        right = break_edit(buffer.char_right),
        home  = break_edit(buffer.vc_home),
        ['end']   = break_edit(buffer.line_end),
        pgup =  break_edit(buffer.page_up),
        pgdn =  break_edit(buffer.page_down),

        -- These don't quite behave as vim, but they'll do for now.
        cp = _M.textadept.editing.autocomplete_word,
        cn = _M.textadept.editing.autocomplete_word,

        cv = self_insert_tab,
    }
}

local function no_action() end

-- Run an action, as a single undoable action.
-- Passes the current repeat count (prefix count) to it,
-- and saves it to be recalled with '.'.
function do_action(action)
    state.last_action = action

    raw_do_action(action)
end

-- Like do_action but doesn't save to last_action
function raw_do_action(action)
    local rpt = 1

    if state.numarg > 0 then
        rpt = state.numarg
        state.numarg = 0
    end
    state.last_numarg = rpt

    buffer.begin_undo_action()
    action(rpt)
    buffer.end_undo_action()
end

function addarg(n)
  state.numarg = state.numarg * 10 + n
  dbg("New numarg: " .. tostring(state.numarg))
end
-- Return a handler for digit n
function dodigit(n)
    return function() addarg(n) end
end

local function do_movement(f, linewise)
    -- Apply a movement command, which may be attached to an editing action.
    if state.pending_action == nil then
        -- no action, just move
        f()
    else
        -- Select the region and apply
        -- TODO: handle line-oriented actions differently
        -- Allow the action to be repeated
        do
          local move = f
          local action = state.pending_action
          state.last_action = function (rpt)

            local start = buffer.current_pos
            move()
            local end_ = buffer.current_pos
            if start > end_ then
                start, end_ = end_, start
            end
            if linewise then
                start = buffer.position_from_line(buffer.line_from_position(start))

                local line_end = buffer.line_from_position(end_)
                end_ = buffer.position_from_line(line_end) +
                                      buffer.line_length(line_end)
            end
            action(start, end_)
          end
        end
        state.last_action(1)
        state.pending_action = nil
    end
end

local function repeatable(f)
    return function(rpt)
        for i=1,rpt do f() end
    end
end

local function repeat_arg(f)
    return function()
        local times = state.numarg
        state.numarg = 0
        if times == 0 then times = 1 end
        for i=1,times do
            f()
        end
    end
end

-- Wrapper to turn a simple command into one which uses the numeric prefix
local function mk_movement(f, linewise)
  -- Run f numarg times (if numarg is non-zero) and clear
  -- numarg
  return function()
     do_movement(f, linewise)
  end
end

function vi_right()
    local line, pos = buffer.get_cur_line()
	local docpos = buffer.current_pos
	local length = buffer.line_length(buffer.line_from_position(docpos))
	if pos < (length - 2) then
	    buffer.char_right()
	end
end

local function enter_command()
    enter_mode(mode_command)
end

local function enter_insert_then_end_undo(cb)
    enter_mode(mode_insert)
    insert_start_edit()
    mode_command.restart = function()
        insert_end_edit()
        buffer.end_undo_action()
        if cb then cb() end
    end
end
local function enter_insert_with_undo(cb)
    buffer.begin_undo_action()
    enter_insert_then_end_undo(cb)
end

--- Function to be called after an insert mode operation.
--  Sets the last action to call prep_f() to prepare (eg go to end of
--  line, etc.) and then insert the last-inserted text.
local function post_insert(prep_f)
  return function()
          -- This function is run when exiting from undo
          state.last_action = function(rpt)
            local rpt = rpt
            if rpt < 1 then rpt = 1 end
            buffer.begin_undo_action()
            prep_f()
            for i=1,rpt do
                buffer.add_text(state.last_insert_string)
            end
            buffer.end_undo_action()
          end
        end
end

local function wrap_lines(lines, width)
  local alltext = table.concat(lines, " ")
  local result = {}

  local linelen = 0 -- length of this line
  local line = {} -- parts of this line

  for word in string.gmatch(alltext, "[^%s]+") do
      local newlen = linelen + string.len(word) + 1
      if linelen > 0 and newlen > width then
          -- Doesn't fit, so start a new line
          table.insert(result, table.concat(line, " "))
          line = {}
          linelen = 0
          newlen = string.len(word)
      end

      table.insert(line, word)
      linelen = newlen
  end
  if linelen > 0 then
    table.insert(result, table.concat(line, " "))
  end
  return result
end

mode_command = {
    name = COMMAND,

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_command.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        -- movement commands
        h = mk_movement(repeat_arg(function ()
	  local line, pos = buffer.get_cur_line()
	  if pos > 0 then buffer.char_left() end
        end), false),
        l = mk_movement(repeat_arg(function()
          vi_right()
        end), false),
        j = mk_movement(repeat_arg(buffer.line_down), true),
        k = mk_movement(repeat_arg(buffer.line_up), true),
        w = mk_movement(repeat_arg(buffer.word_right), false),
        b = mk_movement(repeat_arg(buffer.word_left), false),

        H = mk_movement(function()
             -- We can't use goto_line here as it scrolls the window slightly.
             local top_line = buffer.first_visible_line
             local pos = buffer.position_from_line(top_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end, true),
        M = mk_movement(function()
             buffer.goto_line(buffer.first_visible_line + buffer.lines_on_screen/2)
            end, true),
        L = mk_movement(function()
             local bot_line = buffer.first_visible_line + buffer.lines_on_screen - 1
             local pos = buffer.position_from_line(bot_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end, true),
        ['%'] = mk_movement(function()
             local pos = buffer.brace_match(buffer.current_pos)
             if pos >= 0 then
                 buffer.goto_pos(pos)
             else
                 -- Should search for the next brace on this line.
             end
        end, false),

	-- Mark actions
	m = function()
	    state.pending_keyhandler = function(sym)
	        -- TODO: Marks should move if text is inserted before them.
	        if string.match(sym, "^%a$") then
		    -- alphabetic, so store the mark
		    state.marks[sym] = buffer.current_pos
		end
	    end
	end,
	['\''] = setmetatable({}, {
        __index = function(t, key)
	        if string.match(key, "^%a$") then
		       -- alphabetic, so restore the mark
               return function()
                 newpos = state.marks[key]
                 if newpos ~= nil then
		 	        do_movement(function () buffer.goto_pos(newpos) end, true)
		         end
		       end
	        end
        end}),
	['`'] = setmetatable({}, {
        __index = function(t, key)
	        if string.match(key, "^%a$") then
		       -- alphabetic, so restore the mark
               return function()
                 newpos = state.marks[key]
                 if newpos ~= nil then
		 	        do_movement(function () buffer.goto_pos(newpos) end, false)
		         end
		       end
	        end
        end}),

	['0'] = function()
             if state.numarg == 0 then
                mk_movement(buffer.home, false)()
             else
                addarg(0)
	     end
          end,
	['1'] = dodigit(1),
	['2'] = dodigit(2),
	['3'] = dodigit(3),
	['4'] = dodigit(4),
	['5'] = dodigit(5),
	['6'] = dodigit(6),
	['7'] = dodigit(7),
	['8'] = dodigit(8),
	['9'] = dodigit(9),
	['$'] = mk_movement(function()
		 -- Stop just before the end
		 buffer.line_end()
		 local line, pos = buffer.get_cur_line()
         -- If inside an action (eg d$) then we really do go to the end of
         -- the line rather than one short.
		 if pos > 0 and state.pending_action == nil then buffer.char_left() end
	       end, false),
	['^'] = mk_movement(function()
		   buffer.home()    -- Go to beginning of line
		   buffer.vc_home()  -- swaps between beginning/first visible
                end, false),
	G = mk_movement(function()
	       if state.numarg > 0 then
                   -- Textadept does zero-based line numbers.
		   buffer.goto_line(state.numarg - 1)
		   state.numarg = 0
	       else
                 -- With no arg, go to last line.
                 buffer.document_end()
		 buffer.home()
	       end
	   end, true),

	-- edit mode commands
        i = function() enter_insert_with_undo(post_insert(function() end)) end,
     	a = function()
             buffer.char_right()
             enter_insert_with_undo(post_insert(buffer.char_right))
        end,
        A = function()
             buffer.line_end()
             enter_insert_with_undo(post_insert(buffer.line_end))
        end,
        o = function()
            buffer.line_end()
            buffer.begin_undo_action()
            buffer.new_line()
            enter_insert_then_end_undo(post_insert(function()
                buffer.line_end()
                buffer.new_line()
            end))
        end,
        O = function()
            local function ins_new_line()
              buffer.home()
              buffer.begin_undo_action()
              if buffer.current_pos == 0 then
                 -- start of buffer
                 buffer.new_line()
                 buffer.char_left()  -- position cursor at start of the inserted
                                     -- line
              else
                 buffer.char_left()
                 buffer.new_line()
              end
            end
            ins_new_line()
            enter_insert_then_end_undo(post_insert(ins_new_line))
        end,
	r = function()
	    state.pending_keyhandler = function(sym)
	        -- TODO: Marks should move if text is inserted before them.
	        if string.match(sym, "^.$") then
		      -- Single character, so buffer.replace.
                   do_action(function(rpt)
                       here = buffer.current_pos
                       while rpt > 0 do
                           buffer.set_sel(here, here+1)
                           buffer.replace_sel(sym)
                           buffer.current_pos = here+1

                           here = here + 1
                           rpt = rpt - 1
                       end
                     end)
		    end
	    end
	end,
        ['~'] = function()
            do_action(repeatable(function()
                buffer.set_selection(buffer.current_pos, buffer.current_pos+1)
                local c = buffer.get_sel_text()
                local newc = string.upper(c)
                if newc == c then newc = string.lower(c) end
                buffer.replace_sel(newc)
            end))
        end,

        J = function()
           do_action(function (rpt)
               local lines = rpt
               if rpt < 2 then rpt = 2 end

               for i=1,rpt-1 do
                   buffer.line_end()
                   buffer.target_start = buffer.current_pos
                   buffer.target_end = buffer.current_pos + 1
                   buffer.lines_join()
               end
           end)
        end,
        g = {
            q = function()
                state.pending_action = function(start, end_)
                   raw_do_action(function()
-- local dbg = {}
                      local width = 78 -- FIXME: configurable
                      local line_start = buffer.line_from_position(start)
                      local line_end = buffer.line_from_position(end_)
                      local pos_start = buffer.position_from_line(line_start)
                      local pos_end = buffer.position_from_line(line_end) +
                                      buffer.line_length(line_end)

                      local prefix = nil
                      local lines_to_wrap = {}

                      while line_start <= (line_end+1) do
-- table.insert(dbg, "Processing line "..line_start)
                        local line, new_prefix
                        if line_start <= line_end then
                            line = buffer.get_line(line_start)
                            new_prefix = string.match(line, "^[>| ]*")
                        else
                            -- A dummy end iteration to output the reuslt
                            line = "dummy line"
                            new_prefix = "invalid prefix"
                        end
                        if prefix == nil then prefix = new_prefix end
                        if new_prefix ~= prefix then
                          -- New prefix; Emit previous wrapped lines and
                          -- start again
                          local endpos = buffer.position_from_line(line_start)
                          local new_lines = wrap_lines(lines_to_wrap, width-string.len(prefix))
                          local new_parts = {}
                          for _,l in ipairs(new_lines) do
                            table.insert(new_parts,prefix)
                            table.insert(new_parts,l)
                            table.insert(new_parts,"\n")
                          end
                          buffer.set_selection(pos_start, endpos)
                          local orig_end_line = buffer.line_from_position(endpos)
                          local new_text = table.concat(new_parts)
-- table.insert(dbg, "Replacing "..pos_start.."-"..endpos.." with <"..new_text..">")
                          buffer.replace_sel(new_text)
                          pos_start = buffer.selection_end
                          local new_end_line = buffer.line_from_position(pos_start)
                          buffer.clear_selections()

                          -- Adjust line counts after wrapping text
                          line_start = line_start + (new_end_line - orig_end_line)
                          line_end= line_end + (new_end_line - orig_end_line)

                          prefix = new_prefix
                          lines_to_wrap = {}
                          buffer.goto_pos(pos_start)
                          buffer.line_up()
                        end
                        table.insert(lines_to_wrap,
                                     string.sub(line,
                                                string.len(prefix)))
                        line_start = line_start + 1
                      end
-- gui.print(table.concat(dbg, "\n"))
                  end)
              end
              state.pending_command = 'gq'
            end,
        },

        d = function()
           if state.pending_action ~= nil and state.pending_command == 'd' then
              -- The 'dd' command
              local rept = 1
              local lineno = buffer.line_from_position(buffer.current_pos)

              do_action(function(rpt)
                  state.command_cut = 'line'
                  buffer.home()  -- Start of line
                  local start = buffer.current_pos
                  for i = 1,rpt do
                      buffer.line_down()
                  end
                  local endpos = buffer.current_pos
                  buffer.set_selection(start, endpos)
                  buffer.cut()
              end)

              state.pending_action, state.pending_command, state.numarg = nil, nil, 0
           else
              state.pending_action = function(start, end_)
                  raw_do_action(function()
                      --
                      buffer.set_sel(start, end_)
                      buffer.cut()
                  end)
              end
              state.pending_command = 'd'
           end
        end,

         c = function()
              state.pending_action = function(start, end_)
                  buffer.set_sel(start, end_)
                  buffer.begin_undo_action()
                  buffer.cut()
                  enter_insert_then_end_undo()
              end
              state.pending_command = 'c'
         end,

        D = function()
            do_keys('d', '$')
        end,

        C = function()
            do_keys('c', '$')
        end,

        x = function()
            do_action(function(rept)
                local here = buffer.current_pos
                local text, _ = buffer.get_cur_line()
                local lineno = buffer.line_from_position(buffer.current_pos)
                local lineend = buffer.line_end_position[lineno]
                local endpos = here + rept
                if endpos > lineend then endpos = lineend end
                if endpos == pos and string.len(text) > 1 then
                    -- If at end of line, delete the previous char.
                    here = here - 1
                end
                buffer.set_sel(here, endpos)
                buffer.cut()
                state.command_cut = 'char'
            end)
      end,

         ['>'] = function()
              -- TODO: add support for >> (ideally generically)
              state.pending_action = function(start, end_)
                  buffer.set_sel(start, end_)
                  buffer.tab()
              end
              state.pending_command = '='
         end,

        p = function()
            if state.command_cut == 'line' then
                -- Paste a new line.
                do_action(repeatable(function()
                    buffer.line_end()
                    buffer.goto_pos(buffer.current_pos + 1)
                    buffer.paste()
                    buffer.line_up()
                end))
            else
                vi_right()
                buffer.paste()
            end
        end,

        -- edit commands
	u = buffer.undo,
	cr = buffer.redo,
        ['.'] = function()
              -- Redo the last action, taking into account possible prefix arg.
              local rpt = state.last_numarg
              if state.numarg > 0 then
                  rpt = state.numarg
                  state.numarg = 0
                  state.last_numarg = rpt
              end
              buffer.begin_undo_action()
              state.last_action(rpt)
              buffer.end_undo_action()
           end,

	-- Enter ex mode command
	[':'] = function() M.ex_mode.start(enter_command) end,
	['/'] = function() M.search_mode.start(enter_command) end,
	['?'] = function() M.search_mode.start_rev(enter_command) end,
        n = M.search_mode.restart,
        N = M.search_mode.restart_rev,
        ['*'] = M.search_mode.search_word,
        ['#'] = M.search_mode.search_word_rev,

    -- Views and buffers
    cw = {
        cw = { gui.goto_view, 1, true },  -- cycle between views
    },

    -- Misc: suspend the editor
    cz = M.kill.kill,

    },
}

-- Fall back to main keymap for any unhandled keys
local keys_mt = {
	__index = keys
}

keys[COMMAND] = setmetatable(mode_command.bindings, keys_mt)
keys[INSERT] = setmetatable(mode_insert.bindings, keys_mt)

-- Since it's currently easy to escape from the vi modes to the default mode,
-- make sure we can get back to it from default mode.
keys.esc = function() enter_mode(mode_command) end

-- Disable "normal" keys in command mode if I haven't bound them explicitly.
local function set_default_key(k)
    if mode_command.bindings[k] == nil then
        mode_command.bindings[k] = function()
		gui.statusbar_text = "Unbound key"
	     end
    end
end

for i = 0,25 do
    k = string.char(i + string.byte("a"))
    set_default_key(k)
    set_default_key(string.upper(k))
end

enter_mode(mode_command)

function M.enter_cmd() enter_mode(mode_command) end

-- Return to command mode when switching buffers
events.connect(events.BUFFER_BEFORE_SWITCH, function()
    if mode.name ~= COMMAND then
        M.enter_cmd()
    end
end)

return M
