-- Implement quickfix-like functionality.
local M = {}

local lpeg = require('lpeg')
local P = lpeg.P
local S = lpeg.S
local C = lpeg.C
local R = lpeg.R
local Ct = lpeg.Ct
local Cg = lpeg.Cg
local Cc = lpeg.Cc

local errpat_newdir = Ct(P"make: Entering directory `" * Cg((P(1) - P"'")^0, 'newdir')* P"'")
local errpat_leavedir = Ct(P"make: Leaving directory `" * Cg((P(1) - P"'")^0, 'leavedir')* P"'")
local errpat_error = Ct((P"In file included from " ^-1) * Cg((P(1) - S":\n") ^ 0, 'path') * P":" * Cg(R"09" ^ 0, 'lineno') * P":" * (S(" \t") ^ 0) * Cg((1 - P"\n") ^ 0, "message"))

local errpat_ignore = (P(1) - "\n") ^ 0

local errpat_line = (errpat_newdir + errpat_error)-- + errpat_ignore)

local function pretty(x)
    if type(x) == 'table' then
        local bits = {'{\n'}
        for k,v in pairs(x) do
            bits[#bits+1] = "  "
            bits[#bits+1] = pretty(k)
            bits[#bits+1] = " = "
            bits[#bits+1] = pretty(v)
            bits[#bits+1] = "\n"
        end
        bits[#bits+1] = '}\n'
        
        return table.concat(bits)
    elseif type(x) == 'string' then
        return "'" .. x .. "'"
    else
        return tostring(x)
    end
end

local function ts(...)
    local args = {...}
    local bits = {}
    for i,v in ipairs(args) do
        bits[#bits + 1] = pretty(v)
        bits[#bits + 1] = ","
    end
    return table.concat(bits)
end

function M.quickfix_from_buffer(buffer)
    local dirs = {}
    local results = {}
    for i=0,buffer.line_count-1 do
        local line = buffer:get_line(i)
        line = line:match("([^\n]*)")
        local match = errpat_line:match(line)
        if match then
          if match.newdir then
              dirs[#dirs+1] = match.newdir
          elseif match.leavedir then
              if dirs[#dirs] ~= match.leavedir then
                  error("Non-matching leave directory")
              else
                  dirs[#dirs] = nil
              end
          elseif match.path then
              local path = match.path
              local lineno = tonumber(match.lineno)
              local message = match.message
              if #dirs > 0 then
                  path = dirs[#dirs] .. "/" .. path
              end
              local idx = #results + 1
              results[idx] = { line, path=path, lineno=lineno, idx=idx, message=message }
          end
        end
        --cme_log("<"..buffer:get_line(i)..">")
        --cme_log("{"..ts(errpat_newdir:match((buffer:get_line(i)))).."}")
        --cme_log(ts(errpat_line:match((buffer:get_line(i)))))
    end
    return results
end

return M