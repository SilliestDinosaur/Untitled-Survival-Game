extends SceneTree
## Multiplayer test, guest side (see net_host_test.gd). After joining, gathering, crafting and chopping, the guest
## builds (a foundation blueprint built up with the hammer, then a door on it, opened), hunts and butchers an
## animal, and cooks the meat through the campfire minigame, all through the host.
## NET_JOIN=ip:port joins somewhere else (tests/tools/run_net_test.sh points it at a lag relay).

var _main: Node
var _game: Node
var _net: Node
var _player: Node
var _phase := "join"
var _phase_ms := 0
var _frames := 0
var _fails: Array[String] = []
var _target := {}
var _hits_sent := 0
var _hit_replies := 0
var _last_hit := {}
var _wood := 0
var _structures_before := 0
var _replies := 0
var _GA: GDScript
var _build_id := ""        ## the piece being built up with the hammer
var _after_build := ""     ## the phase after it's built
var _foundation := Vector3.ZERO
var _door_id := ""
var _chest_id := ""
var _stone := 0
var _back := Vector3.ZERO
var _animal: Node
var _meat := 0
var _cooked := 0
var _laid := {}            ## the host's answer to the last blueprint


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")
	_net = root.get_node("Net")
	_player = _main.get_node("Player")
	root.get_node("Settings").player_name = "Test Guest"
	_GA = load("res://scripts/core/game_actions.gd")


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		"join":
			if _frames == 60:
				var to := OS.get_environment("NET_JOIN")
				_check(_net.join(to if to != "" else "127.0.0.1:%d" % _net.PORT), "connecting to %s" % (to if to != "" else "the host"))
			if _main.state == _main.State.PLAYING:
				_check(_game.world_seed == 424242, "got the host's world (seed %d)" % _game.world_seed)
				print("  joined by route: ", _net.join_route)
				if OS.get_environment("NET_FORCE_RELAY") != "":
					_check(_net.join_route == "relay", "came in through the meeting server's relay")
				_check(_player.inventory.count("rock") == 1, "starts with a rock from the host")
				_check(_net.avatars.has(1), "host's avatar exists")
				_next("give")
			elif _waited() > 120.0:
				_check(false, "never finished joining")
				return _finish()
		"give":
			for e in [["fiber", 20], ["sticks", 20], ["stone", 20], ["wood", 10], ["hatchet_t2", 1]]:
				_net.request("debug_add", {"item": e[0], "count": e[1]}, func(_r: Dictionary) -> void: _replies += 1)
			_next("wait_give")
		"wait_give":
			if _replies >= 5 and _player.inventory.count("fiber") >= 20:
				_check(true, "host gave items (fiber %d)" % _player.inventory.count("fiber"))
				var rope_id := ""
				for r in load("res://scripts/items/recipes.gd").all():
					if r.out == "campfire":
						rope_id = r.id
				_net.request("craft", {"recipe": rope_id, "pos": _player.global_position}, func(res: Dictionary) -> void:
					_check(res.get("ok", false), "crafted a campfire through the host"))
				_next("place")
			elif _waited() > 30.0:
				_check(false, "host never sent the items (%d of 5 replies, %d fiber)" % [_replies, _player.inventory.count("fiber")])
				return _finish()
		"place":
			if _player.inventory.count("campfire") == 1:
				var slot := -1
				for i in _player.inventory.slots.size():
					if _player.inventory.slots[i].get("id", "") == "campfire":
						slot = i
				_structures_before = _game.structures.size()
				for k in 12:
					var a := k * 0.6
					var at: Vector3 = _player.global_position + Vector3(cos(a), 0, sin(a)) * 3.0
					at.y = _game.world_gen.get_height(at.x, at.z)
					if load("res://scripts/core/game_actions.gd").placement_problem(at) == "":
						_net.request("place", {"slot": slot, "pos": at, "yaw": 0.0})
						break
				_next("placed")
			elif _waited() > 30.0:
				_check(false, "campfire never arrived")
				return _finish()
		"placed":
			if _game.structures.size() > _structures_before:
				_check(true, "placed campfire shows up for the guest")
				_next("tree")
			elif _waited() > 30.0:
				_check(false, "campfire never placed")
				return _finish()
		"tree":
			# Chop the nearest tree through the host.
			var world = _main.get_node("World")
			var best := 1e9
			for c in world.get_children():
				if "resources" in c and c.tier == 0:
					for r in c.resources:
						if r.kind in ["oak", "pine", "birch", "fir"] and not r.get("removed", false):
							var d: float = r.transform.origin.distance_to(_player.global_position)
							if d < best:
								best = d
								_target = r
			if _target.is_empty():
				_check(false, "no tree nearby")
				return _finish()
			for i in _player.inventory.slots.size():
				if _player.inventory.slots[i].get("id", "") == "hatchet_t2" and i < 8:
					_player.inventory.select(i)
			_wood = _player.inventory.count("wood")
			_next("chop")
		"chop":
			# Chunks are rebuilt when the ground near them changes, so look the tree up again by id.
			var found: Array = _main.get_node("World").find_resource(_target.id)
			if not found.is_empty():
				_target = found[0].resources[found[1]]
			if _frames % 10 == 0 and not _target.get("removed", false):
				_hits_sent += 1
				_net.request("hit_resource", {"id": _target.id, "kind": _target.kind, "key": _target.key, "slot": _player.inventory.selected,
					"pos": _target.transform.origin, "from": _player.global_position}, func(res: Dictionary) -> void:
						_hit_replies += 1
						_last_hit = res)
			if _target.get("removed", false) and _game.removed_resources.has(_target.id):
				_check(_player.inventory.count("wood") > _wood, "chopped a tree through the host (wood %d -> %d)" % [_wood, _player.inventory.count("wood")])
				_next("animals")
			elif _waited() > 45.0:
				_check(false, "tree never fell (hp %s)" % str(_target.get("hp")))
				# What happened, for a failure on two machines: the replies, and whether the tree's changes arrived.
				print("  tree %s (%s) at %.1f m; in a loaded chunk %s; hits sent %d, replies %d, last reply %s; removed here %s, in Game %s; tool %s" % [
					_target.id, _target.kind, _target.transform.origin.distance_to(_player.global_position), str(not _main.get_node("World").find_resource(_target.id).is_empty()), _hits_sent, _hit_replies,
					str(_last_hit).left(300), str(_target.get("removed", false)), str(_game.removed_resources.has(_target.id)),
					_player.inventory.selected_item()])
				return _finish()
		"animals":
			var n: int = _main.get_node("Wildlife").get_animals().size()
			if n > 0:
				_check(true, "host's animals appear for the guest: %d" % n)
				_next("give2")
			elif _waited() > 45.0:
				_check(false, "no animals arrived from the host")
				_next("give2")
		# --- Building: a foundation blueprint built up with the hammer, then a door on its edge, opened ---
		"give2":
			_replies = 0
			for e in [["building_plan", 1], ["hammer", 1], ["spear_t2", 1], ["knife_t2", 1], ["stone", 20], ["plank", 12], ["rope", 3]]:
				_net.request("debug_add", {"item": e[0], "count": e[1]}, func(_r: Dictionary) -> void: _replies += 1)
			_next("wait_give2")
		"wait_give2":
			if _replies >= 7 and _player.inventory.count("hammer") == 1 and _player.inventory.count("plank") >= 12:
				# Tools must sit on the hotbar to be used: move them to its last slots.
				var to := 5
				for id in ["hammer", "spear_t2", "knife_t2"]:
					var at := _slot("id_" + id)
					if at >= 8:
						_player.inventory.move(at, to)
					to += 1
				_next("lay")
			elif _waited() > 30.0:
				_check(false, "host never sent the building kit (%d of 7 replies)" % _replies)
				_next("hunt")
		"lay":
			if _waited() < 1.5:
				return false   # let the hotbar moves come back from the host
			var spot := _clear_cell()
			if spot == Vector3.INF:
				_check(false, "found a clear spot to build")
				_next("hunt")
				return false
			var snap: Dictionary = _GA.snap_piece("foundation", spot)
			_foundation = snap.pos
			_laid = {}
			_net.request("place_blueprint", {"kind": "foundation", "pos": snap.pos, "yaw": 0.0}, func(res: Dictionary) -> void: _laid = res)
			_next("wait_lay")
		"wait_lay":
			if _laid.get("ok", false) and _game.structures.has(String(_laid.id)):
				_check(true, "laid a foundation blueprint through the host")
				_build_id = String(_laid.id)
				_after_build = "door"
				_next("build")
			elif _laid.has("ok") and not _laid.ok:
				_check(false, "foundation blueprint refused: %s" % _laid.get("reason", ""))
				_next("hunt")
			elif _waited() > 20.0:
				_check(false, "foundation blueprint never arrived")
				_next("hunt")
		"build":
			if not _game.structures.has(_build_id):
				_check(false, "the piece being built vanished")
				_next(_after_build)
			elif not _GA.is_blueprint(_game.structures[_build_id]):
				_check(true, "built %s up with the hammer through the host" % _game.structures[_build_id].kind)
				_next(_after_build)
			elif _frames % 8 == 0:
				_net.request("hit_structure", {"structure": _build_id, "slot": _slot("id_hammer")})
			if _waited() > 40.0:
				_check(false, "never finished building %s" % _build_id)
				_next(_after_build)
		"door":
			var snap: Dictionary = _GA.snap_piece("wood_door", _foundation + Vector3(1.45, 0, 0))
			var why: String = _GA.placement_problem(snap.pos, "wood_door", snap.yaw)
			_check(why == "", "a door fits on the foundation's edge (%s)" % why)
			_laid = {}
			_net.request("place_blueprint", {"kind": "wood_door", "pos": snap.pos, "yaw": snap.yaw}, func(res: Dictionary) -> void: _laid = res)
			_next("wait_door")
		"wait_door":
			if _laid.get("ok", false) and _game.structures.has(String(_laid.id)):
				_door_id = String(_laid.id)
				_build_id = _door_id
				_after_build = "open"
				_next("build")
			elif (_laid.has("ok") and not _laid.ok) or _waited() > 20.0:
				_check(false, "door blueprint refused or lost: %s" % _laid.get("reason", "no answer"))
				_next("hunt")
		"open":
			if _frames == 1:
				_net.request("toggle_door", {"structure": _door_id})
			if _game.structures.has(_door_id) and bool(_game.structures[_door_id].get("open", false)):
				_check(true, "opened the door through the host, and it shows open for the guest")
				_next("chest")
			elif _waited() > 15.0:
				_check(false, "the door never opened")
				_next("chest")
		# --- Storage: a chest on the foundation, built, stone put in and taken back out ---
		"chest":
			var at: Vector3 = _foundation + Vector3(-0.6, _GA.FLOOR_TOP, -0.6)
			var why: String = _GA.placement_problem(at, "chest", 0.0)
			_check(why == "", "a chest fits on the foundation (%s)" % why)
			_laid = {}
			_net.request("place_blueprint", {"kind": "chest", "pos": at, "yaw": 0.0}, func(res: Dictionary) -> void: _laid = res)
			_next("wait_chest")
		"wait_chest":
			if _laid.get("ok", false) and _game.structures.has(String(_laid.id)):
				_chest_id = String(_laid.id)
				_build_id = _chest_id
				_after_build = "stash"
				_next("build")
			elif (_laid.has("ok") and not _laid.ok) or _waited() > 20.0:
				_check(false, "chest blueprint refused or lost: %s" % _laid.get("reason", "no answer"))
				_next("hunt")
		"stash":
			if _frames == 1:
				# Walk over to it first (the host only lets you use a chest within reach).
				_back = _player.global_position
				_player.global_position = _foundation + Vector3(1.0, 1.0, 1.0)
				_stone = _player.inventory.count("stone")
				_net.request("chest", {"structure": _chest_id, "op": "quick", "from": "bag", "a": _slot("id_stone"), "pos": _player.global_position}, func(res: Dictionary) -> void:
					if not res.get("ok", false):
						_check(false, "chest refused: %s; stone in slot %d; %.1f m from it" % [res, _slot("id_stone"), _player.global_position.distance_to(_foundation)]))
			var items: Array = _game.structures.get(_chest_id, {}).get("items", [])
			var inside := 0
			for s: Dictionary in items:
				if s.get("id", "") == "stone":
					inside += int(s.count)
			if inside > 0 and _player.inventory.count("stone") == _stone - inside:
				_check(true, "put %d stone in the chest through the host" % inside)
				_next("unstash")
			elif _waited() > 15.0:
				_check(false, "the stone never went into the chest")
				_next("hunt")
		"unstash":
			if _frames == 1:
				var items: Array = _game.structures[_chest_id].get("items", [])
				for i in items.size():
					if (items[i] as Dictionary).get("id", "") == "stone":
						_net.request("chest", {"structure": _chest_id, "op": "quick", "from": "chest", "a": i, "pos": _player.global_position})
			if _player.inventory.count("stone") == _stone and _GA.chest_is_empty(_game.structures[_chest_id]):
				_check(true, "took the stone back out of the chest")
				_player.global_position = _back   # back where the rest happens
				_next("hunt")
			elif _waited() > 15.0:
				_check(false, "the stone never came back out of the chest")
				_next("hunt")
		# --- Hunting: kill an animal with a spear, butcher it with a knife ---
		"hunt":
			if _animal == null or not is_instance_valid(_animal):
				var best := 1e9
				for a in _main.get_node("Wildlife").get_animals():
					if a.net_id >= 0 and not a.dead:
						var d: float = a.global_position.distance_to(_player.global_position)
						if d < best:
							best = d
							_animal = a
			if _animal == null:
				if _waited() > 20.0:
					_check(false, "no animal to hunt")
					_next("cook")
				return false
			if _animal.dead:
				_check(true, "killed an animal through the host")
				_meat = _player.inventory.count("raw_meat")
				_next("butcher")
			elif _frames % 12 == 0:
				_net.request("hit_animal", {"animal": _animal.net_id, "slot": _slot("id_spear_t2"), "from": _animal.global_position + Vector3(1, 0, 0)})
			if _waited() > 60.0:
				_check(false, "the animal never died")
				_next("cook")
		"butcher":
			if _player.inventory.count("raw_meat") > _meat:
				_check(true, "butchered it through the host (raw meat %d)" % _player.inventory.count("raw_meat"))
				_next("cook")
			elif _frames % 12 == 0 and is_instance_valid(_animal):
				_net.request("carcass", {"animal": _animal.net_id, "slot": _slot("id_knife_t2")})
			if _waited() > 30.0:
				_check(false, "butchering gave no meat")
				_next("cook")
		# --- Cooking: the campfire minigame, finished through the host ---
		"cook":
			if _player.inventory.count("raw_meat") < 1:
				if _frames == 1:
					_net.request("debug_add", {"item": "raw_meat", "count": 1})
				if _waited() > 15.0:
					_check(false, "no meat to cook")
					_next("report")
				return false
			_cooked = _player.inventory.count("cooked_meat")
			var r := {}
			for rr in load("res://scripts/items/recipes.gd").all():
				if rr.out == "cooked_meat":
					r = rr
			_player.craft(r, 1, func(res: Dictionary) -> void: _check(false, "cooking refused: %s" % res.get("reason", "")))
			_check(_player.crafting != null, "the campfire minigame starts for the guest")
			_next("cooking" if _player.crafting != null else "report")
		"cooking":
			var sess = _player.crafting
			if sess == null:
				_check(_player.inventory.count("cooked_meat") > _cooked, "cooked meat through the minigame (cooked meat %d)" % _player.inventory.count("cooked_meat"))
				_next("report")
			else:
				sess.autoplay(_delta)
			if _waited() > 60.0:
				_check(false, "cooking never finished")
				if sess:
					sess.stop(true)
				_next("report")
		"report":
			_net._report.rpc_id(1, _player.to_save_data())
			_next("leave")
		"leave":
			if _frames == 30:
				return _finish()
	return false


