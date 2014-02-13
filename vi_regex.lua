-- Support for regular expressions (parsed and implemented with LPeg).
local M = {}

local lpeg = require('lpeg')
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S
local C = lpeg.C
local V = lpeg.V
local Cc = lpeg.Cc
local Cf = lpeg.Cf
local Cp = lpeg.Cp
local Cg = lpeg.Cg
local Ct = lpeg.Ct

local function add(a,b)
    return a + b
end
local function mul(a,b)
    return a * b
end
local function sub1(x)
    return x - 1
end

-- Parts of a regular expression, returning an LPEG pattern which matches it.
local special = S"()\\?*+|"
local any = P"." * Cc(P(1))
local charset_special = S"]-"
local range = (C(P(1) - charset_special) * P"-" * C(P(1) - charset_special)) /
            function(a,b) return R(a .. b) end
local charset_char = C(P(1) - charset_special) / P
local charset = P"[" * Cf((range + charset_char)^0, add) * P"]"
local char = (P(1) - special) / P
local atom = any + charset + char

local atom_star = (atom * P"*") / function(x) return x ^ 0 end
local atom_plus = (atom * P"+") / function(x) return x ^ 1 end
local atom_query = (atom * P"?") / function(x) return x ^ -1 end
local atom_multi = atom_star + atom_plus + atom_query + atom
local piece = atom_multi
local concat = Cf(piece ^ 0, mul)
local branch = concat -- in vim, \& concat \& concat ...
local subpattern = Cf(branch * (P"|" * branch)^0, add)
local _start = Cg(Cp(), "_start")
local _end = Cg(Cp()/sub1, "_end")
local pattern = subpattern

local mt = {
    __index = {
        match = function(t, s)
            return t._pat:match(s)
        end,
    },
}

-- Parse a regular expression string and return a compiled pattern.
function M.compile(re)
    local anchored = false
    if re:sub(1,1) == "^" then
        anchored = true
        re = re:sub(2)
    end
    local _pat = _start * (pattern:match(re)) * _end
    if not anchored then
        _pat = P{_pat + 1*V(1)}
    end
    return setmetatable({
        _pat = Ct(_pat)
    }, mt)
end

return M