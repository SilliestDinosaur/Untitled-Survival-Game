extends SceneTree
## Base building test: godot --headless --path . -s tests/build_test.gd
## Places foundations and walls: grid snapping, walls need a foundation edge, foundations
## level the ground, and nothing can be placed on top of another piece.

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
				_main.create_world("Build Test", 909)
			if _main.state == _main.State.PLAYING:
				_spot = _game.world_gen.find_spawn_point()
				_spot.x = floorf(_spot.x / 2.0) * 2.0 + 1.0   # centre of a grid cell
				_spot.z = floorf(_spot.z / 2.0) * 2.0 + 1.0
				_spot.y = _game.world_gen.get_height(_spot.x, _spot.z)
				_game.inventory_of(1).add("foundation", 2, true)
				_game.inventory_of(1).add("wall", 2, true)
				_step = 1
				_f = 0
		1:
			var snap: Dictionary = _GA.snap_piece("foundation", _spot + Vector3(0.4, 0, 0.3))
			_check(snap.pos.distance_to(_spot) < 0.01, "foundation snaps to the cell centre")
			var problem: String = _GA.placement_problem(snap.pos, "foundation", 0.0)
			_check(problem == "", "foundation is allowed here (%s)" % problem)
			var inv: Inventory = _game.inventory_of(1)
			var slot := _slot_of(inv, "foundation")
			var placed: Dictionary = _GA.place_structure(1, slot, snap.pos, 0.0)
			_check(placed.ok, "foundation placed")
			if placed.ok:
				var lev: Dictionary = _Terrain.apply({"mode": _Terrain.Mode.FLATTEN, "x": snap.pos.x, "z": snap.pos.z, "r": 2.2, "s": 1.0, "target": snap.pos.y}, inv)
				_Terrain.commit(lev.cells)
				var h_corner: float = _game.world_gen.get_height(snap.pos.x + 0.9, snap.pos.z + 0.9)
				_check(absf(h_corner - snap.pos.y) < 0.25, "ground under the slab is levelled (corner %.2f vs %.2f)" % [h_corner, snap.pos.y])
			_step = 2
		2:
			var edge: Vector3 = _spot + Vector3(1.0, 0, 0)       # east edge of the slab
			var wsnap: Dictionary = _GA.snap_piece("wall", edge + Vector3(0.2, 0, 0.1))
			_check(absf(wsnap.pos.x - (_spot.x + 1.0)) < 0.01 and absf(wsnap.yaw - PI * 0.5) < 0.01, "wall snaps to the east edge")
			var problem: String = _GA.placement_problem(wsnap.pos, "wall", wsnap.yaw)
			_check(problem == "", "wall on a foundation edge is allowed (%s)" % problem)
			var wall_slot := _slot_of(_game.inventory_of(1), "wall")
			var placed: Dictionary = _GA.place_structure(1, wall_slot, wsnap.pos, wsnap.yaw)
			_check(placed.ok, "wall placed")
			# A wall out in the open (no foundation) is refused.
			var far := _spot + Vector3(40, 0, 40)
			far.y = _game.world_gen.get_height(far.x, far.z)
			var far_snap: Dictionary = _GA.snap_piece("wall", far)
			var far_problem: String = _GA.placement_problem(far_snap.pos, "wall", far_snap.yaw)
			_check(far_problem != "", "floating wall is refused: %s" % far_problem)
			# The same spot again is refused.
			var again: String = _GA.placement_problem(wsnap.pos, "wall", wsnap.yaw)
			_check(again != "", "a second wall in the same place is refused: %s" % again)
			var dup: String = _GA.placement_problem(_spot, "foundation", 0.0)
			_check(dup != "", "a second foundation in the same cell is refused: %s" % dup)
			_step = 3
		3:
			_check(_game.structures.size() >= 2, "both pieces are in the world (%d)" % _game.structures.size())
			return _finish()
	return false


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
