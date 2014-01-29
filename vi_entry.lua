local M = {}

local redux = require'textredux'

local function ve_refresh(buf)
  buf:add_text(buf.data.prompt, redux.core.style.error)
  buf:add_text(buf.data.text, redux.core.style.comment)
  buf:goto_pos(buf.data.pos + #buf.data.prompt)
end

-- Return a saved version of splits so that we can regenerate them.
local function save_splits(splits)
    if splits[1] and splits[2] then
       -- it's a split
       splits[1] = save_splits(splits[1])
       splits[2] = save_splits(splits[2])
       return splits
    else
       return splits.buffer
    end
end

local function save_views()
    local split_views = ui:get_split_table()
    
    return save_splits(split_views)
end

local function unsplit_all()
    while #_VIEWS > 1 do
        view:unsplit()
    end
end

local function restore_into(v, saved)
    if saved[1] and saved[2] then
        -- restore the split
        first, second = v:split(saved.vertical)
        first.size = saved.size
        restore_into(first, saved[1])
        restore_into(second, saved[2])
    else
        if _BUFFERS[saved] then
            v:goto_buffer(_BUFFERS[saved])
        else
            ui.print("Buffer not found:", saved.filename, saved)
            for k,v in pairs(_BUFFERS) do
                if type(v) == 'table' then
                  ui.print(k,v, v.filename)
                else
                  ui.print(k,v)
                end
            end
        end
    end
end

-- Restore split state, but with the current buffer on the bottom line.
local function restore_saved(saved)
    old, new = view:split()
    old.size = ui.size[2] - 4
    
    restore_into(old,saved)
    return new
end

local ve_keys = {
    ['\t'] = function()
    end,
    ['\b'] = function()
        local buf = buffer._textredux
        local t = buf.data.text
        local pos = buffer.current_pos - #buf.data.prompt
        if pos >= 1 then
            t = t:sub(1, pos-1) .. t:sub(pos+1, -1)
            buf.data.text = t
            buf.data.pos = pos - 1
            buf:refresh()
        end
    end,
    cu = function()
        -- Clear to start of line
        local buf = buffer._textredux
        local t = buf.data.text
        local pos = buffer.current_pos - #buf.data.prompt
        if pos > 0 then
            t = t:sub(pos+1, -1)
            buf.data.text = t
            buf.data.pos = 0
            buf:refresh()
        end
    end,
    esc = function()
        local buf = buffer._textredux
        local saved = buf.data.saved
        buf:close()
        unsplit_all()
        restore_into(view,saved)
    end,
    ['\r'] = function()
        local buf = buffer._textredux
        local saved = buf.data.saved
        local cmd = buf:get_text():sub(#buf.data.prompt + 1)
        local handler = buf.data.handler
        buf:close()
        unsplit_all()
        restore_into(view,saved)
        handler(cmd)
    end
}
local function set_key(k)
    ve_keys[k] = function() 
        local buf = buffer._textredux
        local t = buf.data.text
        local pos = buffer.current_pos
        t = t:sub(1, pos) .. k .. t:sub(pos+1, -1)
        buf.data.text = t
        buf.data.pos = pos + 1
        buf:refresh()
    end
end

local function set_key_range(first, last)
  local i = string.byte(first)
  while i <= string.byte(last) do
     set_key(string.char(i))
     i = i + 1
  end
end

-- Set all ASCII printable keys to just insert.
set_key_range(' ', '\x7e')

function M.enter_mode(prompt, handler)
  local buf = redux.core.buffer.new('entry')
  buf.on_refresh = ve_refresh
  buf.keys = ve_keys
  buf.data = { prompt=prompt, text = '', pos=#prompt, handler=handler }
  local saved = save_views()
  unsplit_all()
  local new, old
  --first, second = view:split()
  local newview = restore_saved(saved)
  newview.size = ui.size[2] - 4
  ui.goto_view(_VIEWS[newview])
  buf.data.saved = saved
  buf:show()
end

return M