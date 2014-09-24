textadept-vi
============

Some customisation for [textadept](http://foicica.com/textadept) to make it
feel a bit like vim.  I like vim's keyboard handling but textadept's
scriptability, so this is the solution.  The aim is for my trained fingers
to keep working, while (at least eventually) making good use of textadept's
features.

This is currently experimental, but the most common key bindings I use have
been implemented to some extent.  It requires a recent textadept (7.6 works).

I use this as my default editor.

Usage
-----
I suggest cloning textadept-vi into ~/.textadept, and setting it up with the
following:

```lua
package.path = "/home/username/.textadept/textadept-vi/?.lua;" .. package.path
package.cpath = "/home/username/.textadept/textadept-vi/?.so;" .. package.cpath
_G.vi_mode = require 'vi_mode'
```

Support
-------
For any questions, issues, requests or complaints, please use the [issue
tracker](https://github.com/jugglerchris/textadept-vi/issues).

What works
----------
* Movement commands: h,j,k,l,w,b,e,H,M,L,%,^,$,0,G
* Selection motions: aw,iw
* Simple mark/jump: m, ', `
* Numeric prefix
* Basic text entry commands: i,a,A,o,O,r,R,~
* Editing: d,D,c,C,x,p,P
* More complex editing commands: J,gq,>,<,=
* Undo/redo/repeat: u,^r,.
* Searching: /,?,n,N,*,#
* Tags: c-],c-t, :tag, :tn, :tp, :tsel
* Buffers: c-w c-w, c-^, :split, :vsplit, :only
* Folds: zo, zc, zM, zR
* Compiling/Quickfix: basic :make, :cb, :cn, :cp, :clist, :lgrep (grep with Lua patterns)
* Other ex-mode commands with completion: :e, :w, :wq, :q, :b, :bdelete, :find, @:
* Misc: ^Z to suspend (with the included "kill" Lua extension)
* Esc to return to command mode
* In insert mode: ^p to find matching completions in the current buffer.

What doesn't
------------
Everything else, and some of the above.  I mainly use the curses version
under Linux (modified to support split views; see below).

Dependencies
------------
Besides textadept (currently tested on 7.6):
* The included "kill" extension to suspend with ^Z
* For error/tag lists, and an experimental buffer-based command entry,
  [textredux](http://rgieseke.github.io/textredux/)  0.10 has been tested
  to work.

Testing
-------
There is a slowly growing set of regression tests.  They run using
textadept-curses inside a recent tmux (>=1.8).  To run, just type "make"
from the textadept-vi/test directory.