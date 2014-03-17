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

-- We use the algorithm to convert from a regular expression to a Peg
-- expression from:
-- http://www.inf.puc-rio.br/~roberto/docs/ry10-01.pdf

local function sub1(x)
    return x - 1
end

-- Parts of a regular expression, returning an LPEG pattern which matches it.
local _start = Cg(Cp(), "_start")
local _end = Cg(Cp()/sub1, "_end")
local mt = {
    __index = {
        match = function(t, s)
            return t._pat:match(s)
        end,
    },
}

local special = S"()\\?*+|"
local any = P"." * Cc({[0] = "."})
local charset_special = S"]-"
local charset_char = C(P(1) - charset_special) /
     function(c) return { [0] = "char", c } end
local range = (C(P(1) - charset_special) * P"-" * C(P(1) - charset_special)) /
            function(a,b) return { [0]="range", a, b } end
local charset = P"[" * Ct((range + charset_char)^0) * P"]" /
    function(x) x[0] = "charset" return x end
local char = C(P(1) - special) / function(c) return { [0] = "char", c } end

local pattern = P{
    "pattern",
    
    -- A complete pattern, starting from an empty pattern.
    pattern = Ct((P"^"*Cg(Cc(1),"anchorstart") + P(0)) * V"subpat" * (P"$"*(-P(1))*Cg(Cc(1),"anchorend") + (-P(1)))) / 
             function(t) t[0] = "pattern" ; return t end,
    
    -- A set of alternate branches
    subpat = (V"branch" * (P"|" * V"branch") ^ 0) / 
             function(...) return { [0] = "alt", ... } end,
    
    branch = V"concat",
    
    -- A set of concatenated pieces
    concat = (V"piece" ^ 0) /
             function(...) return { [0] = "concat", ... } end,
             
    piece = V"atom_multi",
    
    atom_multi = V"atom_plus" + V"atom_star" + V"atom_query" + V"atom",
    
    atom_plus = (V"atom" * P"+") /
             function(atom) return { [0] = "+", atom } end,
    atom_star = (V"atom" * P"*") /
             function(atom) return { [0] = "*", atom } end,
    atom_query = (V"atom" * P"?") /
             function(atom) return { [0] = "?", atom } end,
    
    atom = any + charset + (P"(" * V"subpat" * P")") + char,
}

local function foldr(f, t, init)
    local res = init
    local start = #t
    if res == nil then
        res = t[start]
        start = start - 1
    end
        
    for i=start,1,-1 do
        res = f(t[i], res)
    end
    return res
end

local function map(f, t)
    local result = {}
    for i=1,#t do
        result[i] = f(t[i])
    end
    return result
end

local function add(a,b)
    return a+b
end

-- Convert a charset fragment to a PEG
local function charset_to_peg(charfrag)
    local t = charfrag[0]
    if t == "char" then
        assert(#charfrag == 1)
        return P(charfrag[1])
    else
        error("Got charset bit: "..tostring(t).."/"..tostring(t and t[0]))
    end
end

local function re_to_peg(retab, k)
    local t = retab[0]
    if t == "pattern" then
        assert(#retab == 1)
        local pat = re_to_peg(retab[1], k)
        -- Add match start/end markers
        pat = _start * pat * _end
        if not retab.anchorstart then
            -- Match the pattern, or a character and try again.
            pat = P{pat + 1*V(1)}
        end
        -- TODO: implement $
        if retab.anchorend then
            error("$ not implemented")
        end
        return pat
    elseif t == "alt" then
        if #retab == 1 then
            return re_to_peg(retab[1], k)
        else
            local parts = map(function(x) return re_to_peg(x, k) end, retab)
            return foldr(add, parts)
        end
    elseif t == "concat" then
        return foldr(re_to_peg, retab, k)
    elseif t == "char" then
        assert(#retab == 1)
        return P(retab[1]) * k
    elseif t == "charset" then
        local charset_pat = foldr(add, map(charset_to_peg, retab))
        return charset_pat * k
    elseif t == "*" then
        return P{"A", A=re_to_peg(retab[1], V"A") + k}
    elseif t == "+" then
        return re_to_peg(retab[1], P{"A", A=re_to_peg(retab[1], V"A") + k})
    elseif t == "." then
        assert(#retab == 0)
        return P(1) * k
    elseif t == "?" then
        assert(#retab == 1)
        return re_to_peg(retab[1], k) + k
    else
        error("Not implemented op: " ..tostring(t) .. "/" .. tostring(retab))
    end
end

function M.parse(re)
    return pattern:match(re)
end
function M.compile(re)
    -- Since the RE->Peg construction starts backwards (using the
    -- continuation), it's more convenient to parse the regular expression
    -- backwards.
    local retab = pattern:match(re)
    if retab == nil then
        error("Failed to parse regular expression: {"..re.."}", 2)
    end
    local _pat = re_to_peg(retab, P(0))
    return setmetatable({
        _pat = Ct(_pat)
    }, mt)
end

return M