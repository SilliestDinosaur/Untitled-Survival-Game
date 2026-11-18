extends SceneTree
## Crafting minigame test: godot --headless --path . -s tests/crafting_test.gd
## Puts a campfire, workbench and forge by the player and plays each minigame through: cooking on the spit (and a
## batch of two back to back), smelting an ingot, knapping a flint hatchet by hand, shaping a tool at the
## workbench, and heating and hammering one at the forge. Checks that the items arrive, that nothing moves without
## input, that stopping costs nothing, and that the view comes back to the player.

var _main: Node
var _game: Node
var _player: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _cases: Array = []
var _case := {}
var _before := 0
var _wait := 0
var _strikes := 0
var _Session: GDScript


func _initialize() -> void:
	_Session = load("res://scripts/gameplay/craft_session.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _recipe(out: String) -> Dictionary:
	for r: Dictionary in load("res://scripts/items/recipes.gd").all():
		if r.out == out:
			return r
	return {}


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Craft Test", 4242)
			if _main.state == _main.State.PLAYING:
				_player = _main.get_node("Player")
				var p: Vector3 = _player.global_position
				var kinds := {"campfire": Vector3(2.2, 0, 0), "workbench": Vector3(-2.2, 0, 0.4), "forge": Vector3(0.3, 0, 2.6)}
				for kind: String in kinds:
					var at: Vector3 = p + kinds[kind]
					at.y = _game.world_gen.get_height(at.x, at.z)
					var id: String = _game.new_entity_id("s")
					_game.structures[id] = {"id": id, "kind": kind, "pos": [at.x, at.y, at.z], "yaw": 0.4, "hp": 3, "level": 0}
				_game.structures_changed.emit()
				_cases = [
					{"out": "cooked_meat", "times": 2, "mode": 0},
					{"out": "stew", "times": 1, "mode": 0},
					{"out": "ingot_t2", "times": 1, "mode": 1},
					{"out": "hatchet_t1", "times": 1, "mode": 4},
					{"out": "pickaxe_t2", "times": 1, "mode": 3},
					{"out": "knife_t3", "times": 1, "mode": 2},
				]
				_step = 1
				_f = 0
		1:   # nothing moves without input, and stopping costs nothing
			if _f < 10:
				return false
			var r := _recipe("cooked_meat")
			var inv = _player.inventory
			inv.add("raw_meat", 1, true)
			var meat_before: int = inv.count("raw_meat")
			_player.craft(r, 1, func(_res: Dictionary) -> void: pass)
			_check(_player.crafting != null, "cooking starts a minigame")
			_case = {"session": _player.crafting, "frames": 0}
			_step = 2
			_before = meat_before
			_f = 0
		2:
			var s = _case.session
			if _f < 150:   # 2.5 s of standing there doing nothing
				return false
			_check(s.progress == 0.0, "no progress without input (%.2f)" % s.progress)
			s.stop()
			_step = 3
			_f = 0
		3:
			if _player.crafting != null:
				return false
			_check(_player.inventory.count("raw_meat") == _before, "stopping uses nothing up")
			_check(_player.camera.current, "the view is back with the player after stopping")
			_player.inventory.remove("raw_meat", _before)
			_step = 4
			_f = 0
		4:   # the next case
			if _cases.is_empty():
				return _finish()
			_case = _cases.pop_front()
			var r := _recipe(_case.out)
			_check(not r.is_empty(), "recipe for %s exists" % _case.out)
			_check(_Session.mode_for(r) == int(_case.mode), "%s uses minigame %d (got %d)" % [_case.out, _case.mode, _Session.mode_for(r)])
			var inv = _player.inventory
			for item: String in r.needs:
				inv.add(item, int(r.needs[item]) * int(_case.times), true)
			_before = inv.count(_case.out)
			_player.craft(r, int(_case.times), func(_res: Dictionary) -> void: pass)
			_check(_player.crafting != null, "%s starts a minigame" % _case.out)
			_strikes = 0
			_wait = 0
			_step = 5
			_f = 0
		5:   # play it well until it's done
			_wait += 1
			var s = _player.crafting
			if s == null:
				Input.action_release("attack")
				var got: int = _player.inventory.count(_case.out) - _before
				_check(got == int(_case.times), "made %d %s (wanted %d)" % [got, _case.out, _case.times])
				_check(_player.camera.current, "the view is back with the player after %s" % _case.out)
				var per := float(_wait) / 60.0 / float(_case.times)
				print("  %s: %d strikes, about %.1f s each at 60 fps" % [_case.out, _strikes, per])
				_step = 4
				return false
			if _wait > 60 * 60:
				_check(false, "%s finished within a minute" % _case.out)
				s.stop()
				return false
			var pumping: bool = s.mode == 1 or (s.mode == 2 and s.phase == 0)
			if pumping:
				if s.heat < 0.72:
					Input.action_press("attack")
				else:
					Input.action_release("attack")
			else:
				Input.action_release("attack")
				if s._busy or s._lock > 0.0:
					return false
				# Wait for the cue's best moment, then strike.
				var ready := false
				match s.mode:
					0: ready = absf(s.cue_t - 0.85) < 0.02
					3:
						s.target = clampf(s.sweep_pos(), 0.15, 0.85)
						ready = absf(s.sweep_pos() - s.target) < 0.01
					_: ready = absf(s.cue_t - 1.0) < 0.03
				if ready:
					s.strike()
					_strikes += 1
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
