STRACE :=
TMUX_EXTRA :=

TA ?= ../../textadept-curses
ifeq ($(DEBUG),1)
STRACE := strace -s4096 -o output/ta.strace
TMUX_EXTRA :=  \; attach
TA := $(STRACE) $(TA)
endif
TMUX := tmux -f userhome/tmux.conf
TAIL ?= tail

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
	@if [ ! -f ./userhome/modules/textredux/buffer_list.lua ]; then echo "Textredux must exist at ./userhome/modules/textredux"; exit 1; fi
	@# Remove previous output file to avoid confusion.
	@rm -f output/results.txt output/sem.fifo
	@touch output/results.txt
	@mkfifo output/sem.fifo
	$(TMUX) -S $(TMUX_SOCKET) -C new-session -d $(TMUX_SIZE) "TESTS=\"$(TESTS)\" bash " \; send-keys "$(TA) --nosession --userhome ./userhome " \; send-keys enter $(TMUX_EXTRA)
	@echo Waiting for test...
	@head -1 output/sem.fifo >/dev/null & $(TAIL) --pid=$$! --follow=name output/results.txt
	@grep FAIL output/results.txt && exit 1 || exit 0
  
# Convenience target to attach to any session still running.
attach:
	$(TMUX) -S $(TMUX_SOCKET) attach
# Convenience target to kill any sessions
kill:
	$(TMUX) -S $(TMUX_SOCKET) -C kill-server
  
# Convenience to print out the current screen
show:
	echo capture-pane -p | $(TMUX) -S $(TMUX_SOCKET) -C attach
