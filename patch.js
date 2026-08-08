const fs = require('fs');
let code = fs.readFileSync('index.html', 'utf8');

// 1. CSS
code = code.replace(
`.edit-wrap { display: flex; min-height: 0; overflow: hidden; }
.gutter {
  flex: 0 0 auto; padding: 12px 10px 12px 12px;
  overflow: hidden;
  color: #4d475e; text-align: right;
  line-height: var(--lh);
  user-select: none;
  border-right: 1px solid var(--ink-2);
  background: var(--ink);
}
#code {
  flex: 1; min-width: 0;
  padding: 12px 16px 12px 12px;
  border: 0; resize: none;
  background: var(--ink); color: var(--txt);
  line-height: var(--lh);
  white-space: pre; overflow: auto; tab-size: 4;
  outline: none;
}
#code::selection { background: #4a2440; }`,
`.edit-wrap { grid-column: 2; grid-row: 1; display: flex; min-height: 0; overflow: hidden; background: var(--ink); }
#editor-container { flex: 1; min-width: 0; min-height: 0; display: flex; flex-direction: column; }
#editor-container .cm-editor { flex: 1; height: 100%; outline: none; }
#editor-container .cm-scroller { font: 13px/1.5 var(--mono); }
#editor-container .cm-gutters { background: var(--ink); color: #4d475e; border-right: 1px solid var(--ink-2); }`
);

// 2. DOM
code = code.replace(
`      <div class="edit-wrap">
        <div class="gutter" id="gutter" aria-hidden="true">1</div>
        <textarea id="code" spellcheck="false" autocomplete="off" autocapitalize="off" autocorrect="off" aria-label="Source code"></textarea>`,
`      <div class="edit-wrap" id="editor-container">`
);

// 3. Script tag
code = code.replace(
`<script>
"use strict";`,
`<script src="./love_api.js"></script>
<script type="importmap">
{
  "imports": {
    "@codemirror/state": "https://esm.sh/@codemirror/state",
    "@codemirror/view": "https://esm.sh/@codemirror/view",
    "@codemirror/commands": "https://esm.sh/@codemirror/commands",
    "@codemirror/language": "https://esm.sh/@codemirror/language",
    "@codemirror/autocomplete": "https://esm.sh/@codemirror/autocomplete",
    "@codemirror/legacy-modes/mode/lua": "https://esm.sh/@codemirror/legacy-modes@6.4.2/mode/lua"
  }
}
</script>
<script type="module">
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLineGutter } from "@codemirror/view";
import { defaultKeymap, indentWithTab } from "@codemirror/commands";
import { StreamLanguage } from "@codemirror/language";
import { lua } from "@codemirror/legacy-modes/mode/lua";
import { autocompletion } from "@codemirror/autocomplete";

function loveAutocomplete(context) {
  let word = context.matchBefore(/\\w*/);
  if (word.from == word.to && !context.explicit) return null;
  let before = context.matchBefore(/love\\.\\w*/);
  if (before) {
    let options = window.LOVE_API.modules.map(mod => ({label: mod.name, type: "namespace", info: mod.description}));
    for (let f of window.LOVE_API.functions || []) options.push({label: f.name, type: "function", info: f.description});
    return { from: before.from + 5, options: options, validFor: /^\\w*$/ };
  }
  for (let mod of window.LOVE_API.modules) {
    let re = new RegExp(\`love\\\\.\${mod.name}\\\\.\\\\w*\`);
    let modBefore = context.matchBefore(re);
    if (modBefore) {
      let options = (mod.functions || []).map(f => ({label: f.name, type: "function", info: f.description}));
      return { from: modBefore.from + 6 + mod.name.length, options: options, validFor: /^\\w*$/ };
    }
  }
  return null;
}

window.cmExtensions = [
  lineNumbers(), highlightActiveLineGutter(),
  keymap.of([indentWithTab, ...defaultKeymap]),
  StreamLanguage.define(lua), autocompletion({override: [loveAutocomplete]}),
  EditorView.updateListener.of((update) => {
    if (update.docChanged && window.onEdit) window.onEdit();
  }),
  EditorView.theme({
    "&": { color: "#d8d4e2", backgroundColor: "#14131a" },
    ".cm-content": { caretColor: "#e8489b" },
    "&.cm-focused .cm-cursor": { borderLeftColor: "#e8489b" },
    "&.cm-focused .cm-selectionBackground, ::selection": { backgroundColor: "#4a2440" },
    ".cm-gutters": { backgroundColor: "#14131a", color: "#4d475e", border: "none" }
  }, {dark: true})
];

window.createEditorState = function(text) {
  return EditorState.create({ doc: text, extensions: window.cmExtensions });
};

window.editor = new EditorView({
  parent: document.getElementById("editor-container")
});

window.onEdit = onEdit;
</script>
<script>
"use strict";`
);

