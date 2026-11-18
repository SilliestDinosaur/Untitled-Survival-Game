extends SceneTree
## Inland river probe: godot --headless --path . -s tests/tools/river_inland.gd
## The river probe's deepest channel is usually the estuary at the coast. This one picks the deepest
## channel cell at least INLAND_MIN metres above the sea and prints a cross-section through it.
## Environment: SEED (default 629946553), INLAND_MIN (default 8).

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
			var river_cells := 0
			var inland_river := 0
			var floating := 0   # water above the bank next to it, by more than 0.5 m
			for k in n * n:
				if h.channel[k] > 0.0:
					river_cells += 1
				var x := (k % n) * cell
				var z := (k / n) * cell
				var g: float = gen.get_height(x, z)
				if h.channel[k] > 0.0 and g >= inland:
					inland_river += 1
				if h.channel[k] > best_c and g >= inland:
					best_c = h.channel[k]
					best = k
			print("RIVER CELLS %d, inland (ground >= %.0f m) %d" % [river_cells, inland, inland_river])
			if best < 0:
				print("RESULT: no inland river found")
				return true
			var ci := best % n
			var cj := best / n
			print("DEEPEST INLAND channel cell (%d, %d) at (%.0f, %.0f): channel %.2f, ground %.2f" % [ci, cj, ci * cell, cj * cell, h.channel[best], gen.get_height(ci * cell, cj * cell)])
			for dz in range(-6, 7):
				var j := clampi(cj + dz, 0, n - 1)
				var x := ci * cell
				var z := j * cell
				var ground: float = gen.get_height(x, z)
				var k := j * n + ci
				print("  z %6.0f  ground %6.2f  channel %5.2f  water %6.2f  %s" % [z, ground, h.channel[k], gen.get_base_height(x, z) + h.channel[k] * 0.35, "WATER" if h.channel[k] > 0.0 else ""])
			# Water sitting well above the ground beside it is what a floating river looks like.
			for k in n * n:
				if h.channel[k] > 0.0:
					var x2 := (k % n) * cell
					var z2 := (k / n) * cell
					var surface: float = gen.get_base_height(x2, z2) + h.channel[k] * 0.35
					if surface - gen.get_height(x2, z2) > 0.5:
						floating += 1
			print("WATER ABOVE GROUND by more than 0.5 m: %d cells" % floating)
			# The real water: the builder's own rule (a quad is wet where every corner's base ground is under the level).
			var lvl: PackedFloat32Array = h.level
			var wet_quads := 0
			var wet_inland := 0
			var floating_seen := 0
			var carved_wet_quads := 0
			var worst := 0.0
			for j in n - 1:
				for i in n - 1:
					var ks := [j * n + i, j * n + i + 1, (j + 1) * n + i + 1, (j + 1) * n + i]
					var is_wet := true
					var low := INF
					for kk: int in ks:
						low = minf(low, lvl[kk])
						if gen.get_base_height((kk % n) * cell, (kk / n) * cell) >= lvl[kk] - 0.02:
							is_wet = false
					if is_wet and low < INF:
						wet_quads += 1
						var g_here: float = gen.get_base_height((ks[0] % n) * cell, (ks[0] / n) * cell)
						if g_here >= inland:
							wet_inland += 1
						worst = maxf(worst, low - g_here)
						# What you can see: the water surface against the carved bed under the quad's middle.
						var mx := (i + 0.5) * cell
						var mz := (j + 0.5) * cell
						var carved: float = gen.get_height(mx, mz)
						if low - carved > 0.5:
							floating_seen += 1
						carved_wet_quads += 1
			print("BUILT WATER: %d wet quads, %d over inland ground; highest water above the ground under it %.2f m" % [wet_quads, wet_inland, worst])
			print("SEEN FROM ABOVE: %d of %d wet quads stand more than 0.5 m above the carved bed under them" % [floating_seen, carved_wet_quads])
			var rivers_node := _find_named(root, "Rivers")
			if rivers_node == null:
				print("NO RIVERS MESH IN THE SCENE")
			else:
				var aabb: AABB = rivers_node.get_aabb()
				print("RIVERS MESH: %d vertices, bounds %s" % [rivers_node.mesh.get_surface_count(), str(aabb)])
				var cell_pos := Vector3(ci * cell, lvl[cj * n + ci], cj * cell)
				print("  deepest cell at %s; mesh contains it in xz: %s" % [str(cell_pos), str(aabb.grow(1.0).has_point(cell_pos))])
			var ck := cj * n + ci
			print("AT THE DEEPEST INLAND CELL: level %.2f, base ground %.2f, carved ground %.2f" % [lvl[ck], gen.get_base_height(ci * cell, cj * cell), gen.get_height(ci * cell, cj * cell)])
			print("RESULT: done")
			return true
	return false


func _find_named(node: Node, name_wanted: String) -> Node:
	if node.name == name_wanted:
		return node
	for c in node.get_children():
		var found := _find_named(c, name_wanted)
		if found:
			return found
	return null
