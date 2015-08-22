textadept-vi
============

Some customisation for [textadept](http://foicica.com/textadept) to make it
feel a bit like vim.  I like vim's keyboard handling but textadept's
scriptability, so this is the solution.  The aim is for my trained fingers
to keep working, while (at least eventually) making good use of textadept's
features.

It requires a recent textadept (7.8 at time of writing).

I use this as my default editor, and it implements the common features of
vi/vim that I used to use; there are many less common features I haven't
implemented.

Usage
-----
I suggest cloning textadept-vi into ~/.textadept, and setting it up with the
following:

```lua
package.path = "/home/username/.textadept/textadept-vi/?.lua;" .. package.path
package.cpath = "/home/username/.textadept/textadept-vi/?.so;" .. package.cpath
_G.vi_mode = require 'vi_mode'
```

Textadept-vi also uses a slightly modified textredux (with support for using
the Scintilla-based command entry in recent Textadept versions):
    https://github.com/jugglerchris/textredux.git

I think it's likely that textredux will add this support (possibly a bit
differently), at which point textadept-vi will switch back to upstream
textredux.

Support
-------
For any questions, issues, requests or complaints, please use the [issue
tracker](https://github.com/jugglerchris/textadept-vi/issues).

What works
----------
* Movement commands: h,j,k,l,w,b,e,H,M,L,%,^,_,$,0,G,{,}
* Selection motions: aw,iw
* Simple mark/jump: m, ', `
* Numeric prefix
* Basic text entry commands: i,a,A,o,O,r,R,~
* Editing: d,D,c,C,x,p,P,y
* More complex editing commands: J,gq,>,<,=
* Undo/redo/repeat: u,^r,.
* Searching: /,?,n,N,*,#
* Tags: c-],c-t, :tag, :tn, :tp, :tsel
* Buffers: c-w c-w, c-^, :split, :vsplit, :only
* Folds: zo, zc, zM, zR
* Compiling/Quickfix: basic :make, :cb, :cn, :cp, :clist, :lgrep (grep with Lua patterns)
* Other ex-mode commands with completion: :e, :w, :wq, :x, :q, :b, :bdelete, :find, @:
* Misc: ^Z to suspend (with the included "kill" Lua extension)
* Esc to return to command mode
* In insert mode: ^p to find matching completions in the current buffer.

What doesn't
------------
Everything else, and some of the above.  I mainly use the curses version
under Linux (modified to support split views; see below).

Dependencies
------------
Besides Textadept (currently tested on 7.8):
* textadept-vi uses [textredux](http://rgieseke.github.io/textredux/)
  for some features (grep results) and the command entry.
  
  NOTE: Currently this needs a fork with added support for using
  Textadept 7.8's buffer-based command entry:
  
  https://github.com/jugglerchris/textredux/

Testing
-------
There is a slowly growing set of regression tests.  They run using
textadept-curses inside a recent tmux (>=1.8).  To run, just type "make"
from the textadept-vi/test directory.
