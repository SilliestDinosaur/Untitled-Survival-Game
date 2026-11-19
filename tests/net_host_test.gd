extends SceneTree
## Multiplayer test, host side. Run together with net_client_test.gd:
##   godot --headless --path . -s tests/net_host_test.gd &
##   godot --headless --path . -s tests/net_client_test.gd
## The host opens a world; the client joins, gathers, crafts and places a campfire, builds (a foundation and a
## door, opened), hunts and cooks; then the host checks that the changes reached its world and that the guest's
## character was kept. tests/tools/run_net_test.sh runs the pair (LAG=ms puts a lag relay between them).

var _main: Node
var _game: Node
var _net: Node
var _phase := "load"
var _frames := 0
var _wait_from := 0   ## when the host started waiting for its guest (msec)
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
				_phase = "relay" if _net.relay_server() != "" else "wait"
				_frames = 0
				_wait_from = Time.get_ticks_msec()
		"relay":   # with a meeting server: wait for this game's code on it, for the guest to join by
			if _net.relay_state == "ok":
				print("HOST relay code: ", _net.relay_code)
				_phase = "wait"
				_frames = 0
				_wait_from = Time.get_ticks_msec()
			elif _net.relay_state == "failed" or _frames > 60 * 30:
				_check(false, "registered with the meeting server")
				return _finish()
		"wait":
			if not _net.players.is_empty():
				if not _client_seen:
					print("HOST guest joined: ", _net.players.values()[0].name)
				_client_seen = true
			elif _client_seen:
				_phase = "check"
			# Real seconds (headless frames can run faster than real time); NET_HOST_WAIT for a guest that starts
			# a while later (on another machine).
			var wait_s := float(OS.get_environment("NET_HOST_WAIT")) if OS.get_environment("NET_HOST_WAIT") != "" else 240.0
			if Time.get_ticks_msec() - _wait_from > int(wait_s * 1000.0):
				_check(false, "client never finished")
				return _finish()
		"check":
			_check(_game.structures.size() >= 1, "guest's campfire is in the host's world: %d" % _game.structures.size())
			_check(_game.removed_resources.size() >= 1, "guest's gathering reached the host: %d removed" % _game.removed_resources.size())
			_check(_game.guests.size() == 1, "guest's character kept for next time: %d" % _game.guests.size())
			if not _game.guests.is_empty():
				var g: Dictionary = _game.guests.values()[0]
				_check(g.has("inventory") and g.has("pos"), "guest save has inventory and position")
				_check(str(g.get("inventory", {})).contains("cooked_meat"), "the meat the guest cooked is in their saved pack")
			var GA: GDScript = load("res://scripts/core/game_actions.gd")
			var built_floor := false
			var open_door := false
			for st: Dictionary in _game.structures.values():
				if st.kind == "foundation" and not GA.is_blueprint(st):
					built_floor = true
				if st.kind == "wood_door" and not GA.is_blueprint(st) and bool(st.get("open", false)):
					open_door = true
			_check(built_floor, "the foundation the guest built stands, finished, in the host's world")
			_check(open_door, "the door the guest built and opened is open in the host's world")
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