// 4. syncActiveFile
code = code.replace(
`  const f = state.files.get(state.active);
  if (f && !f.binary) f.text = el("code").value;`,
`  // Deprecated: State is now managed natively inside f.cmState`
);

// 5. selectFile
code = code.replace(
`  const f = state.files.get(name);
  const code = el("code");`,
`  const f = state.files.get(name);
  const code = el("editor-container");`
);

code = code.replace(
`    code.classList.remove("hidden");
    code.value = f.text;
    code.scrollTop = 0;
    editorLoaded = true;
    updateGutter();`,
`    code.classList.remove("hidden");
    if (window.editor) {
      if (!f.cmState && window.createEditorState) f.cmState = window.createEditorState(f.text);
      if (f.cmState) window.editor.setState(f.cmState);
    }
    editorLoaded = true;`
);

// 6. remove updateGutter and handleTabKey
code = code.replace(
`function updateGutter() {
  const code = el("code");
  const lines = code.value.split("\\n").length;
  const gutter = el("gutter");
  if (gutter.childElementCount !== lines) {
    gutter.replaceChildren();
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= lines; i++) {
      const d = document.createElement("div");
      d.textContent = i;
      frag.appendChild(d);
    }
    gutter.appendChild(frag);
  }
  gutter.scrollTop = code.scrollTop;
}

function handleTabKey(ev) {
  const code = el("code");
  const { selectionStart: a, selectionEnd: b, value } = code;
  const lineStart = value.lastIndexOf("\\n", a - 1) + 1;

  if (ev.shiftKey) {
    const before = value.slice(lineStart, a);
    const cut = before.startsWith("    ") ? 4 : (before.match(/^ {1,3}/) || [""])[0].length;
    if (!cut) return;
    code.value = value.slice(0, lineStart) + value.slice(lineStart + cut);
    code.selectionStart = code.selectionEnd = a - cut;
  } else {
    code.value = value.slice(0, a) + "    " + value.slice(b);
    code.selectionStart = code.selectionEnd = a + 4;
  }
}`,
``
);

code = code.replace(
`function onEdit() {
  updateGutter();
  clearTimeout(saveTimer);`,
`function onEdit() {
  clearTimeout(saveTimer);`
);

// 7. applyFrame
code = code.replace(
`      .replace(/(t\\.window\\.height\\s*=\\s*)\\d+/, "$1" + h);
    if (state.active === "conf.lua") el("code").value = conf.text;`,
`      .replace(/(t\\.window\\.height\\s*=\\s*)\\d+/, "$1" + h);
    if (state.active === "conf.lua" && window.editor) {
      const f = state.files.get("conf.lua");
      if (f && f.cmState) window.editor.setState(f.cmState);
    }`
);

// 8. Event listeners for code
code = code.replace(
`  el("code").addEventListener("input", onEdit);
  el("code").addEventListener("scroll", () => { el("gutter").scrollTop = el("code").scrollTop; });
  el("code").addEventListener("keydown", ev => {
    if (ev.key === "Tab") { ev.preventDefault(); handleTabKey(ev); onEdit(); }
  });`,
``
);

fs.writeFileSync('patch.js', code);
console.log("Updated patch.js");
