extends SceneTree
## Collision probe (diagnostic): godot --headless --path . -s tests/collision_probe.gd
## Drops rays onto the loaded terrain around the first cave mouth and compares the surface the
## physics returns with the true ground height: holes, and places where the collider sits off the ground.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _center := Vector3.ZERO


var _CavesS: GDScript


func _initialize() -> void:
	_CavesS = load("res://scripts/world/caves.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Collision Probe", 6161)
			if _main.state == _main.State.PLAYING:
				var c := Vector2(float(OS.get_environment("CX")) if OS.get_environment("CX") != "" else 852.0, float(OS.get_environment("CZ")) if OS.get_environment("CZ") != "" else 1644.0)
				_center = Vector3(c.x, _game.world_gen.get_height(c.x, c.y) + 2.0, c.y)
				_main.player.set_physics_process(false)
				_main.player.global_position = _center
				_f = 0
				_step = 1
		1:
			if _f >= 400:   # let the chunks around the mouth stream in and build their colliders
				_step = 2
		2:
			var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
			var gen: Object = _game.world_gen
			var holes := 0
			var unloaded := 0
			var off := 0
			var worst := 0.0
			var worst_at := Vector3.ZERO
			var samples := 0
			var span := float(OS.get_environment("SPAN")) if OS.get_environment("SPAN") != "" else 60.0
			var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 2.0
			var n := int(span / step)
			for j in range(-n, n + 1):
				for i in range(-n, n + 1):
					var x := _center.x + i * step
					var z := _center.z + j * step
					var g: float = gen.get_height(x, z)
					var q := PhysicsRayQueryParameters3D.create(Vector3(x, g + 40.0, z), Vector3(x, g - 40.0, z), 1)
					var hit: Dictionary = space.intersect_ray(q)
					samples += 1
					var coord := Vector2i(floori(x / _game.CHUNK_SIZE), floori(z / _game.CHUNK_SIZE))
					var loaded: bool = _main.world._chunks.has(coord)
					var in_cave: bool = _CavesS.void_distance(gen.caves, Vector3(x, g - 1.0, z)) < 2.5
					if hit.is_empty():
						if loaded:
							holes += 1
							if holes <= 30:
								print("  HOLE at (%.1f, %.1f) ground %.2f chunk %s loaded %s cave %s" % [x, z, g, coord, loaded, in_cave])
						else:
							unloaded += 1
						continue
					if in_cave:
						continue
					if String(hit.collider.name) != "TerrainBody":
						continue   # a tree or rock standing on the ground, not the ground itself
					var dev: float = absf(hit.position.y - g)
					if dev > 0.25:
						off += 1
						if dev > 1.0 and off < 400:
							print("  OFF at (%.1f, %.1f) ground %.2f hit %.2f  dev %.2f  void %.2f" % [x, z, g, hit.position.y, dev, _CavesS.void_distance(gen.caves, Vector3(x, hit.position.y, z))])
					if dev > worst:
						worst = dev
						worst_at = Vector3(x, hit.position.y, z)
			print("COLLISION samples %d  holes in loaded chunks %d  not loaded %d  off by > 0.25 m: %d  worst %.2f m at %s" % [samples, holes, unloaded, off, worst, worst_at])
			print("RESULT: done")
			return true
	return false
