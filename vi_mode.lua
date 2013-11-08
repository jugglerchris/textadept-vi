local M = {}
local lpeg = require'lpeg'

------ Configuration (should make it possible to pass it in) ------
-- If true, then convert alt-x or meta-x into ESC x (NCURSES only).  This means
-- that you can no longer use alt-key bindings, but means that you can quickly
-- type ESC followed by vi commands without waiting for the ESC to time out.
M.strip_alt = true
-- If true, then take over the main keymap rather than putting the command mode bindings
-- in a separate keymap.
M.vi_global = true

M.ex_mode = require 'vi_mode_ex'
M.search_mode = require 'vi_mode_search'
M.tags = require 'vi_tags'
M.lang = require 'vi_lang'
local vi_tags = M.tags
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

function dbg(...)
    --if debug then print(...) end
    if debug then
        ui._print("vimode", ...)
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
    if M.strip_alt and CURSES and (meta or alt) then
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

-- Various state we modify
state = {
    numarg = 0,  -- The numeric prefix (eg for 10j to go down 10 times)
    last_numarg = 0,  -- The last numeric argument used (for repeating previous)

    pending_action = nil,  -- An action waiting for a movement
    pending_command = nil, -- The name of the editing command pending

    pending_keyhandler = nil, -- A function to call on the next keypress
    last_action = no_action,

    marks = {},

    last_insert_string = nil, -- Last inserted text
    insert_pos = nil,
    
    errmsg = '',              -- error from a command
    
    registers = {}            -- cut/paste registers
}

--- Return the buffer-specific vi state.
local function buf_state(buf)
    if not buf._vi then
        buf._vi = {}
    end
    return buf._vi
end

-- Make state visible.
M.state = state

function M.err(msg)
    state.errmsg = msg
end

function update_status()
    local err = state.errmsg
    local msg

    if mode.name == COMMAND then
        msg = "(command) "
    else
        msg = "-- INSERT -- "
    end
    msg = msg .. err
    ui.statusbar_text = msg

    state.errmsg = ''
end
events.connect(events.UPDATE_UI, update_status)


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

--- Delete a range from this buffer, and save in a register.
--  If the register is not specified, use the unnamed register ("").
local function vi_cut(start, end_, linewise, register)
    buffer.set_sel(start, end_)
    local text = buffer.get_sel_text()
    buffer.cut()
    state.registers[register or '"'] = {text=text, line=linewise}
end

--- Paste from a register (by default the unnamed register "")
--  If after is true, then will paste after the current character or line
--  (depending on whether the buffer was line or character based)
local function vi_paste(after, register)
    local buf = state.registers[register or '"']
    if not buf then return end
    
    local pos = buffer.current_pos
    
    if buf.line then
        local lineno = buffer.line_from_position(pos)
        if after then
            lineno = lineno + 1
        end
        pos = buffer:position_from_line(lineno)
        buffer:goto_pos(pos)
    else
        if after then pos = pos + 1 end
    end
    buffer:insert_text(pos, buf.text)
end

-- Return the number of characters on this line, without
-- line endings.
local function line_length(lineno)
	return buffer.line_end_position[lineno] - buffer.position_from_line(lineno)
end

---  Move the cursor down one line.
-- 
local function vi_down()
    local bufstate = buf_state(buffer)
    
    local lineno = buffer.line_from_position(buffer.current_pos)
    local linestart = buffer.position_from_line(lineno)
    if lineno < buffer.line_count then
        local ln = lineno + 1
        local col = bufstate.col or (buffer.current_pos - linestart)
        bufstate.col = col  -- Try to stay in the same column
        if col >= line_length(ln) then
            col = line_length(ln) - 1
        end
        if col < 0 then col = 0 end
        buffer.goto_pos(buffer.position_from_line(ln) + col)
    end
end

