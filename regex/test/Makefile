# Simple test framework

TEST_FILES := $(wildcard test_*.lua)
TESTS := $(patsubst %.lua,%,$(TEST_FILES))
$(warning TESTS=$(TESTS))

LUA := lua

%: %.lua
	$(LUA) $<

test: $(TESTS)
