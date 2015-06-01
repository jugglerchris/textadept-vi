local M = {}

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
M.vi_tags = require 'vi_tags'
M.lang = require 'vi_lang'
M.vi_complete = require 'vi_complete'
vi_find_files = require 'vi_find_files'
local lpeg = require 'lpeg'

local vi_motion = require 'vi_motion'
local vi_motions = require 'vi_motions'
local vi_down = vi_motions.line_down
local vi_up= vi_motions.line_up
local vi_tags = M.vi_tags
local vi_ops = require'vi_ops'
local vi_ta_util = require 'vi_ta_util'
local line_length = vi_ta_util.line_length
local buf_state = vi_ta_util.buf_state

--[[
Make textadept behave a bit like vim.
--]]

-- The current mode (command, insert, etc.)
COMMAND = "vi_command"
INSERT = "vi_insert"
INSERT_CNP = "vi_complete"  -- Ctrl-P/Ctrl-N search mode

M.COMMAND = COMMAND
M.INSERT = INSERT
M.INSERT_CNP = INSERT_CNP

mode = nil  -- initialised below

local debugFlag = false

function dbg(...)
    --if debugFlag then print(...) end
    if debugFlag then
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
    local handler = nil
    for _,sym in ipairs({...}) do
        handler = (type(handler) == 'table' and handler or mode.bindings)[sym]
        if type(handler) == 'function' then result = handler(sym) end
    end
    -- We expect to have done a full action, not partial keys.
    assert(type(handler) == 'function')
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
    
    registers = {},           -- cut/paste registers
    
    variables = {             -- Configurable variables
        grepprg = "grep -rn --devices=skip",
    }
}

-- Make state visible.
M.state = state

function M.err(msg)
    state.errmsg = msg
end

function enter_replace()
  enter_mode(mode_insert)
  buffer.overtype = true
  mode_command.restart = function()
      buffer.overtype = false
  end
end

function update_status()
    local err = state.errmsg
    local msg

    if mode == nil then return end
    
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

function M.vi_cut(start, end_, linewise, register)
    return vi_ops.cut(start, end_, linewise and MOV_LINE or MOV_INC)
end
local vi_cut = M.vi_cut

local R = lpeg.R
local S = lpeg.S
local P = lpeg.P
local V = lpeg.V
local Cmt = lpeg.Cmt
local Cb = lpeg.Cb
local Cc = lpeg.Cc
local Cg = lpeg.Cg
local Cp = lpeg.Cp
local Carg = lpeg.Carg
-- LPeg pattern to match a number in a line, at a certain
-- minimum position.
local _num_dec = Cp() * (P"-" ^ -1) * R"09" ^ 1 * Cc("dec")

-- Assume lower case if no [a-f]
local _hex_start = P"0x" * Cp() * Cg(Cc("hex"), 'hextype')
-- The last letter will pass its
local _hex_char_upper = R"AF" * Cg(Cc("HEX"), 'hextype')
local _hex_char_lower = R"af" * Cg(Cc("hex"), 'hextype')

local _num_hex = _hex_start * (R"09" + _hex_char_lower + _hex_char_upper)^1 * Cb("hextype")

local _num_any = _num_hex + _num_dec

-- predicate to check that the number ends after a certain position,
-- which will be passed as the first extra argument.
local _ends_after = Cmt(Carg(1), function(subj, pos, col)
                                    return pos > col
                                 end)
                                 
-- Find it anywhere (first match)
-- Returns captures: startpos, base ("dec"/"hex"), endpos
local _find_num = P{ (_num_any * _ends_after * Cp()) + 1*V(1) }

-- Find a number under (or to the right of) the cursor
local function _find_number()
    local line = buffer:get_cur_line()
    local col = buffer.column[buffer.current_pos]
    local linepos = buffer:position_from_line(buffer:line_from_position(buffer.current_pos))
    
    local startpos, base, endpos = _find_num:match(line, 1, col)
    
    if startpos ~= nil then
        return base, linepos+startpos-1, linepos + endpos-1
    else
        return nil
    end