---  Move the cursor up one line.
-- 
local function vi_up()
    local bufstate = buf_state(buffer)
    local lineno = buffer.line_from_position(buffer.current_pos)
    local linestart = buffer.position_from_line(lineno)
    if lineno >= 1 then
        local ln = lineno - 1
        local col = bufstate.col or buffer.current_pos - linestart
        bufstate.col = col
        if col >= line_length(ln) then
            col = line_length(ln) - 1
        end
        if col < 0 then col = 0 end
        buffer.goto_pos(buffer.position_from_line(ln) + col)
    end
end

-- Move to the start of the next word
local function vi_word_right()
    buffer.word_right()
    local lineno = buffer.line_from_position(buffer.current_pos)
    local col = buffer.current_pos - buffer.position_from_line(lineno)
    -- Textadept sticks at the end of the line.
    if col >= line_length(lineno) then
        if lineno == buffer.line_count-1 then
            buffer:char_left()
        else
            buffer:word_right()
        end
    end
end

-- Move to the start of the previous word
local function vi_word_left()
    buffer.word_left()
    local lineno = buffer.line_from_position(buffer.current_pos)
    local col = buffer.current_pos - buffer.position_from_line(lineno)
    -- Textadept sticks at the end of the line.
    if col >= line_length(lineno) then
        buffer:word_left()
    end
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

        up    = break_edit(vi_up),
        down  = break_edit(vi_down),
        left  = break_edit(buffer.char_left),
        right = break_edit(buffer.char_right),
        home  = break_edit(buffer.vc_home),
        ['end']   = break_edit(buffer.line_end),
        pgup =  break_edit(buffer.page_up),
        pgdn =  break_edit(buffer.page_down),

        -- These don't quite behave as vim, but they'll do for now.
        cp = textadept.editing.autocomplete_word,
        cn = textadept.editing.autocomplete_word,

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
            action(start, end_, move, linewise)
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
     -- If this was a horizontal movement, then forget what column
     -- we were trying to stay in.
     if not linewise then buf_state(buffer).col = nil end
  end
end

