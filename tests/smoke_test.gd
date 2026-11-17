extends SceneTree
## Headless smoke test: godot --headless --path . -s tests/smoke_test.gd
## Title -> loading -> playing, walks forward, checks the world and player are sane.

var _main: Node
var _frames := 0
var _start_pos := Vector3.ZERO
var _phase := "title"
var _t0 := 0

func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_t0 = Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	_frames += 1
	var player = _main.get_node("Player")
	var world = _main.get_node("World")
	match _phase:
		"title":
			if _frames == 30:
				_main.create_world("Test World", 629946553)
				_phase = "loading"
		"loading":
			if _main.state == _main.State.PLAYING:
				print("loaded in %d frames, %d ms" % [_frames - 30, Time.get_ticks_msec() - _t0])
				_start_pos = player.global_position
				Input.action_press("move_forward")
				Input.action_press("sprint")
				_phase = "walking"
				_frames = 0
			elif _frames > 3000:
				print("RESULT: FAIL (never finished loading)")
				return true
		"walking":
			if _frames >= 360:
				return _report(player, world)
	return false

func _report(player, world) -> bool:
	var counts := {}
	for c in world.get_children():
		if "resources" in c:
			for r in c.resources:
				counts[r.kind] = counts.get(r.kind, 0) + 1
	var game = root.get_node("Game")
	print("world: ", game.world_name, " seed ", game.world_seed, " exotic=", game.palette.exotic)
	print("spawn: ", player.spawn_point, "  now: ", player.global_position, "  on_floor: ", player.is_on_floor(), " swimming: ", player.swimming)
	print("moved: %.1f m" % player.global_position.distance_to(_start_pos))
	print("chunks: ", world.get_chunk_count(), "  resources: ", counts)
	print("stamina: %.1f  hunger: %.2f  health: %.1f" % [player.stats.stamina, player.stats.hunger, player.stats.health])
	# The ground under and around the player is loaded at full detail (the total chunk count depends on how far streaming got in the frame budget).
	var ok: bool = (player.is_on_floor() or player.swimming) and player.global_position.distance_to(_start_pos) > 10.0 and world.is_area_ready(player.global_position, 1)
	SaveManager.delete(root.get_node("Game").save_id)
	print("RESULT: ", "PASS" if ok else "FAIL")
	return true