end

local numtype_to_base = {
    dec = 10,
    hex = 16,
    HEX = 16,
}
local numtype_to_fmt = {
    dec = '%d',
    hex = '%x',
    HEX = '%X',
}

-- Increment the number under (or to the right of) the cursor by
-- increment (which may be negative).
function do_inc(increment)
    local numtype, start_, end_ = _find_number()
    
    if numtype == nil then return end
    
    local numstr = buffer:text_range(start_, end_)
    local val = tonumber(numstr, numtype_to_base[numtype])
    
    val = val + increment
    
    local newstr = string.format(numtype_to_fmt[numtype], val)
    
    buffer:set_selection(start_, end_)
    buffer:replace_sel(newstr)
end

--- Paste from a register (by default the unnamed register "")
--  If after is true, then will paste after the current character or line
--  (depending on whether the buffer was line or character based)
local function vi_paste(after, register)
    local buf = state.registers[register or '"']
    if not buf then return end
    
    local pos = buffer.current_pos
    
    if buf.line then
        local lineno = buffer:line_from_position(pos)
        if after then
            lineno = lineno + 1
            if lineno >= buffer.line_count then
                -- add a line if necessary
                buffer:line_end()
                buffer:new_line()
            end
        end
        pos = buffer:position_from_line(lineno)
        buffer:goto_pos(pos)
        assert(pos == buffer.current_pos)
        local reported_line = buffer:line_from_position(pos)
        assert(reported_line == lineno)
    else
        if after then pos = pos + 1 end
    end
    buffer:insert_text(pos, buf.text)
    if not buf.line then
        buffer:goto_pos(pos + buf.text:len()-1)
    end
end

-- Return the inserted text.  Can be called immediately after returning
-- from insert mode.
local function get_just_inserted_text()
    local result = ""
    -- If the cursor moved, then assume we've inserted text.
    if state.insert_pos < buffer.current_pos then
        local curpos = buffer.current_pos
        buffer.set_selection(state.insert_pos, curpos)
        result = buffer.get_sel_text()
        buffer.clear_selections()
        buffer.goto_pos(curpos)
    end
    return result
end

--- Mark the end of an edit (either exiting insert mode, or moving the
--  cursor).
local function insert_end_edit()
    local text = get_just_inserted_text()
    if text:len() > 0 then state.last_insert_string = text end
end

-- Start an undo action
local function begin_undo()
    local bst = buf_state(buffer)
    bst.undo_level = bst.undo_level or 0
    assert(bst.undo_level == 0)
    buffer:begin_undo_action()
    bst.undo_level = bst.undo_level + 1
end

-- End an undo action
local function end_undo()
    local bst = buf_state(buffer)
    buffer:end_undo_action()
    assert(bst.undo_level == 1)
    bst.undo_level = bst.undo_level - 1
end

-- Break an insert action to be resumed (at another location/in another
-- buffer)
local function break_edit_start()
    -- Cancel any autocomplete list if active
    if buffer:auto_c_active() then
        buffer:auto_c_cancel()
    end
    end_undo()
    insert_end_edit()
end

-- Resume editing
local function break_edit_end()
    insert_start_edit()
    begin_undo()
end

--- Return a function which does the same as its argument, but also
--  restarts the undo action.
local function break_edit(f)
    return function()
        break_edit_start()
        f()
        break_edit_end()
    end
end

