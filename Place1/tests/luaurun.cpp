#include "lua.h"
#include "lualib.h"
#include "luacode.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

static bool readFile(const char* path, std::string& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::stringstream ss; ss << f.rdbuf(); out = ss.str(); return true;
}

// loadfile(path, chunkname?) -> function | nil, err
static int l_loadfile(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    const char* chunk = luaL_optstring(L, 2, path);
    std::string src;
    if (!readFile(path, src)) { lua_pushnil(L); lua_pushfstring(L, "cannot open %s", path); return 2; }
    size_t size = 0;
    lua_CompileOptions opts = {};
    opts.optimizationLevel = 1; opts.debugLevel = 1;
    char* bc = luau_compile(src.data(), src.size(), &opts, &size);
    std::string name = std::string("@") + chunk;
    int r = luau_load(L, name.c_str(), bc, size, 0);
    free(bc);
    if (r != 0) { lua_pushnil(L); lua_insert(L, -2); return 2; }
    return 1;
}

static int l_readfile(lua_State* L) {
    std::string src;
    if (!readFile(luaL_checkstring(L, 1), src)) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, src.data(), src.size());
    return 1;
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: luaurun script.luau [args]\n"); return 2; }
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    lua_pushcfunction(L, l_loadfile, "loadfile"); lua_setglobal(L, "loadfile");
    lua_pushcfunction(L, l_readfile, "readfile"); lua_setglobal(L, "readfile");
    lua_createtable(L, argc, 0);
    for (int i = 0; i < argc; i++) { lua_pushstring(L, argv[i]); lua_rawseti(L, -2, i); }
    lua_setglobal(L, "arg");
    lua_getglobal(L, "loadfile"); lua_pushstring(L, argv[1]); lua_call(L, 1, 2);
    if (lua_isnil(L, -2)) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
    lua_pop(L, 1);
    lua_getglobal(L, "debug"); lua_getfield(L, -1, "traceback"); lua_remove(L, -2);
    lua_insert(L, -2);
    if (lua_pcall(L, 0, 0, -2) != 0) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
    return 0;
}
