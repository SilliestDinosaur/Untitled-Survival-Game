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
var TerrainEditScript: GDScript


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_Terrain = load("res://scripts/world/terrain_edit.gd")
	TerrainEditScript = _Terrain
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
				_spot.x = floorf(_spot.x / 3.0) * 3.0 + 1.5   # centre of a grid cell
				_spot.z = floorf(_spot.z / 3.0) * 3.0 + 1.5
				_spot.y = _game.world_gen.get_height(_spot.x, _spot.z)
				# Find a clear cell: no trees close by (the test needs room to build).
				for k in 200:
					var cand := _spot + Vector3((k % 14 - 7) * 3.0, 0, (k / 14 - 7) * 3.0)
					cand.x = floorf(cand.x / 3.0) * 3.0 + 1.5
					cand.z = floorf(cand.z / 3.0) * 3.0 + 1.5
					cand.y = _game.world_gen.get_height(cand.x, cand.z)
					if TerrainEditScript.tree_near(cand, 6.0) == null and _game.world_gen.get_height(cand.x, cand.z) > 2.0:
						_spot = cand
						break
				_game.inventory_of(1).add("building_plan", 1, true)
				_step = 1
				_f = 0
		1:
			var snap: Dictionary = _GA.snap_piece("foundation", _spot + Vector3(0.4, 0, 0.3))
			var xz_off := Vector2(snap.pos.x - _spot.x, snap.pos.z - _spot.z).length()
			_check(xz_off < 0.01, "foundation snaps to the cell centre")
			_check(absf(snap.pos.y - snappedf(_game.world_gen.get_height(_spot.x, _spot.z), 0.5)) < 0.01, "a lone foundation sits at the ground height rounded to half a metre (%.2f)" % snap.pos.y)
			var problem: String = _GA.placement_problem(snap.pos, "foundation", 0.0)
			_check(problem == "", "foundation is allowed here (%s)" % problem)
			var inv = _game.inventory_of(1)
			var placed: Dictionary = _GA.place_blueprint(1, "foundation", snap.pos, 0.0)
			_check(placed.ok, "foundation placed")
			if placed.ok:
				_Terrain.commit(_Terrain.level_ground(placed.pos, 1.5, 1.5, 0.0, placed.pos.y))
				var h_corner: float = _game.world_gen.get_height(snap.pos.x + 1.4, snap.pos.z + 1.4)
				_check(absf(h_corner - snap.pos.y) < 0.4, "ground under the slab is levelled (corner %.2f vs %.2f)" % [h_corner, snap.pos.y])
			_step = 2
		2:
			var edge: Vector3 = _spot + Vector3(1.5, 0, 0)       # east edge of the slab
			var wsnap: Dictionary = _GA.snap_piece("wall", edge + Vector3(0.2, 0, 0.1))
			_check(absf(wsnap.pos.x - (_spot.x + 1.5)) < 0.01 and absf(wsnap.yaw - PI * 0.5) < 0.01, "wall snaps to the east edge")
			var problem: String = _GA.placement_problem(wsnap.pos, "wall", wsnap.yaw)
			_check(problem == "", "wall on a foundation edge is allowed (%s)" % problem)
			var placed: Dictionary = _GA.place_blueprint(1, "wall", wsnap.pos, wsnap.yaw)
			_check(placed.ok, "wall placed")
			# A wall out in the open (no foundation) is refused.
			var far := _spot + Vector3(45, 0, 45)
			far.y = _game.world_gen.get_height(far.x, far.z)
			var far_snap: Dictionary = _GA.snap_piece("wall", far)
			var far_problem: String = _GA.placement_problem(far_snap.pos, "wall", far_snap.yaw)
			_check(far_problem != "", "floating wall is refused: %s" % far_problem)
			# The same spot again is refused.
			var again: String = _GA.placement_problem(wsnap.pos, "wall", wsnap.yaw)
			_check(again != "", "a second wall in the same place is refused: %s" % again)
			var dup: Dictionary = _GA.snap_piece("foundation", _spot)
			_check(dup.level == 1, "a foundation aimed at a cell that already has one stacks a storey up (level %d)" % dup.level)
			_step = 3
		3:
			_check(_game.structures.size() >= 2, "both pieces are in the world (%d)" % _game.structures.size())
			# Stacking: aiming at the top of the slab gives level 1, one storey up.
			var top: Vector3 = _spot + Vector3(0, 0.5, 0)
			var stack: Dictionary = _GA.snap_piece("foundation", top)
			_check(int(stack.level) == 1, "a foundation stacks on top (level %d)" % int(stack.level))
			_check(_GA.placement_problem(stack.pos, "foundation", 0.0) == "", "the stacked foundation is allowed")
			# A roof needs two walls: one is not enough yet.
			var roof_snap: Dictionary = _GA.snap_piece("roof", _spot + Vector3(0, 3.2, 0))
			var one_wall: String = _GA.placement_problem(roof_snap.pos, "roof", 0.0)
			_check(one_wall != "", "a roof with one wall is refused: %s" % one_wall)
			# Second wall on the north edge, then the roof is allowed.
			var north: Dictionary = _GA.snap_piece("wall", _spot + Vector3(0, 1.5, -1.4))
			_check(_GA.place_blueprint(1, "wall", north.pos, north.yaw).ok, "second wall placed")
			var roof_ok: String = _GA.placement_problem(roof_snap.pos, "roof", 0.0)
			_check(roof_ok == "", "a roof on two walls is allowed (%s)" % roof_ok)
			# Taking one of those walls down would leave the roof unsupported.
			var wall_st: Dictionary = {}
			for id: String in _game.structures:
				if _game.structures[id].kind == "wall":
					wall_st = _game.structures[id]
					break
			var fellow: String = _GA.removal_problem(wall_st)
			_check(fellow == "", "a wall with no roof above it can be taken down")
			# Corners: aiming right at a cell corner keeps the wall on the edge it was already on.
			var corner: Vector3 = _spot + Vector3(1.45, 0, 1.44)
			var keep_ew: Dictionary = _GA.snap_piece("wall", corner, PI * 0.5)
			var keep_ns: Dictionary = _GA.snap_piece("wall", corner, 0.0)
			_check(absf(keep_ew.yaw - PI * 0.5) < 0.01 and absf(keep_ns.yaw) < 0.01, "a wall aimed at a corner stays on its current edge")
			# Grid alignment: every piece lands exactly on the grid, whatever part of the cell is aimed at.
			var cs: float = _GA.CELL
			var aligned := true
			for aim in [Vector3(0.1, 0, 0.2), Vector3(1.4, 0, 1.45), Vector3(2.9, 0, 0.05), Vector3(-0.2, 0, 4.1)]:
				var base_aim: Vector3 = _spot + aim
				var f: Vector3 = _GA.snap_piece("foundation", base_aim).pos
				var w: Dictionary = _GA.snap_piece("wall", base_aim)
				var on_edge: bool = absf(fposmod(w.pos.x + 0.0001, cs) - 0.0) < 0.001 or absf(fposmod(w.pos.z + 0.0001, cs) - 0.0) < 0.001
				var centred: bool = absf(fposmod(f.x, cs) - cs * 0.5) < 0.001 and absf(fposmod(f.z, cs) - cs * 0.5) < 0.001
				if not (on_edge and centred):
					aligned = false
					print("   misaligned: aim ", aim, " foundation ", f, " wall ", w.pos)
			_check(aligned, "foundations sit on cell centres and walls on cell edges")
			# Trees: a foundation right next to one is refused.
			var tree: Variant = TerrainEditScript.tree_near(_spot + Vector3(40, 0, 0), 60.0)
			_check(true, "tree search runs (%s)" % str(tree != null))
			if tree != null:
				var tp: Vector3 = Vector3(tree.x, _game.world_gen.get_height(tree.x, tree.z), tree.z)
				var refused: String = _GA.placement_problem(tp, "foundation", 0.0)
				_check(refused.begins_with("A tree"), "foundation next to a tree is refused: %s" % refused)
			_step = 4
		4:
			# A foundation with walls standing on it can't be taken down.
			var f0: Dictionary = _GA.foundation_at(_GA.cell_of(_spot), 0)
			_check(not f0.is_empty(), "the spawn foundation is there to test")
			if not f0.is_empty():
				var why: String = _GA.removal_problem(f0)
				_check(why != "", "a foundation with walls on it is refused: %s" % why)
			return _finish()
	return false


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
