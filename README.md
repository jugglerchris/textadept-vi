textadept-vi
============

Some customisation for [textadept](http://foicica.com/textadept) to make it
feel a bit like vim.  I like vim's keyboard handling but textadept's
scriptability, so this is the solution.  The aim is for my trained fingers
to keep working, while (at least eventually) making good use of textadept's
features.

This is currently experimental, but the most common key bindings I use have
been implemented to some extent.  It requires textadept 6.6_beta or later.

Usage
-----
I suggest cloning textadept-vi into ~/.textadept, and setting it up with the
following:

```lua
package.path = "/home/username/.textadept/textadept-vi/?.lua;" .. package.path
package.cpath = "/home/username/.textadept/textadept-vi/?.so;" .. package.cpath
_M.vi_mode = require 'vi_mode'
```

What works
----------
* Movement commands: h,j,k,l,w,b,H,M,L,%,^,$,0,G
* Simple mark/jump: m, '
* Numeric prefix
* Basic text entry commands: i,a,A,o,O,r,~
* Editing: d,D,c,C,x,p
* Undo/redo: u,^r, (limited) .
* Searching: /,?,n,m,*,#
* ex-mode commands (limited): :e, :w, :q
* Misc: ^Z to suspend (with the included "kill" Lua extension)
* Esc to return to command mode
* In insert mode: ^p to find matching completions in the current buffer.

What doesn't
------------
Everything else, and some of the above.  I mainly use the curses version
under Linux.
