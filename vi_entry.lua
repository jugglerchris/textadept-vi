local M = {
    MAX_COMPLETION_LINES = 5
}

local redux = require'textredux'

local function ve_refresh(buf)
  -- Disable all margins, except one we'll use for the :
  buf.margin_width_n[0] = 0
  buf.margin_width_n[1] = 0
  buf.margin_width_n[2] = 0
  buf.margin_width_n[3] = 0
  
  buf.margin_width_n[4] = #buf.data.prompt
  buf.margin_type_n[4] = buf.MARGIN_TEXT
  buf.margin_text[0] = buf.data.prompt
  buf.margin_style[0] = 8 -- error (red)
  
  buf:add_text(buf.data.text, redux.core.style.comment)
  buf:goto_pos(buf.data.pos)

  local linesize = CURSES and 1 or 20
  local offset = CURSES and 4 or 100
  
  if buf.data.completions then
      local cs = buf.data.completions
      local comp_offset = buf.data.completions_offset
      local count = #buf.data.completions - comp_offset
      buf:append_text('\n')
      if count > 10 then count = 10 end
      for i=1,count do
          local comp_idx = i+comp_offset
          local style = (comp_idx == buf.data.completions_sel) and
                                (redux.core.style.string .. { back="#FFFFFF" }) or redux.core.style.string
          buf:append_text(cs[comp_idx].."\n", style)
      end
      local lines = buf.line_count
      if lines > M.MAX_COMPLETION_LINES+1 then lines = M.MAX_COMPLETION_LINES+1 end
      view.size = ui.size[2] - offset - linesize * (lines-1)
  else
      -- go back to one line if necessary
      view.size = ui.size[2] - offset
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
       local curview = view
       ui.goto_view(_VIEWS[splits])
       local result = {
           buffer=splits.buffer,
           current=(splits == curview),
           pos=splits.buffer.current_pos,
           anchor=splits.buffer.anchor,
           firstline = splits.buffer.first_visible_line,
       }
       ui.goto_view(_VIEWS[curview])
       return result
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
            buffer.anchor = saved.anchor
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

-- Replace the current word
local function replace_word(buf, repl)
    local t = buf.data.text
    local pos = buf.data.pos
    local preceding = t:sub(1, pos)
    local startpos, to_complete, endpos = preceding:match("^.-()(%S*)()$")
    
    t = t:sub(1, startpos-1) .. repl .. t:sub(endpos)
    buf.data.text = t
    buf.data.pos = startpos + #repl - 1
    buf:refresh()
end

-- expand=nil/false means only show completions, don't update buffer.
local function complete_now(expand)
    local buf = buffer._textredux
    if not buf.data.complete then
        return
    end
    buf.data.completions = nil
    buf.data.completions_sel = 0
    local t = buf.data.text
    local pos = buf.data.pos
    local preceding = t:sub(1, pos)
    
    local startpos, to_complete, endpos = preceding:match("^.-()(%S*)()$")
    local first_word = t:match("^(%S*)")
    local completions = buf.data.complete(to_complete, first_word) or {}
    
    if #completions == 1 and expand then
        local repl = completions[1]
        
        replace_word(buf, repl)
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
        if #prefix > #to_complete then
            replace_word(buf, prefix)
        else
            -- No common prefix, so show completions.
            buf.data.completions = completions
            buf.data.completions_offset = 0
            buf:refresh()
        end
    end
end

-- Show the next N completions
local function complete_advance()
    local buf = buffer._textredux
    local offset = buf.data.completions_offset
    local completions = buf.data.completions
    offset = offset + M.MAX_COMPLETION_LINES
    if offset >= #completions then
        offset = 0
    end
    buf.data.completions_offset = offset
    -- If the user has started selecting completions, move it along.
    if buf.data.completions_sel and buf.data.completions_sel > 0 then
        buf.data.completions_sel = buf.data.completions_offset + 1
    end
    buf:refresh()
