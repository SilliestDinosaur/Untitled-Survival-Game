extends SceneTree
## Inland river probe: godot --headless --path . -s tests/tools/river_inland.gd
## Picks the deepest channel cell at least INLAND_MIN metres above the sea (the river probe's pick is
## usually the estuary), prints a cross-section through it, and checks the water that is built there:
## every channel cell should hold water, and the water should not stand above the land beside it.
## Environment: SEED (default 629946553), INLAND_MIN (default 8).

var _main: Node
var _game: Node
var _f := 0
var _step := 0
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
				var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 629946553
				_main.create_world("Inland River Probe", seed_value)
			if _main.state == _main.State.PLAYING:
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var h: Dictionary = gen.hydro
			var n: int = h.n
			var cell: float = 8.0
			var inland := float(OS.get_environment("INLAND_MIN")) if OS.get_environment("INLAND_MIN") != "" else 8.0
			var best := -1
			var best_c := -1.0
			var channel_cells := 0
			var dry_channel := 0
			var inland_channel := 0
			var inland_dry := 0
			for k in n * n:
				var x := (k % n) * cell
				var z := (k / n) * cell
				var g: float = gen.get_height(x, z)
				if h.channel[k] > 0.0:
					channel_cells += 1
					if h.water[k] <= 0.0 and h.lake[k] <= 0.0:
						dry_channel += 1
					if g >= inland:
						inland_channel += 1
						if h.water[k] <= 0.0 and h.lake[k] <= 0.0:
							inland_dry += 1
				if h.channel[k] > best_c and g >= inland:
					best_c = h.channel[k]
					best = k
			print("CHANNEL CELLS %d, dry %d; inland channel %d, dry %d" % [channel_cells, dry_channel, inland_channel, inland_dry])
			if best < 0:
				print("RESULT: no inland river found")
				return true
			var ci := best % n
			var cj := best / n
			print("DEEPEST INLAND channel cell (%d, %d) at (%.0f, %.0f): channel %.2f, bed %.2f, water depth %.2f" % [ci, cj, ci * cell, cj * cell, h.channel[best], gen.get_base_height(ci * cell, cj * cell), h.water[best]])
			for dz in range(-6, 7):
				var j := clampi(cj + dz, 0, n - 1)
				var k := j * n + ci
				var x := ci * cell
				var z := j * cell
				var surface: float = gen.get_base_height(x, z) + h.water[k] if h.water[k] > 0.0 else h.lake[k]
				print("  z %6.0f  ground %6.2f  surface %6.2f  %s" % [z, gen.get_height(x, z), surface, "WATER" if surface > 0.0 else ""])
			# Dry ground under the water, the same check the river test makes (Hydrology.flooded). A river's own
			# surface sits above its bed by design; what matters is water standing over land beside it.
			var fl: Dictionary = _Hydro.flooded(gen, 0.1)
			print("DRY GROUND UNDER WATER: %d points more than 0.1 m under a neighbour's surface, worst %.2f m" % [fl.count, fl.worst])
			if fl.at >= 0:
				print("  worst at (%.0f, %.0f)" % [(fl.at % n) * cell, (fl.at / n) * cell])
			print("RESULT: done")
			return true
	return false
