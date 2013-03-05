local M = {}

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
        esc = function() enter_mode(mode_command) end,
    }
}
mode_command = {
    name = COMMAND,

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_command.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        -- movement commands
        h = function ()
	  local line, pos = buffer.get_cur_line()
	  if pos > 0 then buffer.char_left() end
        end,
        l = function()
	  local line, pos = buffer.get_cur_line()
	  local docpos = buffer.current_pos
	  local length = buffer.line_length(buffer.line_from_position(docpos))
	  if pos < (length - 1) then
	      buffer.char_right()
	  end
        end,
        j = buffer.line_down,
        k = buffer.line_up,
	['0'] = buffer.home,
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
                 buffer.document_end()
		 buffer.home()
               end,

	-- edit mode commands
        i = function() enter_mode(mode_insert) end,
	a = function() buffer.char_right() enter_mode(mode_insert) end,
        
        -- edit commands
	u = buffer.undo,
	cr = buffer.redo,

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
