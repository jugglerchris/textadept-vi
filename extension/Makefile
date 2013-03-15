LUA_INCLUDE := /usr/include/lua5.2
INCLUDES :=
INCLUDES += -I$(LUA_INCLUDE)

kill.so: kill.c
	gcc $(INCLUDES) -O2 -fpic -shared -o $@ $<