-- Wraps a key handler function to pass the key through to the
-- autocomplete list if present.
local function allow_autoc(f)
    return function()
        if buffer:auto_c_active() then
            -- Allow the next handler
            return false
        else
            return f()
        end
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

        up    = allow_autoc(break_edit(vi_up)),
        down  = allow_autoc(break_edit(vi_down)),
        left  = break_edit(buffer.char_left),
        right = break_edit(buffer.char_right),
        home  = allow_autoc(break_edit(buffer.vc_home)),
        ['end'] = allow_autoc(break_edit(buffer.line_end)),
        pgup =  allow_autoc(break_edit(buffer.page_up)),
        pgdn =  allow_autoc(break_edit(buffer.page_down)),

        -- These don't quite behave as vim, but they'll do for now.
        cp = M.vi_complete.complete_backwards,
        cn = M.vi_complete.complete_forwards,

        cv = self_insert_tab,
    }
}

local function no_action() end

-- Run an action, as a single undoable action.
-- Passes the current repeat count (prefix count) to it,
-- and saves it to be recalled with '.'.
function do_action(action)
    local saved_rpt = state.numarg
    if saved_rpt < 1 then saved_rpt = 1 end
    state.last_action = function(rpt)
        if rpt < 1 then rpt = saved_rpt end
        action(rpt)
    end

    raw_do_action(action)
end

-- Return the current numeric prefix (and clear it)
-- Returns nil if not set.
local function get_numarg()
    local numarg = state.numarg
    
    state.numarg = 0
    
    return ((numarg == 0) and nil) or numarg
end

-- Like do_action but doesn't save to last_action
function raw_do_action(action)
    local rpt = 1

    if state.numarg > 0 then
        rpt = state.numarg
        state.numarg = 0
    end
    state.last_numarg = rpt

    begin_undo()
    action(rpt)
    end_undo()
end

function addarg(n)
  state.numarg = state.numarg * 10 + n
  dbg("New numarg: " .. tostring(state.numarg))
end
-- Return a handler for digit n
function dodigit(n)
    return function() addarg(n) end
end

-- Valid movement types
MOV_LINE = 'linewise'
MOV_INC = 'inclusive'
MOV_EXC = 'exclusive'
MOV_LATER = 'later'
MOV_TYPES = {
  [MOV_LINE] = true,
  [MOV_INC] = true,
  [MOV_EXC] = true,
}

-- Apply a movement command, which may be attached to an editing action.
local function do_movement(f, movtype)
    assert(MOV_TYPES[movtype], "Invalid or missing motion type: [["..tostring(movtype).."]]")
    
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
            if movtype == MOV_LINE then
                start = buffer.position_from_line(buffer.line_from_position(start))

                local line_end = buffer.line_from_position(end_)
                end_ = buffer.position_from_line(line_end) +
                                      buffer.line_length(line_end)
            else
                local endlineno = buffer:line_from_position(end_)
                local endcol = end_ - buffer.position_from_line(endlineno)
                
                if movtype == MOV_INC then
                  -- inclusive motion - include the last character
                  if end_ < buffer.text_length and 
                     endcol < buffer:line_length(endlineno) then
                     end_ = end_ + 1
                  end
                else
                  -- exclusive motion
                  -- If the end is at the start of a new line, then move it
                  -- back to the end for this.
                  if endcol == 0 and end_ > start then
                      end_ = buffer.line_end_position[endlineno-1]
                  end
                end
            end
            action(start, end_, move, movtype == MOV_LINE)
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
local function mk_movement(f, movtype)
  -- Run f numarg times (if numarg is non-zero) and clear
  -- numarg
  return function()
     do_movement(f, movtype)
     -- If this was a horizontal movement, then forget what column
     -- we were trying to stay in.
     if movtype ~= MOV_LINE then buf_state(buffer).col = nil end
  end
end

local function enter_command()
    enter_mode(mode_command)
end

function M.enter_insert_then_end_undo(cb)
    -- Save the numeric argument
    local rpt = 1
    if state.numarg > 0 then
        rpt = state.numarg
        state.numarg = 0
    end
    state.last_numarg = rpt
        
    enter_mode(mode_insert)
    insert_start_edit()
    mode_command.restart = function()
        end_undo()
        if cb then cb() end
    end
end
local enter_insert_then_end_undo = M.enter_insert_then_end_undo

