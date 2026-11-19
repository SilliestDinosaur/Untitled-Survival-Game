extends SceneTree
## Building pieces test: godot --headless --path . -s tests/building_test.gd
## Floors take walls, half walls and doors on their edges, roofs need two full walls (half walls don't
## count), doors swing open and shut, and stairs need a floor to climb from and nothing overhead.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _spot := Vector3.ZERO
var _GA: GDScript
var _Terrain: GDScript
var _door_id := ""


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
				var inv = _game.inventory_of(1)
				inv.add("building_plan", 1, true)
				_step = 1
				_f = 0
		1:
			# Cell A (the spot) gets a plank floor, then a staircase.
			var snap: Dictionary = _GA.snap_piece("wood_floor", _spot + Vector3(0.4, 0, 0.3))
			_check(absf(snap.pos.x - _spot.x) < 0.01 and absf(snap.pos.z - _spot.z) < 0.01, "a plank floor snaps to the cell centre")
			var floor_problem: String = _GA.placement_problem(snap.pos, "wood_floor", 0.0)
			_check(floor_problem == "", "a plank floor is allowed on open ground (%s)" % floor_problem)
			_check(_GA.place_blueprint(1, "wood_floor", snap.pos, 0.0).ok, "a plank floor is placed")
			_Terrain.commit(_Terrain.level_ground(snap.pos, 1.5, 1.5, 0.0, snap.pos.y))
			var roof_snap: Dictionary = _GA.snap_piece("roof", _spot + Vector3(0, 3.2, 0))
			var no_wall: String = _GA.placement_problem(roof_snap.pos, "roof", 0.0)
			_check(no_wall != "", "a roof with no walls under it is refused: %s" % no_wall)
			var stairs_snap: Dictionary = _GA.snap_piece("brick_stairs", _spot + Vector3(0, 0.5, 0), -1.0, 0.0)
			_check(int(stairs_snap.level) == 0, "stairs climb from the cell's floor (level %d)" % int(stairs_snap.level))
			var stairs_problem: String = _GA.placement_problem(stairs_snap.pos, "brick_stairs", stairs_snap.yaw)
			_check(stairs_problem == "", "stairs on a floor are allowed (%s)" % stairs_problem)
			_check(_GA.place_blueprint(1, "brick_stairs", stairs_snap.pos, stairs_snap.yaw).ok, "stairs placed")
			var again: String = _GA.placement_problem(stairs_snap.pos, "brick_stairs", stairs_snap.yaw)
			_check(again != "", "a second staircase in the same cell is refused: %s" % again)
			var in_air := _spot + Vector3(0, 0, -6.0)
			var air: Dictionary = _GA.snap_piece("brick_stairs", in_air, -1.0, 0.0)
			var air_problem: String = _GA.placement_problem(air.pos, "brick_stairs", air.yaw)
			_check(air_problem != "", "stairs with no floor to climb from are refused: %s" % air_problem)
			_step = 2
		2:
			# Cell B, one cell east: a floor, a window wall and a half wall on its edges. A roof needs two
			# full walls, so the half wall doesn't count and one full wall is not enough.
			var b := _spot + Vector3(3.0, 0, 0)
			b.y = _spot.y
			var fsnap: Dictionary = _GA.snap_piece("wood_floor", b)
			_check(_GA.place_blueprint(1, "wood_floor", fsnap.pos, 0.0).ok, "a second floor is placed")
			_Terrain.commit(_Terrain.level_ground(fsnap.pos, 1.5, 1.5, 0.0, fsnap.pos.y))
			var east: Dictionary = _GA.snap_piece("window_wall", fsnap.pos + Vector3(1.45, 0, 0))
			_check(absf(east.yaw - PI * 0.5) < 0.01, "a window wall snaps to the east edge of the floor")
			_check(_GA.place_blueprint(1, "window_wall", east.pos, east.yaw).ok, "window wall placed on the east edge")
			var south: Dictionary = _GA.snap_piece("brick_half", fsnap.pos + Vector3(0, 0, 1.45))
			_check(absf(south.yaw) < 0.01, "a half wall snaps to the south edge")
			_check(_GA.place_blueprint(1, "brick_half", south.pos, south.yaw).ok, "half wall placed on the south edge")
			var roof_b: Dictionary = _GA.snap_piece("roof", b + Vector3(0, 3.2, 0))
			var one_full: String = _GA.placement_problem(roof_b.pos, "roof", 0.0)
			_check(one_full != "", "a roof with one full wall and one half wall is refused: %s" % one_full)
			var north: Dictionary = _GA.snap_piece("wood_doorway", fsnap.pos + Vector3(0, 0, -1.45))
			_check(_GA.place_blueprint(1, "wood_doorway", north.pos, north.yaw).ok, "plank doorway placed on the north edge")
			var roof_ok: String = _GA.placement_problem(roof_b.pos, "roof", 0.0)
			_check(roof_ok == "", "a roof on two full walls is allowed (%s)" % roof_ok)
			# Stairs can't be built under a roof (the cell's roof would be in the way): test in cell A.
			var over_stairs: Dictionary = _GA.snap_piece("roof", _spot + Vector3(0, 3.2, 0))
			var stair_roof: String = _GA.placement_problem(over_stairs.pos, "roof", 0.0)
			_check(stair_roof != "", "a roof over the staircase is refused: %s" % stair_roof)
			# Cell B's floor can't come up while walls stand on it.
			var floor_b: Dictionary = {}
			for id: String in _game.structures:
				var st: Dictionary = _game.structures[id]
				if st.kind == "wood_floor" and _GA.cell_of(_GA._pos(st)) == _GA.cell_of(fsnap.pos):
					floor_b = st
			_check(not floor_b.is_empty() and _GA.removal_problem(floor_b) != "", "a floor with walls on it can't be taken down")
			_step = 3
		3:
			# A door on cell B's west edge: it opens and shuts.
			var west: Dictionary = _GA.snap_piece("wood_door", _spot + Vector3(3.0 - 1.45, 0, 0))
			_check(absf(west.yaw - PI * 0.5) < 0.01, "a door snaps to the west edge of cell B")
			var door_problem: String = _GA.placement_problem(west.pos, "wood_door", west.yaw)
			_check(door_problem == "", "a door on a floor edge is allowed (%s)" % door_problem)
			_check(_GA.place_blueprint(1, "wood_door", west.pos, west.yaw).ok, "door placed")
			for id: String in _game.structures:
				if _game.structures[id].kind == "wood_door":
					_door_id = id
			_check(_door_id != "", "the door is in the world")
			_check(_GA.is_blueprint(_game.structures[_door_id]), "a placed piece starts as a blueprint")
			_GA.toggle_door(1, _door_id)
			_check(not bool(_game.structures[_door_id].get("open", false)), "a blueprint door doesn't open")
			var inv = _game.inventory_of(1)
			var planks_before: int = inv.count("plank")
			_build(_door_id)
			var door: Dictionary = _game.structures[_door_id]
			_check(not _GA.is_blueprint(door), "the hammer finishes the door")
			_check(inv.count("plank") == planks_before and inv.count("rope") == 0,
				"building takes exactly the door's cost (%d planks, %d rope left)" % [inv.count("plank") - planks_before, inv.count("rope")])
			_check(is_equal_approx(float(door.hp), float(_GA.MAT_HP.wood)), "a finished wood piece has full health (%.0f)" % float(door.hp))
			_check(not bool(_game.structures[_door_id].get("open", true)), "a new door starts shut")
			_GA.toggle_door(1, _door_id)
			_check(bool(_game.structures[_door_id].open), "using the door opens it")
			_GA.toggle_door(1, _door_id)
			_check(not bool(_game.structures[_door_id].open), "using it again shuts it")
			_check("brick_door" in _GA.DOOR_KINDS and "brick_half" in _GA.EDGE_KINDS and "brick_half" not in _GA.WALL_KINDS, "doors are edge pieces that count as walls; half walls are edges only")
			# Tools on a finished wood piece: a pickaxe can't break it, a hatchet can; the hammer repairs it for
			# materials; knocked down, it gives back half its cost.
			var inv2 = _game.inventory_of(1)
			inv2.add("pickaxe_t1", 1, true)
			inv2.add("hatchet_t1", 1, true)
			inv2.select(_slot_of(inv2, "pickaxe_t1"))
			_check(not _GA.hit_structure(1, _door_id).get("ok", true), "a pickaxe can't knock down a wood piece")
			inv2.select(_slot_of(inv2, "hatchet_t1"))
			var hit: Dictionary = _GA.hit_structure(1, _door_id)
			_check(hit.get("ok", false) and float(_game.structures[_door_id].hp) < float(_GA.MAT_HP.wood), "a hatchet damages it (%.0f left)" % float(_game.structures[_door_id].hp))
			var hp_hurt: float = float(_game.structures[_door_id].hp)
			inv2.add("plank", 10, true)
			var planks: int = inv2.count("plank")
			inv2.select(_slot_of(inv2, "hammer"))
			var fix: Dictionary = _GA.hit_structure(1, _door_id)
			_check(fix.get("repaired", false) and float(_game.structures[_door_id].hp) > hp_hurt and inv2.count("plank") < planks,
				"the hammer repairs it and takes planks (%.0f hp, %d planks used)" % [float(_game.structures[_door_id].hp), planks - inv2.count("plank")])
			inv2.select(_slot_of(inv2, "hatchet_t1"))
			planks = inv2.count("plank")
			for i in 40:
				if not _game.structures.has(_door_id):
					break
				_GA.hit_structure(1, _door_id)
			_check(not _game.structures.has(_door_id), "enough hatchet hits knock it down")
			_check(inv2.count("plank") - planks == 3, "it gives back half its planks (%d)" % (inv2.count("plank") - planks))
			# An unfinished blueprint comes down to any hit but the hammer's.
			var stairs_id := ""
			for id: String in _game.structures:
				if _game.structures[id].kind == "brick_stairs":
					stairs_id = id
			_check(stairs_id != "" and _GA.is_blueprint(_game.structures[stairs_id]), "the stairs are still a blueprint")
			_check(_GA.hit_structure(1, stairs_id).get("removed", false) and not _game.structures.has(stairs_id), "a hatchet takes a blueprint down")
			_step = 4
		4:
			_check(_GA.is_building("stone_roof") and _GA.is_building("stone_stairs") and _GA.is_building("brick_floor"), "every material variant is a building piece")
			_check(_GA.PIECES.size() == 24, "24 building pieces (%d)" % _GA.PIECES.size())
			_step = 5
		5:
			# Stations on floors: a workbench stands on a finished foundation, not sunk into one from the ground, not
			# against a wall, and the floor can't be knocked down from under it.
			var cell := Vector3.INF
			for k in 60:
				var cand: Vector3 = _spot + Vector3((k % 6 - 3) * 3.0, 0, 9.0 + (k / 6) * 3.0)
				cand.y = _game.world_gen.get_height(cand.x, cand.z)
				if _Terrain.tree_near(cand, 5.0) == null and cand.y > 2.0 and _GA.placement_problem(_GA.snap_piece("foundation", cand).pos, "foundation", 0.0) == "":
					cell = cand
					break
			_check(cell != Vector3.INF, "found a clear cell for the station checks")
			if cell == Vector3.INF:
				return _finish()
			var fs: Dictionary = _GA.snap_piece("foundation", cell)
			var laid: Dictionary = _GA.place_blueprint(1, "foundation", fs.pos, 0.0)
			_check(laid.ok, "a foundation for the workbench")
			_Terrain.commit(_Terrain.level_ground(fs.pos, 1.5, 1.5, 0.0, fs.pos.y))
			var not_built: String = _GA.placement_problem(fs.pos + Vector3(0.2, _GA.FLOOR_TOP, 0.1), "workbench")
			_check(not_built != "", "a workbench can't stand on a blueprint: %s" % not_built)
			_build(String(laid.id))
			var top: Vector3 = fs.pos + Vector3(0.2, _GA.FLOOR_TOP, 0.1)
			var on_top: String = _GA.placement_problem(top, "workbench")
			_check(on_top == "", "a workbench can stand on a finished foundation (%s)" % on_top)
			var inv = _game.inventory_of(1)
			inv.add("workbench", 1, true)
			var placed: Dictionary = _GA.place_structure(1, _slot_of(inv, "workbench"), top, 0.0)
			_check(placed.get("ok", false), "the workbench is placed on the foundation")
			var under: String = _GA.removal_problem(_game.structures[String(laid.id)])
			_check(under.begins_with("Pack up"), "the foundation can't be knocked down from under it: %s" % under)
			var sunk := Vector3(fs.pos.x + 0.6, _game.world_gen.get_height(fs.pos.x + 0.6, fs.pos.z), fs.pos.z)
			var sunk_problem: String = _GA.placement_problem(sunk, "forge")
			_check(sunk_problem != "", "a station on the ground inside a slab is refused: %s" % sunk_problem)
			var ws: Dictionary = _GA.snap_piece("wall", fs.pos + Vector3(0, 0.5, -1.4))
			var wall: Dictionary = _GA.place_blueprint(1, "wall", ws.pos, ws.yaw)
			_check(wall.ok, "a wall on the foundation's edge")
			var near: Array = _GA.stations_near(fs.pos)
			_check(near == ["workbench"], "only stations count as nearby, not building pieces: %s" % str(near))
			var by_wall: String = _GA.placement_problem(fs.pos + Vector3(-0.9, _GA.FLOOR_TOP, -1.2), "campfire")
			_check(by_wall.contains("wall") or by_wall.contains("Too close"), "a station against a wall is refused: %s" % by_wall)
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
		var clear := _Terrain.tree_near(cand, 6.0) == null
		clear = clear and _Terrain.tree_near(cand + Vector3(3.0, 0, 0), 6.0) == null
		if clear and _game.world_gen.get_height(cand.x, cand.z) > 2.0 and _game.world_gen.get_height(cand.x + 3.0, cand.z) > 2.0:
			return cand
	return spot


func _slot_of(inv, id: String) -> int:
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

## Finish a blueprint the way a player does: a hammer in hand and the materials in the pack, hit until it's built.
func _build(id: String) -> void:
	var inv = _game.inventory_of(1)
	var st: Dictionary = _game.structures[id]
	for item: String in _GA.PIECE_COSTS[st.kind]:
		inv.add(item, int(_GA.PIECE_COSTS[st.kind][item]), true)
	if inv.count("hammer") < 1:
		inv.add("hammer", 1, true)
	var keep: int = inv.selected
	inv.select(_slot_of(inv, "hammer"))
	for i in 20:
		if not _GA.is_blueprint(_game.structures[id]):
			break
		_GA.hit_structure(1, id)
	inv.select(keep)
