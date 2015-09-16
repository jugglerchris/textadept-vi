package = "pegex"
version = "0.1-1"
source = {
   url = "git://github.com/jugglerchris/ta-regex",
   tag = "v0.1"
}
description = {
   summary = "Regular expression search support for Textadept",
   detailed = "Regular expression search support for Textadept",
   homepage = "http://github.com/jugglerchris/ta-regex",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1, < 5.4",
   "lpeg >= 0.12",
}
build = {
   type = "builtin",
   modules = {
      regex = "regex.lua",
   }
}