local function enter_insert_with_undo(cb)
    begin_undo()
    enter_insert_then_end_undo(cb)
end

-- Helper function for doing a replace operation
local function do_replace(pos, s)
    local slen = s:len()
    local line_end = buffer.line_end_position[buffer:line_from_position(pos)]
    local endpos = pos + slen
    if endpos > line_end then endpos = line_end end
    buffer:set_selection(pos, endpos)
    buffer:replace_sel(s)
    pos = pos + slen
    buffer:clear_selections()
    buffer:goto_pos(pos-1)
end

local function enter_replace_with_undo(cb)
    begin_undo()
    
    -- Save the numeric argument
    local rpt = get_numarg() or 1
        
    buffer.overtype = true
    enter_mode(mode_insert)
    insert_start_edit()
    mode_command.restart = function()
        buffer.overtype = false
        
        if rpt > 1 then
          do_replace(buffer.current_pos+1, string.rep(state.last_insert_string, rpt-1))
        end
        end_undo()
        state.last_action = function(rpt)
            local rpt = rpt
            if rpt < 1 then rpt = 1 end
            begin_undo()
            local pos = buffer.current_pos
            local s = state.last_insert_string
            do_replace(pos, s:rep(rpt))
            end_undo()
            buffer:goto_pos(pos+rpt*(s:len())-1)
        end
    end
end

--- Function to be called after an insert mode operation.
--  Sets the last action to call prep_f() to prepare (eg go to end of
--  line, etc.) and then insert the last-inserted text.
function M.post_insert(prep_f)
  return function()
          -- This function is run when exiting from undo
          state.last_action = function(rpt)
            local rpt = rpt
            if rpt < 1 then rpt = 1 end
            begin_undo()
            prep_f()
            for i=1,rpt do
                buffer.add_text(state.last_insert_string)
            end
            end_undo()
          end
        end
end
local post_insert = M.post_insert

-- Do a movement (with optional repeat override) and return the range
-- selected for an edit, taking into account inclusive/exclusive etc.
--
-- movdesc: { movtype, movf, rep }
-- rpt: 0 or an override repeat
--
-- returns start, end positions.
local function movdesc_get_range(movdesc, rpt_motion, rpt_cmd)
    local movtype, movf, rep = table.unpack(movdesc)

    if rpt_motion == nil or rpt_motion < 1 then rpt_motion = rep end
    local cmdrep = (rpt_cmd and rpt_cmd > 0) and rpt_cmd or 1
    local rpt = rpt_motion * cmdrep
    local start, end_ = movf(rpt)
    
    -- Now adjust the range depending on the movement class
    if movtype == MOV_LINE then
        start = buffer.position_from_line(buffer.line_from_position(start))

        local line_end = buffer.line_from_position(end_)
        end_ = buffer.position_from_line(line_end) +
               buffer.line_length(line_end)
    else
        local endlineno = buffer:line_from_position(end_)
        local endcol = end_ - buffer.position_from_line(endlineno)
                
        if movtype == MOV_INC then
            -- inclusive motion - include the last character
            if end_ < buffer.text_length and 
                endcol < buffer:line_length(endlineno) then
                end_ = end_ + 1
            end
        else
            -- exclusive motion
            -- If the end is at the start of a new line, then move it
            -- back to the end for this.
            if endcol == 0 and end_ > start then
                end_ = buffer.line_end_position[endlineno-1]
            end
        end
    end
    return start, end_
end

