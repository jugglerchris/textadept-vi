TA_PATH := $(HOME)/working/textadept/ta_hg/textadept
LUA_INCLUDE := $(TA_PATH)/src/lua/src
INCLUDES :=
INCLUDES += -I$(LUA_INCLUDE)

kill.so: kill.c
	gcc $(INCLUDES) -O2 -fpic -shared -o $@ $<
