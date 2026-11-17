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
	var badlands_steep := 0
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
				if gen.badlands_amount(x, z) > 0.01:
					badlands_steep += 1
	print("   steep cells: average height 12 m inland %.1f m, %d of %d are over 15 m inland, %d in badlands" % [inland_sum / maxf(steep, 1), high, steep, badlands_steep])
	return [worst, steep, shore]


## Land roughness: share of dry land steeper than 0.8 and 1.5 (slope = rise over run, sampled over 8 m).
func _land(gen: Object) -> String:
	var n := 0
	var s1 := 0
	var s2 := 0
	for j in range(40, 480, 2):
		for i in range(40, 480, 2):
			var x := i * 4.0
			var z := j * 4.0
			var h: float = gen.get_base_height(x, z)
			if h < 1.0:
				continue
			n += 1
			var gx: float = (gen.get_base_height(x + 4.0, z) - gen.get_base_height(x - 4.0, z)) / 8.0
			var gz: float = (gen.get_base_height(x, z + 4.0) - gen.get_base_height(x, z - 4.0)) / 8.0
			var sl := sqrt(gx * gx + gz * gz)
			if sl > 0.8:
				s1 += 1
			if sl > 1.5:
				s2 += 1
	return "land %d cells  steeper than 0.8: %.1f%%  steeper than 1.5: %.1f%%" % [n, 100.0 * s1 / maxf(n, 1), 100.0 * s2 / maxf(n, 1)]


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
			# Transect across the steepest shoreline cell (rivers and lakes off): heights every 4 m.
			var best_x := 0.0
			var best_z := 0.0
			var best_s := 0.0
			for j in range(40, 480):
				for i in range(40, 480):
					var x := i * 4.0
					var z := j * 4.0
					if absf(gen.get_base_height(x, z)) > 0.6:
						continue
					var gx: float = (gen.get_base_height(x + 4.0, z) - gen.get_base_height(x - 4.0, z)) / 8.0
					var gz: float = (gen.get_base_height(x, z + 4.0) - gen.get_base_height(x, z - 4.0)) / 8.0
					var sl := sqrt(gx * gx + gz * gz)
					if sl > best_s:
						best_s = sl
						best_x = x
						best_z = z
			var line := ""
			for k in range(-8, 9):
				line += " %.1f" % gen.get_base_height(best_x + k * 4.0, best_z)
			print("TRANSECT x-axis at (%.0f, %.0f) slope %.2f, heights every 4 m:%s" % [best_x, best_z, best_s, line])
			line = ""
			for k in range(-8, 9):
				line += " %.1f" % gen.get_base_height(best_x, best_z + k * 4.0)
			print("TRANSECT z-axis:%s" % line)
			print("LAND " + _land(gen))
			print("RESULT: done")
			return true
	return false