-- Return a table implementing an action which can take a motion, and
-- which does NOT involve insert mode.
-- Also handles taking care of being able to redo the action.
--
-- actions: a table -f non-motion bindings.
-- handler: a function called with (start, end, movtype)
--       start/end are the selected range, and movtype is MOV_{INC,EXC,LINE}
--       The handler should do its action.  The system will take care of
--       saving the action to repeat, and undo/redo.
local function with_motion(actions, handler)
    local function apply_action(mdesc)
       local cmdrpt = get_numarg()
       local movtype = mdesc[1]
       local start, end_ = movdesc_get_range(mdesc, nil, cmdrpt)
       begin_undo()
       handler(start, end_, movtype)
       end_undo()
       
       state.last_action = function(new_rpt)
           local rpt = (new_rpt and new_rpt > 0) and new_rpt or cmdrpt
           local start, end_ = movdesc_get_range(mdesc, rpt, 1)
           begin_undo()
           handler(start, end_, movtype)
           end_undo()
       end
    end
    wrapped_handler = function(movdesc)
       if movdesc[1] == MOV_LATER then
         -- Special case - we don't get the action until later.
         return function()
            local mov_f = movdesc[2]
            mov_f(function (mdesc)
              apply_action(vi_motion.movf_to_self(mdesc))
            end)
         end
       else
         return function()
           apply_action(movdesc)
         end
       end
    end
    return vi_motion.bind_motions(actions, wrapped_handler)
end

-- Return a table implementing an action which can take a motion, and
-- which involves text being entered in insert mode.
-- Also handles taking care of being able to redo the action.
--
-- actions: a table -f non-motion bindings.
-- handler: a function called with (start, end, movtype)
--       start/end are the selected range, and movtype is MOV_{INC,EXC,LINE}
--       The handler should do whatever needs doing before entering insert
--       mode and return.  The system will handle entering insert mode and
--       being able to repeat, as well as undo.
local function with_motion_insert(actions, handler)
    wrapped_handler = function(movdesc)
       return function()
           local cmdrpt = get_numarg()
           local start, end_ = movdesc_get_range(movdesc, nil, cmdrpt)
           begin_undo()
           handler(start, end_, movtype)
           
           insert_start_edit()
           enter_mode(mode_insert)
           mode_command.restart = function()
               local text = state.last_insert_string
               end_undo()
               state.last_action = function(new_rpt)
                   local rpt = (new_rpt and new_rpt > 0) and new_rpt or cmdrpt
                   local start, end_ = movdesc_get_range(movdesc, rpt, 1)
                   begin_undo()
                   handler(start, end_, movtype)
                   buffer:add_text(text)
                   end_undo()
               end
           end
       end
    end
    return vi_motion.bind_motions(actions, wrapped_handler)
end

-- Take a selection movdesc and turns it into one which trims whitespace
-- from the end.
local function self_trim_right_space(movdesc)
    local movtype, sel_f, rep = table.unpack(movdesc)
    return { movtype, function(rep)
        local pos1, pos2 = sel_f(rep)
        while pos2 > pos1 and buffer:text_range(pos2-1, pos2):match("%s") do
            pos2 = pos2 - 1
        end
        if pos2 > pos1 then
            -- And back one to step on to the last character of the word.
            pos2 = pos2 - 1
        end
        return pos1, pos2
     end, rep }
end

-- Ask the user for some text, and return the text or nil.
function ask_string(prompt)
    local idx, res
    idx, res = ui.dialogs.inputbox{title=prompt}
    if idx == 1 then return res end
end

-- Filename characters
FILENAME_CHARS = "abcdefghijklmnopqrstuvwxyz" ..
                 "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ..
                 "0123456789" ..
                 "_.-#,/"
-- Find a filename under the cursor and try to open that file.
-- If the filename is followed by :number, then go to that line in the file.
function find_filename_at_pos()
    local s, e, filename = vi_ta_util.find_word_at(buffer.current_pos, FILENAME_CHARS)
    local lineno = nil
    
    if buffer:text_range(e, e+1) == ":" then
        local _
        _, _, linenostr = vi_ta_util.find_word_at(e+1, "0123456789")
        if linenostr ~= nil then
            lineno = tonumber(linenostr)
        end
    end
    
    if filename:sub(1,1) == '/' or filename:sub(1,2) == "./" then
        -- Absolute path: keep as is
    else
        -- Relative - find one
        local paths = vi_find_files.find_matching_files(filename)
        
        if paths and #paths >= 1 then
            filename = paths[1]
        else
            filename = nil
        end
    end
    if filename then
        io.open_file(filename)
        if lineno ~= nil then
            buffer:goto_line(lineno-1)
        end
    end
