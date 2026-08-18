#!/usr/bin/env node
"use strict";
/*
 * Batch driver for the LOVE live editor (index.html). Reads a script of
 * commands from stdin (one per line), runs them in order against a headless
 * Chromium instance, and exits. There is no interactive prompt and no tmux
 * dependency -- pipe a heredoc, same style as chromium-cli usage:
 *
 *   node .claude/skills/run-love2d-live-editor/driver.mjs <<'EOF'
 *   launch
 *   ss 01-loaded
 *   quit
 *   EOF
 *
 * The app is a single static page (index.html + love.js + love.wasm) with no
 * build step. It fetches love.js/love.wasm relative to its own URL, so it
 * must be served over http:// -- file:// fails fetch(). This driver spins up
 * its own static server (plain Node http, no external deps) on ROOT.
 */
import { chromium } from "playwright";
import * as http from "node:http";
import * as fs from "node:fs";
import * as path from "node:path";
import * as readline from "node:readline";

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const ROOT = path.resolve(HERE, "..", "..", "..");
const SHOT_DIR = process.env.SCREENSHOT_DIR || path.join(HERE, "shots");
const DL_DIR = process.env.DOWNLOAD_DIR || path.join(HERE, "downloads");
fs.mkdirSync(SHOT_DIR, { recursive: true });
fs.mkdirSync(DL_DIR, { recursive: true });

const MIME = {
  ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".txt": "text/plain", ".lua": "text/plain", ".png": "image/png", ".love": "application/octet-stream"
};

// Extracted the same way test-runner-handshake.js does: pull the zip helpers
// out of index.html's inline <script> so exported archives can be verified
// byte-for-byte against the app's own zipStore/unzip implementation.
const indexHtml = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
const mainSrc = indexHtml.match(/<script>\n"use strict";([\s\S]*?)<\/script>/)[1];
const zipSrc = mainSrc.slice(
  mainSrc.indexOf("const CRC_TABLE"),
  mainSrc.indexOf("/* ---", mainSrc.indexOf("function stripCommonRoot"))
);
const { zipStore, unzip } = new Function(zipSrc + "return { zipStore, unzip };")();

let server = null;
let baseUrl = null;
let browser = null;
let page = null;
const consoleErrors = [];
const pageErrors = [];

