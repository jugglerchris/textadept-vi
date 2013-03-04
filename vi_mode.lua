local M = {}

--[[
Make textadept behave a bit like vim.
--]]

-- The current mode (command, insert, etc.)
COMMAND = "command"
INSERT = "insert"
mode = nil  -- initialised below
local key_handler = nil

function dbg(...)
    print(...)
end

function enter_mode(m)
    mode = m

    dbg("Enter mode:" .. m.name)
    if key_handler ~= nil then
        events.disconnect(events.KEYPRESS, key_handler)
    end
    key_handler = events.connect(events.KEYPRESS, m.key_handler)
end

function key_handler_common(bindings, code, shift, ctrl, alt, meta)
    sym = keys.KEYSYMS[code] or string.char(code)

    print(sym)
    handler = bindings[sym]
    if handler then
        handler(sym)
        return true
    end
end

mode_insert = {
    name = "INSERT",

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_insert.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        esc = function() enter_mode(mode_command) end,
    }
}
mode_command = {
    name = "COMMAND",

    key_handler = function(code, shift, ctrl, alt, meta)
          return key_handler_common(mode_command.bindings, code, shift, ctrl, alt, meta)
    end,

    bindings = {
        h = char_left,
        l = char_right,
        j = line_down,
        k = line_up,
        i = function() enter_mode(mode_insert) end,
    },
}

enter_mode(mode_command)

return M
