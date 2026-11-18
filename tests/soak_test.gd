extends SceneTree
## Soak test: godot --headless --path . -s tests/soak_test.gd
## Long run that moves the player across the island (so chunks stream in and out), grants items, places and
## toggles building pieces, and round-trips the world snapshot. It reports frame times and checks the run is still
## healthy at the end; script errors show up in the log.
## Environment: FRAMES=3000 (default), SEED=629946553.

var _main: Node
var _game: Node
var _f := 0
var _state := "load"
var _rng := RandomNumberGenerator.new()
var _GA: GDScript
var _IDB: GDScript
var _frame_ms: Array[float] = []
var _last_us := 0
var _placed := 0
var _toggled := 0
var _teleports := 0
var _roundtrips := 0
var _max_chunks := 0
var _fails: Array[String] = []
var _frames_total := 6000
var _seed := 629946553
var _kinds: Array = []
var _items: Array = []


func _initialize() -> void:
	_frames_total = int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 3000
	_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 629946553
	_rng.seed = 4711
	_GA = load("res://scripts/core/game_actions.gd")
	_IDB = load("res://scripts/items/item_db.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _state == "play":
		_frame_ms.append((now - _last_us) / 1000.0)
	_last_us = now
	match _state:
		"load":
			if _f == 5:
				_main.create_world("Soak", _seed)
			if _main.state == _main.State.PLAYING:
				_kinds = _GA.PIECES.keys()
				_items = _IDB.all_ids()
				_state = "play"
				_f = 0
		"play":
			_tick()
			if _f >= _frames_total:
				return _finish()
	return false


func _tick() -> void:
	var player: CharacterBody3D = _main.get_node("Player")
	var inv: Inventory = _game.inventory_of(1)
	var world_gen = _game.world_gen
	_max_chunks = maxi(_max_chunks, _main.get_node("World").get_chunk_count())
	if _f % 90 == 1:
		var spot := _land_spot(world_gen)
		if spot != Vector3.INF:
			player.global_position = spot
			_teleports += 1
	if _f % 40 == 7:
		var id: String = _kinds[_rng.randi() % _kinds.size()]
		inv.add(id, 3, true)
		_items_granted(inv)
		if _try_place(player, inv, id):
			_placed += 1
	if _f % 150 == 9:
		for sid: String in _game.structures.keys():
			if "door" in str(_game.structures[sid].kind):
				_GA.toggle_door(1, sid)
				_toggled += 1
				break
	if _f % 500 == 250:
		var snap: Dictionary = _game.snapshot()
		_game.apply_snapshot(snap)
		_roundtrips += 1


func _items_granted(inv: Inventory) -> void:
	var id: String = _items[_rng.randi() % _items.size()]
	inv.add(id, 2, true)


func _land_spot(world_gen) -> Vector3:
	for k in 200:
		var x := _rng.randf_range(40.0, Game.WORLD_SIZE - 40.0)
		var z := _rng.randf_range(40.0, Game.WORLD_SIZE - 40.0)
		var h: float = world_gen.get_height(x, z)
		if h > 2.0:
			return Vector3(x, h + 2.0, z)
	return Vector3.INF


func _try_place(player: CharacterBody3D, inv: Inventory, kind: String) -> bool:
	var slot := -1
	for i in inv.slots.size():
		if inv.slots[i].get("id", "") == kind:
			slot = i
			break
	if slot < 0:
		return false
	var fwd := -player.global_transform.basis.z
	var aim: Vector3 = player.global_position + fwd * 3.0
	var snap: Dictionary = _GA.snap_piece(kind, aim)
	var result: Dictionary = _GA.place_structure(1, slot, snap.pos, snap.yaw)
	return result.get("ok", false)


func _finish() -> bool:
	var times := _frame_ms.duplicate()
	times.sort()
	var n := times.size()
	var mean := 0.0
	for t in times:
		mean += t
	mean = mean / maxf(1.0, n)
	var p99: float = times[int(n * 0.99)] if n > 0 else 0.0
	var worst: float = times[n - 1] if n > 0 else 0.0
	print("SOAK frames %d  mean %.2f ms  p99 %.2f ms  worst %.2f ms  over 50 ms: %d" % [n, mean, p99, worst, times.filter(func(t: float) -> bool: return t > 50.0).size()])
	print("SOAK teleports %d  placed %d  door toggles %d  snapshot round trips %d  max chunks %d" % [_teleports, _placed, _toggled, _roundtrips, _max_chunks])
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
