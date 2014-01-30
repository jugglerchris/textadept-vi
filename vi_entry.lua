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

local function common_prefix(s1, s2)
    local len = #s1
    if #s2 < len then len = #s2 end
    
    local prefixlen = 0
    
    for i=1,len do
        if s1:sub(i,i) == s2:sub(i,i) then
            prefixlen = i
        else
            break
        end
    end
    return s1:sub(1, prefixlen)
end

local ve_keys = {
    ['\t'] = function()
        local buf = buffer._textredux
        if not buf.data.complete then
            return
        end
        local t = buf.data.text
        local pos = buffer.current_pos - #buf.data.prompt
        local preceding = t:sub(1, pos)
        
        local startpos, to_complete, endpos = preceding:match("^.-()(%S*)()$")
        local first_word = t:match("^(%S*)")
        local completions = buf.data.complete(to_complete, first_word)
        
        --[[]
        ui.print("#completions: "..tostring(#completions))
        for k,v in ipairs(completions) do
            ui.print("  "..v)
        end
        --[[]]
        
        if #completions == 1 then
            local repl = completions[1]
            t = t:sub(1, startpos-1) .. repl .. t:sub(endpos)
            buf.data.text = t
            buf.data.pos = startpos + #repl - 1
            buf:refresh()
        elseif #completions > 1 then
            -- See if there's a common prefix
            local prefix = completions[1]
            for i=2,#completions do
                prefix = common_prefix(prefix, completions[i])
                if #prefix == 0 then break end
            end
            if #prefix > #to_complete then
                t = t:sub(1, startpos-1) .. prefix .. t:sub(endpos)
                buf.data.text = t
                buf.data.pos = startpos + #prefix - 1
                buf:refresh()
            end
        end
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
        local pos = buffer.current_pos - #buf.data.prompt
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

function M.enter_mode(prompt, handler, complete)
  local buf = redux.core.buffer.new('entry')
  buf.on_refresh = ve_refresh
  buf.keys = ve_keys
  buf.data = {
      prompt=prompt,
      text = '',
      pos=#prompt,
      handler=handler,
      complete=complete,
  }
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