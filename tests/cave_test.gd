extends SceneTree
## Cave test: godot --headless --path . -s tests/cave_test.gd
## Caves are cut into the ground: the plan has entrances and tunnels under the surface, the chunk
## at an entrance is built as solid ground with the tunnel walls in it, and standing in a tunnel
## counts as being in a cave.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _CavesScript: GDScript      ## loaded at run time: naming project classes early breaks the autoloads
var _ChunkScript: GDScript
var root_pos := Vector3.ZERO


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Cave Test", 6161)
			if _main.state == _main.State.PLAYING:
				_CavesScript = load("res://scripts/world/caves.gd")
				_ChunkScript = load("res://scripts/world/chunk_generator.gd")
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var plan: Dictionary = gen.caves
			_check(plan.has("roots") and plan.roots.size() >= 1, "the island has cave entrances (%d)" % plan.roots.size())
			_check(plan.roots.size() == plan.entrances.size(), "every entrance has a root in the plan")
			_check(plan.segs.size() >= 60, "the caves have tunnels (%d pieces)" % plan.segs.size())
			var root: Vector3 = plan.nodes[plan.roots[0]].p
			var ground: float = gen.get_base_height(root.x, root.z)
			_check(root.y < ground and root.y > ground - 2.0, "the mouth is just under the slope (root %.1f, ground %.1f)" % [root.y, ground])
			var inside: float = _CavesScript.void_distance(plan, root + Vector3(0, 0.2, 0))
			_check(inside < 0.0, "the mouth is a void in the ground (%.2f)" % inside)
			var deep := 0
			for s: Array in plan.segs:
				if minf(s[0].y, s[1].y) < gen.get_base_height(s[0].x, s[0].z) - 4.0:
					deep += 1
			_check(deep > 0, "some tunnels run well under the ground (%d pieces)" % deep)
			# The chunk at the mouth is built as solid ground, and its mesh has the tunnel walls in it.
			print("MOUTH ", root, " ground ", ground)
			var coord := Vector2i(floori(root.x / _game.CHUNK_SIZE), floori(root.z / _game.CHUNK_SIZE))
			var job := {"coord": coord, "tier": 0, "gen": gen, "flora": _game.flora, "removed": {}, "grass_density": 0.0}
			var t0 := Time.get_ticks_msec()
			_ChunkScript.generate(job)
			print("CHUNK_MS ", Time.get_ticks_msec() - t0)
			var result: Dictionary = job.result
			_check(result.has("collision_faces") and not result.collision_faces.is_empty(), "the mouth's chunk is built as solid ground (%d faces)" % result.get("collision_faces", PackedVector3Array()).size())
			var verts: PackedVector3Array = result.mesh[0]
			var walls := 0
			var origin := Vector3(coord.x * _game.CHUNK_SIZE, 0.0, coord.y * _game.CHUNK_SIZE)
			for v: Vector3 in verts:
				var w := v + origin
				if w.y < gen.get_base_height(w.x, w.z) - 1.5 and _CavesScript.void_distance(plan, w) < 0.6:
					walls += 1
			_check(walls > 20, "the mesh has cave walls underground (%d vertices)" % walls)
			# Standing in a tunnel counts as underground; standing on the slope doesn't.
			_main.player.global_position = root + Vector3(0, 0.1, 0)
			_main._cave_check = 0.0
			_main._update_cave_state(0.0)
			_check(_game.in_cave, "standing in a tunnel is underground")
			root_pos = root
			_main.player.global_position = Vector3(root.x, ground + 6.0, root.z)
			_main._cave_check = 0.0
			_main._update_cave_state(0.0)
			_check(not _game.in_cave, "standing above ground is not underground")
			_step = 2
			_f = 0
		2:
			# Drop the player onto the mouth: the ground there must hold them (no falling through).
			if _f == 1:
				_main.player.global_position = Vector3(root_pos.x, root_pos.y + 9.0, root_pos.z)
			if _f == 300:
				var y: float = _main.player.global_position.y
				_check(y > root_pos.y - 12.0 and y < root_pos.y + 12.0, "the player lands on the ground at the mouth, not through it (y %.1f)" % y)
				return _finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
