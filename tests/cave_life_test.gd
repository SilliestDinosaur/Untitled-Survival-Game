extends SceneTree
## Cave contents test: godot --headless --path . -s tests/cave_life_test.gd
## The caves are dressed: ore, crystals and stalagmites are real, mineable resources in their chunks; a cave beast
## turns up in its lair when someone comes near, and walks the cave floor without leaving its lair; bats burst off a
## roost when you come close; the camps' crates are lootable chests.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _C: GDScript
var _lair := Vector3.ZERO
var _beast: Node = null


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Cave Life", 6161)
			if _main.state == _main.State.PLAYING:
				_C = load("res://scripts/world/caves.gd")
				_step = 1
		1:
			var plan: Dictionary = _game.world_gen.caves
			for k in ["ores", "stalagmites", "stalactites", "pillars", "pools", "moss", "worms", "camps", "lairs", "roosts"]:
				_check(plan.has(k) and plan[k].size() > 0, "the caves have %s (%d)" % [k, plan.get(k, []).size()])
			# Every deposit sits on a cave floor: in the tunnel just above it, in rock just under it.
			var bad := 0
			for o: Array in plan.ores:
				var p: Vector3 = o[0]
				if _C.void_distance(plan, p + Vector3(0, 0.3, 0)) > 0.0 or _C.void_distance(plan, p - Vector3(0, 0.3, 0)) < 0.0:
					bad += 1
			_check(bad <= plan.ores.size() / 10, "ore sits on the cave floors (%d of %d off)" % [bad, plan.ores.size()])
			_check(plan.ores.any(func(o: Array) -> bool: return o[1] == "ore_t3"), "deep rock holds the third metal")
			# A deposit is a resource in its chunk, with the id the plan gives it.
			var o0: Vector3 = plan.ores[0][0]
			var coord := Vector2i(floori(o0.x / _game.CHUNK_SIZE), floori(o0.z / _game.CHUNK_SIZE))
			var res: Array = load("res://scripts/world/chunk_generator.gd")._place_resources(coord, Vector3(coord.x * _game.CHUNK_SIZE, 0, coord.y * _game.CHUNK_SIZE), _game.world_gen, _game.flora, {})
			var want := "%d_%d_c0" % [coord.x, coord.y]
			var found: Array = res.filter(func(r: Dictionary) -> bool: return r.id == want)
			_check(found.size() == 1, "the first deposit is a resource in its chunk (%s)" % want)
			if found.size() == 1:
				_check(float(found[0].get("sky", 1.0)) < 1.0, "it's drawn in the cave's dark (sky %.2f)" % float(found[0].get("sky", 1.0)))
			# Go to a lair.
			_lair = plan.lairs[0]
			_main.player.global_position = _lair + Vector3(0, 1.0, 0)
			_main.player.set_physics_process(false)
			_step = 2
			_f = 0
		2:
			if _f == 120:
				var wm: Node = _main.get_node("Wildlife")
				for a in wm.get_animals():
					if is_instance_valid(a) and a.species.habitat == "cave":
						_beast = a
				_check(_beast != null, "a cave beast is in the lair when someone comes near")
				if _beast == null:
					return _finish()
				_beast.player = null
				_beast.targets = []
			if _f == 900:
				var p: Vector3 = _beast.global_position
				var plan: Dictionary = _game.world_gen.caves
				var flat := Vector2(p.x - _lair.x, p.z - _lair.z).length()
				_check(flat < 15.0, "it stays by its lair (%.1f m away)" % flat)
				_check(_C.void_distance(plan, p + Vector3(0, 0.4, 0)) < 0.0, "it's in the cave, not in the rock (%.2f)" % _C.void_distance(plan, p + Vector3(0, 0.4, 0)))
				_check(_C.void_distance(plan, p - Vector3(0, 0.4, 0)) > 0.0, "it stands on the floor, not floating (%.2f)" % _C.void_distance(plan, p - Vector3(0, 0.4, 0)))
				# Bats: stand under a roost.
				var roost: Vector3 = plan.roosts[0]
				_main.player.global_position = roost - Vector3(0, 2.0, 0)
				_game.in_cave = true
				var cam: Camera3D = _main.player.camera
				cam.global_position = roost - Vector3(0, 2.0, 0)
				_step = 3
				_f = 0
		3:
			if _f == 60:
				var bats: Node = _find(_main, "CaveBats")
				_check(bats != null and not bats._flocks.is_empty(), "bats burst off the roost when you come close")
				return _finish()
	return false


func _find(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_script() and c.get_script().get_global_name() == cls:
			return c
		var f := _find(c, cls)
		if f:
			return f
	return null


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
