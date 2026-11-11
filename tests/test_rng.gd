extends TestCase


func test_same_seed_same_sequence() -> void:
	var a := GameRng.new(42)
	var b := GameRng.new(42)
	for i in 20:
		eq(a.range_i(0, 1000), b.range_i(0, 1000), "roll %d" % i)


func test_forks_are_independent_and_stable() -> void:
	var r := GameRng.new(7)
	var x := r.fork("map").range_i(0, 1_000_000)
	r.range_i(0, 10)  # consuming the parent must not change forks
	eq(r.fork("map").range_i(0, 1_000_000), x, "fork stable")
	check(r.fork("map").seed_value != r.fork("loot").seed_value, "streams differ")


func test_shuffle_is_permutation() -> void:
	var arr := range(10)
	GameRng.new(3).shuffle(arr)
	var sorted := arr.duplicate()
	sorted.sort()
	eq(sorted, range(10))


func test_weighted_respects_zero_weight() -> void:
	var r := GameRng.new(5)
	for i in 200:
		check(r.weighted({"a": 1, "b": 0}) == "a", "picked zero-weight key")
