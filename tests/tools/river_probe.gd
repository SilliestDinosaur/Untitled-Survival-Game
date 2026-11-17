extends SceneTree
## River probe (diagnostic): godot --headless --path . -s tests/tools/river_probe.gd
## Cuts across the deepest river channel and prints the ground, the carved depth and the water level.

var _main: Node
var _game: Node
var _f := 0
var _step := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("River Probe", 629946553)
			if _main.state == _main.State.PLAYING:
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var h: Dictionary = gen.hydro
			var n: int = h.n
			var cell: float = 8.0
			var best := 0
			var best_c := -1.0
			for k in n * n:
				if h.channel[k] > best_c:
					best_c = h.channel[k]
					best = k
			var ci := best % n
			var cj := best / n
			print("DEEPEST channel cell (%d, %d) at (%.0f, %.0f): channel %.2f, relaxed depth %.2f" % [ci, cj, ci * cell, cj * cell, h.channel[best], h.depth[best]])
			# Cross-section along x through that cell: ground, carved depth field, channel, water level.
			for dx in range(-8, 9):
				var i := clampi(ci + dx, 0, n - 1)
				var k := cj * n + i
				var x := i * cell
				var z := cj * cell
				var ground: float = gen.get_height(x, z)
				var base: float = gen.get_base_height(x, z)
				print("  x %6.0f  ground %6.2f  base %6.2f  relaxed depth %5.2f  channel %5.2f  water level %6.2f" % [x, ground, base, h.depth[k], h.channel[k], base + h.channel[k] * 0.35])
			gen._hydro_ready = false
			for dx in [-16, -8, 0, 8, 16]:
				var i2 := clampi(ci + dx, 0, n - 1)
				var x2 := i2 * cell
				print("  UNCARVED x %6.0f  base without rivers %6.2f  with rivers %6.2f" % [x2, gen.get_base_height(x2, cj * cell), 0.0])
			gen._hydro_ready = true
			# Overall: how much of the river water is above the ground next to it?
			print("RESULT: done")
			return true
	return false
