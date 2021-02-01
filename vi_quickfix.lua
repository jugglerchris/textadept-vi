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

local ws = S" \t"
local to_nl = (P(1) - P"\n") ^ 0
local errpat_newdir = Ct(P"make: Entering directory " * S("'`") * Cg((P(1) - P"'")^0, 'newdir')* P"'")
local errpat_leavedir = Ct(P"make: Leaving directory " * S("'`") * Cg((P(1) - P"'")^0, 'leavedir')* P"'")
local errpat_error = Ct((P"In file included from " ^-1) * Cg((P(1) - S":\n") ^ 0, 'path') * P":" * Cg(R"09" ^ 0, 'lineno') * P":" * ((Cg(R"09" ^ 0, 'colno') * P":")^-1) * (S(" \t") ^ 0) * Cg(to_nl, "message"))
local errpat_error_nofile = Ct((P"error" + P"Error" + P"ERROR") * P":" * ws * Cg(to_nl, "message")) +
                            Ct(Cg(P"make: ***" * to_nl, "message"))

local errpat_ignore = (P(1) - "\n") ^ 0

local errpat_line = (errpat_newdir + errpat_error + errpat_error_nofile)-- + errpat_ignore)

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
    for i=1,buffer.line_count do
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
          elseif match.path or match.message then
              local path = match.path
              local lineno = match.lineno and tonumber(match.lineno) or nil
              local colno = match.colno and tonumber(match.colno) or nil
              local message = match.message

              -- Get any extra lines of a multi-line message
              local errline = i + 1
              while errline <= buffer.line_count do
                   local contline = buffer:get_line(errline)
                   local matchlen = contline:match("^[ %d]* | ()")
                   if matchlen then
                       message = message .. "\n" .. contline:sub(matchlen)
                       contline = contline:match("([^\n]*)")
                       line = line .. "\n" .. contline
                       i = i + 1
                   else
                       break
                   end
                   errline = errline + 1
              end

              if path and #dirs > 0 then
                  path = dirs[#dirs] .. "/" .. path
              end
              local idx = #results + 1
              results[idx] = { line, path=path, lineno=lineno, colno=colno, idx=idx, message=message }
          end
        end
        --cme_log("<"..buffer:get_line(i)..">")
        --cme_log("{"..ts(errpat_newdir:match((buffer:get_line(i)))).."}")
        --cme_log(ts(errpat_line:match((buffer:get_line(i)))))
    end
    return results
end

return M
