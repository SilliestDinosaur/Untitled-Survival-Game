extends SceneTree
## Multiplayer test, host side. Run together with net_client_test.gd:
##   godot --headless --path . -s tests/net_host_test.gd &
##   godot --headless --path . -s tests/net_client_test.gd
## The host opens a world; the client joins, gathers, crafts and places a campfire; then the
## host checks that the changes reached its world and that the guest's character was kept.

var _main: Node
var _game: Node
var _net: Node
var _phase := "load"
var _frames := 0
var _fails: Array[String] = []
var _client_seen := false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")
	_net = root.get_node("Net")
	_net.use_upnp = false


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		"load":
			if _frames == 5:
				_main.create_world("Net Test", 424242)
			if _main.state == _main.State.PLAYING:
				_check(_net.host(), "hosting")
				print("HOST lan code: ", _net.lan_code)
				_phase = "wait"
				_frames = 0
		"wait":
			if not _net.players.is_empty():
				if not _client_seen:
					print("HOST guest joined: ", _net.players.values()[0].name)
				_client_seen = true
			elif _client_seen:
				_phase = "check"
			if _frames > 60 * 240:
				_check(false, "client never finished")
				return _finish()
		"check":
			_check(_game.structures.size() >= 1, "guest's campfire is in the host's world: %d" % _game.structures.size())
			_check(_game.removed_resources.size() >= 1, "guest's gathering reached the host: %d removed" % _game.removed_resources.size())
			_check(_game.guests.size() == 1, "guest's character kept for next time: %d" % _game.guests.size())
			if not _game.guests.is_empty():
				var g: Dictionary = _game.guests.values()[0]
				_check(g.has("inventory") and g.has("pos"), "guest save has inventory and position")
			return _finish()
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("HOST RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	_net.stop()
	return true
