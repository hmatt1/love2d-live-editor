---
name: run-love2d-live-editor
description: Build, run, and drive the LOVE live editor (index.html) -- a single-page static app for editing and previewing LOVE2D games in-browser. Use when asked to start the editor, load files into it, run a project, export a .love/.html/.zip, screenshot its UI, or otherwise interact with the running app.
---

The LOVE live editor is a single static page (`index.html`, plus the vendored
`love.js`/`love.wasm` runtime) with no build step. It fetches `love.js` and
`love.wasm` relative to its own URL, so it must be served over `http://` --
`file://` breaks `fetch()`. Drive it via the batch driver at
`.claude/skills/run-love2d-live-editor/driver.mjs`: it starts its own static
server, launches headless Chromium (Playwright), and runs a script of
commands piped over stdin.

All paths below are relative to the repo root (`love2d-live-editor/`).

## Prerequisites

Node with npm. No OS packages needed -- Playwright's bundled Chromium runs
headless out of the box on both Windows and Linux for this app (no xvfb, no
GTK libs; it's a plain web page, not Electron).

## Setup

Playwright lives in the skill's own `package.json`, not the project's (the
project has no JS tooling otherwise -- don't add any to project root).

```bash
cd .claude/skills/run-love2d-live-editor
npm install
npx playwright install chromium
```

## Run (agent path)

Pipe a command script to the driver over stdin. It executes commands in
order and exits (exit code 1 if any command errored) -- there is no
interactive prompt to babysit and no tmux dependency.

```bash
cd .claude/skills/run-love2d-live-editor
node driver.mjs <<'EOF'
launch
ss 01-loaded
upload fixtures/test-import.love
run
export html
verify-standalone downloads/index.html
quit
EOF
```

Screenshots -> `.claude/skills/run-love2d-live-editor/shots/` (override:
`SCREENSHOT_DIR`). Exported downloads -> `.claude/skills/run-love2d-live-editor/downloads/`
by default, or wherever you pass as the `export`/`ss` argument (override:
`DOWNLOAD_DIR`).

### Commands

| command | what it does |
|---|---|
| `launch [port]` | start the static server (default port 8934) + headless Chromium, wait for the runtime (`#run` enabled) |
| `ss [name]` | screenshot -> `shots/<name>.png` |
| `click <css-sel>` | click an element |
| `text <css-sel>` | print `textContent` (note: useless on `#code` -- see Gotchas, use `eval` instead) |
| `wait <css-sel> [timeoutMs]` | wait for an element |
| `upload <path[,path2,...]>` | feed file(s) into the hidden `#filepicker` input, same as "Load files"; waits for the app's own console log confirming the upload actually finished (see Gotchas) |
| `tabs` | list open tab names |
| `run` | click Run, wait for the status LED to settle, print boot time |
| `export love\|html\|zip [outfile]` | click the matching export button, capture the download, save it (default name under `downloads/`) |
| `unzip <path>` | list a `.love`/`.zip` file's entries + sizes, using the app's own `zipStore`/`unzip` (extracted from `index.html`) |
| `verify-standalone <html-path> [name]` | open an exported standalone `.html` fresh via `file://` (no server), confirm the canvas actually sized and no error panel appeared, screenshot it |
| `build-fixtures` | regenerate `fixtures/` (see below) |
| `eval <js>` | evaluate JS in the page, print JSON. Top-level `state`, `addUploads`, etc. from `index.html`'s inline script are reachable directly. |
| `errors` | print collected `console.error` and uncaught `pageerror` messages |
| `quit` | close the browser and stop the server (also runs automatically at end of script) |

### Fixtures

`fixtures/` has three small pre-built files for exercising "Load files":
`sprite.lua` (loose text file), `icon.png` (loose binary asset, 256 bytes),
and `test-import.love` (a 3-entry archive: `main.lua` that draws the string
`IMPORTED_LOVE_MARKER`, `conf.lua`, `data/readme.txt`). Regenerate them with
the `build-fixtures` command if `index.html`'s zip format ever changes.

## Run (human path)

Open `index.html` directly in a browser (double-click, or any static file
server). Not useful headless.

## Test

```bash
# existing jsdom-based unit tests (need jsdom on NODE_PATH; not vendored
# in the project or the skill -- install wherever is convenient):
node test-editor-dom.js
node test-runner-handshake.js
```

Both pass clean as of this skill's creation.

## Gotchas

- **`upload` must wait for more than `setInputFiles()` resolving.** The
  app's `change` listener calls `addUploads()` (async: `file.arrayBuffer()`,
  possibly `unzip()`) without awaiting it. `setInputFiles()` resolves once
  the DOM event fires, not once the app finishes processing it -- a
  `run`/`export` issued immediately after can race it and silently operate
  on the stale project. The driver's `upload` command waits for the
  matching console log line (`Loaded <name>` / `Imported N file(s) from
  <name>`) before returning; don't bypass that by driving `#filepicker`
  any other way without an equivalent wait.

- **`page.textContent("#code")` is always empty.** `#code` is a
  `<textarea>`; the app sets its content via the `.value` IDL property,
  which does not touch `textContent`/`innerHTML`. Use `eval
  document.getElementById('code').value` instead. (The driver's `text`
  command is kept for other elements; don't rely on it for `#code`.)

- **Top-level `state`, `addUploads`, `selectFile`, etc. are reachable from
  `eval`.** `index.html`'s inline script is a classic (non-module) script,
  so its top-level function declarations attach to `window`, and its
  top-level `const`/`let` bindings (like `state`) live in the shared global
  lexical scope that later `page.evaluate()` calls can still see. Useful
  for bypassing the file-picker entirely and calling `addUploads([new
  File(...)])` directly when isolating a bug in the upload path itself.

## Bug found and fixed while building this skill

**Uploading/importing a file whose name matches the currently-open tab
silently discarded the new content**, keeping whatever was in the editor
before the upload. Since `main.lua` is the default active tab, this hit the
single most common case: importing a `.love`/zip archive almost always
lost its `main.lua` and kept the old one instead (confirmed with `conf.lua`
open instead of `main.lua` -- the corruption follows whichever tab was
active, not `main.lua` specifically).

Root cause: `selectFile(name)` calls `syncActiveFile()` -- which writes the
textarea's current value into `state.files.get(state.active)` -- *before*
reassigning `state.active = name`. `addUploads()` finishes by calling
`selectFile(state.active)` with the *same* name (not a real tab switch). If
the upload replaced the entry at that name with fresh content, this second,
pointless sync overwrote it with the stale textarea value that was on
screen before the upload started.

Fixed in `index.html`'s `addUploads()` (near line 967): sync the *old*
active file once, explicitly, at the top of the function (preserving any
edit made just before clicking "Load files"), then set `editorLoaded =
false` so `selectFile()`'s internal sync at the end becomes a no-op instead
of clobbering the just-loaded file:

```js
async function addUploads(fileList) {
  syncActiveFile();
  editorLoaded = false;
  for (const file of fileList) {
  ...
```

Verified via `eval`-driven direct calls to `addUploads()` with both
`main.lua` and `conf.lua` pre-selected (both corrupted before the fix, both
correct after), and via the full `upload` -> `run` -> `export
love/html/zip` -> `verify-standalone` driver flow (screenshots show the
imported project's `IMPORTED_LOVE_MARKER` text, not the default starter
project). The existing `test-editor-dom.js` / `test-runner-handshake.js`
jsdom suite still passes unchanged.

## Troubleshooting

- **`launch` hangs / times out waiting for `#run:not([disabled])`:** the
  runtime never finished loading (`love.js`/`love.wasm` fetch failed).
  Check the port isn't already bound by a previous stuck driver process.
- **`export` times out waiting for the `download` event:** the button was
  disabled (runtime not ready, or no `main.lua` in the project) -- `click()`
  succeeded on a disabled button does nothing; check `tabs` first.
