"use strict";
/* Loads the real page in jsdom and exercises the paths that touch file contents:
   first paint, tab switching, screen presets, autosave, and a full reload cycle. */

const fs = require("fs");
const assert = require("assert");
const { JSDOM } = require("jsdom");

const html = fs.readFileSync(__dirname + "/index.html", "utf8");

function boot(storage) {
  const dom = new JSDOM(html, { runScripts: "dangerously", pretendToBeVisual: true, url: "http://localhost/" });
  const w = dom.window;
  // jsdom has no ResizeObserver, and fetch would try to reach love.js.
  w.ResizeObserver = class { observe() {} disconnect() {} };
  for (const [k, v] of Object.entries(storage || {})) w.localStorage.setItem(k, v);
  return { dom, w };
}

/* jsdom evaluates scripts at construction, so seed storage in a throwaway window
   and replay it into a fresh one. */
function bootWith(storage) {
  const dom = new JSDOM(html, {
    runScripts: "outside-only", url: "http://localhost/"
  });
  dom.window.ResizeObserver = class { observe() {} disconnect() {} };
  dom.window.fetch = () => Promise.reject(new Error("no runtime in test"));
  for (const [k, v] of Object.entries(storage || {})) dom.window.localStorage.setItem(k, v);

  const script = html.match(/<script>\n"use strict";([\s\S]*?)<\/script>/)[1];
  dom.window.eval('"use strict";' + script);
  return dom.window;
}

const KEY = "love-live-editor/project/v1";
const $ = (w, id) => w.document.getElementById(id);

/* ---- 1. first paint keeps the starter example intact ---- */
let w = bootWith(null);
let saved = JSON.parse(w.localStorage.getItem(KEY));
assert.ok(saved, "nothing was autosaved on first paint");

const mainFile = saved.files.find(f => f.name === "main.lua");
assert.ok(mainFile.text.includes("love.draw"), "main.lua was blanked on first paint");
assert.ok(mainFile.text.length > 400, `main.lua truncated to ${mainFile.text.length} chars`);
assert.strictEqual($(w, "code").value, mainFile.text, "textarea does not show main.lua");
const freshMainLua = mainFile.text;
console.log("PASS  first paint preserves main.lua (" + mainFile.text.length + " chars)");

/* ---- 2. gutter tracks line count ---- */
const lines = mainFile.text.split("\n").length;
assert.strictEqual($(w, "gutter").childElementCount, lines, "gutter line count mismatch");
console.log("PASS  gutter rendered " + lines + " line numbers");

/* ---- 3. tabs render, one per file, main.lua not closable ---- */
const tabs = [...$(w, "tabs").querySelectorAll(".tab:not(.tab-add)")];
assert.deepStrictEqual(tabs.map(t => t.textContent.replace("×", "")), [
  "main.lua", "conf.lua", "clay.lua", "foley.lua", "ui_widgets.lua",
  "demo_layout.lua", "demo_text.lua", "demo_style.lua", "demo_scroll.lua",
  "demo_interact.lua", "demo_floating.lua", "demo_soundboard.lua", "demo_sounddesign.lua",
]);
assert.strictEqual(tabs[0].querySelector(".x"), null, "main.lua must not be removable");
for (const tab of tabs.slice(1)) assert.ok(tab.querySelector(".x"), tab.textContent + " should be removable");
assert.strictEqual(w.document.querySelector(".tab .x button, .tab button button"), null,
  "no nested buttons (invalid HTML)");
console.log("PASS  tab bar markup");

/* ---- 4. switching tabs does not lose edits ---- */
$(w, "code").value = mainFile.text + "\n-- edited\n";
$(w, "code").dispatchEvent(new w.Event("input"));
tabs[1].dispatchEvent(new w.MouseEvent("click", { bubbles: true }));
assert.ok($(w, "code").value.includes("love.conf"), "conf.lua did not open");

const backToMain = [...$(w, "tabs").querySelectorAll(".tab:not(.tab-add)")][0];
backToMain.dispatchEvent(new w.MouseEvent("click", { bubbles: true }));
assert.ok($(w, "code").value.includes("-- edited"), "edit to main.lua was lost when switching tabs");
console.log("PASS  edits survive tab switching");

/* ---- 5. screen preset rewrites conf.lua and the frame ---- */
const preset = $(w, "preset");
preset.value = "412x915";
preset.dispatchEvent(new w.Event("change"));
saved = JSON.parse(w.localStorage.getItem(KEY));
const conf = saved.files.find(f => f.name === "conf.lua");
assert.ok(/t\.window\.width\s*=\s*412/.test(conf.text), "conf.lua width not synced");
assert.ok(/t\.window\.height\s*=\s*915/.test(conf.text), "conf.lua height not synced");
assert.strictEqual($(w, "screen").style.width, "412px");
assert.strictEqual($(w, "dims").textContent, "412 × 915");
console.log("PASS  screen preset syncs conf.lua and the preview frame");

/* ---- 6. reload restores everything, including the unsaved-looking edit ---- */
const carried = w.localStorage.getItem(KEY);
const w2 = bootWith({ [KEY]: carried });
assert.ok($(w2, "code").value.includes("-- edited"), "edit did not survive reload");
assert.strictEqual($(w2, "preset").value, "412x915", "screen preset did not survive reload");
assert.strictEqual($(w2, "dims").textContent, "412 × 915");
const reMain = JSON.parse(w2.localStorage.getItem(KEY)).files.find(f => f.name === "main.lua");
assert.ok(reMain.text.includes("-- edited") && reMain.text.includes("love.draw"),
  "reload round-trip corrupted main.lua");
console.log("PASS  full reload round-trip");

/* ---- 7. run is blocked until the runtime loads, and says so ---- */
assert.strictEqual($(w2, "run").disabled, true, "Run should be disabled before the runtime is ready");
console.log("PASS  Run gated on runtime availability");

/* ---- 8. Reset restores the real starter main.lua, not the stale on-screen edit ---- */
w2.confirm = () => true;
$(w2, "reset").dispatchEvent(new w2.Event("click", { bubbles: true }));
assert.strictEqual($(w2, "code").value, freshMainLua,
  "Reset must show the fresh starter main.lua, not the stale edited textarea value");
assert.ok(!$(w2, "code").value.includes("-- edited"), "Reset left the old edit in main.lua");
const resetTabs = [...$(w2, "tabs").querySelectorAll(".tab:not(.tab-add)")].map(t => t.textContent.replace("×", ""));
assert.ok(resetTabs.includes("clay.lua"), "Reset did not reseed the full starter file set");
const savedAfterReset = JSON.parse(w2.localStorage.getItem(KEY)).files.find(f => f.name === "main.lua");
assert.strictEqual(savedAfterReset.text, freshMainLua, "Reset persisted the stale main.lua to storage");
console.log("PASS  Reset restores the real starter main.lua");

console.log("\nAll editor DOM tests passed.");
