extends SceneTree
## World size per world: godot --headless --path . -s tests/size_test.gd
## New worlds are 3 km; a save from before the island grew (no "world_size") loads as the 2 km world it was, and
## its terrain comes out exactly as before; a 3 km save loads as 3 km; a guest joining gets the host's size; the
## explored grid and the map follow the size.

var _g: Node
var _f := 0
var _fails: Array[String] = []
var _SM: GDScript


func _initialize() -> void:
	_SM = load("res://scripts/core/save_manager.gd")
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_g = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	var seed_value := 4242
	# A new world: 3 km.
	_g.new_world(seed_value)
	_check(_g.WORLD_SIZE == _g.NEW_WORLD_SIZE and _g.WORLD_SIZE == 3072.0, "a new world is 3 km (%d)" % _g.WORLD_SIZE)
	_check(_g.explored.size() == int(3072 / _g.EXPLORE_CELL) ** 2, "its explored grid covers 3 km")
	var h3: float = _g.world_gen.get_height(700.0, 900.0)
	var snap: Dictionary = _g.snapshot()
	_check(float(snap.get("world_size", 0)) == 3072.0, "the snapshot a guest gets carries the size")
	# The same seed at 2 km, as an old world.
	_g.new_world(seed_value, 2048.0)
	var h2: float = _g.world_gen.get_height(700.0, 900.0)
	_check(_g.WORLD_SIZE == 2048.0, "an old world is 2 km")
	_check(absf(h3 - h2) > 0.001, "the two sizes are different islands (%.2f vs %.2f)" % [h2, h3])
	# An old save, with no size in it, loads as 2 km, with the same ground as an old 2 km world of its seed.
	var old_id: String = _SM.create(seed_value, "Size Test Old")
	var data: Dictionary = _SM.read(old_id)
	data.erase("world_size")
	_SM.write(old_id, data)
	_g.new_world(seed_value)   # (start from a 3 km world, to be sure loading changes it)
	_g.load_save(old_id)
	_check(_g.WORLD_SIZE == 2048.0, "an old save (no size in it) loads as 2 km (%d)" % _g.WORLD_SIZE)
	_check(absf(_g.world_gen.get_height(700.0, 900.0) - h2) < 0.001, "and its ground is what it always was")
	_check(_g.explored.size() == int(2048 / _g.EXPLORE_CELL) ** 2, "and its explored grid is 2 km's")
	# A 3 km save keeps its size.
	_g.new_world(seed_value)
	var new_id: String = _SM.create(seed_value, "Size Test New")
	_g.save_id = new_id
	_g.write_save({})
	_check(float(_SM.read(new_id).get("world_size", 0)) == 3072.0, "a 3 km world saves its size")
	_g.new_world(seed_value, 2048.0)
	_g.load_save(new_id)
	_check(_g.WORLD_SIZE == 3072.0, "and loads back as 3 km (%d)" % _g.WORLD_SIZE)
	# A guest becomes a copy of the host's world, size and all.
	_g.new_world(seed_value)
	_g.apply_snapshot(snap)
	_check(_g.WORLD_SIZE == 3072.0, "a guest gets the host's 3 km world")
	var old_snap := snap.duplicate()
	old_snap.erase("world_size")
	_g.apply_snapshot(old_snap)
	_check(_g.WORLD_SIZE == 2048.0, "an older host's snapshot (no size) makes a 2 km world")
	_SM.delete(old_id)
	_SM.delete(new_id)
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	quit()
	return true


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)
