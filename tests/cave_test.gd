extends SceneTree
## Cave test: godot --headless --path . -s tests/cave_test.gd
## Finds the entrances, goes down, checks the cave is built and the player is inside it, comes back
## up, and checks that a game saved underground reloads at the entrance.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _CavesScript: GDScript


func _initialize() -> void:
	_CavesScript = load("res://scripts/world/caves.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Cave Test", 6161)
			if _main.state == _main.State.PLAYING:
				var spots: Array = _CavesScript.entrances(_game.world_gen)
				_check(spots.size() >= 1, "the island has cave entrances (%d)" % spots.size())
				_check(_main._mouths.get_child_count() == spots.size(), "each entrance has a visible mouth")
				var pts: Array = []
				for m: Node3D in _main._mouths.get_children():
					pts.append(m.position)
				var net: Dictionary = _CavesScript.network(pts)
				_check(net.roots.size() == pts.size(), "every entrance drops into the network")
				_check(net.nodes.size() >= 60 and net.rooms.size() >= 2, "the network has tunnels and chambers (%d nodes, %d chambers)" % [net.nodes.size(), net.rooms.size()])
				_check(net.edges.size() >= net.nodes.size() - 1, "the network is connected by its edges (%d edges)" % net.edges.size())
				_main.enter_cave(0)
				_step = 1
				_f = 0
		1:
			if _game.in_cave or _f > 300:
				_check(_game.in_cave, "entering takes you underground")
				var p = _main.get_node("Player")
				_check(p.global_position.y < _CavesScript.CAVE_Y + 20.0 and p.global_position.y > _CavesScript.CAVE_Y - 20.0, "the player is in the cave (y %.1f)" % p.global_position.y)
				_check(_main.get_node_or_null("Underground") != null, "the underground scene exists")
				_check(not p.swimming and not p.underwater, "underground is not treated as water")
				_step = 2
				_f = 0
		2:
			if _f == 60:
				_main.leave_cave()
				_step = 3
				_f = 0
		3:
			if not _game.in_cave and _f > 5 and not _main._fading:
				var p = _main.get_node("Player")
				_check(p.global_position.y > 0.0, "back up on the surface (y %.1f)" % p.global_position.y)
				_step = 4
				_f = 0
		4:
			if _f == 2 and not _game.in_cave and not _main._fading:
				_main.enter_cave(0)
			if _game.in_cave and _f > 60:
				_main.save_now()
				_check(_game.save_id != "", "saved underground")
				var id: String = _game.save_id
				_main._to_title()
				_main.load_world(id)
				_step = 5
				_f = 0
		5:
			if _main.state == _main.State.PLAYING or _f > 900:
				_check(not _game.in_cave, "a game saved in a cave reloads at the entrance")
				var p = _main.get_node("Player")
				_check(p.global_position.y > 0.0, "and on the surface (y %.1f)" % p.global_position.y)
				return _finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