end

local function do_enter()
    local buf = buffer._textredux
    
    if buf.data.completions_sel and buf.data.completions_sel ~= 0 then
        -- We've selected a completion.
        local chosen = buf.data.completions[buf.data.completions_sel]
        buf.data.completions = nil
        buf.data.completions_sel = 0
        replace_word(buf, chosen)
    else
        local saved = buf.data.saved
        local cmd = buf:get_text()
        local handler = buf.data.handler
        local hist = buf.data.context._history
        local histsaveidx = buf.data.histsaveidx
        buf:close()
        unsplit_all()
        local newcur = restore_into(view,saved)
        if newcur and _VIEWS[newcur] then
          ui.goto_view(_VIEWS[newcur])
        end
        -- Save the command in the history
        hist[histsaveidx] = cmd
        handler(cmd)
    end
end

local ve_keys = {
    ['\t'] = function()
        local buf = buffer._textredux
        if buf.data.completions ~= nil and #buf.data.completions > 1 then
            complete_advance()
        else
            complete_now(true)
        end
    end,
    ['\b'] = function()
        local buf = buffer._textredux
        local t = buf.data.text
        local pos = buffer.current_pos
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
        local pos = buffer.current_pos
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
    ['\r'] = do_enter,
    ['\n'] = do_enter,
    up = function()
        local buf = buffer._textredux
        if buf.data.completions then
            local sel_line = buf.data.completions_sel
            sel_line = sel_line - 1
            if sel_line < 1 then
                sel_line = #buf.data.completions
            end
            buf.data.completions_sel = sel_line
            
            local min_visible = buf.data.completions_offset + 1
            local max_visible = buf.data.completions_offset + M.MAX_COMPLETION_LINES
            if sel_line > max_visible or sel_line < min_visible then
                buf.data.completions_offset = math.floor((sel_line - 1) / M.MAX_COMPLETION_LINES) * M.MAX_COMPLETION_LINES
            end
        else
            local idx = buf.data.histidx
            local hist = buf.data.context._history
            -- Save this item
            if idx == buf.data.histsaveidx then
                buf.data.context._history[idx] = buf.data.text
            end
            if idx > 1 then
                idx = idx - 1
                buf.data.histidx = idx
            end
            buf.data.text = hist[idx]
            buf.data.pos = #buf.data.text
        end
        buf:refresh()
    end,
    down = function()
        local buf = buffer._textredux
        if buf.data.completions then
            local sel_line = buf.data.completions_sel
            sel_line = sel_line + 1
            if sel_line > #buf.data.completions then
                sel_line = 1
            end
            buf.data.completions_sel = sel_line
            
            local min_visible = buf.data.completions_offset + 1
            local max_visible = buf.data.completions_offset + M.MAX_COMPLETION_LINES
            if sel_line > max_visible or sel_line < min_visible then
                buf.data.completions_offset = math.floor((sel_line - 1) / M.MAX_COMPLETION_LINES) * M.MAX_COMPLETION_LINES
            end
        else
            local idx = buf.data.histidx
            local hist = buf.data.context._history
            if idx < buf.data.histsaveidx then
                idx = idx + 1
                buf.data.histidx = idx
                buf.data.text = hist[idx]
                buf.data.pos = #buf.data.text
            end
        end
        buf:refresh()
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

local function do_start(context)
  local buf = redux.core.buffer.new('entry')
  buf.on_refresh = ve_refresh
  buf.keys = ve_keys
  buf.data = {
      prompt=context._prompt,
      text = '',
      pos=0,
      handler=context._handler,
      complete=context._complete,
      context=context,
      histidx=#context._history+1,
      histsaveidx=#context._history+1,
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

-- Create a new entry context
function M.new(prompt, handler, complete)
    local result = {
        _prompt=prompt,
        _handler=handler,
        _complete=complete,
        _history={},
        start = do_start,
    }
    return result
end

return M
