local M = {
    MAX_COMPLETION_LINES = 5
}
local DEBUG_COMPLETE = true
local debug_complete
local debug_complete_file
local debug_ts
if DEBUG_COMPLETE then
    debug_ts = require('textadept-vi.vi_util').tostring
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

-- Handle expanding the word as possible.
-- Params:
--    word: The entire word containing (or just to the left of) the
--          cursor
--    pos:  The cursor position (0 == just before the word)
--    completions: A list of possible matches.
-- Returns:
--    new_word: Possibly updated word, or nil if no change could be made
--    new_pos:  Position of cursor within the word (if new_word is present)
local function do_expand(word, pos, completions)
    debug_complete("do_expand("..debug_ts(word)..", "..pos..", "..debug_ts(completions))
    local prefix = completions[1]
    for i=2,#completions do
        prefix = common_prefix(prefix, completions[i])
        if #prefix == 0 then break end
    end
    -- If we've made no progress (no common prefix), then give up now.
    if #prefix == 0 or prefix == word:sub(1, #prefix) then
        return nil, nil
    end

    -- We've expanded the prefix.  However, if the original pattern doesn't
    -- appear in the prefix, then put it after the prefix and the cursor
    -- in between.  This assumes a straight text match of the suffix.
    --
    -- The suffix is either:
    --   The whole word, if the cursor was at the end OR
    --   the part of the word after the cursor
    local suffix
    if pos == #word then
        suffix = word
    else
        suffix = word:sub(pos+1)
    end
    local add_suffix = true
    for i=1,#completions do
        local s, e = completions[i]:find(suffix, 1, true)
        if s == nil or s < #prefix then
            -- The suffix doesn't follow the prefix, so we can't just add the suffix
            add_suffix = false
            break
        end
    end
    if add_suffix then
        return prefix .. suffix, #prefix
    else
        return prefix, #prefix
    end
end

local _test_expand_cases = {
    -- No progress possible
    {
        "foo", 3,
        { "foobar", "fooqux" },
        nil, nil
    },
    -- Some progress possible
    {
        "foo", 3,
        { "foobar", "foobaz" },
        "fooba", 5
    },
    -- Some progress, but the pattern is not at the start
    {
        "foo", 3,
        { "bar/baz/foo", "baz/bar/foo" },
        "bafoo", 2
    },
    -- Some progress with the cursor not at the end of the word
    {
        "barfoo", 2,
        { "bar/baz/foo" },
        "bar/baz/foo", 11
    },
    -- No expansion from middle
    {
        "dirxx", 3,
        { "dirone/xxx.c", "dirtwo/xxx.c" },
        nil, nil
    },
    -- Full expansion from middle
    {
        "diroxx", 4,
        { "dirone/xxx.c" },
        "dirone/xxx.c", 12
    },
}
function M._test_expand()
    local ts = require('textadept-vi.vi_util').tostring
    for _,testcase in ipairs(_test_expand_cases) do
        local word = testcase[1]
        local wordpos = testcase[2]
        local completions = testcase[3]
        local res1 = testcase[4]
        local res2 = testcase[5]
        local out1, out2 = do_expand(word, wordpos, completions)
        if out1 ~= res1 or out2 ~= out2 then
            test.log("Expand test case failed:" .. ts(testcase))
            test.log("do_expand returned: " .. ts(out1) .. " and " .. ts(out2))
            assert(false)
        end
    end
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

    local startpos, to_complete_prefix, endpos = preceding:match("^.-()(%S*)()$")
    local first_word = t:match("^(%S*)")
    local following = t:sub(pos)
    local to_complete_suffix = following:match("^(%S*)")
    local to_complete = to_complete_prefix .. to_complete_suffix
    debug_complete("complete_now: first_word='"..debug_ts(first_word).."'")
    debug_complete("complete_now: to_complete='"..debug_ts(to_complete).."'")
    local completions = buf.data.complete(to_complete_prefix, first_word, to_complete_suffix) or {}
    debug_complete("complete_now: completions="..debug_ts(completions))

    -- Completions are no longer stale.
    buf.data.completions_stale = false

    if #completions >= 1 then
        -- See if there's a common prefix
        local new_word, new_wordpos
        if expand then
            new_word, new_wordpos = do_expand(to_complete, pos - startpos, completions)
            debug_complete("complete_now: expand: prefix=[["..debug_ts(prefix).."]]")
        end
        if new_word ~= nil then
            debug_complete("complete_now: prefix is longer, so replacing.")
            -- replace_word only replaces the word before the cursor, but we
            -- want to replace the whole word - so move the cursor before
            -- calling it for now.
            buf.data.pos = buf.data.pos + #to_complete_suffix
            replace_word(buf, new_word)
            buf.data.pos = new_wordpos + startpos
            buf:refresh()
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
    home = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        buf.data.pos = 1
        buf:refresh()
    end,
    ['end'] = function()
        local buffer = ui.command_entry
        local buf = buffer._textredux
        buf.data.pos = #buf.data.text + 1
        buf:refresh()
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
    ['ctrl+u'] = function()
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
