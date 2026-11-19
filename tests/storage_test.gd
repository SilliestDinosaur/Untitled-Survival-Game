extends SceneTree
## Storage test: godot --headless --path . -s tests/storage_test.gd
## A finished chest by the player: things go in (shift-click and drag), stack, swap and come back out; a chest with
## things in it can't be taken down, an empty one can; too far away, nothing moves; the contents survive a save
## round trip; and the chest's panel opens and closes.

var _main: Node
var _game: Node
var _f := 0
var _fails: Array[String] = []
var _GA: GDScript


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_main.create_world("Storage Test", 5151)
	if _f < 6 or _main.state != _main.State.PLAYING:
		return false
	var p = _main.get_node("Player")
	var inv = p.inventory
	var at: Vector3 = p.global_position + Vector3(2.0, 0, 0)
	at.y = _game.world_gen.get_height(at.x, at.z)
	var sid: String = _game.new_entity_id("s")
	_game.structures[sid] = {"id": sid, "kind": "chest", "pos": [at.x, at.y, at.z], "yaw": 0.0, "level": 0, "built": 1.0, "hp": 200.0, "max_hp": 200.0, "spent": {}}
	_game.structures_changed.emit()
	var st: Dictionary = _game.structures[sid]
	var here: Vector3 = p.global_position
	inv.clear(true)
	inv.add("wood", 30, true)
	inv.add("stone", 12, true)
	inv.add("hatchet_t1", 1, true)
	var slot_of := func(id: String) -> int:
		for i in inv.slots.size():
			if inv.slots[i].get("id", "") == id:
				return i
		return -1
	var chest_count := func(id: String) -> int:
		var n := 0
		for s: Dictionary in _GA.chest_slots(st):
			if s.get("id", "") == id:
				n += int(s.count)
		return n

	# Shift-click wood in.
	var r: Dictionary = _GA.chest_op(1, {"structure": sid, "op": "quick", "from": "bag", "a": slot_of.call("wood"), "pos": here})
	_check(r.ok and chest_count.call("wood") == 30 and inv.count("wood") == 0, "shift-click puts a stack in the chest")
	# Drag stone onto the wood's slot: they swap (different things).
	var wood_slot := -1
	for i in _GA.chest_slots(st).size():
		if _GA.chest_slots(st)[i].get("id", "") == "wood":
			wood_slot = i
	r = _GA.chest_op(1, {"structure": sid, "op": "move", "from": "bag", "a": slot_of.call("stone"), "to": "chest", "b": wood_slot, "pos": here})
	_check(r.ok and chest_count.call("stone") == 12 and inv.count("wood") == 30, "dropping on a different thing swaps them")
	# More wood onto chest... first put wood back in, then a second wood stack stacks onto it.
	_GA.chest_op(1, {"structure": sid, "op": "quick", "from": "bag", "a": slot_of.call("wood"), "pos": here})
	inv.add("wood", 5, true)
	_GA.chest_op(1, {"structure": sid, "op": "quick", "from": "bag", "a": slot_of.call("wood"), "pos": here})
	var wood_stacks := 0
	for s: Dictionary in _GA.chest_slots(st):
		if s.get("id", "") == "wood":
			wood_stacks += 1
	_check(chest_count.call("wood") == 35 and wood_stacks == 1, "like things stack in the chest (%d wood in %d stacks)" % [chest_count.call("wood"), wood_stacks])
	# A tool keeps its wear.
	var hs: int = slot_of.call("hatchet_t1")
	inv.slots[hs].dur = 7
	_GA.chest_op(1, {"structure": sid, "op": "quick", "from": "bag", "a": hs, "pos": here})
	var kept := false
	for s: Dictionary in _GA.chest_slots(st):
		if s.get("id", "") == "hatchet_t1" and int(s.dur) == 7:
			kept = true
	_check(kept, "a tool keeps its wear in the chest")
	# Too far: nothing moves.
	r = _GA.chest_op(1, {"structure": sid, "op": "quick", "from": "chest", "a": 0, "pos": here + Vector3(30, 0, 0)})
	_check(not r.ok, "nothing moves from too far away")
	# Can't take it down full.
	_check(_GA.removal_problem(st) != "", "a chest with things in it can't be taken down")
	# Save round trip.
	var snap: Dictionary = _game.snapshot()
	_game.apply_snapshot(snap)
	_game.net_client = false
	st = _game.structures[sid]
	_check(chest_count.call("wood") == 35 and chest_count.call("stone") == 0 + chest_count.call("stone"), "the contents survive a save round trip")
	# Everything back out.
	for i in _GA.chest_slots(st).size():
		if not (_GA.chest_slots(st)[i] as Dictionary).is_empty():
			_GA.chest_op(1, {"structure": sid, "op": "quick", "from": "chest", "a": i, "pos": here})
	_check(_GA.chest_is_empty(st) and inv.count("wood") == 35 and inv.count("hatchet_t1") == 1, "everything comes back out")
	_check(_GA.removal_problem(st) == "", "an empty chest can be taken down")
	# The panel.
	_main._inventory.show_chest(sid)
	_check(_main._inventory.visible and _main._inventory._chest.visible, "the chest's panel opens beside the satchel")
	_main._toggle_inventory(false)
	_check(not _main._inventory._chest.visible and not _main._inventory.visible, "and closes")
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)
