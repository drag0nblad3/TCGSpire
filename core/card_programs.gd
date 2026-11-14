class_name CardPrograms
extends RefCounted
## Physical-card memory and play-order rules. All state lasts for one combat.

const DESCRIPTIONS := {
	"interrupt": "Names one or more enemy intents, such as Purge. If the target's next move holds that intent, that part is cancelled; the rest of the move still happens. Nothing happens if the intent isn't there, so read the icons first. Any \"If it cancels\" payoff fires once per enemy cut.",
	"relay_cashout": "Gain this copy's normal Relay Firewall, then deal the listed damage per Relay point. Consume the signal: it does not pass to another card. Without Relay, there is no bonus damage.",
	"handshake": "The named partner must have been played earlier this turn. Either order works, with a different payoff. Copies share the partner name, not temporary bonuses.",
	"cooldown": "Charge this copy only when it is discarded unplayed at turn end. Cache and Volatile prevent that discard. Charge boosts the printed damage or Firewall effect. Charge survives shuffles, is capped, and resets on play.",
	"compile": "Cache (Retain) keeps the compiler in hand. Each other card played while it is held records its type, up to capacity. Play it to execute the stored instructions in order and clear them. It cannot record itself or plays before it was drawn.",
	"plant": "The top draw-pile card carries a one-use Firewall payload until drawn, even through shuffling. Empty draw pile: no payload. Multiple payloads use the strongest, not their sum.",
	"sequence": "Your immediately preceding plays must match the listed types in order, within this turn. The payoff card itself is not part of that sequence.",
	"relay": "A specific card carries Relay. Playing it grants Firewall and passes a stronger Relay to the leftmost remaining card in hand, up to the cap. No other card: the signal ends. Relays do not add together. A Relay finisher keeps the current Firewall payout but consumes the signal instead of passing it. All temporary card memory resets next fight.",
}

static func effects(c: Combat, card: CardInstance) -> Array:
	var out: Array = []
	if card.relay > 0:
		out.append({"op": "ward", "amount": card.relay})
	for e in card.effects():
		match str(e.get("op", "")):
			"handshake":
				if str(e.get("card", "")) in c.played_ids:
					out.append_array(e.get("effects", []))
			"sequence":
				var types: Array = e.get("types", [])
				if c.played_types.size() >= types.size() and c.played_types.slice(-types.size()) == types:
					out.append_array(e.get("effects", []))
			"cooldown":
				out.append({"op": str(e.get("effect", "damage")), "amount": int(e.get("amount", 0)) + card.cooldown, "to": str(e.get("to", "self" if e.get("effect", "damage") == "ward" else "target"))})
			"relay_cashout":
				if card.relay > 0:
					out.append({"op": "damage", "amount": card.relay * int(e.get("mult", 2))})
			"compile":
				for t in card.compiled:
					var op := "damage" if t == "attack" else ("draw" if t == "power" else "ward")
					if e.get("mode", "mixed") == "ward" and t != "power":
						op = "ward"
					out.append({"op": op, "amount": 1 if op == "draw" else int(e.get("amount", 3))})
			_:
				out.append(e)
	return out


static func after_play(c: Combat, card: CardInstance, held: Array) -> void:
	card.cooldown = 0
	card.compiled.clear()
	var relay := card.relay
	var cap := card.relay_cap
	card.relay = 0
	card.relay_cap = 0
	c.played_ids.append(card.def.id)
	c.played_types.append(card.def.type)
	if c.is_over():
		return
	if relay > 0 and not card.effects().any(func(e: Dictionary) -> bool: return e.get("op") == "relay_cashout"):
		pass_relay(c, mini(relay + 1, cap), cap)
	for other in held:
		if not c.hand.has(other):
			continue
		for e in other.effects():
			if e.get("op", "") == "compile" and other.compiled.size() < int(e.get("cap", 3)):
				other.compiled.append(card.def.type)
				c.emit("compile", {"card": other.key(), "type": card.def.type, "count": other.compiled.size()})


static func on_discard(card: CardInstance) -> void:
	for e in card.effects():
		if e.get("op", "") == "cooldown":
			card.cooldown = mini(card.cooldown + int(e.get("step", 4)), int(e.get("cap", 8)))


static func pass_relay(c: Combat, amount: int, cap: int) -> void:
	if c.hand.is_empty():
		return
	var host: CardInstance = c.hand[0]
	if amount > host.relay:
		host.relay = amount
		host.relay_cap = cap
		c.emit("relay", {"card": host.key(), "amount": amount})
