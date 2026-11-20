extends SceneTree
## Voxel terrain test: godot --headless --path . -s tests/voxel_test.gd
## Checks the solid ground near caves: the surface matches the ground, and a patch of neighbouring
## cave chunks is watertight (no holes between chunks, nothing open inside).

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _ChunkScript: GDScript
var _VoxelScript: GDScript
var _CavesScript: GDScript


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Voxel Test", 8181)
			if _main.state == _main.State.PLAYING:
				_ChunkScript = load("res://scripts/world/chunk_generator.gd")
				_VoxelScript = load("res://scripts/world/voxel_terrain.gd")
				_CavesScript = load("res://scripts/world/caves.gd")
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var plan: Dictionary = gen.caves
			var root_p: Vector3 = plan.nodes[plan.roots[0]].p
			# A centre chunk whose eight neighbours are all cave ground too, found from the cave plan.
			var cx := -1
			var cz := -1
			for nd: Dictionary in plan.nodes:
				var rp: Vector3 = nd.p
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						if cx >= 0:
							break
						var c := Vector2i(floori(rp.x / _game.CHUNK_SIZE) + dx, floori(rp.z / _game.CHUNK_SIZE) + dz)
						var all_cave := true
						for ez in range(-1, 2):
							for ex in range(-1, 2):
								var origin := Vector3((c.x + ex) * _game.CHUNK_SIZE, 0.0, (c.y + ez) * _game.CHUNK_SIZE)
								if _CavesScript.segments_near(plan, origin, _game.CHUNK_SIZE).is_empty():
									all_cave = false
						if all_cave:
							cx = c.x
							cz = c.y
				if cx >= 0:
					break
			_check(cx >= 0, "there is a cave patch of nine chunks to test (found at %d, %d)" % [cx, cz])
			# Patch: 3 x 3 chunks around the mouth, all built as cave ground.
			var tris := {}
			var open := 0
			var total := 0
			var voxel_chunks := 0
			var bad_chunks := 0
			var max_dev := 0.0
			var edge_count := {}
			var patch_min := Vector2(INF, INF)
			var patch_max := Vector2(-INF, -INF)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var coord := Vector2i(cx + dx, cz + dz)
					var job := {"coord": coord, "tier": 0, "gen": gen, "flora": _game.flora, "removed": {}, "grass_density": 0.0}
					_ChunkScript.generate(job)
					var result: Dictionary = job.result
					if result.has("collision_faces") and not result.collision_faces.is_empty():
						voxel_chunks += 1
					var verts: PackedVector3Array = result.mesh[0]
					var idx: PackedInt32Array = result.mesh[3]
					var origin := Vector3(coord.x * _game.CHUNK_SIZE, 0.0, coord.y * _game.CHUNK_SIZE)
					patch_min = Vector2(minf(patch_min.x, origin.x), minf(patch_min.y, origin.z))
					patch_max = Vector2(maxf(patch_max.x, origin.x + _game.CHUNK_SIZE), maxf(patch_max.y, origin.z + _game.CHUNK_SIZE))
					# Surface accuracy: each vertex that is on the ground should sit on the ground height.
					# Surface accuracy, away from caves: the ground surface should match the ground height.
					for v: Vector3 in verts:
						var w := v + origin
						if _CavesScript.void_distance(plan, w) < 2.5:
							continue
						var g: float = gen.get_height(w.x, w.z)
						max_dev = maxf(max_dev, absf(w.y - g))
					# Edges by world position, to join chunks that share a border.
					var t := 0
					while t + 2 < idx.size():
						var keys := []
						for k in 3:
							var w: Vector3 = verts[idx[t + k]] + origin
							keys.append(Vector3(snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001)))
						for e in 3:
							var a: Vector3 = keys[e]
							var b: Vector3 = keys[(e + 1) % 3]
							if a == b:
								continue
							var ek := [a, b] if a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))) else [b, a]
							var key := str(ek[0]) + "|" + str(ek[1])
							edge_count[key] = edge_count.get(key, 0) + 1
						t += 3
			# An edge used an odd number of times is a hole, unless it's on the outer edge of the patch
			# (the neighbours beyond it aren't part of this test).
			var inner_open := 0
			var near_edge := 0
			for key: String in edge_count:
				total += 1
				if edge_count[key] % 2 == 1:
					var parts := key.split("|")
					var a := _parse(parts[0])
					var b := _parse(parts[1])
					var da := minf(minf(a.x - patch_min.x, patch_max.x - a.x), minf(a.z - patch_min.y, patch_max.y - a.z))
					var db := minf(minf(b.x - patch_min.x, patch_max.x - b.x), minf(b.z - patch_min.y, patch_max.y - b.z))
					if minf(da, db) < 1.5:
						near_edge += 1
					else:
						inner_open += 1
						if inner_open <= 12:
							print("  OPEN %s -> %s" % [a, b])
			open = inner_open
			print("PATCH chunks voxel %d/9  edges %d  open inside %d  open at patch edge %d  max surface deviation %.3f m" % [voxel_chunks, total, open, near_edge, max_dev])
			_check(voxel_chunks == 9, "all nine chunks around the mouth are solid ground")
			_check(open == 0, "no holes between the cave chunks (%d open edges)" % open)
			_check(max_dev < 1.25, "the solid ground sits on the ground height away from caves (worst %.2f m on a cliff)" % max_dev)
			return _finish()
	return false


func _parse(s: String) -> Vector3:
	var t := s.trim_prefix("(").trim_suffix(")").split(", ")
	return Vector3(float(t[0]), float(t[1]), float(t[2]))


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