## The hotbar slot holding an item ("id_<item>"), or the first slot.
func _slot(key: String) -> int:
	var id := key.trim_prefix("id_")
	for i in _player.inventory.slots.size():
		if _player.inventory.slots[i].get("id", "") == id:
			return i
	return 0


## A 3 m grid cell near the player with no tree close by and dry, buildable ground.
func _clear_cell() -> Vector3:
	var TE: GDScript = load("res://scripts/world/terrain_edit.gd")
	var p: Vector3 = _player.global_position
	for k in 120:
		var c := p + Vector3((k % 11 - 5) * 3.0, 0, (k / 11 - 5) * 3.0)
		c.x = floorf(c.x / 3.0) * 3.0 + 1.5
		c.z = floorf(c.z / 3.0) * 3.0 + 1.5
		c.y = _game.world_gen.get_height(c.x, c.z)
		if c.distance_to(p) < 4.0 or c.y < 2.0 or TE.tree_near(c, 6.0) != null:
			continue
		var snap: Dictionary = _GA.snap_piece("foundation", c)
		if _GA.placement_problem(snap.pos, "foundation", 0.0) == "":
			return c
	return Vector3.INF


func _next(p: String) -> void:
	_phase = p
	_frames = 0
	_phase_ms = Time.get_ticks_msec()


## Seconds spent in this phase. Waits are timed in seconds, not frames: a busy host makes frames come fast or slow.
func _waited() -> float:
	return (Time.get_ticks_msec() - _phase_ms) / 1000.0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("CLIENT RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	_net.stop()
	return true
