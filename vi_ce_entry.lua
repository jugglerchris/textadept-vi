local M = {
    MAX_COMPLETION_LINES = 5
}
local DEBUG_COMPLETE = false
local debug_complete
local debug_complete_file
local debug_ts
if DEBUG_COMPLETE then
    debug_ts = require('vi_util').tostring
    debug_complete = function(text)
        if debug_complete_file == nil then
            debug_complete_file = io.open("ta_debug_complete.txt", "w")
        end
        debug_complete_file:write(text .. "\n")
        debug_complete_file:flush()
    end
else
    debug_complete = function() end
    debug_ts = function() return "" end
end

local redux = require'textredux'

-- Save any margin state we might be changing, so that
-- it can be restored later.
local function save_margins(buffer)
    local result = {
        width = {},
        type = {},
        text = {},
        style = {},
    }
    for i=1,5 do
        result.width[i] = buffer.margin_width_n[i]
        result.type[i] = buffer.margin_type_n[i]
        result.text[i] = buffer.margin_text[i]
        result.style[i] = buffer.margin_style[i]
    end
    return result
end

local function restore_margins(buffer, state)
    for i=1,5 do
        buffer.margin_width_n[i] = state.width[i]
        buffer.margin_type_n[i] = state.type[i]
        buffer.margin_text[i] = state.text[i]
        buffer.margin_style[i] = state.style[i]
    end
end

-- Define a style for highlighting completions
redux.core.style.string_hl = redux.core.style.string .. { back="#FFFFFF" }
local function ve_refresh(buf)
  -- Disable all margins, except one we'll use for the :
  buf.margin_width_n[1] = 0
  buf.margin_width_n[2] = 0
  buf.margin_width_n[3] = 0
  buf.margin_width_n[4] = 0

  buf.margin_width_n[5] = #buf.data.prompt
  buf.margin_type_n[5] = buf.MARGIN_TEXT
  buf.margin_text[1] = buf.data.prompt
  buf.margin_style[1] = 8 -- error (red)

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
                                redux.core.style.string_hl or redux.core.style.string
          buf:append_text(cs[comp_idx].."\n", style)
      end
      local lines = buf.line_count
      if lines > M.MAX_COMPLETION_LINES+1 then lines = M.MAX_COMPLETION_LINES+1 end
      ui.command_entry.height = lines
  else
      -- go back to one line if necessary
      ui.command_entry.height = 1
  end
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
    local preceding = t:sub(1, pos-1)
    local startpos, to_complete, endpos = preceding:match("^.-()(%S*)()$")
    debug_complete("replace_word: text=[["..debug_ts(t).."]]")
    debug_complete("replace_word: pos="..debug_ts(pos))
    debug_complete("replace_word: preceding=[["..debug_ts(preceding).."]]")

    t = t:sub(1, startpos-1) .. repl .. t:sub(endpos)
    buf.data.text = t
    buf.data.pos = startpos + #repl
    debug_complete("replace_word: text=[["..debug_ts(t).."]]")
    buf:refresh()
end

-- expand=nil/false means only show completions, don't update buffer.
local function complete_now(expand)
    debug_complete("complete_now("..debug_ts(expand)..")")
    local buffer = ui.command_entry
    local buf = buffer._textredux
    if not buf.data.complete then
        debug_complete("complete_now: not buf.data.complete")
        return
    end
    buf.data.completions = nil
    buf.data.completions_sel = 0
    local t = buf.data.text
    local pos = buf.data.pos
    local preceding = t:sub(1, pos-1)

    local startpos, to_complete, endpos = preceding:match("^.-()(%S*)()$")
    local first_word = t:match("^(%S*)")
    debug_complete("complete_now: first_word='"..debug_ts(first_word).."'")
    local completions = buf.data.complete(to_complete, first_word) or {}
    debug_complete("complete_now: completions="..debug_ts(completions))

    -- Completions are no longer stale.
    buf.data.completions_stale = false

    if #completions == 1 and expand then
        local repl = completions[1]
        debug_complete("complete_now: One completion so expanding: repl=[["..debug_ts(repl).."]]")

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
            debug_complete("complete_now: expand: prefix=[["..debug_ts(prefix).."]]")
        end
        if #prefix > #to_complete then
            debug_complete("complete_now: prefix is longer, so replacing.")
            replace_word(buf, prefix)
        else
            debug_complete("complete_now: No longer prefix, showing completions.")
            -- No common prefix, so show completions.
            buf.data.completions = completions
            buf.data.completions_offset = 0
            buf:refresh()
        end
    end
