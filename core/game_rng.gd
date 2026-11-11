class_name GameRng
extends RefCounted
## Seeded RNG. Every random roll in game logic goes through one of these so runs
## replay exactly from a seed. Use fork() to give each system (map, rewards,
## each combat) its own stream, so a change in one never reshuffles another.

var seed_value: int
var _rng := RandomNumberGenerator.new()


func _init(seed_in: int = 0) -> void:
	seed_value = seed_in
	_rng.seed = seed_in


static func from_string(s: String) -> GameRng:
	return GameRng.new(s.hash())


func fork(stream: String) -> GameRng:
	return GameRng.new(("%d:%s" % [seed_value, stream]).hash())


func range_i(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi)


func chance(p: float) -> bool:
	return _rng.randf() < p


func roll() -> float:
	return _rng.randf()


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## weights: {key: weight}. Dictionary order is insertion order, so this is deterministic.
func weighted(weights: Dictionary) -> Variant:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := _rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r < 0.0:
			return k
	return weights.keys().back()


func get_state() -> int:
	return _rng.state


func set_state(s: int) -> void:
	_rng.state = s
