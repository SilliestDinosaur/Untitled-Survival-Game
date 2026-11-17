extends SceneTree
## Multiplayer test, guest side (see net_host_test.gd).

var _main: Node
var _game: Node
var _net: Node
var _player: Node
var _phase := "join"
var _frames := 0
var _fails: Array[String] = []
var _target := {}
var _wood := 0
var _structures_before := 0
var _replies := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")
	_net = root.get_node("Net")
	_player = _main.get_node("Player")
	root.get_node("Settings").player_name = "Test Guest"


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		"join":
			if _frames == 60:
				_check(_net.join("127.0.0.1:%d" % _net.PORT), "connecting")
			if _main.state == _main.State.PLAYING:
				_check(_game.world_seed == 424242, "got the host's world (seed %d)" % _game.world_seed)
				_check(_player.inventory.count("rock") == 1, "starts with a rock from the host")
				_check(_net.avatars.has(1), "host's avatar exists")
				_next("give")
			elif _frames > 60 * 120:
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
			elif _frames > 600:
				_check(false, "host never sent the items")
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
			elif _frames > 600:
				_check(false, "campfire never arrived")
				return _finish()
		"placed":
			if _game.structures.size() > _structures_before:
				_check(true, "placed campfire shows up for the guest")
				_next("tree")
			elif _frames > 600:
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
				_net.request("hit_resource", {"id": _target.id, "kind": _target.kind, "key": _target.key, "slot": _player.inventory.selected,
					"pos": _target.transform.origin, "from": _player.global_position})
			if _target.get("removed", false) and _game.removed_resources.has(_target.id):
				_check(_player.inventory.count("wood") > _wood, "chopped a tree through the host (wood %d -> %d)" % [_wood, _player.inventory.count("wood")])
				_next("animals")
			elif _frames > 1200:
				_check(false, "tree never fell (hp %s)" % str(_target.get("hp")))
				return _finish()
		"animals":
			var n: int = _main.get_node("Wildlife").get_animals().size()
			if n > 0:
				_check(true, "host's animals appear for the guest: %d" % n)
				_next("report")
			elif _frames > 60 * 30:
				_check(false, "no animals arrived from the host")
				_next("report")
		"report":
			_net._report.rpc_id(1, _player.to_save_data())
			_next("leave")
		"leave":
			if _frames == 30:
				return _finish()
	return false


func _next(p: String) -> void:
	_phase = p
	_frames = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("CLIENT RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	_net.stop()
	return true
