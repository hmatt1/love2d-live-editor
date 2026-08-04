"use strict";
/* Drives the runner script from the template against a stub that mimics the real
   love.js glue: MODULARIZE factory, FS_createDataFile assigned before preRun runs. */

const fs = require("fs");
const assert = require("assert");

const html = fs.readFileSync(__dirname + "/index.html", "utf8");
const runnerSrc = html.match(/<script type="text\/plain" id="runner-source">([\s\S]*?)<\/script>/)[1];
const mainSrc = html.match(/<script>\n"use strict";([\s\S]*?)<\/script>/)[1];

const zipSrc = mainSrc.slice(
  mainSrc.indexOf("const CRC_TABLE"),
  mainSrc.indexOf("/* ---", mainSrc.indexOf("function stripCommonRoot"))
);
const { zipStore, unzip } = new Function(zipSrc + "return { zipStore, unzip };")();

/* ---- fake browser ---- */
const posted = [];
const listeners = {};
const virtualFS = new Map();
let appendedScript = null;

const canvas = { focus() {} };
const win = {
  parent: { postMessage: m => posted.push(m) },
  addEventListener: (t, fn) => { (listeners[t] = listeners[t] || []).push(fn); },
  Love: null
};
win.parent.__isHost = true;

const doc = {
  getElementById: id => (id === "canvas" ? canvas : null),
  addEventListener: () => {},
  createElement: () => ({
    set textContent(v) { this._inline = v; },
    get textContent() { return this._inline; },
    _inline: null, src: null, onload: null, onerror: null
  }),
  body: { appendChild(s) { appendedScript = s; } }
};

/* Stub glue: mirrors the real ordering, FS API assigned before preRun fires. */
function LoveFactory(Module) {
  Module.FS_createPath = () => {};
  Module.FS_createDataFile = (parent, name, data) => {
    assert.strictEqual(parent, "/", "game.love must land at the filesystem root");
    virtualFS.set(parent + name, data);
  };
  Module.pauseMainLoop = () => { virtualFS.set("__paused", true); };
  Module.resumeMainLoop = () => { virtualFS.set("__paused", false); };

  assert.ok(Array.isArray(Module.preRun), "preRun must be an array");
  for (const fn of Module.preRun) fn();

  assert.strictEqual(Module.arguments[0], "./game.love");
  assert.strictEqual(Module.INITIAL_MEMORY, 33554432);
  assert.strictEqual(typeof Module.instantiateWasm, "function");

  Module.print("hello from lua");
  Module.printErr("Error: main.lua:3: something broke");
  Module.onRuntimeInitialized();
  return Promise.resolve(Module);
}

new Function("window", "document", "performance", "WebAssembly", runnerSrc)(
  win, doc, { now: () => 42 }, { instantiate: () => Promise.resolve({}) }
);

assert.deepStrictEqual(posted.shift(), { type: "hello" }, "runner must announce itself first");

/* ---- host sends the boot payload ---- */
const enc = new TextEncoder();
const loveBytes = zipStore([
  { name: "main.lua", data: enc.encode("function love.draw() end\n") },
  { name: "conf.lua", data: enc.encode("function love.conf(t) t.window.width = 390 end\n") }
]);

win.Love = LoveFactory;
listeners.message[0]({
  source: win.parent,
  data: { type: "boot", love: loveBytes, memory: 33554432, glueUrl: "blob:fake", wasmModule: {} }
});

assert.ok(appendedScript, "runner must append the glue script");
assert.strictEqual(appendedScript.src, "blob:fake");
appendedScript.onload();

/* ---- assertions ---- */
const written = virtualFS.get("/game.love");
assert.ok(written, "game.love was never written to the virtual filesystem");
assert.ok(Buffer.from(written).equals(Buffer.from(loveBytes)), "game.love bytes were mangled in transit");

const kinds = posted.map(m => m.type + (m.stream ? ":" + m.stream : ""));
assert.ok(kinds.includes("log:out"), "stdout not forwarded to the host");
assert.ok(kinds.includes("log:err"), "stderr not forwarded to the host");
assert.ok(kinds.includes("running"), "boot completion not reported");

const caps = posted.find(m => m.type === "caps");
assert.ok(caps && caps.pause === true, "pause capability not detected");

/* pause/resume round trip */
listeners.message[0]({ source: win.parent, data: { type: "pause" } });
assert.strictEqual(virtualFS.get("__paused"), true, "pause did not reach Module.pauseMainLoop");
listeners.message[0]({ source: win.parent, data: { type: "resume" } });
assert.strictEqual(virtualFS.get("__paused"), false, "resume did not reach Module.resumeMainLoop");

/* the archive LÖVE receives must actually be readable */
unzip(written).then(entries => {
  assert.deepStrictEqual(entries.map(e => e.name).sort(), ["conf.lua", "main.lua"]);
  console.log("PASS  runner handshake, FS write, log forwarding, pause/resume, archive integrity");
  console.log("      messages:", kinds.join(", "));
});
