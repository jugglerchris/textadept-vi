local M = {}

local state = {
    tags = nil,   -- current set of tags
}
M.state = state

-- Load a tags file
local function load_tags()
    local tagf = io.open("tags") -- TODO: configurable tags file location
    local results = {}
    local pat = "^([^\t]*)\t([%\t]*)\t(.*)$"
    for line in tagf:lines() do
        local tname, fname, excmd = line:match(pat)
        gui.print("Line: " .. line)
        gui.print("  tname="..tostring(tname)..", fname="..tostring(fname)..
                  ", excmd="..tostring(excmd).."\n")
        if tname then
          results[tname] = { fname, excmd }
        end
    end
    tagf:close()
    state.tags = results
end

-- Return or load the tags
local function get_tags()
    -- TODO: check if tags file needs reloading
    if state.tags == nil then
        load_tags()
    end
    return state.tags
end

function M.find_tag_exact(name)
    local tags = get_tags()
    return tags[name]
end

return M