end

-- Show the next N completions
local function complete_advance()
    local buffer = ui.command_entry
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

-- Close the entry
local function close(reduxbuf)
    local marginstate = reduxbuf.data.marginstate
    local buffer = reduxbuf.target
    restore_margins(buffer, marginstate)
    buffer:clear_all()
    reduxbuf:close()
end

local function do_enter()
    local buffer = ui.command_entry
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
        close(buf)

        -- Save the command in the history
        hist[histsaveidx] = cmd
        handler(cmd)
    end
end

local ve_keys = {
    ['\t'] = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        if buf.data.completions ~= nil and #buf.data.completions > 1 and not buf.data.completions_stale then
            complete_advance()
        else
            complete_now(true)
        end
    end,
    left = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        if buf.data.pos > 1 then
            buf.data.pos = buf.data.pos - 1
            buf:refresh()
        end
    end,
    right = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        if buf.data.pos <= #buf.data.text then
            buf.data.pos = buf.data.pos + 1
            buf:refresh()
        end
    end,
    ['\b'] = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        local t = buf.data.text
        if t == "" then -- exit
            do_enter()
            return
        end
        local pos = buffer.current_pos
        if pos > 1 then
            t = t:sub(1, pos-2) .. t:sub(pos, -1)
            buf.data.text = t
            buf.data.pos = pos - 1
            buf:refresh()
        end
    end,
    cu = function()
        -- Clear to start of line
        local buffer = ui.command_entry
        local buf = buffer._textredux
        local t = buf.data.text
        local pos = buffer.current_pos
        if pos > 1 then
            t = t:sub(pos, -1)
            buf.data.text = t
            buf.data.pos = 1
            buf:refresh()
        end
    end,
    esc = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        local saved = buf.data.saved
        close(buf)
    end,
    ['\r'] = do_enter,
    ['\n'] = do_enter,
    up = function()
        local buffer = ui.command_entry
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
            local newidx = idx
            local origtext = buf.data.text
            while newidx > 1 do
                newidx = newidx - 1
                if hist[newidx]:sub(1, #origtext) == origtext then
                    idx = newidx
                    buf.data.histidx = idx
                    break
                end
            end
            buf.data.text = hist[idx]
            buf.data.pos = #buf.data.text+1
        end
        buf:refresh()
    end,
    down = function()
        local buffer = ui.command_entry
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
                buf.data.pos = #buf.data.text+1
            end
        end
        buf:refresh()
    end
}
local function set_key(k)
    ve_keys[k] = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        local t = buf.data.text
        local pos = buffer.current_pos
        t = t:sub(1, pos-1) .. k .. t:sub(pos, -1)
        buf.data.text = t
        buf.data.pos = pos + 1
        if buf.data.completions then
            complete_now()
            -- We should retry completion on tab even if we have saved the completions,
            -- but we can continue using them if just typing extra characters.
            buf.data.completions_stale = true
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
  for k,v in pairs(ve_keys) do
      buf.keys[k] = v
  end
  buf.data = {
      prompt=context._prompt,
      text = '',
      pos=1,
      handler=context._handler,
      complete=context._complete,
      context=context,
      histidx=#context._history+1,
      histsaveidx=#context._history+1,
  }
  buf.data.marginstate = save_margins(ui.command_entry)

  buf:attach_to_command_entry()
  ui.command_entry.height = 1
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
