extends SceneTree
## Headless gameplay test: godot --headless --path . -s tests/gameplay_test.gd
## Chops a tree, mines a rock, eats, checks wildlife spawns, hunts and harvests an animal.

var _main: Node
var _player: CharacterBody3D
var _world: Node
var _game: Node
var _phase := "load"
var _frames := 0
var _target := {}
var _swings := 0
var _animal: Node = null
var _fails: Array[String] = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_delta: float) -> bool:
	_frames += 1
	_player = _main.get_node("Player")
	_world = _main.get_node("World")
	match _phase:
		"load":
			if _frames == 5:
				_main._start_loading()
			elif _main.state == _main.State.PLAYING:
				_next("tree")
		"tree":
			if _aim_at_kind(["oak", "pine", "birch", "autumn_oak"]):
				_next("chop")
		"chop":
			if _swing_until_removed():
				_check(_player.inventory.count("wood") >= 20, "wood from a tree: %d" % _player.inventory.count("wood"))
				_next("rock")
		"rock":
			if _aim_at_kind(["rock", "ore"]):
				_next("mine")
		"mine":
			if _swing_until_removed():
				_check(_player.inventory.count("stone") >= 10, "stone from a rock: %d" % _player.inventory.count("stone"))
				_next("eat")
		"eat":
			_player.inventory.add("berries", 3)
			_player.stats.hunger = 50.0
			_player.inventory.select(_player.inventory.hotbar.find("berries"))
			Input.action_press("attack")
			_next("eat_wait")
		"eat_wait":
			if _player.inventory.count("berries") < 3 and _player.stats.hunger > 50.0 or _frames > 3000:
				Input.action_release("attack")
				_check(_player.stats.hunger > 50.0, "eating berries raised food to %.1f" % _player.stats.hunger)
				_player.inventory.select(0)
				_next("wildlife")
		"wildlife":
			var wl: Node = _main.get_node("Wildlife")
			if wl.get_animals().size() > 0 or _frames > 400:
				_check(wl.get_animals().size() > 0, "animals spawned: %d" % wl.get_animals().size())
				_check(_game.fauna.species.size() >= 8, "species generated: %d" % _game.fauna.species.size())
				for s in _game.fauna.species:
					print("   species: %-22s %-17s size %.2f" % [s.name, s.label, s.size])
				if wl.get_animals().size() > 0:
					_animal = wl.get_animals()[0]
					_next("hunt")
				else:
					return _finish()
		"hunt":
			# Put the animal right in front of the player and hit it until it dies.
			if not is_instance_valid(_animal):
				return _finish()
			_animal.set_physics_process(false)
			var front := _player.global_position - _player.global_transform.basis.z * 2.0
			_animal.global_position = Vector3(front.x, _player.global_position.y, front.z)
			_player.get_node("Head").look_at(_animal.global_position + Vector3.UP * _animal.species.leg_len, Vector3.UP)
			Input.action_press("attack")
			if _animal.dead:
				_next("harvest")
			elif _frames > 1200:
				_check(false, "animal never died (hp %.1f)" % _animal.hp)
				return _finish()
		"harvest":
			Input.action_press("attack")
			if not is_instance_valid(_animal) or _animal.carcass_hp <= 0.0 or _frames > 1500:
				Input.action_release("attack")
				_check(_player.inventory.count("raw_meat") > 0, "raw meat from carcass: %d" % _player.inventory.count("raw_meat"))
				_check(_player.inventory.count("hide") > 0, "hide from carcass: %d" % _player.inventory.count("hide"))
				return _finish()
	return false


func _next(p: String) -> void:
	_phase = p
	_frames = 0
	_swings = 0


## Teleport next to the nearest resource of these kinds and look at it.
func _aim_at_kind(kinds: Array) -> bool:
	var best = null
	var best_chunk = null
	var bd := 1e9
	for c in _world.get_children():
		if not ("resources" in c) or c.tier != 0:
			continue
		for r in c.resources:
			if r.kind in kinds and not r.get("removed", false):
				var d: float = r.transform.origin.distance_to(_player.global_position)
				if d < bd:
					bd = d
					best = r
					best_chunk = c
	if best == null:
		return false
	var o: Vector3 = best.transform.origin
	var from := o + Vector3(2.0, 0, 0)
	from.y = _game.world_gen.get_height(from.x, from.z)
	_player.global_position = from
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.look_at(Vector3(o.x, from.y, o.z), Vector3.UP)
	_player.rotation.x = 0
	var aim_y := 1.0 if best.kind in ["oak", "pine", "birch", "autumn_oak"] else 0.3
	_player.get_node("Head").look_at(o + Vector3.UP * aim_y, Vector3.UP)
	_target = {"res": best, "chunk": best_chunk}
	return true


func _swing_until_removed() -> bool:
	Input.action_press("attack")
	if _target.res.get("removed", false):
		Input.action_release("attack")
		return true
	if _frames > 900:
		Input.action_release("attack")
		_check(false, "%s was never gathered (hp %.1f, looking at %s)" % [_target.res.kind, _target.res.hp, _player.looking_at.get("name", "nothing")])
		return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("inventory: ", _player.inventory.counts)
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
