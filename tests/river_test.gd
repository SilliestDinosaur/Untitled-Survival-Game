extends SceneTree
## River test: godot --headless --path . -s tests/river_test.gd
## Rivers must be built properly on this seed:
##   - the banks slope out gently: neighbouring cells never differ in depth by more than the slope allows
##   - every river cell holds water, so a river can't break up into dry gaps
##   - no dry ground lies under the water beside it: reported, not asserted yet. Steep hillside reaches still
##     float a sheet over the slope below them (see the open question on river beds that drop fast)
## and rivers still exist.

const FLOOD_TOL := 0.1   ## metres the ground may lie under a neighbour's surface before it counts as flooded

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _Hydro: GDScript


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")
	_Hydro = load("res://scripts/world/hydrology.gd")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("River Test", 629946553)
			if _main.state == _main.State.PLAYING:
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var h: Dictionary = gen.hydro
			var n: int = h.n
			var depth: PackedFloat32Array = h.depth
			var deepest := 0.0
			var worst_step := 0.0
			var rivers := 0
			for j in n:
				for i in n:
					var d := depth[j * n + i]
					deepest = maxf(deepest, d)
					if d > 0.3:
						rivers += 1
					if i + 1 < n:
						worst_step = maxf(worst_step, absf(d - depth[j * n + i + 1]))
					if j + 1 < n:
						worst_step = maxf(worst_step, absf(d - depth[(j + 1) * n + i]))
			var dry_channel := 0
			for k in n * n:
				if h.channel[k] > 0.0 and h.lake[k] == 0.0 and h.water[k] <= 0.0:
					dry_channel += 1
			var flood: Dictionary = _Hydro.flooded(gen, FLOOD_TOL)
			print("RIVERS cells %d  deepest %.2f m  worst step between neighbours %.2f m" % [rivers, deepest, worst_step])
			print("WATER dry river cells %d; dry ground under water %d (worst %.2f m)" % [dry_channel, flood.count, flood.worst])
			_check(rivers > 50, "the island has rivers (%d cells)" % rivers)
			_check(worst_step <= 0.6 * 1.45 + 0.05, "river banks slope gently (worst step %.2f m per 8 m)" % worst_step)
			_check(dry_channel == 0, "every river cell holds water (%d dry)" % dry_channel)
			print("KNOWN GAP dry ground under water beside it: %d points, worst %.2f m (not asserted yet)" % [flood.count, flood.worst])
			return _finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
