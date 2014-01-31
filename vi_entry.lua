local M = {}

local redux = require'textredux'

local function ve_refresh(buf)
  -- Disable fold margin
  buffer.margin_width_n[2] = 0
  
  buf:add_text(buf.data.prompt, redux.core.style.error)
  buf:add_text(buf.data.text, redux.core.style.comment)
  buf:goto_pos(buf.data.pos + #buf.data.prompt)
  
  if buf.data.completions then
      local cs = buf.data.completions
      local count = #buf.data.completions
      buf:append_text('\n')
      if count > 10 then count = 10 end
      for i=1,count do
          buf:append_text(cs[i].."\n", redux.core.style.string)
      end
      local lines = buf.line_count
      if lines > 6 then lines = 6 end
      view.size = ui.size[2] - 4 - (lines-1)
  else
      -- go back to one line if necessary
      view.size = ui.size[2] - 4
  end
end

-- Return a saved version of splits so that we can regenerate them.
local function save_splits(splits)
    if splits[1] and splits[2] then
       -- it's a split
       splits[1] = save_splits(splits[1])
       splits[2] = save_splits(splits[2])
       return splits
    else
       return {
           buffer=splits.buffer,
           current=(splits == view),
           pos=splits.buffer.current_pos,
           firstline = splits.buffer.first_visible_line,
       }
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

-- Returns the view which should be current, or nil
local function restore_into(v, saved)
    if saved[1] and saved[2] then
        local cur1, cur2
        -- restore the split
        first, second = v:split(saved.vertical)
        first.size = saved.size
        cur1 = restore_into(first, saved[1])
        cur2 = restore_into(second, saved[2])
        -- return current if found in theis branch
        return cur1 or cur2
    else
        local buf = saved.buffer
        if _BUFFERS[buf] then
            ui.goto_view(_VIEWS[v])
            v:goto_buffer(_BUFFERS[buf])
            buffer.first_visible_line = saved.firstline
            buffer.current_pos = saved.pos
            if saved.current then return v end
        else
            ui.print("Buffer not found:", buf.filename, buf)
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
    local old, new = view:split()
    old.size = ui.size[2] - 4
    
    local cur = restore_into(old,saved)
    return new, cur
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

-- expand=nil/false means only show completions, don't update buffer.
local function complete_now(expand)
    local buf = buffer._textredux
    if not buf.data.complete then
        return
    end
    buf.data.completions = nil
    local t = buf.data.text
    local pos = buf.data.pos
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
    local skip_prefix = completions.skip_prefix or 0
    
    if #completions == 1 and expand then
        local repl = completions[1]
        t = t:sub(1, startpos+skip_prefix-1) .. repl .. t:sub(endpos)
        buf.data.text = t
        buf.data.pos = startpos + skip_prefix + #repl - 1
        buf:refresh()
    elseif #completions >= 1 then
        -- See if there's a common prefix
        local prefix = ""
        if expand then
            prefix = completions[1]
            for i=2,#completions do
                prefix = common_prefix(prefix, completions[i])
                if #prefix == 0 then break end
            end
        end
        if #prefix > (#to_complete - skip_prefix) then
            t = t:sub(1, startpos+skip_prefix-1) .. prefix .. t:sub(endpos)
            buf.data.text = t
            buf.data.pos = startpos + skip_prefix + #prefix - 1
            buf:refresh()
        else
            -- No common prefix, so show completions.
            buf.data.completions = completions
            buf:refresh()
        end
    end
end

local ve_keys = {
    ['\t'] = function()
        complete_now(true)
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
        local newcur = restore_into(view,saved)
        if newcur and _VIEWS[newcur] then
            ui.goto_view(_VIEWS[newcur])
        end
    end,
    ['\r'] = function()
        local buf = buffer._textredux
        local saved = buf.data.saved
        local cmd = buf:get_text():sub(#buf.data.prompt + 1)
        local handler = buf.data.handler
        buf:close()
        unsplit_all()
        local newcur = restore_into(view,saved)
        if newcur and _VIEWS[newcur] then
          ui.goto_view(_VIEWS[newcur])
        end
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
        if buf.data.completions then
            complete_now()
        end
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
  local newview, prevcur = restore_saved(saved)
  newview.size = ui.size[2] - 4
  ui.goto_view(_VIEWS[newview])
  buf.data.saved = saved
  buf:show()
end

return M