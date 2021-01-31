local lexer = require('lexer')
local token, word_match = lexer.token, lexer.word_match
local P, S = lpeg.P, lpeg.S

local lex = lexer.new('tavi_make', { lex_by_line = true })

-- Whitespace.
local ws = token(lexer.WHITESPACE, lexer.space^1)
--lex:add_rule('whitespace', ws)

local filename = token(lexer.VARIABLE, (lexer.any - lexer.space - ':')^1)
local colon = token(lexer.OPERATOR, P':')
local linenum = token(lexer.NUMBER, lexer.dec_num)
local colnum = token(lexer.NUMBER, lexer.dec_num)
local line = token(lexer.STRING, lexer.any^1)

local error = token(lexer.ERROR, " error")
local warning = token(lexer.COMMENT, " warning")

lex:add_rule('make_warning', lexer.starts_line(filename * colon * linenum * ((colon * colnum) ^ 0) * colon * warning * line))
lex:add_rule('make_error', lexer.starts_line(filename * colon * linenum * ((colon * colnum) ^ 0) * colon * error * line))
lex:add_rule('make_result', lexer.starts_line(filename * colon * linenum * colon * line))

return lex