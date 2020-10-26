-- Search for file by name/pattern.
local M = {}
local DEBUG_FIND_FILES=false
local debug_find
local debug_find_files_file
local debug_ts
if DEBUG_FIND_FILES then
    debug_ts = require('vi_util').tostring
    debug_find = function(text)
        if debug_find_files_file == nil then
            debug_find_files_file = io.open("ta_debug_find_files.txt", "w")
        end
        debug_find_files_file:write(text .. "\n")
        debug_find_files_file:flush()
    end
else
    debug_ts = function() return "" end
    debug_find = function() end
end

local lfs = _G.lfs
local vi_regex = require('regex.pegex')

-- Escape a Lua pattern to make it an exact match.
function M.luapat_escape(s)
    -- replace metacharacters
    s = s:gsub("[%(%)%%%.%[%]%*%+%-%?]", function (s) return "%"..s end)

    -- ^ and $ only apply at the start/end
    if s:sub(1,1) == "^" then s = "%" .. s end
    if s:sub(-1,-1) == "$" then s = s:sub(1,-2) .. "%$" end
    return s
end

-- Escape a glob pattern to make it an exact match.
function M.glob_escape(s)
    -- replace metacharacters
    local s = s:gsub("[][\\*?]", function (s) return "\\"..s end)

    return s
end

local function mkmatch_luapat(pat, allow_wild_end)
    local fullpat = '^' .. pat

    if allow_wild_end then
        fullpat = fullpat .. '.*'
    end
    fullpat = fullpat .. '$'
    return function(text)
        local result = text:match(fullpat)
        return result
    end
end

-- Convert a glob pattern into a Lua pattern
local function glob_to_luapat(pat)
    local tab = {'^'}
    local i=1
    while i <= #pat do
        local c = pat:sub(i, i)
        if c == "*" then
            table.insert(tab, ".*")
        elseif c == "?" then
            table.insert(tab, ".")
        elseif c:match("[%^%$%(%)%%%.%[%]%+%-]") then
            table.insert(tab, "%")
            table.insert(tab, c)
        -- elseif handle character class
        else
            table.insert(tab, c)
        end
        i = i + 1
    end
    return table.concat(tab)
end

local function mkmatch_glob(pat, allow_wild_end)
    -- Convert a glob pattern into a Lua pattern
    local fullpat = glob_to_luapat(pat)
    if allow_wild_end then
        -- Special case for empty pattern - don't match dotfiles
        if fullpat == "^" then
            fullpat = fullpat .. '[^%.].*'
        else
            fullpat = fullpat .. '.*'
        end
    end
    fullpat = fullpat .. '$'
    debug_find("mkmatch_glob: [["..pat.."]] -> [["..fullpat.."]]")
    return function(text)
        local result = text:match(fullpat)
        return result
    end
end

local function mkmatch_null(pat, allow_wild_end)
    local escaped_pat = '^' .. M.luapat_escape(pat)
    if allow_wild_end then
        escaped_pat = escaped_pat .. '.*'
    end
    escaped_pat = escaped_pat .. '$'
    return function(text)
        local result = text:match(escaped_pat)
        return result
    end
end

