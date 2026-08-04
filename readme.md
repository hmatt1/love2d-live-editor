# love2d live editor

An interactive feature-tour app for two LÖVE2D Lua libraries: **clay.lua** (UI layout) and **foley.lua** (procedural UI sound). Runs in the browser via LÖVE compiled to WebAssembly.

Open `index.html` to launch. Pick a library from the menu, then navigate the tabbed sections to explore each feature of the API live and interactively.

## Libraries

### clay.lua

A pure-Lua port of [Clay](https://github.com/nicbarker/clay) (v0.14) for LÖVE2D. Single file, no dependencies beyond LÖVE.

Features: flexbox-style row/column layout, grow/fit/fixed/percent sizing, padding, child gap and alignment, text with word-wrap and alignment, scroll containers with drag momentum, floating/tooltip elements, borders (per-side + between-children), per-corner radius, overlay color, images, aspect ratio, pointer hit-testing, and offscreen culling.

See [clay.md](clay.md) for full API reference.

### foley.lua

Procedural UI sound design for LÖVE2D. Demonstrated via a sound board and sound design explorer.

## Running locally

Open `index.html` directly in a browser — no build step required. The LÖVE runtime is bundled as `love.wasm`/`love.js`.

To run natively with LÖVE installed:

```sh
love .
```