function vi_right()
    local line, pos = buffer.get_cur_line()
	local docpos = buffer.current_pos
    -- Don't include line ending characters, so we can't use buffer.line_length().
    local lineno = buffer:line_from_position(docpos)
	local length = line_length(lineno)
	if pos < (length - 1) then
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
        j = mk_movement(repeat_arg(vi_down), true),
        k = mk_movement(repeat_arg(vi_up), true),
        w = mk_movement(repeat_arg(vi_word_right), false),
        b = mk_movement(repeat_arg(vi_word_left), false),
        e = mk_movement(repeat_arg(function()
                                      buffer.char_right()
                                      buffer.word_right_end() 
                                      local lineno = buffer:line_from_position(buffer.current_pos)
                                      local col = buffer.current_pos - buffer.position_from_line(lineno)
                                      if col == 0 then
                                        -- word_right_end sticks at start of
                                        -- line.
                                        buffer:word_right_end()
                                      end
                                      buffer.char_left()
                                   end), false),

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
             local orig_pos = buffer.current_pos
             -- Simple case: match on current character
             local pos = buffer.brace_match(buffer.current_pos)
             if pos >= 0 then
                 buffer.goto_pos(pos)
                 return
             end
             
             -- Get the current line and position, as we'll need it for
             -- the next tests.
             local line, idx = buffer:get_cur_line()
             
             -- Are we on a C conditional?
             do
                 -- TODO: cache the pattern
                 local P = lpeg.P
                 local S = lpeg.S
                 local C = lpeg.C
                 local R = lpeg.R
                 
                 local ws = S' \t'
                
                 local cpppat = (ws ^ 0) * P"#" * (ws ^ 0) * 
                            (C(P"if" + P"elif" + P"else"+ P"ifdef" + P"endif") + -R("az", "AZ", "09"))
                 
                 local cppcond = cpppat:match(line)
                 
                 -- How each operation adjusts the nesting level
                 local nestop = {
                     ['if'] = 1,
                     ['ifdef'] = 1,
                     ['else'] = 0,
                     ['elif'] = 0,
                     ['endif'] = -1,
                 }
                 
                 local lineno = buffer.line_from_position(buffer.current_pos)
                 local level = 0
                 if cppcond == 'endif' then
                     -- Search backwards for the original if/ifdef
                     while lineno > 0 do
                         lineno = lineno - 1
                         line = buffer:get_line(lineno)
                         cppcond = cpppat:match(line)
                         if nestop[cppcond] == 1 and level == 0 then
                             -- found!
                             buffer.goto_line(lineno)
                             return
                         elseif cppcond then
                             level = level + nestop[cppcond]
                         end
                     end
                 elseif cppcond then
                     -- Search forwards for matching level
                     local lines = buffer.line_count
                     while lineno < lines do
                         lineno = lineno + 1
                         line = buffer:get_line(lineno)
                         cppcond = cpppat:match(line)
                         if cppcond and level == 0 then
                             -- found!
                             buffer.goto_line(lineno)
                             return
                         elseif cppcond then
                             level = level + nestop[cppcond]
                         end
                     end
                 end
             end
             
             -- Try searching forwards on the line
             local bracketpat =  "[%(%)<>%[%]{}]"
             
             local newidx, _, c = line:find(bracketpat, idx+1)
             if newidx then
                 pos = buffer:brace_match(orig_pos + newidx - idx - 1)
                 if pos >= 0 then
                     buffer:goto_pos(pos)
                 end
                 return
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
               if rpt < 2 then rpt = 2 end

               for i=1,rpt-1 do
                   buffer.line_end()
                   buffer.target_start = buffer.current_pos
                   buffer.target_end = buffer.current_pos + 1
                   
                   -- Avoid an infinite loop when trying to join past the end.
                   if buffer.target_end > buffer.text_length then break end
                   
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
                            -- A dummy end iteration to output the result
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
-- ui.print(table.concat(dbg, "\n"))
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
                  local bufstate = buf_state(buffer)
                  buffer:home()  -- Start of line
                  bufstate.col = nil  -- don't try to jump to the wrong column.
                  
                  local start = buffer.current_pos
                  for i = 1,rpt do
                      vi_down()
                  end
                  local endpos = buffer.current_pos
                  vi_cut(start, endpos, true)
              end)

              state.pending_action, state.pending_command, state.numarg = nil, nil, 0
           else
              state.pending_action = function(start, end_, move, linewise)
                  raw_do_action(function()
                      --
                      vi_cut(start, end_, linewise)
                  end)
              end
              state.pending_command = 'd'
           end
        end,

         c = function()
              state.pending_action = function(start, end_, move, linewise)
                  buffer.begin_undo_action()
                  vi_cut(start, end_, linewise)
                  enter_insert_then_end_undo(post_insert(function()
                      local start = buffer.current_pos
                      move()
                      local end_ = buffer.current_pos
                      vi_cut(start, end_, linewise)
                  end))
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
                vi_cut(here, endpos, false)
            end)
      end,

         ['>'] = function()
              -- TODO: add support for >> (ideally generically)
                state.pending_action = function(start, end_)
                    buffer.set_sel(start, end_)
                    buffer.tab()
                end
              state.pending_command = '>'
         end,
         
         -- Re-indent the range
         ['='] = function()
           state.pending_action = function(start, end_)
             local line_start = buffer.line_from_position(start)
             local line_end = buffer.line_from_position(end_)
             local ff = io.open("eq_test.txt", "w")
             local function f(msg) ff:write(msg .. "\n") ff:flush() end
             local pat = M.lang.indents.xml.indent
             local dpat = M.lang.indents.xml.dedent
             
             local indent_inc = 2
             local next_indent = nil
             -- If this isn't the first line, then get the indent
             -- from the previous line
             if line_start > 1 then
               local prev_line = buffer:get_line(line_start-1)
               local prev_indent = prev_line:match(" *()")
               next_indent = prev_indent + pat:match(prev_line)
             end
             for lineno=line_start,line_end do
                 local line = buffer:get_line(lineno)
                 local indent_delta = pat:match(line)
                 -- re-indent this line
                 if next_indent then
                     local this_indent = next_indent
                     -- Special case - looking at this line may
                     -- make us want to dedent (eg closing brace/tag)
                     this_indent = this_indent + indent_inc * dpat:match(line)
                     line = line:gsub("^%s*", (" "):rep(this_indent))
                     buffer:set_selection(buffer:position_from_line(lineno+1),
                                          buffer:position_from_line(lineno))
                     buffer:replace_sel(line)
                 else
                     next_indent = 0
                 end
                 next_indent = next_indent + indent_inc * indent_delta
             end
           end
           state.pending_command = '='
         end,

        p = function()
            -- Paste a new line.
            do_action(repeatable(function() vi_paste(true) end))
        end,

        P = function()
            do_action(repeatable(function() vi_paste(false) end))
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
	['ce']= function() ui.command_entry.enter_mode('lua_command') end,
	['/'] = function() M.search_mode.start(enter_command) end,
	['?'] = function() M.search_mode.start_rev(enter_command) end,
        n = M.search_mode.restart,
        N = M.search_mode.restart_rev,
        ['*'] = M.search_mode.search_word,
        ['#'] = M.search_mode.search_word_rev,
        
    -- Tags
    ['c]'] = function()
                local pos = buffer.current_pos
                local s, e = buffer:word_start_position(pos, true), buffer:word_end_position(pos)
                local word = buffer:text_range(s, e)
                local tag = vi_tags.find_tag_exact(word)
                if tag then
                    vi_tags.goto_tag(tag)
                else
                    M.err("Not found")
                end
    end,
    ['ct'] = vi_tags.pop_tag,
    
    -- Errors (in compile error buffer)
    ['c}'] = function() textadept.run.goto_error(false, true) end,

    -- Views and buffers
    cw = {
        cw = { ui.goto_view, 1, true },  -- cycle between views
    },
    ['c^'] = function()
        if view.vi_last_buf then 
            bufnum = _BUFFERS[view.vi_last_buf]
            if bufnum then
                view:goto_buffer(bufnum)
            end
        end
    end,

    -- Misc: suspend the editor
    cz = M.kill.kill,

    },
}

