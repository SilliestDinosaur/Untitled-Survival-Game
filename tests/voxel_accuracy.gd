extends SceneTree
## Voxel accuracy (diagnostic): godot --headless --path . -s tests/voxel_accuracy.gd
## How far the cave-ground surface sits from the ground height, away from caves.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _ChunkScript: GDScript
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
				_main.create_world("Voxel Accuracy", 6161)
			if _main.state == _main.State.PLAYING:
				_ChunkScript = load("res://scripts/world/chunk_generator.gd")
				_CavesScript = load("res://scripts/world/caves.gd")
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var plan: Dictionary = gen.caves
			var csz: int = _game.CHUNK_SIZE
			var hist := [0, 0, 0, 0, 0]   # <0.1, <0.3, <0.6, <1, >=1 metres
			var worst := 0.0
			var worst_at := Vector3.ZERO
			var n := 0
			var wrong_faces := 0
			var total_faces := 0
			# The chunks around the first cave mouth in the current plan (all of them cave ground).
			var rp: Vector3 = plan.nodes[plan.roots[0]].p
			var rc := Vector2i(floori(rp.x / csz), floori(rp.z / csz))
			var picks: Array[Vector2i] = []
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					picks.append(rc + Vector2i(dx, dz))
			for coord: Vector2i in picks:
				var job := {"coord": coord, "tier": 0, "gen": gen, "flora": _game.flora, "removed": {}, "grass_density": 0.0}
				_ChunkScript.generate(job)
				var res: Dictionary = job.result
				if not res.has("collision_faces") or res.collision_faces.is_empty():
					continue   # a heightfield chunk: measured by the terrain tests, not here
				var verts: PackedVector3Array = res.mesh[0]
				var nrms: PackedVector3Array = res.mesh[1]
				var tris: PackedInt32Array = res.mesh[3]
				var t := 0
				while t + 2 < tris.size():
					var ta: Vector3 = verts[tris[t]]
					var tb: Vector3 = verts[tris[t + 1]]
					var tc: Vector3 = verts[tris[t + 2]]
					var tn := (tb - ta).cross(tc - ta)
					var avg: Vector3 = nrms[tris[t]] + nrms[tris[t + 1]] + nrms[tris[t + 2]]
					if tn.length_squared() > 0.0 and tn.dot(avg) > 0.0:
						wrong_faces += 1
					total_faces += 1
					t += 3
				var origin := Vector3(coord.x * csz, 0.0, coord.y * csz)
				for v: Vector3 in verts:
					var w := v + origin
					if _CavesScript.void_distance(plan, w) < 2.5:
						continue
					var d := absf(w.y - gen.get_height(w.x, w.z))
					n += 1
					if d < 0.1: hist[0] += 1
					elif d < 0.3: hist[1] += 1
					elif d < 0.6: hist[2] += 1
					elif d < 1.0: hist[3] += 1
					else: hist[4] += 1
					if d > worst:
						worst = d
						worst_at = w
			print("ACCURACY surface vertices %d  <0.1m %d  <0.3m %d  <0.6m %d  <1m %d  >=1m %d  worst %.2f m at %s" % [n, hist[0], hist[1], hist[2], hist[3], hist[4], worst, worst_at])
			print("FACES %d of %d face the wrong way (culled from outside)" % [wrong_faces, total_faces])
			print("RESULT: done")
			return true
	return false
