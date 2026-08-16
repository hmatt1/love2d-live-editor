# love.js custom build

Builds `love.js` + `love.wasm` with `emscripten_fetch()` support, adding a `love.fetch`
Lua module that lets game code make HTTPS requests from the browser.

## What's added

- `src/modules/fetch/wrap_Fetch.cpp` — C module exposing `love.fetch.request()` and `love.fetch.poll()`
- `patches/CMakeLists.patch` — adds fetch sources and `-sFETCH=1` to the LÖVE emscripten build
- `patches/love_cpp.patch` — registers `love.fetch` in LÖVE's module preload list

## Build

```bash
# From the repo root:
docker build -t love-builder build/
docker run --rm \
  -v "$(pwd)/build":/build \
  -v "$(pwd)":/out \
  love-builder bash /build/build.sh
```

Build takes ~10–20 minutes. Outputs `love.js` and `love.wasm` directly into the repo root,
replacing the existing runtime files.

## Lua API

```lua
local http = require('fetch')   -- fetch.lua wraps the built-in love.fetch C module

-- GET request
http.get('https://management.example.com/api/assign', function(status, body, ok)
  if ok then
    local data = json.decode(body)
    net.connect(data.host, data.port, function(conn) ... end)
  end
end)

-- POST request
http.post('https://management.example.com/api/register', json.encode(payload),
  function(status, body, ok) ... end)
```

`fetch.lua` is auto-added to the project when a Server URL is configured in the editor.
It hooks `love.update` to poll for completed responses each frame — no manual polling needed.

## Pinned versions

| Repo | Branch | Commit |
|------|---------|--------|
| Davidobot/love.js | master | `c4f04e1` |
| Davidobot/love | emscripten | `32e0716` |
| Davidobot/megasource | emscripten | see build.sh |

Emscripten version: **2.0.0** (pinned in Dockerfile — newer versions break `getMemory`).
