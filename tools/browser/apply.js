// Applies edits exported from the data browser (or read from its shared store) to data/.
//   node tools/browser/apply.js edits.json
// edits.json: {"edits": [{"kind": "card"|"enemy", "id", "file", "isNew", "data": {...}}]}
// Files keep one entry per line; an edited entry's line is replaced, a new one is appended.
const fs = require("fs");
const path = require("path");
const ROOT = path.join(__dirname, "..", "..");
const input = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const list = Array.isArray(input) ? input : input.edits;
let failed = 0;
for (const ed of list) {
  const rel = ed.file;
  if (!/^data\/(cards|enemies)\/[a-z0-9_]+\.json$/.test(rel)) { console.log(`skip ${ed.id}: bad file ${rel}`); failed++; continue; }
  const file = path.join(ROOT, rel);
  const lines = fs.readFileSync(file, "utf8").split("\n");
  const entries = JSON.parse(lines.join("\n"));
  const at = entries.findIndex((e) => e.id === ed.id);
  const line = JSON.stringify(ed.data);
  if (at >= 0) {
    const i = lines.findIndex((l) => { const t = l.trim().replace(/,$/, ""); try { return t.startsWith("{") && JSON.parse(t).id === ed.id; } catch (e) { return false; } });
    if (i < 0) { console.log(`skip ${ed.id}: entry is not on one line in ${rel}`); failed++; continue; }
    lines[i] = line + (lines[i].trim().endsWith(",") ? "," : "");
    console.log(`edited ${ed.kind} ${ed.id} in ${rel}`);
  } else {
    const close = lines.map((l) => l.trim()).lastIndexOf("]");
    let prev = close - 1;
    while (prev >= 0 && lines[prev].trim() === "") prev--;
    if (!lines[prev].trim().endsWith(",")) lines[prev] += ",";
    lines.splice(prev + 1, 0, line);
    console.log(`added ${ed.kind} ${ed.id} to ${rel}`);
  }
  const out = lines.join("\n");
  JSON.parse(out);
  fs.writeFileSync(file, out);
}
process.exit(failed ? 1 : 0);
