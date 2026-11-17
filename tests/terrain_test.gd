extends SceneTree
## Ground levelling test: godot --headless --path . -s tests/terrain_test.gd
## Placed foundations level the ground under them (up and down), blend out at the rim, leave the
## rest of the island alone, and walls only cut away ground above them. The edit list survives a
## round trip through its save format.

var TerrainEditScript: GDScript
var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _p := Vector3.ZERO
var _h0 := 0.0


func _initialize() -> void:
	TerrainEditScript = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Terrain Test", 555)
			if _main.state == _main.State.PLAYING:
				_p = _game.world_gen.find_spawn_point()
				_h0 = _game.world_gen.get_height(_p.x, _p.z)
				_next(1)
		1:   # a foundation levels the ground up to its height
			var target := _h0 + 2.0
			var cells: Array = TerrainEditScript.level_ground(Vector3(_p.x, target, _p.z), 1.5, 1.5, 0.0, target)
			_check(cells.size() > 0, "levelling changes the ground (%d cells)" % cells.size())
			TerrainEditScript.commit(cells)
			var centre: float = _game.world_gen.get_height(_p.x, _p.z)
			_check(absf(centre - target) < 0.05, "centre is levelled to %.2f (got %.2f)" % [target, centre])
			var corner: float = _game.world_gen.get_height(_p.x + 1.0, _p.z + 1.0)
			_check(absf(corner - target) < 0.05, "footprint corner is levelled (%.2f)" % corner)
			_next(2)
		2:   # the rim blends: between the two heights, not a cliff
			var rim: float = _game.world_gen.get_height(_p.x + 2.4, _p.z)
			var lo := minf(_h0, _h0 + 2.0) - 0.05
			var hi := maxf(_h0, _h0 + 2.0) + 0.05
			_check(rim >= lo and rim <= hi, "rim blends between the heights (%.2f)" % rim)
			_next(3)
		3:   # well outside the footprint, nothing changed
			var far := Vector2(_p.x + 8.0, _p.z + 8.0)
			var base: float = _game.world_gen.get_base_height(far.x, far.y)
			var now: float = _game.world_gen.get_height(far.x, far.y)
			_check(absf(now - base) < 0.001, "ground outside the footprint is untouched")
			_next(4)
		4:   # a foundation can also sit lower than the ground around it (fill, then cut)
			var target := _h0 - 1.5
			TerrainEditScript.commit(TerrainEditScript.level_ground(Vector3(_p.x, target, _p.z), 1.5, 1.5, 0.0, target))
			var centre: float = _game.world_gen.get_height(_p.x, _p.z)
			_check(absf(centre - target) < 0.05, "levelling down works (%.2f, wanted %.2f)" % [centre, target])
			_next(5)
		5:   # walls only cut ground that rises above their base
			var top := _h0 + 1.0
			TerrainEditScript.commit(TerrainEditScript.level_ground(Vector3(_p.x, top, _p.z), 1.5, 1.5, 0.0, top))
			var y := top - 1.0
			var cut: Array = TerrainEditScript.clear_rect(Vector3(_p.x, y, _p.z), 1.5, 0.25, 0.0, y)
			TerrainEditScript.commit(cut)
			# Check the grid cell the wall stands on (the cut works on whole metres).
			var h: float = _game.world_gen.get_height(roundf(_p.x), roundf(_p.z))
			_check(h <= y + 0.02, "wall clearance cut the ground down to %.2f (got %.2f)" % [y, h])
			_next(6)
		6:   # the edit list survives its save format
			var edits: Dictionary = _game.world_gen.edits
			var back: Dictionary = TerrainEditScript.from_list(TerrainEditScript.to_list(edits))
			_check(back.size() == edits.size(), "edit list round-trips (%d cells)" % back.size())
			var same := true
			for k: Vector2i in edits:
				if not back.has(k) or absf(float(back[k]) - float(edits[k])) > 0.0001:
					same = false
			_check(same, "every edit keeps its height change")
			return _finish()
	return false


func _next(s: int) -> void:
	_step = s
	_f = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