function do_matching_files(text, mk_matcher, escape)
    local patparts = {} -- the pieces of the pattern
    debug_find("do_matching_files(text=[["..debug_ts(text).."]], mk_matcher, [["..debug_ts(escape).."]])")
    -- Split the pattern into parts separated by /
    local is_abs
    if text then
        if text:sub(1,1) == '/' then
            text = text:sub(2)
            is_abs = true
        end
        for part in text:gmatch('[^/]+') do
            table.insert(patparts, part)
        end
        -- If tab on trailing /, then will want to complete on files in the
        -- directory.
        if text:sub(-1) == '/' then
            table.insert(patparts, '')
        end
    end
    debug_find("do_matching_files: patparts="..debug_ts(patparts))
    -- partmatches[n] is a list of matches for patparts[n] at that level
    local parts = { }
    -- Set of directories to look in
    local dirs = { }

    -- The start depends on whether the path is absolute or relative
    if is_abs then
        table.insert(dirs, '/')
    elseif patparts[1] == '~' then
        -- Handle ~/...
        table.insert(dirs, os.getenv("HOME") .. "/")
        -- Remove the initial ~
        table.remove(patparts, 1)
    else
        table.insert(dirs, './')
    end
    debug_find("do_matching_files: parts="..debug_ts(parts))
    debug_find("do_matching_files: dirs="..debug_ts(dirs))

    -- For each path section
    for level, patpart in ipairs(patparts) do
      debug_find("for each path: level="..debug_ts(level)..", patpart="..debug_ts(patpart))
      local last = (level == #patparts)

      debug_find("for each: last="..debug_ts(last))
      -- If the last part, then allow trailing parts
      -- TODO: if we complete from a middle-part, then
      -- this test should be for where the cursor is.
      local allow_wild_end = last
      debug_find("for each: allow_wild_end="..debug_ts(allow_wild_end))

      -- The set of paths for the following loop
      local newdirs = {}
      local matcher = mk_matcher(patpart, allow_wild_end)

      -- For each possible directory at this level
      for _,dir in ipairs(dirs) do
        debug_find(" for dir [["..debug_ts(dir).."]]")
        for fname in lfs.dir(dir) do
          debug_find("   for fname [["..debug_ts(fname).."]]")
          if matcher(fname) then
            local fullpath
            if dir == "./" then
                fullpath = fname
            else
                fullpath = dir .. fname
            end
            debug_find("   for fname: fullpath=[["..debug_ts(fullpath).."]]")
            local isdir = lfs.attributes(fullpath, 'mode') == 'directory'
            debug_find("   for fname: isdir=[["..debug_ts(isdir).."]]")

            -- Record this path if it's not a non-directory with more path
            -- parts to go.
            if isdir and not last then
                table.insert(newdirs, fullpath .. '/')
            elseif last then
                table.insert(newdirs, fullpath)
            end
          end
        end
      end
      -- Switch to the next level of items
      dirs = newdirs
    end  -- loop through pattern parts
    debug_find("do_matching_files: dirs="..debug_ts(dirs))

    -- Find out the set of components at each level
    -- parts[level] is a table { fname="f",fname2="f",dirname="d",fileordir="b", fname,fname2}
    local parts = {}
    for _,res in ipairs(dirs) do
        local level = 1
        debug_find("   res=[["..res.."]]")
        local res_is_dir = lfs.attributes(res, 'mode') == 'directory'
        -- Remove the leading / for this search
        if is_abs then
            assert(res:sub(1,1) == "/")
            res = res:sub(2)
        end
        for piece in res:gmatch('[^/]*') do
            local last = (level == #patparts)
            local isdir = (not last) or res_is_dir
            debug_find("   level="..level..", last="..tostring(last)..", isdir="..debug_ts(isdir))
            debug_find("   piece=[["..debug_ts(piece).."]]")
            ps = parts[level] or {}
            parts[level] = ps

            local type = isdir and "d" or "f"
            if ps[piece] == nil then
              ps[piece] = type
              table.insert(ps, piece)
            elseif ps[piece] ~= type then
              ps[piece] = "b"
            end
            level = level + 1
        end
    end
    debug_find("do_matching_files: #3: parts="..debug_ts(parts))

    -- Now rebuild the pattern, with some ambiguities removed
    local narrowed = false  -- whether we've added more unambiguous info
    local newparts = {}
    -- keep absolute or relative
    if is_abs then
        table.insert(newparts,  '/')
    end
    for level,matches in ipairs(parts) do
        debug_find("for level="..debug_ts(level)..", matches="..debug_ts(matches))
        local last = (level == #parts)
        debug_find("   last="..tostring(last)..", #matches="..tostring(#matches))
        if #matches == 1 then
            -- Only one thing, so use that.
            local newpart = escape(matches[1])
            debug_find("   newpart=[["..debug_ts(newpart).."]]")
            if newpart ~= patparts[level] then
                narrowed = true
            end
            debug_find("   narrowed=[["..debug_ts(narrowed).."]]")
            table.insert(newparts, newpart)
            if last and matches[matches[1]] == "d" then
                table.insert(newparts, '/')
            end
        else
            table.insert(newparts, patparts[level])
        end
        if not last then table.insert(newparts, '/') end
    end
    debug_find("After loop, newparts="..debug_ts(newparts))
    local files
    if narrowed then
        files = { table.concat(newparts) }
    else
        debug_find("After loop not narrowed, but dirs="..debug_ts(dirs))
        files = {}
        table.sort(dirs)
        for i,d  in ipairs(dirs) do
            files[i] = escape(d)
        end
    end
    debug_find("do_matching_files: files="..debug_ts(files))
    return files
end

-- Match filename exactly, with no escaping or wildcards etc.
function M.matching_files_nopat(text)
    local escape = function(s) return s end
    return do_matching_files(text, mkmatch_null, escape)
end

-- Find files with globs.
function M.matching_files(text, doescape)
    -- Escape by default
    local escape
    if doescape == nil or doescape then
        escape = M.glob_escape
    else
        escape = function(s) return s end
    end

    return do_matching_files(text, mkmatch_glob, escape)
end

-- Find files matching a Regex pattern (or a string match)
function find_matching_files_lua(pattern)
    local results = {}
    local pat = vi_regex.compile(pattern)
    local function f(filename)
        if (pat and pat:match(filename)) or filename:find(pattern, 1, true) then
            results[#results+1] = filename
        end
    end
    lfs.dir_foreach('.', f, { folders = { "build"}}, nil, false)
    return results
end

function M.find_matching_files(pat)
    local findprg = vi_mode.state.variables.findprg
    if findprg ~= nil then
        local fproc = os.spawn(findprg .. " " .. pat)
        local files = {}
        while true do
            local line, err, errmsg = fproc:read()
            -- TODO: log errors and stderr
            if line == nil then break end
            table.insert(files, line)
        end
        fproc:close()
        return files
    else
        -- Default to built-in function
        return find_matching_files_lua(pat)
    end
end

return M
