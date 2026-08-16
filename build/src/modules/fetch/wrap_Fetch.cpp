#include "wrap_Fetch.h"
#include <emscripten/fetch.h>
#include <vector>
#include <string>
#include <cstring>

struct FetchResult {
    int         ref;    // luaL_ref to the Lua callback
    int         status;
    std::string body;
    bool        ok;
};

static std::vector<FetchResult> g_queue;
static lua_State               *g_L = nullptr;

static void on_success(emscripten_fetch_t *f)
{
    g_queue.push_back({
        (int)(intptr_t)f->userData,
        (int)f->status,
        std::string(f->data, f->numBytes),
        true
    });
    emscripten_fetch_close(f);
}

static void on_error(emscripten_fetch_t *f)
{
    g_queue.push_back({
        (int)(intptr_t)f->userData,
        (int)f->status,
        std::string(),
        false
    });
    emscripten_fetch_close(f);
}

// love.fetch.request({ url=, method=, body=, onsuccess= })
static int w_request(lua_State *L)
{
    g_L = L;
    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "url");
    const char *url = luaL_checkstring(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 1, "method");
    const char *method = lua_isstring(L, -1) ? lua_tostring(L, -1) : "GET";
    lua_pop(L, 1);

    // optional body
    const char *body     = nullptr;
    size_t      body_len = 0;
    lua_getfield(L, 1, "body");
    if (lua_isstring(L, -1))
        body = lua_tolstring(L, -1, &body_len);
    lua_pop(L, 1);

    lua_getfield(L, 1, "onsuccess");
    if (!lua_isfunction(L, -1))
        return luaL_error(L, "love.fetch.request: onsuccess must be a function");
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    emscripten_fetch_attr_t attr;
    emscripten_fetch_attr_init(&attr);
    strncpy(attr.requestMethod, method, sizeof(attr.requestMethod) - 1);
    attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY;
    attr.onsuccess  = on_success;
    attr.onerror    = on_error;
    attr.userData   = (void *)(intptr_t)ref;

    if (body && body_len > 0) {
        attr.requestData     = body;
        attr.requestDataSize = body_len;
    }

    emscripten_fetch(&attr, url);
    return 0;
}

// love.fetch.poll() — drain completed requests, fire callbacks
// Call once per frame from love.update (fetch.lua does this automatically).
static int w_poll(lua_State *L)
{
    for (auto &r : g_queue) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, r.ref);
        luaL_unref(L, LUA_REGISTRYINDEX, r.ref);
        lua_pushinteger(L, r.status);
        lua_pushlstring(L, r.body.c_str(), r.body.size());
        lua_pushboolean(L, r.ok ? 1 : 0);
        lua_call(L, 3, 0);
    }
    g_queue.clear();
    return 0;
}

static luaL_Reg funcs[] = {
    { "request", w_request },
    { "poll",    w_poll    },
    { nullptr,   nullptr   }
};

extern "C" int luaopen_love_fetch(lua_State *L)
{
    luaL_newlib(L, funcs);
    return 1;
}
