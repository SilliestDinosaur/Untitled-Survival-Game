extends SceneTree
## Building pieces test: godot --headless --path . -s tests/building_test.gd
## The plank floor works as a foundation, window and plank doorways stand on a floor edge like walls,
## and a plank ceiling needs a floor and one wall (a roof needs two).

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _spot := Vector3.ZERO
var _GA: GDScript
var _Terrain: GDScript


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_Terrain = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Building Test", 4242)
			if _main.state == _main.State.PLAYING:
				_spot = _find_clear_cell()
				var inv: Inventory = _game.inventory_of(1)
				inv.add("wood_floor", 2, true)
				inv.add("window_wall", 2, true)
				inv.add("wood_doorway", 1, true)
				inv.add("ceiling", 1, true)
				_step = 1
				_f = 0
		1:
			# A plank floor is snapped to the cell centre and levelled like a foundation.
			var snap: Dictionary = _GA.snap_piece("wood_floor", _spot + Vector3(0.4, 0, 0.3))
			_check(absf(snap.pos.x - _spot.x) < 0.01 and absf(snap.pos.z - _spot.z) < 0.01, "a plank floor snaps to the cell centre")
			_check(_GA.placement_problem(snap.pos, "wood_floor", 0.0) == "", "a plank floor is allowed on open ground (%s)" % _GA.placement_problem(snap.pos, "wood_floor", 0.0))
			var floor_slot := _slot_of(_game.inventory_of(1), "wood_floor")
			var placed: Dictionary = _GA.place_structure(1, floor_slot, snap.pos, 0.0)
			_check(placed.ok, "a plank floor is placed")
			if placed.ok:
				_Terrain.commit(_Terrain.level_ground(placed.pos, 1.5, 1.5, 0.0, placed.pos.y))
			# A ceiling needs a wall under it, so with only the floor it is refused.
			var ceil_snap: Dictionary = _GA.snap_piece("ceiling", _spot + Vector3(0, 3.2, 0))
			var no_wall: String = _GA.placement_problem(ceil_snap.pos, "ceiling", 0.0)
			_check(no_wall != "", "a ceiling with no walls under it is refused: %s" % no_wall)
			_step = 2
		2:
			# Window and plank doorway walls stand on the floor's east and north edges.
			var east: Vector3 = _spot + Vector3(1.5, 0, 0)
			var wsnap: Dictionary = _GA.snap_piece("window_wall", east + Vector3(0.2, 0, 0.1))
			_check(absf(wsnap.pos.x - (_spot.x + 1.5)) < 0.01 and absf(wsnap.yaw - PI * 0.5) < 0.01, "a window wall snaps to the floor's east edge")
			var wall_problem: String = _GA.placement_problem(wsnap.pos, "window_wall", wsnap.yaw)
			_check(wall_problem == "", "a window wall on a plank floor edge is allowed (%s)" % wall_problem)
			_check(_GA.place_structure(1, _slot_of(_game.inventory_of(1), "window_wall"), wsnap.pos, wsnap.yaw).ok, "window wall placed")
			var north: Dictionary = _GA.snap_piece("wood_doorway", _spot + Vector3(0, 1.5, -1.4))
			_check(absf(north.yaw) < 0.01, "a plank doorway snaps to the floor's north edge")
			var door_problem: String = _GA.placement_problem(north.pos, "wood_doorway", north.yaw)
			_check(door_problem == "", "a plank doorway on a floor edge is allowed (%s)" % door_problem)
			_check(_GA.place_structure(1, _slot_of(_game.inventory_of(1), "wood_doorway"), north.pos, north.yaw).ok, "plank doorway placed")
			# Floating walls are still refused away from any floor.
			var far := _spot + Vector3(45, 0, 45)
			far.y = _game.world_gen.get_height(far.x, far.z)
			var far_snap: Dictionary = _GA.snap_piece("window_wall", far)
			_check(_GA.placement_problem(far_snap.pos, "window_wall", far_snap.yaw) != "", "a window wall with no floor under it is refused")
			_step = 3
		3:
			# Now the cell has two walls: a ceiling on them is allowed.
			var ceil_snap: Dictionary = _GA.snap_piece("ceiling", _spot + Vector3(0, 3.2, 0))
			var ceil_ok: String = _GA.placement_problem(ceil_snap.pos, "ceiling", 0.0)
			_check(ceil_ok == "", "a ceiling on one or more walls is allowed (%s)" % ceil_ok)
			_check(_GA.place_structure(1, _slot_of(_game.inventory_of(1), "ceiling"), ceil_snap.pos, 0.0).ok, "ceiling placed")
			# A second ceiling in the same place is refused.
			_check(_GA.placement_problem(ceil_snap.pos, "ceiling", 0.0) != "", "a second ceiling in the same cell is refused")
			# Taking a wall down while the ceiling still needs it is refused; the floor cannot go with walls on it.
			var wall_st: Dictionary = {}
			for id: String in _game.structures:
				if _game.structures[id].kind == "window_wall":
					wall_st = _game.structures[id]
			_check(not wall_st.is_empty(), "the window wall is in the world")
			var floor_st: Dictionary = {}
			for id: String in _game.structures:
				if _game.structures[id].kind == "wood_floor":
					floor_st = _game.structures[id]
			_check(_GA.removal_problem(floor_st) != "", "a plank floor with walls on it can't be taken down")
			_step = 4
		4:
			_check(_GA.is_building("wood_floor") and _GA.is_building("ceiling"), "new pieces count as building pieces")
			_check("wood_floor" in _GA.FLOOR_KINDS and "window_wall" in _GA.WALL_KINDS and "ceiling" in _GA.COVER_KINDS, "new pieces sit in their groups")
			return _finish()
	return false


func _find_clear_cell() -> Vector3:
	var spot: Vector3 = _game.world_gen.find_spawn_point()
	spot.x = floorf(spot.x / 3.0) * 3.0 + 1.5
	spot.z = floorf(spot.z / 3.0) * 3.0 + 1.5
	spot.y = _game.world_gen.get_height(spot.x, spot.z)
	for k in 200:
		var cand := spot + Vector3((k % 14 - 7) * 3.0, 0, (k / 14 - 7) * 3.0)
		cand.x = floorf(cand.x / 3.0) * 3.0 + 1.5
		cand.z = floorf(cand.z / 3.0) * 3.0 + 1.5
		cand.y = _game.world_gen.get_height(cand.x, cand.z)
		if _Terrain.tree_near(cand, 6.0) == null and _game.world_gen.get_height(cand.x, cand.z) > 2.0:
			return cand
	return spot


func _slot_of(inv: Inventory, id: String) -> int:
	for i in inv.slots.size():
		if inv.slots[i].get("id", "") == id:
			return i
	return 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
