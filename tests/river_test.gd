extends SceneTree
## River banks test: godot --headless --path . -s tests/river_test.gd
## The river channel must slope out into the land gently: neighbouring grid cells never differ in
## depth by more than the bank slope allows, and rivers still exist.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


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
			print("RIVERS cells %d  deepest %.2f m  worst step between neighbours %.2f m" % [rivers, deepest, worst_step])
			_check(rivers > 50, "the island has rivers (%d cells)" % rivers)
			_check(worst_step <= 0.6 * 1.45 + 0.05, "river banks slope gently (worst step %.2f m per 8 m)" % worst_step)
			return _finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
