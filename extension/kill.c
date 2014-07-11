/* A simple Lua module to suspend this process. */
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>

int l_kill(lua_State *L)
{
    /* Send ourselves the terminal stop signal, equivalent to normally
     * pressing ^Z. */
    kill(0, SIGTSTP);

    return 0;
}

/* The module's functions */
struct luaL_Reg functions[] = {
    { "kill", l_kill },
    { 0, 0 },
};

/* Called when importing this module */
int luaopen_kill(lua_State *L)
{
    luaL_newlib(L, functions);

    return 1;
}
