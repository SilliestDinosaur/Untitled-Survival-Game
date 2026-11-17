extends SceneTree
## Map test: godot --headless --path . -s tests/map_test.gd
## Walking uncovers the map around you, what's uncovered is kept in saves, and the map draws the
## island's ground picture.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _MapScript: GDScript


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Map Test", 4242)
			if _main.state == _main.State.PLAYING:
				_MapScript = load("res://scripts/ui/world_map.gd")
				_step = 1
		1:
			# Well away from the spawn point, which is already uncovered when play starts.
			var spot: Vector3 = _game.world_gen.find_spawn_point() + Vector3(400, 0, 400)
			spot.x = clampf(spot.x, 100.0, Game_size() - 100.0)
			spot.z = clampf(spot.z, 100.0, Game_size() - 100.0)
			_check(not _game.is_explored(spot), "a place far from the start is still unexplored")
			_check(_game.reveal(spot), "standing somewhere uncovers the ground around it")
			_check(_game.is_explored(spot), "the spot you stand on is uncovered")
			_check(not _game.reveal(spot), "standing still uncovers nothing new")
			_check(not _game.is_explored(spot + Vector3(300, 0, 0)), "far away is still covered")
			var snap: Dictionary = _game.snapshot()
			_check(String(snap.get("explored", "")) != "", "the uncovered map is in a save")
			var back: PackedByteArray = Marshalls.base64_to_raw(String(snap.explored))
			_check(back.size() == _game.explored.size(), "the saved map is the right size (%d cells)" % back.size())
			_step = 2
		2:
			var m = _MapScript.new()
			m.player = _main.player
			m.reset_for_world()
			# Build the whole picture in one go for the test.
			m._build_ground_rows(10000)
			_check(m._ground_tex != null, "the island's ground picture is drawn")
			m._build_fog()
			_check(m._fog_tex != null, "the fog is drawn")
			m.free()
			return _finish()
	return false


func Game_size() -> float:
	return _game.WORLD_SIZE


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
