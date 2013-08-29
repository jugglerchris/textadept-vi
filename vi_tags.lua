local M = {}

local state = {
    tags = nil,   -- current set of tags
}
M.state = state

-- Load a tags file
local function load_tags()
    local tagf = io.open("tags") -- TODO: configurable tags file location
    local results = {}
    local pat = "^([^\t]*)\t([^\t]*)\t(.*)$"
    for line in tagf:lines() do
        local tname, fname, excmd = line:match(pat)
        local flags
        if tname then
          -- Initialise to an empty list if necessary
          if not results[tname] then results[tname] = {} end
          -- And append.
          local l = results[tname]  -- now guaranteed to be a table
          
          do
             -- Try to separate the ex command from other info
             local e,f = excmd:match('^(.-);"\t(.*)$')
             if e then
                 excmd = e
                 flags = f
             end
          end
          l[#l+1] = { filename=fname, excmd=excmd, flags=flags }
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