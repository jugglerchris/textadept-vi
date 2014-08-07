-- Search for file by name/pattern.
local M = {}

local lfs = require 'lfs'
local vi_regex = require('regex.regex')

-- Escape a Lua pattern to make it an exact match.
function M.luapat_escape(s)
    -- replace metacharacters
    s = s:gsub("[%(%)%%%.%[%]%*%+%-%?]", function (s) return "%"..s end)

    -- ^ and $ only apply at the start/end
    if s:sub(1,1) == "^" then s = "%" .. s end
    if s:sub(-1,-1) == "$" then s = s:sub(1,-2) .. "%$" end
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

local ignore_complete_files = { ['.'] = 1 }
function do_matching_files(text, mk_matcher, escape)
    local patparts = {} -- the pieces of the pattern
    -- Split the pattern into parts separated by /
    if text then
        for part in text:gmatch('[^/]+') do
            table.insert(patparts, part)
        end
        -- If tab on trailing /, then will want to complete on files in the
        -- directory.
        if text:sub(-1) == '/' then
            table.insert(patparts, '')
        end
    end
    -- partmatches[n] is a list of matches for patparts[n] at that level
    local parts = { }
    -- Set of directories to look in
    local dirs = { }

    -- The start depends on whether the path is absolute or relative
    if text and text:sub(1, 1) == '/' then
        table.insert(dirs, '/')
    elseif patparts[1] == '~' then
        -- Handle ~/...
        table.insert(dirs, os.getenv("HOME") .. "/")
        -- Remove the initial ~
        table.remove(patparts, 1)
    else
        table.insert(dirs, './')
    end

    -- For each path section
    for level, patpart in ipairs(patparts) do
      local last = (level == #patparts)

      -- If the last part, then allow trailing parts
      -- TODO: if we complete from a middle-part, then
      -- this test should be for where the cursor is.
      local allow_wild_end = last

      -- The set of paths for the following loop
      local newdirs = {}
      local matcher = mk_matcher(patpart, allow_wild_end)

      -- For each possible directory at this level
      for _,dir in ipairs(dirs) do
        for fname in lfs.dir(dir) do
          if not ignore_complete_files[fname] and matcher(fname) then
            local fullpath
            if dir == "./" then
                fullpath = fname
            else
                fullpath = dir .. fname
            end
            local isdir = lfs.attributes(fullpath, 'mode') == 'directory'

            -- Record this path if it's not a non-directory with more path
            -- parts to go.
            if lfs.attributes(fullpath, 'mode') == 'directory' then
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

    -- Find out the set of components at each level
    -- parts[level] is a table { fname=1,fname2=1, fname,fname2}
    local parts = {}
    for _,res in ipairs(dirs) do
        local level = 1
        for piece in res:gmatch('[^/]*') do
            ps = parts[level] or {}
            parts[level] = ps

            if ps[piece] == nil then
              ps[piece] = 1
              table.insert(ps, piece)
            end
        end
    end

    -- Now rebuild the pattern, with some ambiguities removed
    local narrowed = false  -- whether we've added more unambiguous info
    local newparts = {}
    -- keep absolute or relative
    if text:sub(1,1) == '/' then
        table.insert(newparts,  '/')
    end
    for level,matches in ipairs(parts) do
        local last = (level == #parts)
        if #matches == 1 then
            -- Only one thing, so use that.
            local newpart = escape(matches[1])
            if newpart ~= patparts[level] then
                narrowed = true
            end
            table.insert(newparts, newpart)
            -- matches[fname] is true if all options are directories
            if last and matches[matches[1]] then
                table.insert(newparts, '/')
            end
        else
            table.insert(newparts, patparts[level])
        end
        if not last then table.insert(newparts, '/') end
    end
    local files
    if narrowed then
        files = { table.concat(newparts) }
    else
        files = {}
        table.sort(dirs)
        for i,d  in ipairs(dirs) do
            files[i] = escape(d)
        end
    end
    return files
end

-- Find files with patterns
function M.matching_files(text, doescape)
    -- Escape by default
    local escape
    if doescape == nil or doescape then
        escape = M.luapat_escape
    else
        escape = function(s) return s end
    end

    return do_matching_files(text, mkmatch_luapat, escape)
end

-- Find files matching a Regex pattern (or a string match)
function M.find_matching_files(pattern)
    local results = {}
    local pat = vi_regex.compile(pattern)
    local function f(filename)
        if (pat and pat:match(filename)) or filename:find(pattern, 1, true) then
            results[#results+1] = filename
        end
    end
    lfs.dir_foreach('.', f, { folders = { "build"}}, false)
    return results
end

return M