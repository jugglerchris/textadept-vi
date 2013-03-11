local M = {}

M.ex_mode = require 'vi_mode_ex'
M.search_mode = require 'vi_mode_search'
--[[
Make textadept behave a bit like vim.
--]]

-- The current mode (command, insert, etc.)
COMMAND = "command"
INSERT = "insert"
mode = nil  -- initialised below
local key_handler = nil

local debug = false

function dbg(...)
    --if debug then print(...) end
    if debug then
        gui._print("vimode", ...)
    end
end

function enter_mode(m)
    mode = m

    dbg("Enter mode:" .. m.name)
    if key_handler ~= nil then
        events.disconnect(events.KEYPRESS, key_handler)
    end
    key_handler = events.connect(events.KEYPRESS, m.key_handler, 1)

    update_status()
end

function key_handler_common(bindings, code, shift, ctrl, alt, meta)
    sym = keys.KEYSYMS[code] or string.char(code)
    -- dbg("Code:", code)
    if alt then sym = 'a' .. sym end
    if ctrl then sym = 'c' .. sym end
    if shift then sym = 's' .. sym end -- Need to change for alphabetic

    --dbg("Sym:", sym, "Code:", code)
    handler = bindings[sym]
    if handler then
        handler(sym)
        return true
    end
end

function update_status()
    if mode.name == COMMAND then
        gui.statusbar_text = "(command)"
    else
        gui.statusbar_text = "-- INSERT --"
    end

end

mode_insert = {
    name = INSERT,

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_insert.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        esc = function()
	    local line, pos = buffer.get_cur_line()
            if pos > 0 then buffer.char_left() end
            enter_mode(mode_command)
        end,
    }
}

command_numarg = 0
function addarg(n)
  command_numarg = command_numarg * 10 + n
  dbg("New numarg: " .. tostring(command_numarg))
end
-- Return a handler for digit n
function dodigit(n)
    return function() addarg(n) end
end

local pending_action

local function do_movement(f)
    -- Apply a movement command, which may be attached to an editing action.
    if pending_action == nil then
        -- no action, just move
        f()
    else
        -- Select the region and apply
        -- TODO: handle line-oriented actions differently
        local start = buffer.current_pos
        f()
        local end_ = buffer.current_pos
        if start > end_ then
            start, end_ = end_, start
        end
        pending_action(start, end_)
        pending_action = nil
    end
end

local function repeat_arg(f)
    return function()
        local times = command_numarg
        command_numarg = 0
        if times == 0 then times = 1 end
        for i=1,times do
            f()
        end
    end
end

-- Wrapper to turn a simple command into one which uses the numeric prefix
local function mk_movement(f)
  -- Run f command_numarg times (if command_numarg is non-zero) and clear
  -- command_numarg
  return function()
     do_movement(f)
  end
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
        end)),
        l = mk_movement(repeat_arg(function()
	  local line, pos = buffer.get_cur_line()
	  local docpos = buffer.current_pos
	  local length = buffer.line_length(buffer.line_from_position(docpos))
	  if pos < (length - 1) then
	      buffer.char_right()
	  end
        end)),
        j = mk_movement(repeat_arg(buffer.line_down)),
        k = mk_movement(repeat_arg(buffer.line_up)),
        H = mk_movement(function()
             -- We can't use goto_line here as it scrolls the window slightly.
             local top_line = buffer.first_visible_line
             local pos = buffer.position_from_line(top_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end),
        M = mk_movement(function()
             buffer.goto_line(buffer.first_visible_line + buffer.lines_on_screen/2)
            end),
        L = mk_movement(function()
             local bot_line = buffer.first_visible_line + buffer.lines_on_screen - 1
             local pos = buffer.position_from_line(bot_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end),

	['0'] = function()
             if command_numarg == 0 then
                mk_movement(buffer.home)()
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
	['$'] = function()
		 -- Stop just before the end
		 buffer.line_end()
		 local line, pos = buffer.get_cur_line()
		 if pos > 0 then buffer.char_left() end
	       end,
	['^'] = mk_movement(function()
		   buffer.home()    -- Go to beginning of line
		   buffer.vc_home()  -- swaps between beginning/first visible
                end),
	G = mk_movement(function()
	       if command_numarg > 0 then
                   -- Textadept does zero-based line numbers.
		   buffer.goto_line(command_numarg - 1)
		   command_numarg = 0
	       else
                 -- With no arg, go to last line.
                 buffer.document_end()
		 buffer.home()
	       end
	   end),

	-- edit mode commands
        i = function() enter_mode(mode_insert) end,
	a = function() buffer.char_right() enter_mode(mode_insert) end,
        A = function() buffer.line_end() enter_mode(mode_insert) end,
        o = function() buffer.line_end() buffer.new_line() enter_mode(mode_insert) end,
        d = function()
           if pending_action ~= nil and pending_command == 'd' then
              -- The 'dd' command
              local rept = 1
              local lineno = buffer.line_from_position(buffer.current_pos)

              if command_numarg > 0 then rept = command_numarg end

              buffer.begin_undo_action()
              for i=1, rept do
                  buffer.line_delete()

                  -- Only delete forwards, so if we end up on a different
                  -- line we should stop.
                  if buffer.line_from_position(buffer.current_pos) ~= lineno
                  then
                      break
                  end
              end
              buffer.end_undo_action()

              pending_action, pending_command, command_numarg = nil, nil, 0
           else
              pending_action = function(start, end_)
                  buffer.delete_range(start, end_-start)
              end
              pending_command = 'd'
           end
        end,
        x = function()
                local here = buffer.current_pos
                local rept = command_numarg
                if command_numarg > 0 then
                    command_numarg = 0
                else
                    rept = 1
                end
                local text, _ = buffer.get_cur_line()
                local lineno = buffer.line_from_position(buffer.current_pos)
                local lineend = buffer.line_end_position[lineno]
                local endpos = here + rept
                if endpos > lineend then endpos = lineend end
                if endpos == pos and string.len(text) > 1 then
                    -- If at end of line, delete the previous char.
                    here = here - 1
                end
                buffer.delete_range(here, endpos-here)
        end,
        -- edit commands
	u = buffer.undo,
	cr = buffer.redo,

	-- Enter ex mode command
	[':'] = M.ex_mode.start,
	['/'] = M.search_mode.start,

    },
}

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

return M
