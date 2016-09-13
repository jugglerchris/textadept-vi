-- XML language settings
local lpeg = require 'lpeg'
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S
local Cc = lpeg.Cc
local Cf = lpeg.Cf

local M = {}

-- Define patterns to specify indentation increments
-- Increment indent inside a tag
-- convention: include leading whitespace in patterns.
local sp = S" \t\n" ^ 0
local bra = sp * P"<" * Cc(1)
local ket = sp * P">" * Cc(-1)

local nameStartChar = R("AZ") + ":" + "_" + R("az") -- plus unicodes
local nameChar = nameStartChar + "-" + "." + R("09")

local name = sp * nameStartChar * (nameChar^0)

-- TODO: implement escaping
local squot = sp * P"'" * (P(1) - "'")^0 * P("'")
local dquot = sp * P'"' * (P(1) - '"')^0 * P('"')
local attr_val = squot + dquot
local attr = name * sp * P"=" * attr_val
local attrs = attr ^ 0
local slash = sp * P"/"
-- simple_cdata matches at least one char
local simple_cdata = ((1 - S("<>&")) + (P"&" * (R"az"^1) * P";"))^1
local cdata = simple_cdata  -- implement CDATA too.
local tag_start = bra * name * attrs * ket * Cc(1)
local tag_end = bra * slash * name * ket * Cc(-1)
local tag_empty = bra * name * attrs * sp * slash * ket

-- Doesn't work with lines with partial tags
local line = sp * (tag_start + tag_end + tag_empty + cdata) ^ 0 * sp

M.indent_pat = Cf(Cc(0)*line*sp, function(a,b) return a+b end)
-- Dedent if the line starts with an end tag.
local function kill() end -- used to kill subcaptures
M.dedent_pat = (sp * (tag_end / kill) * Cc(-1)) + Cc(0)

function M.test()
   assert(sp:match("  \n"))
   assert(bra:match("  <") == 1)
   assert(ket:match("  >") == -1)
   assert(name:match("asdf") == 5)
   assert(name:match("  asdf") == 7)
   assert(squot:match(" 'fjsalfjafwijf\"o3'"))
   assert(dquot:match(' "fjsalfjafwijf\'o3"'))
   assert(attr_val:match(" 'foo'") == 7)
   assert(attr_val:match(' "foo"') == 7)
   assert(attr:match(' foo="bar"') == 11)
   assert(attrs:match('') == 1)
   assert(attrs:match(' a="b" c="d"') == 13)
   assert(slash:match('/') == 2)
   assert(slash:match('  /') == 4)
   local function add(a,b) return a+b end
   assert(Cf(tag_start, add):match(" <foo x='y'>") == 1)
   assert(Cf(tag_end, add):match(" </foo>") == -1)
   assert(Cf(tag_empty, add):match(" <foo x='y'/>") == 0)
   assert(M.indent_pat:match("<foo>\n") == 1)
   assert(M.indent_pat:match("</foo>\n") == -1)
   assert(M.indent_pat:match("<foo/>\n") == 0)
   assert(M.indent_pat:match("<foo></foo>\n") == 0)
   assert(M.indent_pat:match("<foo>bar</foo>\n") == 0)
   assert(M.dedent_pat:match("<foo>bar</foo>\n") == 0)
   assert(M.dedent_pat:match("</foo>") == -1)
   assert(M.dedent_pat:match("</foo><foo>") == -1)
end

return M