end

-- Key binding which takes a motion, then prompts for two strings for
-- before and after, and wraps the region with that text.
surround_keys = vi_motion.bind_motions({
    w = vi_motion.movf_to_self({ MOV_INC, vi_motion.r(vi_motions.word_end), 1}),
    s = { MOV_LINE, vi_motions.sel_line, 1 },
},
  function(movdesc)
      return function()
         local cmdrpt = get_numarg()
         local start, end_ = movdesc_get_range(movdesc, nil, cmdrpt)
         
         local pre = ask_string('Pre text')
         local post = ask_string('Post text')
         
         if movdesc[1] == MOV_LINE then
             pre = pre .. "\n"
             post = post .. "\n"
         end
         
         local function handler(start, end_, movtype)
             buffer:insert_text(end_, post)
             buffer:insert_text(start, pre)
         end
         
         begin_undo()
         handler(start, end_, movtype)
         end_undo()
         
         state.last_action = function(rpt)
             local start, end_ = movdesc_get_range(movdesc, rpt, 1)
             begin_undo()
             handler(start, end_, movtype)
             end_undo()
         end
      end
  end)

-- Check that the cursor hasn't wandered off beyond the end of the line
local function ensure_cursor()
  local docpos = buffer.current_pos
  local lineno = buffer:line_from_position(docpos)
  local linestart = buffer:position_from_line(lineno)
  local length = line_length(lineno)
  
  if docpos-linestart >= length then
      buffer.current_pos = linestart + length - 1
  end
end

-- A table which implements the second keypres of 'r'.
 local handle_r = setmetatable({}, {
    __index = function(t, sym)
                 if string.match(sym, "^.$") then
                   return function()
                   local cmdrpt = get_numarg()
                   if not (cmdrpt and cmdrpt > 0) then cmdrpt = 1 end
                  -- Single character, so buffer.replace.
                   local function handler(rpt)
                       rpt = (rpt and rpt > 0) and rpt or cmdrpt
                       local here = buffer.current_pos
                       local lineno = buffer:line_from_position(here)
                       local linestart = buffer:position_from_line(lineno)
                       local col = here - linestart
                       local numcols = line_length(lineno)
                       local left = numcols - col
                       begin_undo()
                       if rpt <= left then
                         while rpt > 0 do
                           local nextpos = buffer:position_relative(here, 1)
                           buffer:set_sel(here, nextpos)
                           buffer:replace_sel(sym)
                           -- Recalculate nextpos as the new character may
                           -- not be the same length.
                           nextpos = buffer:position_relative(here, 1)
                           buffer.current_pos = nextpos

                           here = nextpos
                           rpt = rpt - 1
                         end
                         ensure_cursor()
                       else
                         M.err('**EOL')
                       end
                       end_undo()
                     end
                     
                     state.last_action = handler

                     handler(cmdrpt)
                 end
             end
         end
           
})

--- Open or close all folds recursively.
--  From Carlos Pita <carlosjosepita@gmail.com> on the Textadept mailing
--  list.
local function do_fold_all(action)
    for line = 0, buffer.line_count do
        if bit32.band(line, buffer.FOLDLEVELHEADERFLAG) and
           bit32.band(line, buffer.FOLDLEVELBASE) then
            buffer:fold_children(line, action)
        end
    end
end

