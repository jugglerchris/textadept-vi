STRACE :=
TMUX_EXTRA :=

ifeq ($(DEBUG),1)
STRACE := strace -o ta.strace
TMUX_EXTRA :=  \; attach
endif
TA := $(STRACE) ../../ta_hg/textadept-curses
TMUX := tmux

# tmux configuration
TMUX_SOCKET := ./output/tmux-socket
TMUX_WIDTH := 80
TMUX_HEIGHT := 24
TMUX_SIZE := -x $(TMUX_WIDTH) -y $(TMUX_HEIGHT)

all: test

output:
	mkdir -p $@

test: output
	$(TMUX) -S $(TMUX_SOCKET) -C new-session -d $(TMUX_SIZE) "$(TA) --nosession --userhome ./userhome ; echo Finished >> results.txt" $(TMUX_EXTRA)
	@#$(TMUX) -S $(TMUX_SOCKET) -C attach
  
# Convenience target to attach to any session still running.
attach:
	$(TMUX) -S $(TMUX_SOCKET) attach