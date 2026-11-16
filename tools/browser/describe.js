// Rules text for the data browser: a port of Effects.describe, DaemonRules.describe,
// the trigger part of Talismans.describe and CardDef.get_text/upgrade_summary.
// `node tools/browser/verify.js <text.json>` checks it word for word against the game.
// G holds the tables exported by tools/export_browser.gd plus `names` {cards, enemies}.
(function (root) {
  let G = null;
  const setTables = (t) => { G = t; };
  const int = (v) => { const n = Number(v); return Number.isFinite(n) ? Math.trunc(n) : 0; };
  const num = (v, d) => (v === undefined || v === null ? d : Number(v));
  const roundi = (x) => (x < 0 ? -Math.round(-x) : Math.round(x));
  const gs = (x) => (Number.isInteger(Number(x)) ? Number(x) + ".0" : String(Number(x))); // GDScript str(float)
  const status = (id) => (G.statuses[id] ? G.statuses[id].name : cap(id));
  const keyword = (id) => (G.keywords[id] ? G.keywords[id].name : cap(id));
  const typeName = (id) => G.types[id] || cap(id);
  const intent = (k) => G.intents[k] || cap(k);
  const cardName = (id) => (G.names.cards[id] !== undefined ? G.names.cards[id] : cap(id));
  const enemyName = (id) => (G.names.enemies[id] !== undefined ? G.names.enemies[id] : cap(id));
  function cap(s) { // String.capitalize(): snake_case -> "Snake Case"
    return String(s).split(/[_\s]+/).filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
  }
  const PER_KEYS = ["per", "per_mult", "per_key"];
  const perKey = (e) => String(e.per_key !== undefined ? e.per_key : (G.loop_key[String(e.op || "")] || "amount"));
  const fx = (list) => (list || []).map((x) => describe(x)).join(" ");

  function describe(e) {
    if (e.per !== undefined) return describePer(e);
    const s = _describe(e);
    if (e.loop === undefined) return s;
    const tag = "Loop +" + int(e.loop);
    if (String(e.op || "") === "summon") return s.replace(" HP):", " HP, " + tag + "):");
    let i = s.indexOf(". ");
    if (i < 0) i = s.length - 1;
    return s.slice(0, i) + " (" + tag + ")" + s.slice(i);
  }

  function describePer(e) {
    const per = String(e.per);
    const k = perKey(e);
    const d = Object.assign({}, e);
    PER_KEYS.forEach((pk) => delete d[pk]);
    const base = int(d[k] || 0);
    d[k] = 7777;
    let s = describe(d);
    const letter = per === "x" ? "X" : "N";
    const m = num(e.per_mult, 1);
    let note = G.per_sources[per] || "";
    let term = letter;
    if (Math.abs(m - Math.round(m)) < 1e-5) {
      term = (int(m) !== 1 ? String(int(m)) : "") + letter;
    } else if (letter === "N") {
      const part = Math.abs(m - 0.5) < 1e-5 ? "half the" : gs(m) + " x the";
      note = note.replace("N = cards", "N = " + part + " cards").replace("N = other cards", "N = " + part + " other cards")
        .replace("N = your", "N = " + part).replace(/\.$/, "") + ", rounded down.";
    } else {
      term = gs(m) + letter;
    }
    if (base > 0) term = base + "+" + term;
    s = s.split("7777").join(term);
    return s + (note !== "" ? " " + note : "");
  }

  function _describe(e) {
    const op = String(e.op || "");
    const n = int(e.amount || 0);
    const to = String(e.to || "");
    const where = { all_enemies: " to ALL enemies", all_allies: " to you and your daemons", front: " to the front enemy", daemon: " to your front daemon" }[to] || "";
    switch (op) {
      case "handshake":
        return "Handshake — if you played " + cardName(String(e.card || "")) + " this turn: " + fx(e.effects);
      case "sequence":
        return "Sequence — after " + (e.types || []).map(typeName).join(" → ") + ", in order this turn: " + fx(e.effects);
      case "cooldown": {
        const effect = String(e.effect || "damage");
        const base = _describe({ op: effect, amount: n, to: to });
        return base + " Cooldown: discarded unplayed at turn end, charge +" + int(num(e.step, 4)) + " " + (effect === "ward" ? "Firewall" : "damage") + " (max +" + int(num(e.cap, 8)) + "). Playing resets charge.";
      }
      case "relay_cashout":
        return "Consume this card's Relay: deal " + int(num(e.mult, 2)) + " damage per point. Keep its Firewall payout; do not pass it.";
      case "compile":
        if ((e.mode || "mixed") === "ward")
          return "Compile up to " + int(num(e.cap, 3)) + " other plays while held: each adds " + n + " Firewall; Rootkits instead draw 1. Execute and clear on play.";
        return "Compile up to " + int(num(e.cap, 3)) + " other plays while held: Exploit +" + n + " damage, Script/Daemon +" + n + " Firewall, Rootkit draw 1. Execute and clear on play.";
      case "plant":
        return "Plant " + n + " Firewall on the top draw-pile card: gain it once when drawn. Replaces weaker payloads.";
      case "relay":
        return "Give the leftmost other card in hand Relay " + n + ": on play gain that much Firewall, then pass +1 (max " + int(num(e.cap, 6)) + "). Stronger Relay replaces weaker.";
      case "damage": {
        const hits = int(num(e.hits, 1));
        if (to === "daemon") return "Purge " + n + ": your front daemon loses " + n + " HP.";
        return "Deal " + n + " damage" + (hits > 1 ? " " + hits + " times" : "") + where + ".";
      }
      case "damage_per_ward": {
        const mult = num(e.mult, 1.0);
        return "Deal damage equal to your Firewall" + (mult === 1 ? "" : " x" + gs(mult)) + where + ".";
      }
      case "ward": return "Gain " + n + " Firewall.";
      case "heal": return to === "this" ? "This daemon repairs " + n + " HP." : "Repair " + n + " HP.";
      case "apply": {
        const s = status(String(e.status || ""));
        const stacks = int(num(e.stacks, 1));
        if (String(e.status || "") === "stall") {
          if (to === "all_enemies") return "Lag ALL enemies: each skips its next move (no effect on an enemy already Lagged).";
          return "Lag the target: it skips its next move (no effect if already Lagged).";
        }
        if (to === "self") return "Gain " + stacks + " " + s + ".";
        return "Apply " + stacks + " " + s + where + ".";
      }
      case "draw": return "Draw " + n + " card" + (n === 1 ? "" : "s") + ".";
      case "energy": return "Gain " + n + " RAM.";
      case "summon": return "Run " + (e.name !== undefined ? e.name : "Unit") + " (" + int(num(e.hp, 1)) + " HP): " + describeRule(e.rule || {});
      case "rally": return "Your daemons gain +" + n + " HP.";
      case "cleanse": return "Purge your harmful statuses.";
      case "add_card": {
        const nm = cardName(String(e.card !== undefined ? e.card : "?")) + (e.upgraded ? "+" : "");
        const cnt = Math.max(n, 1);
        if (String(e.pile || "hand") === "draw") return "Put " + cnt + " " + nm + " on top of your draw pile.";
        return cnt === 1 ? "Add " + nm + " to your hand." : "Add " + n + " " + nm + " to your hand.";
      }
      case "spawn": return "Call in a " + enemyName(String(e.enemy !== undefined ? e.enemy : "?")) + ".";
      case "devour": {
        const boost = int(e.stacks || 0);
        return "Devour every helper it called in: repair " + n + " HP" + (boost > 0 ? " and gain " + boost + " " + status("might") : "") + " for each one eaten.";
      }
      case "revive":
        if (int(e.max || 0) > 0) return "Restore its crashed twin at " + Math.max(roundi(int(e.max) * num(e.pct, 0.5)), 1) + " HP, its new max HP.";
        return "Restore its crashed twin at " + roundi(num(e.pct, 0.5) * 100) + "% HP.";
      case "lose_hp": return "Lose " + n + " HP.";
      case "damage_per_status": {
        const st = status(String(e.status || ""));
        const base = int(e.base || 0);
        const mult = num(e.mult, 1.0);
        const nm = mult === Math.trunc(mult) ? String(Math.trunc(mult)) : gs(mult);
        let txt = base > 0 ? "Deal " + base + " damage +" + nm + " per " + st + where + "." : "Deal " + nm + " damage per " + st + where + ".";
        if (String(e.of || "") === "target") {
          const who = to === "all_enemies" ? " on each enemy" : " on the target";
          txt = base > 0 ? "Deal " + base + " damage +" + nm + " per " + st + who + "." : "Deal " + nm + " damage per " + st + who + ".";
          return txt + (e.consume ? " Remove it." : "");
        }
        return txt + (e.consume ? " Spend all " + st + "." : "");
      }
      case "amplify": {
        const st2 = status(String(e.status || ""));
        const m2 = num(e.mult, 2.0);
        const word = m2 === 2 ? "Double" : m2 === 3 ? "Triple" : "Multiply by " + gs(m2);
        const whose = to === "all_enemies" ? "each enemy's" : to === "self" ? "your" : "the target's";
        const b = int(e.base || 0);
        if (b > 0) return word + " " + whose + " " + st2 + " (" + (to === "self" ? "gain " + b : "apply " + b) + " if there is none).";
        return word + " " + whose + " " + st2 + ".";
      }
      case "strip": return "Strip all helpful statuses from " + (to === "all_enemies" ? "ALL enemies" : "the target") + ".";
      case "dump":
        if (n <= 0) return "Dump your hand: discard every other card in it.";
        return "Dump " + n + ": discard " + (n === 1 ? "a card" : n + " cards") + " from your hand.";
      case "recover": {
        let from = String(e.from || "") === "wiped" ? "a Wiped program (not a Rootkit)" : "a program from your discard pile";
        if (Math.max(n, 1) > 1) from = from.replace("a Wiped program", n + " Wiped programs").replace("a program", n + " programs");
        if (String(e.into || "draw") === "top") return "Put " + from + " on top of your draw pile.";
        return "Shuffle " + from + " into your draw pile.";
      }
      case "interrupt": {
        let t = "Interrupt " + (e.kinds || []).map(intent).join(" or ") + (to === "all_enemies" ? " on ALL enemies" : "") + ".";
        if ((e.effects || []).length) t += " If it cancels: " + fx(e.effects);
        return t;
      }
      case "fuel":
        return "Fuel " + Math.max(int(num(e.stacks, 1)), 1) + " " + (to === "self" ? "of your " : "") + status(String(e.status || "might")) +
          (to === "all_enemies" ? " (each enemy)" : "") + ": " + fx(e.effects);
      case "sacrifice": {
        const m3 = num(e.mult, 1.0);
        const x = m3 === 1 ? "its HP" : (m3 === Math.trunc(m3) ? String(Math.trunc(m3)) : gs(m3)) + "x its HP";
        const then = { damage: "deal damage equal to " + x + where, ward: "gain Firewall equal to " + x, heal: "repair HP equal to " + x,
          draw: "draw cards equal to " + x, energy: "gain RAM equal to " + x }[String(e.effect || "damage")] || "";
        return "Crash your front daemon: " + then + ".";
      }
    }
    return "?" + op + "?";
  }

  function describeRule(rule) {
    const parts = [];
    const flags = rule.flags || {};
    Object.keys(flags).forEach((k) => {
      const txt = G.daemon_flags[k] !== undefined ? G.daemon_flags[k] : "?" + k + "?";
      parts.push(txt.indexOf("%d") >= 0 ? txt.replace("%d", String(int(flags[k]))) : txt);
    });
    if ((rule.triggers || []).length) parts.push(describeTriggers(rule.triggers));
    return parts.join(" ");
  }

  function describeTriggers(triggers) {
    const parts = [];
    triggers.forEach((trig) => {
      const on = trig.on || "";
      let when = G.trigger_labels[on] !== undefined ? G.trigger_labels[on] : "?";
      if (trig.card_type !== undefined) {
        const tn = typeName(String(trig.card_type));
        when = "When you play " + ("aeiou".indexOf(tn[0].toLowerCase()) >= 0 ? "an" : "a") + " " + tn;
      }
      if (trig.every !== undefined) {
        let noun = { card_played: "cards you play", turn_start: "turns", turn_end: "turns", kill: "crashed enemies",
          daemon_closed: "daemons destroyed or refreshed", reshuffle: "reshuffles" }[on] || "times";
        if (trig.card_type !== undefined) noun = typeName(String(trig.card_type)) + "s you play";
        when = "Every " + int(trig.every) + " " + noun;
        if (on === "loop") when = "Every " + int(trig.every) + " times a Loop program grows";
      } else if (trig.keyword !== undefined && on === "card_played") {
        when = "When you play a " + keyword(String(trig.keyword)) + " program";
      }
      if (trig.turn !== undefined) when = "On turn " + int(trig.turn);
      parts.push(when + ": " + fx(trig.effects));
    });
    return parts.join(" ");
  }

  // ---- implants (Talismans.describe, Perks.describe_mod, RunOutcomes.describe) ----
  const plural = (n) => (n === 1 ? "" : "s");
  const pct = (v) => roundi(Number(v) * 100);
  function describeMod(k, v) {
    v = Number(v); const n = int(v);
    switch (k) {
      case "jumps": return "+" + n + " jump" + plural(n) + " per layer: leap diagonally to the next floor through walls, into sealed vaults too.";
      case "max_hp": return "+" + n + " max HP.";
      case "start_gold": return "Start runs with +" + n + " creds.";
      case "gold_pct": return "+" + pct(v) + "% creds from fights.";
      case "rest_heal_pct": return "Safehouses repair " + pct(v) + "% more.";
      case "shop_discount_pct": return "Fixer prices " + pct(v) + "% lower.";
      case "reward_choices": return "+" + n + " program choice" + plural(n) + " after fights.";
      case "reward_rerolls": return "Reroll program rewards after fights " + n + " time" + plural(n) + " per run.";
      case "event_rerolls": return "Reroll a Signal before choosing " + n + " time" + plural(n) + " per run.";
      case "combat_heal": return "Repair " + n + " HP after each fight you win.";
      case "start_ward": return "Jack in with " + n + " Firewall.";
      case "ward_retention": return "Keep " + pct(v) + "% of remaining Firewall at the start of your turn, rounded up.";
      case "daemon_death_damage": return "When one of your daemons is destroyed or refreshed, it explodes for " + n + " damage to all enemies.";
      case "manual_crash": return "In fights, you can shut down your own daemons.";
      case "daemon_heal": return "Each time you run a daemon, repair " + n + " HP.";
      case "daemon_ward": return "Your daemons start with " + n + " Firewall that blocks attacks and doesn't decay.";
      case "second_wind": return "Once per fight, the first hit that would flatline you leaves you at 1 HP and gives you " + n + " Firewall.";
      case "start_mods": return "Start runs with " + n + " random mod" + plural(n) + " installed.";
      case "start_perks": return "Start runs with " + n + " random subroutine" + plural(n) + ".";
      case "rep_pct": return "+" + pct(v) + "% rep from jobs.";
      case "max_energy": return "+" + n + " RAM every turn.";
      case "hand_size": return "Draw " + Math.abs(n) + " " + (v < 0 ? "fewer" : "more") + " program" + plural(Math.abs(n)) + " each turn.";
      case "board_slots": return (n >= 0 ? "+" : "") + n + " daemon slot" + plural(Math.abs(n)) + ".";
      case "daemon_hp": return "Your daemons have +" + n + " HP.";
      case "perk_choices": return "+" + n + " subroutine choice" + plural(n) + ".";
      case "remove_discount_pct": return "Deleting a program at the Fixer costs " + pct(v) + "% less.";
      case "turn_ward": return "Gain " + n + " Firewall at the start of each turn.";
      case "remove_discount": return "Deleting a program at the Fixer costs " + n + " less.";
      case "run_scrap": return "When the run ends, gain " + n + " Scrap.";
      case "bonus_packs": return "If you breach at least one Core, the run pays " + n + " more Data cache" + plural(n) + ".";
      case "enemy_hp_pct": return "Enemies have " + Math.abs(pct(v)) + "% " + (v < 0 ? "less" : "more") + " HP.";
      case "enemy_dmg_pct": return "Enemies deal " + Math.abs(pct(v)) + "% " + (v < 0 ? "less" : "more") + " damage.";
    }
    return "?";
  }
  function describeOutcome(o) {
    const n = int(o.amount || 0);
    switch (String(o.op || "")) {
      case "gold":
        if (o.pct !== undefined) return "Gain " + pct(o.pct) + "% of the creds you hold.";
        return (n >= 0 ? "Gain" : "Lose") + " " + Math.abs(n) + " creds.";
      case "heal": return o.pct !== undefined ? "Repair " + int(Number(o.pct) * 100) + "% of max HP." : "Heal " + n + ".";
      case "lose_hp": return "Lose " + n + " HP.";
      case "max_hp": return (n >= 0 ? "Gain" : "Lose") + " " + Math.abs(n) + " max HP.";
      case "add_card":
        if (o.card !== undefined) return "Add " + cardName(String(o.card)) + " to your deck.";
        return "Add a random " + (o.rarity || "common") + (o.faction !== undefined ? " " + (G.factions[o.faction] || cap(o.faction)) : "") + " card.";
      case "remove_card": return "Remove " + Math.max(n, 1) + " starter card" + plural(Math.max(n, 1)) + ".";
      case "upgrade": return "Upgrade " + Math.max(n, 1) + " random card" + plural(Math.max(n, 1)) + ".";
      case "talisman": return o.id === undefined ? "Gain a " + (o.rarity || "random") + " implant." : "Gain " + ((G.names.implants || {})[o.id] || o.id) + ".";
      case "mod": {
        const cnt = Math.max(n, 1);
        if (o.id !== undefined) return "Install " + ((G.names.mods || {})[o.id] || o.id) + " on a random program.";
        return "Install " + cnt + " random " + (o.rarity !== undefined ? o.rarity + " " : "") + "mod" + plural(cnt) + ".";
      }
      case "perk": return o.id !== undefined ? "Load the " + ((G.names.perks || {})[o.id] || o.id) + " subroutine." : "Load a random subroutine.";
    }
    return "?";
  }
  function implantText(t) {
    const parts = [];
    (t.pickup || []).forEach((o) => parts.push(describeOutcome(o)));
    const dm = t.daemon || {};
    if (dm.hp_mult !== undefined) { const m = Number(dm.hp_mult); parts.push(Math.abs(m - 2) < 1e-5 ? "Your daemons start with double HP." : "Your daemons start with " + roundi((m - 1) * 100) + "% more HP (rounded up)."); }
    if (dm.hp !== undefined) parts.push("Your daemons have +" + int(dm.hp) + " HP.");
    const flags = t.flags || {};
    if (Object.keys(flags).length) { let f = describeRule({ flags }); if (t.flags_while_daemon) f = "While you run a daemon: " + f; parts.push(f); }
    Object.keys(t.mods || {}).forEach((k) => parts.push(describeMod(k, t.mods[k])));
    (t.run || []).forEach((trig) => parts.push((G.run_labels[String(trig.on || "")] || "?") + ": " + (trig.outcomes || []).map(describeOutcome).join(" ")));
    if ((t.triggers || []).length) parts.push(describeTriggers(t.triggers));
    return parts.join(" ");
  }

  // ---- card level (CardDef) ----
  const isUp = (c) => c.upgrade && Object.keys(c.upgrade).length > 0;
  const costOf = (c, up) => { const v = up && c.upgrade && c.upgrade.cost !== undefined ? c.upgrade.cost : c.cost; return v === "X" ? "X" : int(num(v, 1)); };
  const effectsOf = (c, up) => (up && c.upgrade && c.upgrade.effects !== undefined ? c.upgrade.effects : c.effects || []);
  const keywordsOf = (c, up) => (up && c.upgrade && c.upgrade.keywords !== undefined ? c.upgrade.keywords : c.keywords || []);
  const onDumpOf = (c, up) => (up && c.upgrade && c.upgrade.on_dump !== undefined ? c.upgrade.on_dump : c.on_dump || []);

  function cardText(c, up) {
    const override = up && c.upgrade && c.upgrade.text !== undefined ? String(c.upgrade.text) : String(c.text || "");
    if (override !== "") return override;
    const parts = effectsOf(c, up).map((e) => describe(e));
    keywordsOf(c, up).forEach((k) => parts.push(keyword(String(k)) + "."));
    const od = onDumpOf(c, up);
    if (od.length) parts.push("When dumped: " + fx(od));
    if (c.evolve && Object.keys(c.evolve).length) parts.push("Evolve " + int(num(c.evolve.after, 20)) + ": becomes " + cardName(String(c.evolve.into || "")) + ".");
    return parts.join(" ");
  }

  function costLabel(c, up) { return String(costOf(c, up)); }

  function enemyMoveText(m) { return fx(m.effects); }

  root.Describe = { setTables, implantText, describeMod, describeOutcome, describe, describeRule, cardText, costLabel, enemyMoveText, isUp, effectsOf, keywordsOf, status, keyword, typeName, cardName, enemyName };
  if (typeof module !== "undefined") module.exports = root.Describe;
})(typeof window !== "undefined" ? window : globalThis);