mode_command = {
    name = COMMAND,

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_command.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        -- movement commands
        H = mk_movement(function()
             -- We can't use goto_line here as it scrolls the window slightly.
             local top_line = buffer.first_visible_line
             local pos = buffer.position_from_line(top_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end, MOV_LINE),
        M = mk_movement(function()
             buffer.goto_line(math.floor(buffer.first_visible_line + buffer.lines_on_screen/2))
            end, MOV_LINE),
        L = mk_movement(function()
             local bot_line = buffer.first_visible_line + buffer.lines_on_screen - 1
             local pos = buffer.position_from_line(bot_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end, MOV_LINE),

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
	['`'] = setmetatable({}, {
        __index = function(t, key)
	        if string.match(key, "^%a$") then
		       -- alphabetic, so restore the mark
               return function()
                 newpos = state.marks[key]
                 if newpos ~= nil then
		 	        do_movement(function () buffer.goto_pos(newpos) end, MOV_EXC)
		         end
		       end
	        end
        end}),

	['0'] = function()
             if state.numarg == 0 then
                mk_movement(buffer.home, MOV_EXC)()
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
            begin_undo()
            buffer.new_line()
            enter_insert_then_end_undo(post_insert(function()
                buffer.line_end()
                buffer.new_line()
            end))
        end,
        O = function()
            local function ins_new_line()
              buffer.home()
              begin_undo()
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
        r = handle_r,
        R = function() enter_replace_with_undo() end,
        ['~'] = function()
            do_action(function(rpt)
              local here = buffer.current_pos
              local lineno = buffer:line_from_position(here)
              local linestart = buffer:position_from_line(lineno)
              local col = here - linestart
              local numcols = line_length(lineno)
              local left = numcols - col
              if rpt > left then
                rpt = left
              end
              while rpt > 0 do
                buffer.set_sel(here, here+1)
                local c = buffer.get_sel_text()
                local newc = string.upper(c)
                if newc == c then newc = string.lower(c) end
                buffer.replace_sel(newc)
                buffer.current_pos = here+1

                here = here + 1
                rpt = rpt - 1
              end
              ensure_cursor()
           end)
        end,

        J = function()
           do_action(function (rpt)
               if rpt < 2 then rpt = 2 end

               for i=1,rpt-1 do
                   local lineno = buffer:line_from_position(buffer.current_pos)
                   if lineno < buffer.line_count then
                       local line1 = buffer:get_line(lineno)
                       local line2 = buffer:get_line(lineno+1)
                       local joiner = ''
                       
                       -- Strip line ending
                       line1 = line1:match('(.-)[\n\r]*$')
                       
                       -- Add an extra space after a sentence end
                       if line1:match('[%.$]$') then joiner = ' ' end
                       
                       -- Strip leading whitespace in second line
                       line2 = line2:match('%s*(.*)')
                       
                       -- Set the range to change and replace it
                       buffer.target_start = buffer:position_from_line(lineno)
                       buffer.target_end = buffer:position_from_line(lineno+1) + buffer:line_length(lineno+1)
                       buffer:replace_target(line1..joiner..' '..line2)
                       buffer:goto_pos(buffer.target_start + line1:len())
                   end
               end
           end)
        end,
        g = {
            q = with_motion({
                q = { MOV_LINE, vi_motions.sel_line, 1 },
            }, vi_ops.wrap),
            s = surround_keys,
            f = find_filename_at_pos,
        },

        d = with_motion({
           d = { MOV_LINE, vi_motions.sel_line, 1 },
        }, vi_ops.cut),
        
        -- Temporary binding to test improved way of doing compound commands.
        c = with_motion_insert({
           -- insert non-motion completions (eg tt?) here.
          c = { MOV_LINE, vi_motions.sel_line, 1 },
              
          -- cw is a special case, and doesn't include whitespace at the end
          -- of the words.  It behaves more like ce, but doesn't change
          -- line at the end of a word.
          w = self_trim_right_space(vi_motion.movf_to_self({ MOV_INC, vi_motion.r(vi_motions.word_right), 1})),
        }, vi_ops.change),

        D = function()
            do_keys('d', '$')
        end,

        C = function()
            do_keys('c', '$')
        end,

        ['>'] = with_motion({
          ['>'] = { MOV_LINE, vi_motions.sel_line, 1 },
        }, vi_ops.indent),
        ['<'] = with_motion({
          ['<'] = { MOV_LINE, vi_motions.sel_line, 1 },
        }, vi_ops.undent),
         
        x = function()
            do_action(function(rept)
                local here = buffer.current_pos
                local text, _ = buffer.get_cur_line()
                local lineno = buffer.line_from_position(buffer.current_pos)
                local lineend = buffer.line_end_position[lineno]
                local endpos = buffer:position_relative(here, rept)
                if endpos > lineend then endpos = lineend end
                if endpos < here then endpos = lineend end
                if endpos == here and string.len(text) > 1 then
                    -- If at end of line, delete the previous char.
                    here = here - 1
                end
                vi_cut(here, endpos, false)
                ensure_cursor()
            end)
      end,

         -- Re-indent the range
         ['='] = with_motion({
           ['='] = { MOV_LINE, vi_motions.sel_line, 1 },
         }, vi_ops.reindent),
         
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
              local rpt = get_numarg()
              state.last_action(rpt)
              
              -- Slightly unclean way of making sure the cursor doesn't end
              -- up past the end of the line.
              local line, pos = buffer.get_cur_line()
              if pos >= line:len() then buffer.char_left() end
           end,

	-- Enter ex mode command
	[':'] = function() M.ex_mode.start(enter_command) end,
        ['@'] = {
            [':'] = M.ex_mode.repeat_last_command,
        },
	['ce']= function() ui.command_entry.enter_mode('lua_command') end,
        
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
    
    -- Folds
    z = {
      o = function() buffer:fold_line(buffer:line_from_position(buffer.current_pos), buffer.FOLDACTION_EXPAND) end,
      c = function() buffer:fold_line(buffer:line_from_position(buffer.current_pos), buffer.FOLDACTION_CONTRACT) end,
      M = function() do_fold_all(buffer.FOLDACTION_CONTRACT) end,
      R = function() do_fold_all(buffer.FOLDACTION_EXPAND) end,
    },
    
    -- Increment/decrement under cursor
    ca = function() do_action(function(rpt) do_inc(rpt) end) end,
    cx = function() do_action(function(rpt) do_inc(-1*rpt) end) end,
    
    -- Show help
    f1 = textadept.editing.show_documentation,
    },
}
M.mode_command = mode_command

events.connect(events.VIEW_BEFORE_SWITCH, function()
       -- Add undo boundaries when switching buffers
       if keys.MODE == mode_insert.name then
           break_edit_start()
       end
end)

events.connect(events.VIEW_AFTER_SWITCH, function () 
       -- Add undo boundaries when switching buffers
       if keys.MODE == mode_insert.name then
           break_edit_end()
       end
    end)

events.connect(events.BUFFER_BEFORE_SWITCH, function () 
       -- Save the previous buffer to be able to switch back
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
  keys[INSERT_CNP] = M.vi_complete.get_keys(keys[INSERT])
  
  -- Convert a motion table to a key function
  local function motion2key(movdesc)
     local movtype, mov_f, rep = table.unpack(movdesc)
     
     if movtype == MOV_LATER then
       -- Call the movement function with the right count.
       return function()
         mov_f(function (md)
           motion2key(md)()
         end)
       end
     else
       -- Call the movement function with the right count.
       return function()
                  local rpt = get_numarg()
                  if not(rpt and rpt > 0) then rpt = rep end
                  mov_f(rpt)
                  if movtype ~= MOV_LINE then buf_state(buffer).col = nil end
              end
     end
  end
  -- Delegate to the motion commands.
  setmetatable(keys, {
    __index = function(t,k)
        local m = vi_motion.motions[k]
        if type(m) == 'table' and m[1] then
            return motion2key(m)
        elseif type(m) == 'table' then
            return vi_motion.wrap_table(m, motion2key)
        end
    end })
    
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
