// Joins the raw data JSON with the game's generated text into one data blob for the
// browser page, and checks describe.js against the game word for word.
//   node tools/browser/build.js <godot_text.json> <out_dir>
const fs = require("fs");
const path = require("path");
const D = require("./describe.js");
const ROOT = path.join(__dirname, "..", "..");
const [textPath, outDir] = process.argv.slice(2);
const T = JSON.parse(fs.readFileSync(textPath, "utf8"));
const read = (rel) => JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8"));

const cards = [];
for (const f of fs.readdirSync(path.join(ROOT, "data/cards")).filter((f) => f.endsWith(".json")).sort())
  read("data/cards/" + f).forEach((c) => cards.push({ file: "data/cards/" + f, raw: c }));
const enemies = [];
for (const f of fs.readdirSync(path.join(ROOT, "data/enemies")).filter((f) => f.endsWith(".json")).sort())
  read("data/enemies/" + f).forEach((e) => enemies.push({ file: "data/enemies/" + f, raw: e }));
const encounters = read("data/encounters.json");
const factions = read("data/factions.json");

const names = { cards: {}, enemies: {} };
cards.forEach((c) => (names.cards[c.raw.id] = c.raw.name));
enemies.forEach((e) => (names.enemies[e.raw.id] = e.raw.name));
const tables = {
  statuses: T.statuses, keywords: T.keywords, types: T.types, type_desc: T.type_desc, factions: T.factions,
  intents: T.intents, daemon_flags: T.daemon_flags, trigger_labels: T.trigger_labels, per_sources: T.per_sources,
  loop_key: T.loop_key, ops: T.ops, rarities: T.rarities, names,
};
D.setTables(tables);

let bad = 0, checked = 0;
const check = (where, mine, game) => {
  checked++;
  if (mine !== game) { bad++; if (bad <= 15) console.log("MISMATCH " + where + "\n  js:   " + mine + "\n  game: " + game); }
};
cards.forEach((c) => {
  const g = T.cards[c.raw.id];
  if (!g) return;
  c.text = g.text; c.text_up = g.text_up; c.summary = g.summary;
  check(c.raw.id, D.cardText(c.raw, false), g.text);
  if (D.isUp(c.raw)) check(c.raw.id + "+", D.cardText(c.raw, true), g.text_up);
});
enemies.forEach((e) => {
  const g = T.enemies[e.raw.id];
  e.moves = g.moves; e.phase_moves = g.phase_moves; e.rules = g.rules;
  (e.raw.moves || []).forEach((m, i) => check(e.raw.id + "/" + m.name, D.enemyMoveText(m), g.moves[i]));
});
console.log(`describe.js: ${checked - bad}/${checked} texts match the game`);

const data = { built: new Date().toISOString(), commit: process.env.COMMIT || "", tables, cards, enemies, encounters, factions };
fs.mkdirSync(outDir, { recursive: true });
const tpl = fs.readFileSync(path.join(__dirname, "page.html"), "utf8");
const js = fs.readFileSync(path.join(__dirname, "describe.js"), "utf8");
const html = tpl.replace("/*DESCRIBE_JS*/", () => js)
  .replace("/*DATA_JSON*/null", () => JSON.stringify(data).replace(/</g, "\\u003c"));
fs.writeFileSync(path.join(outDir, "browser.html"), html);
console.log("wrote " + path.join(outDir, "browser.html") + " (" + Math.round(html.length / 1024) + " KB)");
process.exit(bad ? 1 : 0);
