-- Test utilities
local M = {}

-- Get access to the regex modules
package.path = "../?.lua;" .. package.path

local eq
local tableEq

function eq(a, b)
    -- Easy case: builtin equal works for most cases.
    if a == b then return true end
    
    if type(a) ~= 'table' or type(b) ~= 'table' then
        -- If not both tables, then not equal.
        return false
    end
    return tableEq(a, b)
end

-- Compare two tables, treating them as the same if they key pairs
-- are equal.
function tableEq(a, b)
  -- First, check that every key in a matches one in b.
  for k,v in pairs(a) do
      if not eq(v, b[k]) then return false end
  end
  
  -- Second, check that every key in b exists in a.
  -- We don't need to compare - if the key is in a then we've already
  -- checked.
  for k,_ in pairs(b) do
    if a[k] == nil then return false end
  end
  
  -- They must be equal
  return true
end

-- Pretty-print tables
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

--- Assert that a and b are equal.  Tables are equal if their keys
--  and values are equal.  Calls error() with level to report an error.
local function assertEqLevel(a, b, level)
    if not eq(a,b) then
        error("Failed assertion: [["..M.tostring(a).."]] != [["..M.tostring(b).."]]\n", level)
    end
end

--- Assert that a and b are equal.  Tables are equal if their keys
--  and values are equal.  Returns true or calls error().  
function M.assertEq(a, b)
    return assertEqLevel(a, b, 2)
end

function M.log(x)
    print(M.tostring(x))
end

return M