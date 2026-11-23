class_name CombatPlayback
extends RefCounted
## Event playback for CombatScreen, split out of the screen to keep it readable: replays new
## combat.events entries one by one (animations, floating numbers, card motion) on screen `s`.
## Every await goes through s._wait, a tween owned by the screen, so a freed screen never resumes.


## Replays new log entries. Returns one entry per card that reached the hand, in order:
## true if it came off the draw pile, false if it was made on the spot (to deal them in).
## Add new event types here, not in Combat.
static func play(s: CombatScreen, played: CardView) -> Array:
	var draws := []
	while s._event_cursor < s.combat.events.size():
		var e: Dictionary = s.combat.events[s._event_cursor]
		s._event_cursor += 1
		s._present_implant_event(e, s.step_scale > 0.0)
		if s.step_scale > 0.0:
			GameAudio.play(GameAudio.event_cue(e))
		var v: FighterView = s._views.get(str(e.get("target", "")))
		if v != null and not is_instance_valid(v):
			v = null
		if e["t"] not in ["damage", "death"]:
			s._combo_key = ""
		match e["t"]:
			"play":
				if s.step_scale > 0.0 and played != null:
					GameAudio.play(played.card.def.faction)
				if e.has("x"):
					s._float_text(s._player_view, "X = %d" % int(e["x"]), Palette.ENERGY, -40, true)
				if played != null and is_instance_valid(played):
					s._fly_card(played, s._views.get(str(e["target"])))
					played = null
					await s._wait(0.22)
			"damage":
				var damage := int(e["amount"])
				var blocked := int(e.get("blocked", 0))
				# Multi-hit attacks: each hit lands on its own beat, its number stacked above the last.
				var combo_key := "%s>%s" % [e.get("source", ""), e.get("target", "")]
				s._combo_n = s._combo_n + 1 if combo_key == s._combo_key and e.get("kind", "") == "attack" else 0
				s._combo_key = combo_key
				var next: Dictionary = s.combat.events[s._event_cursor] if s._event_cursor < s.combat.events.size() else {}
				var more_hits: bool = next.get("t", "") == "damage" and "%s>%s" % [next.get("source", ""), next.get("target", "")] == combo_key
				var lift := -26.0 * (s._combo_n % 4)
				if v != null:
					# The event amount can include overkill. Report the HP actually lost.
					var remaining := int(e.get("hp", v.fighter.hp))
					damage = maxi(0, v.hp() - remaining)
					v.shown_hp = remaining
					if e.get("kind", "") != "lose_hp":
						v.shown_ward = int(e.get("ward", v.fighter.ward))
					v.flash = 1.0 if damage > 0 else 0.0
					v.firewall_flash = 1.0 if blocked > 0 else 0.0
					s._recoil(v, damage)
				if blocked > 0:
					s._float_text(v, "%d Firewall absorbed" % blocked, Palette.WARD, (-24 if damage > 0 else 0) + lift, true)
				if damage > 0:
					# Bigger hits get bigger numbers and a harder shake.
					s._float_text(v, "−%d HP" % damage, Palette.HP, (10 if blocked > 0 else 0) + lift, true, clampi(20 + damage, 22, 40))
				if v == s._player_view and damage > 0:
					s._shake(clampf(4.0 + damage * 0.5, 5.0, 16.0))
				elif damage >= 12:
					s._shake(clampf(damage * 0.25, 3.0, 9.0))
				await s._wait(0.3 if more_hits or s._combo_n > 0 else 0.16)
			"ward":
				if v != null:
					v.firewall_flash = 1.0
					v.shown_ward = int(e.get("ward", v.fighter.ward))
				s._float_text(v, "+%d Firewall" % e["amount"], Palette.WARD)
				await s._wait(0.12)
			"heal":
				if v != null:
					v.shown_hp = int(e.get("hp", v.fighter.hp))
				s._float_text(v, "+%d HP" % e["amount"], Palette.UPGRADED)
				await s._wait(0.12)
			"status":
				if v != null and e["status"] == "burn" and e["stacks"] > 0:
					v.virus_flash = 1.0
				var debuff: bool = Statuses.DEFS.get(e["status"], {}).get("debuff", false)
				s._float_text(v, "%s %s%d" % [Lexicon.status(str(e["status"])), "+" if e["stacks"] >= 0 else "", e["stacks"]], Palette.ENEMY if debuff else Palette.UPGRADED)
				await s._wait(0.1)
			"interrupt":
				if v != null:
					s._float_text(v, "Interrupted", Palette.UPGRADED)
				await s._wait(0.1)
			"fuel":
				if v != null:
					s._float_text(v, "Fueled", Palette.UPGRADED)
				await s._wait(0.1)
			"immune":
				if v != null:
					v.firewall_flash = 1.0
					s._float_text(v, "Shielded", Palette.WARD)
				await s._wait(0.1)
			"sync":
				if v != null:
					v.shown_hp = int(e["hp"])
			"phase":
				if v != null:
					v.boss_action = 1.0
					v.frozen_intents = null
				await s._banner(str(e.get("name", "")) if str(e.get("name", "")) != "" else "Phase %d" % int(e["index"]), Palette.ENEMY)
			"gauge":
				if v != null:
					s._float_text(v, "Heat %d/%d" % [int(e["value"]), int(e["max"])], Palette.faction("ember"), -30)
			"gauge_full":
				if v != null:
					v.frozen_intents = null
					s._float_text(v, "%s next move" % str(e["name"]), Palette.HP, -50, true)
				await s._wait(0.2)
			"twin_down":
				var tv2: FighterView = s._views.get(str(e["by"]))
				if tv2 != null and is_instance_valid(tv2):
					s._float_text(tv2, "Will restore its twin", Palette.ENEMY, -40, true)
				await s._wait(0.25)
			"bond":
				if v != null:
					v.boss_action = 1.0
					s._float_text(v, "Bond broken: enraged", Palette.ENEMY, -40, true)
				await s._wait(0.25)
			"shield_down":
				if v != null:
					s._float_text(v, "Shield down", Palette.UPGRADED, -40, true)
				await s._wait(0.25)
			"shield_up":
				if v != null:
					v.firewall_flash = 1.0
					s._float_text(v, "Shield restored", Palette.WARD, -40, true)
				await s._wait(0.2)
			"devour":
				var dv: FighterView = s._views.get(str(e["source"]))
				if dv != null and is_instance_valid(dv):
					s._float_text(dv, "Devoured %d" % int(e["count"]), Palette.ENEMY, -40, true)
				await s._wait(0.2)
			"tide":
				if v != null and int(s.combat.turn) > 1:
					s._float_text(v, "Low tide" if e["state"] == "low" else "High tide", Palette.faction("tide"), -40)
			"timer":
				if v != null and int(e["left"]) == 0:
					s._float_text(v, "Trace complete", Palette.HP, -40, true)
			"infect":
				s._float_text(s._player_view, "%d %s put on top of your draw pile" % [int(e["amount"]), Lexicon.card_name(str(e["card"]))], Palette.ENEMY, -60, true)
				await s._wait(0.25)
			"hatch":
				s._float_text(s._player_view, "%s hatched" % Lexicon.card_name(str(e["card"]).trim_suffix("+")), Palette.ENEMY, -60, true)
				await s._wait(0.2)
			"strip":
				if v != null:
					s._float_text(v, "Stripped", Palette.faction("void"))
				await s._wait(0.1)
			"expire":
				var xv: FighterView = s._views.get(str(e["target"]))
				if xv != null and is_instance_valid(xv):
					s._float_text(xv, "Crashed" if e.get("crashed", false) else "Closed", Palette.TEXT_DIM)
					xv.create_tween().tween_property(xv, "modulate:a", 0.0, 0.3)
				await s._wait(0.15)
			"rule":
				var rv: FighterView = s._views.get(str(e["id"]))
				if rv != null and is_instance_valid(rv):
					rv.flash = 0.6
					rv.create_tween().tween_property(rv, "flash", 0.0, 0.3)
				await s._wait(0.1)
			"uptime":
				var tv: FighterView = s._views.get(str(e["target"]))
				if tv != null and is_instance_valid(tv):
					tv.shown_hp = int(e["hp"])
					tv.queue_redraw()
			"refresh":
				var fv: FighterView = s._views.get(str(e["target"]))
				if fv != null and is_instance_valid(fv):
					s._float_text(fv, "Refreshed", Palette.ENERGY)
					fv.shown_ward = int(e.get("ward", fv.fighter.ward))
				await s._wait(0.12)
			"death":
				if v != null:
					if v.kind == "unit":
						v.offline = true
						s._float_text(v, "Daemon crashed", Palette.HP, 8, true)
					var tw := v.create_tween()
					tw.tween_property(v, "modulate", Color(Palette.HP, 0.0), 0.35)
				await s._wait(0.3)
			"second_wind":
				s._float_text(s._player_view, "Second Wind", Palette.UPGRADED, -40, true)
				await s._wait(0.3)
			"daemon_explosion":
				s._float_text(v, "Detonate", Palette.HP)
				await s._wait(0.12)
			"enemy_phase":
				# Unplayed programs leave the hand for their pile; Retain ones stay put.
				var k := 0
				s._glide_after_change()
				for cv: CardView in s._hand_row.get_children():
					if s.combat.hand.has(cv.card):
						continue
					s._send_to_pile(cv, "exhaust" if s.combat.exhaust_pile.has(cv.card) else "discard", k * 0.04)
					k += 1
				await s._banner("Enemy turn", Palette.ENEMY)
			"enemy_move":
				var src: FighterView = s._views.get(str(e["source"]))
				if src != null and is_instance_valid(src):
					src.boss_action = 1.0
					if src.fighter.status("fortify") <= 0:
						src.shown_ward = 0
					src.frozen_intents = []
					s._float_text(src, str(e["move"]), Palette.ENEMY, -40)
					var tw := src.create_tween()
					tw.tween_property(src, "offset", Vector2(0, 36), 0.12 * s.step_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tw.tween_property(src, "offset", Vector2.ZERO, 0.2 * s.step_scale)
				await s._wait(0.2)
			"turn_start":
				s._player_view.shown_ward = int(e["ward"])
				if int(e["turn"]) > 1:
					await s._banner("Your turn", Palette.ENERGY)
			"summon":
				var u: Fighter = s._find(s.combat.units, str(e["target"]))
				if u == null:
					# A daemon can be summoned and destroyed before this action is replayed.
					u = Fighter.make(str(e["target"]), str(e["name"]), int(e["hp"]))
				var nv := s._add_unit_view(u)
				nv.shown_hp = int(e["hp"])
				nv.shown_ward = int(e.get("ward", 0))
				s._pop_in(nv)
				await s._wait(0.2)
			"spawn":
				var en: Fighter = s._find(s.combat.enemies, str(e["target"]))
				if en != null:
					var nv := s._add_enemy_view(en, s.combat.enemies.find(en))
					nv.freeze()
					nv.shown_hp = int(e.get("hp", en.max_hp))
					nv.shown_ward = 0
					s._pop_in(nv)
				await s._wait(0.25)
			"talisman":
				s._float_text(s._player_view, str(s.combat.db.talismans.get(e["id"], s.combat.db.perks.get(e["id"], {})).get("name", "")), Palette.RARITY["rare"], -30)
				await s._wait(0.18)
			"loop":
				s._float_text(s._player_view, "Loop: +%d now" % int(e.get("grown", e["loops"])), Palette.faction("void"), -30)
			"reshuffle":
				s._float_text(s._player_view, "Discard shuffled into draw pile", Palette.TEXT_DIM, -60)
			"dump":
				# The dumped card leaves the hand for the discard pile.
				s._glide_after_change()
				for cv: CardView in s._hand_row.get_children():
					if cv.card.key() == str(e["card"]) and not s.combat.hand.has(cv.card) and cv.modulate.a > 0.5:
						s._send_to_pile(cv, "discard", 0.0)
						break
				s._float_text(s._player_view, "Dumped %s" % s._card_label(str(e["card"])), Palette.TEXT_DIM, -50)
				await s._wait(0.15)
			"recover":
				var where := "on top of your draw pile" if str(e.get("into", "")) == "top" else "into your draw pile"
				s._float_text(s._player_view, "%s back %s" % [s._card_label(str(e["card"])), where], Palette.ENERGY, -60)
				s._bump_pile("draw")
				await s._wait(0.2)
			"evolve":
				await s._banner("%s evolved into %s" % [s._card_label(str(e["card"])), s._card_label(str(e["into"]))], Palette.UPGRADED)
			"draw":
				draws.append(not e.get("created", false))
			"rally":
				for uv in s._units_row.get_children():
					s._float_text(uv, "+%d HP" % int(e["amount"]), Palette.ENERGY)
				await s._wait(0.12)
			"combat_end":
				await s._banner("Victory" if e["won"] else "Defeated", Palette.ENERGY if e["won"] else Palette.HP)
	return draws
