-- Language-specific settings
local M = {}

-- Indent settings
M.indents = {}

local lang_xml = require 'textadept-vi.vi_lang.xml'
M.indents.xml = { indent=lang_xml.indent_pat,
                  dedent=lang_xml.dedent_pat }

return M
