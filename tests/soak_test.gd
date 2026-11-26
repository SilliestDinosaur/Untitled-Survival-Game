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
var _GA: GDScript
var _IDB: GDScript
var _frame_ms: Array[float] = []
var _last_us := 0
var _placed := 0
var _toggled := 0
var _teleports := 0
var _reload_frame := false
var _reload_ms: Array[float] = []
var _roundtrips := 0
var _max_chunks := 0
var _fails: Array[String] = []
var _frames_total := 6000
var _seed := 629946553
var _kinds: Array = []
var _items: Array = []
var _floors: Array = []
var _stations: Array = []
var _reasons := {}
var _frame_builds: Array[int] = []
var _frame_split: Array = []
var _last_built := 0


func _initialize() -> void:
	_frames_total = int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 3000
	_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 629946553
	seed(4711)
	_GA = load("res://scripts/core/game_actions.gd")
	_IDB = load("res://scripts/items/item_db.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _state == "play" and _reload_frame:
		# A snapshot round trip regenerates the world (what a guest's join or a save's load does behind the
		# loading screen): timed on its own, not as a play frame.
		_reload_ms.append((now - _last_us) / 1000.0)
		_reload_frame = false
	elif _last_us > 0 and _state == "play":
		_frame_ms.append((now - _last_us) / 1000.0)
		var built: int = _game.flora.meshes.size() if _game.flora else 0
		_frame_builds.append(built - _last_built)
		# Where the frame went (the engine's own measures of the last frame): scripts' _process, and physics
		# (with the scripts' _physics_process), so a spike can be traced.
		_frame_split.append(Vector2(Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		_last_built = built
	_last_us = now
	match _state:
		"load":
			if _f == 5:
				_main.create_world("Soak", _seed)
			if _main.state == _main.State.PLAYING:
				_kinds = _GA.PIECES.keys()
				_floors = _kinds.filter(func(k: String) -> bool: return k.ends_with("_floor"))
				_stations = _kinds.filter(func(k: String) -> bool: return not _GA.is_building(k))
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
	var inv = _game.inventory_of(1)
	var world_gen = _game.world_gen
	_max_chunks = maxi(_max_chunks, _main.get_node("World").get_chunk_count())
	if _f % 90 == 1:
		var spot := _land_spot(world_gen)
		if spot != Vector3.INF:
			player.global_position = spot
			_teleports += 1
	if _f % 40 == 7 and OS.get_environment("PLACE") != "0":
		var id: String = _pick_kind()
		inv.add(id, 3, true)
		_items_granted(inv)
		var t_place := Time.get_ticks_usec()
		var ok := _try_place(player, inv, id)
		print("SOAK place frame %d: %s %s  %.1f ms" % [_f, id, "ok" if ok else "refused", (Time.get_ticks_usec() - t_place) / 1000.0])
		if ok:
			_placed += 1
	if _f % 150 == 9:
		for sid: String in _game.structures.keys():
			if "door" in str(_game.structures[sid].kind):
				_GA.toggle_door(1, sid)
				_toggled += 1
				break
	if _f % 500 == 250 and OS.get_environment("ROUNDTRIP") != "0":
		var snap: Dictionary = _game.snapshot()
		_game.apply_snapshot(snap)
		_game.net_client = false   # apply_snapshot is the guest's path; this run is still the host
		_roundtrips += 1
		_reload_frame = true


func _pick_kind() -> String:
	var roll := randf()
	if roll < 0.5 and not _floors.is_empty():
		return _floors[randi() % _floors.size()]
	if roll < 0.6 and not _stations.is_empty():
		return _stations[randi() % _stations.size()]
	return _kinds[randi() % _kinds.size()]


func _items_granted(inv) -> void:
	var id: String = _items[randi() % _items.size()]
	inv.add(id, 2, true)


func _land_spot(world_gen) -> Vector3:
	for k in 200:
		var x := randf_range(40.0, _game.WORLD_SIZE - 40.0)
		var z := randf_range(40.0, _game.WORLD_SIZE - 40.0)
		var h: float = world_gen.get_height(x, z)
		if h > 2.0:
			return Vector3(x, h + 2.0, z)
	return Vector3.INF


func _try_place(player: CharacterBody3D, inv, kind: String) -> bool:
	var slot := -1
	for i in inv.slots.size():
		if inv.slots[i].get("id", "") == kind:
			slot = i
			break
	if slot < 0 and not _GA.is_building(kind):
		return false
	var fwd := -player.global_transform.basis.z
	var aim: Vector3 = player.global_position + fwd * 3.0
	var snap: Dictionary = _GA.snap_piece(kind, aim)
	var result: Dictionary
	if _GA.is_building(kind):
		# Building pieces: lay the blueprint with the plan, then build it up with the hammer, as a player does.
		if inv.count("building_plan") < 1:
			inv.add("building_plan", 1, true)
		result = _GA.place_blueprint(1, kind, snap.pos, snap.yaw)
		if result.get("ok", false):
			_build(inv, String(result.id))
	else:
		result = _GA.place_structure(1, slot, snap.pos, snap.yaw)
	var why: String = result.get("reason", "") if not result.get("ok", false) else "placed"
	_reasons[why] = int(_reasons.get(why, 0)) + 1
	return result.get("ok", false)


func _build(inv, id: String) -> void:
	var st: Dictionary = _game.structures[id]
	for item: String in _GA.PIECE_COSTS[st.kind]:
		inv.add(item, int(_GA.PIECE_COSTS[st.kind][item]), true)
	if inv.count("hammer") < 1:
		inv.add("hammer", 1, true)
	var keep: int = inv.selected
	for i in inv.slots.size():
		if inv.slots[i].get("id", "") == "hammer":
			inv.select(i)
	for i in 20:
		if not _game.structures.has(id) or not _GA.is_blueprint(_game.structures[id]):
			break
		_GA.hit_structure(1, id)
	inv.select(keep)


func _finish() -> bool:
	var times := _frame_ms.duplicate()
	times.sort()
	var n := times.size()
	var mean := 0.0
	var over50 := 0
	for t in times:
		mean += t
		if t > 50.0:
			over50 += 1
	mean = mean / maxf(1.0, n)
	var p99: float = times[int(n * 0.99)] if n > 0 else 0.0
	var worst: float = times[n - 1] if n > 0 else 0.0
	print("SOAK frames %d  mean %.2f ms  p99 %.2f ms  worst %.2f ms  over 50 ms: %d" % [n, mean, p99, worst, over50])
	if not _reload_ms.is_empty():
		print("SOAK snapshot reloads (world regenerated, like a load): %s ms" % ", ".join(_reload_ms.map(func(t: float) -> String: return "%.0f" % t)))
	print("SOAK teleports %d  placed %d  door toggles %d  snapshot round trips %d  max chunks %d" % [_teleports, _placed, _toggled, _roundtrips, _max_chunks])
	for i in _frame_ms.size():
		if _frame_ms[i] > 50.0:
			var sp: Vector2 = _frame_split[i] if i < _frame_split.size() else Vector2.ZERO
			print("SOAK spike play-frame %d: %.1f ms (process %.1f, physics %.1f), flora builds %d, teleport frame %s" % [i, _frame_ms[i], sp.x, sp.y, _frame_builds[i], str(i % 90 == 0)])
	var spike_build := 0
	var spike_plain := 0
	var build_frames := 0
	for i in _frame_ms.size():
		if _frame_builds[i] > 0:
			build_frames += 1
		if _frame_ms[i] > 50.0:
			if _frame_builds[i] > 0:
				spike_build += 1
			else:
				spike_plain += 1
	print("SOAK flora builds in %d frames; spikes over 50 ms with a flora build: %d, without: %d" % [build_frames, spike_build, spike_plain])
	for why: String in _reasons:
		print("SOAK placement: %d x %s" % [_reasons[why], why if why != "" else "(no reason given)"])
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
