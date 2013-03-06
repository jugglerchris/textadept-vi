local M = {}

M.ex_mode = require 'vi_mode_ex'
--[[
Make textadept behave a bit like vim.
--]]

-- The current mode (command, insert, etc.)
COMMAND = "command"
INSERT = "insert"
mode = nil  -- initialised below
local key_handler = nil

local debug = true

function dbg(...)
    --if debug then print(...) end
    if debug then
        gui.statusbar_text = table.concat({...}, ' ')
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
    dbg("Code:", code)
    if alt then sym = 'a' .. sym end
    if ctrl then sym = 'c' .. sym end
    if shift then sym = 's' .. sym end -- Need to change for alphabetic

    dbg("Sym:", sym, "Code:", code)
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

-- Wrapper to turn a simple command into one which uses the numeric prefix
local function repeat_arg(f)
  -- Run f command_numarg times (if command_numarg is non-zero) and clear
  -- command_numarg
  return function()
     local times = command_numarg
     command_numarg = 0
     if times == 0 then times = 1 end
     for i=1,times do
         f()
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
        h = repeat_arg(function ()
	  local line, pos = buffer.get_cur_line()
	  if pos > 0 then buffer.char_left() end
        end),
        l = repeat_arg(function()
	  local line, pos = buffer.get_cur_line()
	  local docpos = buffer.current_pos
	  local length = buffer.line_length(buffer.line_from_position(docpos))
	  if pos < (length - 1) then
	      buffer.char_right()
	  end
        end),
        j = repeat_arg(buffer.line_down),
        k = repeat_arg(buffer.line_up),
        H = function()
             -- We can't use goto_line here as it scrolls the window slightly.
             local top_line = buffer.first_visible_line
             local pos = buffer.position_from_line(top_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end,
        M = function()
             buffer.goto_line(buffer.first_visible_line + buffer.lines_on_screen/2)
            end,
        L = function()
             local bot_line = buffer.first_visible_line + buffer.lines_on_screen - 1
             local pos = buffer.position_from_line(bot_line)
             buffer.current_pos = pos
             buffer.anchor = pos
            end,

	['0'] = function()
             if command_numarg == 0 then
                buffer.home()
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
	['^'] = function()
		   buffer.home()    -- Go to beginning of line
		   buffer.vc_home()  -- swaps between beginning/first visible
                end,
	G = function()
	       if command_numarg > 0 then
                   -- Textadept does zero-based line numbers.
		   buffer.goto_line(command_numarg - 1)
		   command_numarg = 0
	       else    
                 -- With no arg, go to last line.
                 buffer.document_end()
		 buffer.home()
	       end
	   end,

	-- edit mode commands
        i = function() enter_mode(mode_insert) end,
	a = function() buffer.char_right() enter_mode(mode_insert) end,
        A = function() buffer.line_end() enter_mode(mode_insert) end,
        
        -- edit commands
	u = buffer.undo,
	cr = buffer.redo,

	-- Enter ex mode command
	[':'] = M.ex_mode.start,

	-- test/debug
	home = function() l, n = buffer.get_cur_line()
                          print(l, n) end,
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
