-- Lua utility functions
local M = {}

-- Pretty-print Lua values.
function M.tostring(a)
    if type(a) == "string" then
        return '"' .. a .. '"'
    elseif type(a) ~= 'table' then return tostring(a) end
    local maxn = 0
    local sbits = {'{'}
    for i,v in ipairs(a) do
        table.insert(sbits, M.tostring(v) .. ", ")
        maxn = i
    end
    for k,v in pairs(a) do
        -- Do the non-contiguous-integer keys
        if type(k) == 'number' and k == math.ceil(k) and k <= maxn and k >= 1 then 
           -- Ignore an integer key we've already seen
        else
            table.insert(sbits, '['..M.tostring(k)..'] = '..M.tostring(v)..', ')
        end
    end
    table.insert(sbits, '}')
    return table.concat(sbits)
end

return M