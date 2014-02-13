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

local _start = Cg(Cp(), "_start")
local _end = Cg(Cp()/sub1, "_end")
local pattern = P{
    "matcher",
    matcher = (P"^" * V"pattern") + V"unanchored",
    unanchored = V"pattern" / function(pat) return P{pat + 1*V(1)} end,
    pattern = V"subpattern" / function(pat) return _start * pat * _end end,
    subpattern = Cf(V"branch" * (P"|" * V"branch")^0, add),
    branch = V"concat",
    concat = Cf(V"piece" ^ 0, mul), -- in vim, \& concat \& concat ...
    piece = V"atom_multi",
    atom_multi = V"atom_star" + V"atom_plus" + V"atom_query" + V"atom",
    atom_star = (V"atom" * P"*") / function(x) return x ^ 0 end,
    atom_plus = (V"atom" * P"+") / function(x) return x ^ 1 end,
    atom_query = (V"atom" * P"?") / function(x) return x ^ -1 end,
    atom = any + charset + (P"(" * V"subpattern" * P")") + char,
}

local mt = {
    __index = {
        match = function(t, s)
            return t._pat:match(s)
        end,
    },
}

-- Parse a regular expression string and return a compiled pattern.
function M.compile(re)
    local _pat = pattern:match(re)
    return setmetatable({
        _pat = Ct(_pat)
    }, mt)
end

return M