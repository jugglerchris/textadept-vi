STRACE :=
TMUX_EXTRA :=

ifeq ($(DEBUG),1)
STRACE := strace -o output/ta.strace
TMUX_EXTRA :=  \; attach
endif
TA := $(STRACE) ../../ta_hg/textadept-curses
TMUX := tmux -f userhome/tmux.conf

# tmux configuration
TMUX_SOCKET := ./output/tmux-socket
TMUX_WIDTH := 80
TMUX_HEIGHT := 24
TMUX_SIZE := -x $(TMUX_WIDTH) -y $(TMUX_HEIGHT)

all: test

output:
	mkdir -p $@
  
clean:
	rm -r output

test: output
	$(TMUX) -S $(TMUX_SOCKET) -C new-session -d $(TMUX_SIZE) "$(TA) --nosession --userhome ./userhome ; echo Finished >> output/results.txt" $(TMUX_EXTRA)
	@cat output/results.txt
  
# Convenience target to attach to any session still running.
attach:
	$(TMUX) -S $(TMUX_SOCKET) attach
  
# Convenience to print out the current screen
show:
	echo capture-pane -p | $(TMUX) -S $(TMUX_SOCKET) -C attach