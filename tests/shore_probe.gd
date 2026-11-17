extends SceneTree
## Shoreline probe (diagnostic): godot --headless --path . -s tests/shore_probe.gd
## Steepest slopes where the ground meets the water, with the river and lake carving switched off in turn.

var _main: Node
var _game: Node
var _f := 0
var _step := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _shore(gen: Object) -> Array:
	# Returns [steepest slope, count of steep (>0.35) shoreline cells, count of shoreline cells]
	var step := 4.0
	var worst := 0.0
	var steep := 0
	var shore := 0
	var inland_sum := 0.0
	var high := 0
	for j in range(40, 480):
		for i in range(40, 480):
			var x := i * step
			var z := j * step
			var h: float = gen.get_base_height(x, z)
			if absf(h) > 0.6:
				continue
			shore += 1
			var gx: float = (gen.get_base_height(x + step, z) - gen.get_base_height(x - step, z)) / (2.0 * step)
			var gz: float = (gen.get_base_height(x, z + step) - gen.get_base_height(x, z - step)) / (2.0 * step)
			var s := sqrt(gx * gx + gz * gz)
			worst = maxf(worst, s)
			if s > 0.35:
				steep += 1
				# Height 12 m inland, uphill from the shore.
				var inland: float = gen.get_base_height(x + gx / maxf(s, 0.01) * 12.0, z + gz / maxf(s, 0.01) * 12.0)
				inland_sum += inland
				if inland > 15.0:
					high += 1
	print("   steep cells: average height 12 m inland %.1f m, %d of %d are over 15 m inland" % [inland_sum / maxf(steep, 1), high, steep])
	return [worst, steep, shore]


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Shore Probe", 629946553)
			if _main.state == _main.State.PLAYING:
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var a: Array = _shore(gen)
			print("ALL          worst slope %.2f  steep shore cells %d of %d" % [a[0], a[1], a[2]])
			gen._hydro_ready = false
			var b: Array = _shore(gen)
			print("NO RIVERS    worst slope %.2f  steep shore cells %d of %d" % [b[0], b[1], b[2]])
			gen._hydro_ready = true
			gen.lake_amount = -10.0
			var c: Array = _shore(gen)
			print("NO LAKES     worst slope %.2f  steep shore cells %d of %d" % [c[0], c[1], c[2]])
			gen._hydro_ready = false
			var d: Array = _shore(gen)
			print("NO EITHER    worst slope %.2f  steep shore cells %d of %d" % [d[0], d[1], d[2]])
			print("RESULT: done")
			return true
	return false
