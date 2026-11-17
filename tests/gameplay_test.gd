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
var _saved_items := {}
var _saved_pos := Vector3.ZERO
var _saved_removed := 0
var _save_id := ""
var _berries_before := 0
var _dropped := 0
var _skip: Array = []


# Game classes are loaded at runtime: test scripts compile before autoloads exist.
var _GA: GDScript
var _IDB: GDScript
var _FL: GDScript


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_IDB = load("res://scripts/items/item_db.gd")
	_FL = load("res://scripts/world/flora_library.gd")
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
				_main.create_world("Test World", 629946553)
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
			if _aim_at_kind(["rock"]):
				_next("mine")
		"mine":
			if _swing_until_removed():
				_check(_player.inventory.count("stone") >= 10, "stone from a rock: %d" % _player.inventory.count("stone"))
				_check(_player.inventory.slots[0].get("dur", 0) < _IDB.tool_stats("rock").durability, "the rock wears down: %d" % _player.inventory.slots[0].get("dur", 0))
				_next("berry")
		"berry":
			if _aim_at_kind(["berry"]):
				_berries_before = _player.inventory.count("berries")
				Input.action_press("interact")
				_next("berry_wait")
		"berry_wait":
			if _player.inventory.count("berries") > _berries_before or _frames > 3000:
				Input.action_release("interact")
				_check(_player.inventory.count("berries") > _berries_before, "picked berries with Interact: %d" % _player.inventory.count("berries"))
				_check(not _target.res.get("removed", false), "the berry bush is still there")
				_next("ore")
		"ore":
			if _aim_at_kind(["ore_t2"]):
				_next("ore_blocked")
			elif _frames > 5:
				print("   (no ore_t2 nearby, skipping tier checks)")
				_next("pebbles")
		"ore_blocked":
			# A rock can't mine tier-2 ore; a stone pickaxe can.
			Input.action_press("attack")
			if _frames > 120:
				Input.action_release("attack")
				_check(float(_target.res.hp) >= float(_FL.KINDS.ore_t2.hp), "rock can't mine %s" % _IDB.display_name("ore_t2"))
				_player.inventory.add("pickaxe_t1", 1)
				_player.inventory.select(_player.inventory.slots.find(_player.inventory.slots.filter(func(x): return x.get("id", "") == "pickaxe_t1")[0]))
				_next("ore_mine")
		"ore_mine":
			if _swing_until_removed():
				_check(_player.inventory.count("ore_t2") > 0, "mined %s with a stone pickaxe: %d" % [_IDB.display_name("ore_t2"), _player.inventory.count("ore_t2")])
				_player.inventory.select(0)
				_next("pebbles")
		"pebbles":
			if _aim_at_kind(["pebbles"]):
				Input.action_press("interact")
				_next("pebbles_wait")
			elif _frames > 5:
				_next("eat")
		"pebbles_wait":
			# If something blocks the view of this pile, try the next nearest one.
			if _frames % 40 == 39 and not _target.res.get("removed", false) and _player.looking_at.get("resource", {}) != _target.res:
				_skip.append(_target.res.id)
				_aim_at_kind(["pebbles"])
			if _target.res.get("removed", false) or _frames > 3000:
				Input.action_release("interact")
				_check(_target.res.get("removed", false), "picked up loose stones (looking at %s)" % _player.looking_at.get("name", "nothing"))
				_next("drop")
		"drop":
			# Drop the stone and pick it back up.
			var stone_before: int = _player.inventory.count("stone")
			var slot := -1
			for i in 32:
				if _player.inventory.slots[i].get("id", "") == "stone":
					slot = i
			_player.drop_slot(slot, true)
			_check(_player.inventory.count("stone") < stone_before and _game.pickups.size() > 0, "dropped stone into the world")
			_dropped = stone_before
			_next("pickup")
		"pickup":
			if _frames < 30:
				return false
			var pid: String = _game.pickups.keys()[0]
			_GA.pick_up(_game.LOCAL_PLAYER, pid)
			_check(_player.inventory.count("stone") == _dropped and _game.pickups.is_empty(), "picked the stone back up: %d" % _player.inventory.count("stone"))
			_next("eat")
		"eat":
			_player.inventory.add("berries", 3)
			_player.stats.hunger = 50.0
			for i in 8:
				if _player.inventory.slots[i].get("id", "") == "berries":
					_player.inventory.select(i)
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
			elif _frames > 8000:
				_check(false, "animal never died (hp %.1f)" % _animal.hp)
				return _finish()
		"harvest":
			if is_instance_valid(_animal):
				_player.get_node("Head").look_at(_animal.global_position + Vector3.UP * 0.3, Vector3.UP)
			Input.action_release("attack")
			Input.action_press("interact")
			if not is_instance_valid(_animal) or _animal.carcass_hp <= 0.0 or _frames > 8000:
				Input.action_release("interact")
				_check(_player.inventory.count("raw_meat") > 0, "raw meat from carcass: %d" % _player.inventory.count("raw_meat"))
				_check(_player.inventory.count("hide") > 0, "hide from carcass: %d" % _player.inventory.count("hide"))
				_next("craft")
		"craft":
			var inv = _player.inventory
			for e in [["fiber", 20], ["sticks", 20], ["stone", 20], ["wood", 20], ["resin", 3], ["raw_meat", 2]]:
				inv.add(e[0], e[1], true)
			var rope := _recipe("rope")
			var res: Dictionary = _GA.craft(1, rope, _player.global_position)
			_check(res.ok and inv.count("rope") >= 1, "crafted rope by hand")
			var cook: Dictionary = _GA.craft(1, _recipe("cooked_meat"), _player.global_position)
			_check(not cook.ok, "can't cook without a campfire (%s)" % cook.get("reason", ""))
			_check(_GA.craft(1, _recipe("campfire"), _player.global_position).ok and inv.count("campfire") == 1, "crafted a campfire")
			var slot := -1
			for i in inv.slots.size():
				if inv.slots[i].get("id", "") == "campfire":
					slot = i
			var at: Vector3 = _player.global_position + Vector3(2.0, 0, 0)
			at.y = _game.world_gen.get_height(at.x, at.z)
			var placed: Dictionary = _GA.place_structure(1, slot, at, 0.0)
			if not placed.ok:   # odd terrain right here: try a few spots around the player
				for a in 8:
					at = _player.global_position + Vector3(cos(a * 0.8), 0, sin(a * 0.8)) * 2.5
					at.y = _game.world_gen.get_height(at.x, at.z)
					placed = _GA.place_structure(1, slot, at, 0.0)
					if placed.ok:
						break
			_check(placed.ok and _game.structures.size() == 1, "placed the campfire (%s)" % placed.get("reason", "ok"))
			cook = _GA.craft(1, _recipe("cooked_meat"), _player.global_position, 2)
			_check(cook.ok and inv.count("cooked_meat") == 2, "cooked meat at the campfire: %d" % inv.count("cooked_meat"))
			_next("save")
		"save":
			# Save, go back to the title, load it again and check everything came back.
			_saved_items = _player.inventory.to_data()
			_saved_pos = _player.global_position
			_saved_removed = _game.removed_resources.size()
			_save_id = _game.save_id
			_main.save_now()
			_main._to_title()
			_next("reload")
		"reload":
			if _frames == 10:
				_check(_game.save_id == "", "back on the title screen")
				_main.load_world(_save_id)
			elif _frames > 10 and _main.state == _main.State.PLAYING:
				_check(_player.inventory.to_data() == _saved_items, "inventory restored (%d stone, %d wood)" % [_player.inventory.count("stone"), _player.inventory.count("wood")])
				_check(_game.structures.size() == 1, "campfire still there after reload")
				_check(_player.global_position.distance_to(_saved_pos) < 1.5, "position restored (%.2f m off)" % _player.global_position.distance_to(_saved_pos))
				_check(_game.removed_resources.size() == _saved_removed and _saved_removed > 0, "gathered resources stay gone: %d" % _game.removed_resources.size())
				var listed := false
				for s in SaveManager.list_saves():
					if s.id == _save_id:
						listed = true
				_check(listed, "save shows up in the world list")
				SaveManager.delete(_save_id)
				return _finish()
			elif _frames > 3000:
				_check(false, "reload never finished")
				return _finish()
	return false


func _recipe(out: String) -> String:
	for rc: Dictionary in load("res://scripts/items/recipes.gd").all():
		if rc.out == out:
			return rc.id
	return ""


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
			if r.kind in kinds and not r.get("removed", false) and not _skip.has(r.id):
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
	var aim_y := 1.0 if best.kind in ["oak", "pine", "birch", "autumn_oak"] else (0.5 if best.kind in ["berry", "bush"] else (0.08 if best.kind == "pebbles" else 0.3))
	_player.get_node("Head").look_at(o + Vector3.UP * aim_y, Vector3.UP)
	_target = {"res": best, "chunk": best_chunk}
	return true


func _swing_until_removed() -> bool:
	Input.action_press("attack")
	if _target.res.get("removed", false):
		Input.action_release("attack")
		return true
	if _frames > 9000:
		Input.action_release("attack")
		_check(false, "%s was never gathered (hp %.1f, looking at %s)" % [_target.res.kind, _target.res.hp, _player.looking_at.get("name", "nothing")])
		return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	var summary := {}
	for sl in _player.inventory.slots:
		if not sl.is_empty():
			summary[sl.id] = summary.get(sl.id, 0) + int(sl.count)
	print("inventory: ", summary)
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