-- Save the previous buffer to be able to switch back
events.connect(events.BUFFER_BEFORE_SWITCH, function () 
       if not buffer._textredux  then
           view.vi_last_buf = buffer
       end
    end)

if M.vi_global then
  -- Rather than adding a command mode, copy all our bindings in and replace mode_command.bindings
  -- with a reference to the global keys table.
  for k,v in pairs(mode_command.bindings) do
    keys[k] = v
  end
  
  -- Make sure we've only got one table with the bindings.
  mode_command.bindings = keys
  -- And make sure that our mode is represented.
  keys[COMMAND] = keys
  
  keys[INSERT] = mode_insert.bindings
else
  -- Fall back to main keymap for any unhandled keys
  local keys_mt = {
  	__index = keys
  }

  keys[COMMAND] = setmetatable(mode_command.bindings, keys_mt)
  keys[INSERT] = setmetatable(mode_insert.bindings, keys_mt)

  -- Since it's currently easy to escape from the vi modes to the default mode,
  -- make sure we can get back to it from default mode.
  keys.esc = function() enter_mode(mode_command) end
end

-- Disable "normal" keys in command mode if I haven't bound them explicitly.
local function set_default_key(k)
    if mode_command.bindings[k] == nil then
        mode_command.bindings[k] = function()
            M.err("Unbound key: <" .. tostring(k) .. ">")
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