function startServer(port) {
  return new Promise((resolve, reject) => {
    server = http.createServer((req, res) => {
      const reqPath = decodeURIComponent(req.url.split("?")[0]);
      const filePath = path.join(ROOT, reqPath === "/" ? "/index.html" : reqPath);
      if (!filePath.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
      fs.readFile(filePath, (err, data) => {
        if (err) { res.writeHead(404); return res.end("not found"); }
        res.writeHead(200, { "Content-Type": MIME[path.extname(filePath)] || "application/octet-stream" });
        res.end(data);
      });
    });
    server.on("error", reject);
    server.listen(port, "127.0.0.1", () => resolve());
  });
}

const EXPORT_BUTTONS = { love: "#export", html: "#exporthtml", zip: "#exportzip", editorzip: "#exporteditorzip" };
const EXPORT_NAMES = { love: "game.love", html: "index.html", zip: "game.zip", editorzip: "editor-project.zip" };

const COMMANDS = {
  async launch(arg) {
    if (browser) return console.log("already launched");
    const port = Number(arg) || 8934;
    await startServer(port);
    baseUrl = `http://127.0.0.1:${port}`;
    browser = await chromium.launch();
    page = await browser.newPage();
    page.on("console", m => { if (m.type() === "error") consoleErrors.push(m.text()); });
    page.on("pageerror", e => pageErrors.push(String(e)));
    await page.goto(baseUrl + "/index.html");
    await page.waitForSelector("#run:not([disabled])", { timeout: 60_000 });
    console.log("launched. served from", baseUrl, "runtime ready.");
  },

  async ss(name) {
    if (!page) return console.log("ERROR: launch first");
    const f = path.join(SHOT_DIR, (name || `ss-${Date.now()}`) + ".png");
    await page.screenshot({ path: f });
    console.log("screenshot:", f);
  },

  async click(sel) {
    if (!page) return console.log("ERROR: launch first");
    await page.click(sel);
    console.log("clicked", sel);
  },

  async text(sel) {
    if (!page) return console.log("ERROR: launch first");
    console.log(await page.textContent(sel || "body"));
  },

  async wait(arg) {
    if (!page) return console.log("ERROR: launch first");
    const [sel, ms] = arg.split(/\s+/);
    try { await page.waitForSelector(sel, { timeout: Number(ms) || 10_000 }); console.log("found:", sel); }
    catch { console.log("TIMEOUT:", sel); }
  },

  // Feeds one or more files into the hidden #filepicker input, same as
  // clicking "Load files" and picking them in a real file dialog. Comma-
  // separate for a multi-file selection.
  //
  // addUploads() in index.html is async (file.arrayBuffer()/unzip()) and its
  // change-event listener does not await it, so setInputFiles() resolving is
  // NOT proof the upload finished -- a `run`/`export` issued immediately
  // after can race it and silently operate on the stale project. Every
  // addUploads() code path (loaded/imported/error) logs a line containing
  // the file's own name, so wait for that line to prove the upload actually
  // landed before returning.
  async upload(arg) {
    if (!page) return console.log("ERROR: launch first");
    const paths = arg.split(",").map(p => p.trim());
    const last = path.basename(paths[paths.length - 1]);
    await page.setInputFiles("#filepicker", paths);
    await page.waitForFunction(
      name => document.getElementById("console").textContent.includes(name),
      last, { timeout: 10_000 }
    );
    console.log("uploaded:", paths.join(", "));
  },

  async tabs() {
    if (!page) return console.log("ERROR: launch first");
    const names = await page.$$eval(".tab:not(.tab-add)", els => els.map(e => e.textContent.replace("×", "").trim()));
    console.log("tabs:", names.join(", "));
  },

  // Clicks Run and waits for the status LED to settle, printing the boot
  // time (or the error state, whichever happens first).
  async run() {
    if (!page) return console.log("ERROR: launch first");
    await page.click("#run");
    await page.waitForSelector('#status[data-state="running"], #status[data-state="error"]', { timeout: 20_000 });
    const state = await page.getAttribute("#status", "data-state");
    const boot = await page.textContent("#boottime");
    console.log("run ->", state, boot);
  },

  // export love|html|zip|editorzip <outfile-path>
  async export(arg) {
    if (!page) return console.log("ERROR: launch first");
    const [kind, outPath] = arg.split(/\s+/);
    const sel = EXPORT_BUTTONS[kind];
    if (!sel) return console.log("ERROR: kind must be one of love|html|zip|editorzip");

    // Open the export modal first
    await page.click("#export-menu-btn");

    const dest = outPath || path.join(DL_DIR, EXPORT_NAMES[kind]);
    const [download] = await Promise.all([page.waitForEvent("download"), page.click(sel)]);
    await download.saveAs(dest);
    const size = fs.statSync(dest).size;
    console.log("exported", kind, "->", dest, `(${size} bytes, suggested name: ${download.suggestedFilename()})`);
  },

  // Verifies a .love/.zip archive by unzipping it with the app's own
  // zipStore/unzip implementation and listing entries + sizes.
  async unzip(filePath) {
    const bytes = new Uint8Array(fs.readFileSync(filePath.trim()));
    const entries = await unzip(bytes);
    for (const e of entries) console.log(" ", e.name, `(${e.data.length} bytes)`);
    console.log(entries.length, "entries");
  },

  // Regenerates fixtures/test-import.love, fixtures/sprite.lua and
  // fixtures/icon.png -- see fixtures/README.md for what each is for.
  async 'build-fixtures'() {
    const enc = new TextEncoder();
    const FIX = path.join(HERE, "fixtures");
    fs.mkdirSync(FIX, { recursive: true });
    const loveBytes = zipStore([
      { name: "main.lua", data: enc.encode('function love.load() love.graphics.setBackgroundColor(0.1,0.2,0.3) end\nfunction love.draw() love.graphics.print("IMPORTED_LOVE_MARKER", 10, 10) end\n') },
      { name: "conf.lua", data: enc.encode('function love.conf(t) t.window.width = 390 t.window.height = 844 end\n') },
      { name: "data/readme.txt", data: enc.encode("fixture asset text file\n") }
    ]);
    fs.writeFileSync(path.join(FIX, "test-import.love"), loveBytes);
    fs.writeFileSync(path.join(FIX, "sprite.lua"), "-- sprite module marker LOOSE_LUA_MARKER\nreturn { speed = 42 }\n");
    const bin = Buffer.alloc(256);
    for (let i = 0; i < bin.length; i++) bin[i] = i % 256;
    fs.writeFileSync(path.join(FIX, "icon.png"), bin);
    console.log("fixtures written to", FIX);
  },

  // Opens an exported standalone .html directly over file:// (no server
  // involved) in a fresh page, and checks it actually boots: canvas gets
  // sized and the in-page error panel never shows. This is the whole point
  // of "Export .html" -- it must work with zero server / zero network.
  async 'verify-standalone'(arg) {
    if (!browser) return console.log("ERROR: launch first");
    const [filePath, name] = arg.split(/\s+/);
    const abs = path.resolve(filePath);
    const p2 = await browser.newPage();
    const errs = [];
    p2.on("pageerror", e => errs.push(String(e)));
    await p2.goto("file:///" + abs.replace(/\\/g, "/"));
    await p2.waitForTimeout(4000);
    const errBoxVisible = await p2.isVisible("#err");
    const canvasBox = await p2.$eval("#canvas", c => ({ w: c.width, h: c.height }));
    const f = path.join(SHOT_DIR, (name || "verify-standalone") + ".png");
    await p2.screenshot({ path: f });
    await p2.close();
    console.log("verify-standalone:", abs);
    console.log("  canvas:", canvasBox.w + "x" + canvasBox.h, " error panel visible:", errBoxVisible, " page errors:", errs.length);
    console.log("  screenshot:", f);
    if (errBoxVisible || errs.length || !canvasBox.w) throw new Error("standalone export did not boot cleanly");
  },

  async eval(expr) {
    if (!page) return console.log("ERROR: launch first");
    try { console.log(JSON.stringify(await page.evaluate(expr))); }
    catch (e) { console.log("ERROR:", e.message); }
  },

  async errors() {
    console.log("console.error:", consoleErrors.length ? "\n  " + consoleErrors.join("\n  ") : "(none)");
    console.log("pageerror:", pageErrors.length ? "\n  " + pageErrors.join("\n  ") : "(none)");
  },

  async quit() {
    if (browser) await browser.close().catch(() => {});
    if (server) await new Promise(r => server.close(r));
    browser = null; page = null; server = null;
  },

  help() { console.log("commands:", Object.keys(COMMANDS).join(", ")); }
};

async function main() {
  const lines = [];
  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  for await (const line of rl) {
    const t = line.trim();
    if (t && !t.startsWith("#")) lines.push(t);
  }

  let hadError = false;
  for (const line of lines) {
    const sp = line.indexOf(" ");
    const cmd = sp === -1 ? line : line.slice(0, sp);
    const rest = sp === -1 ? "" : line.slice(sp + 1);
    const fn = COMMANDS[cmd];
    console.log(`$ ${line}`);
    if (!fn) { console.log("unknown command:", cmd, "-- try: help"); hadError = true; continue; }
    try { await fn(rest); }
    catch (e) { console.log("ERROR:", e.message); hadError = true; }
  }

  await COMMANDS.quit();
  process.exit(hadError ? 1 : 0);
}

main();
