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
				# The game faces a new player a random way; walk somewhere clear instead, so a tree right in front of
				# the spawn doesn't decide the result.
				player.rotation.y = _clear_heading(player)
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


## A heading with nothing solid in the first 18 m (checked with rays a metre above the ground, 2 m at a time).
func _clear_heading(player) -> float:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var gen = root.get_node("Game").world_gen
	for k in 16:
		var yaw := TAU * k / 16.0
		var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))   # the player's forward (-Z) turned by yaw
		var clear := true
		var p: Vector3 = player.global_position
		for s in 9:
			var q := p + dir * 2.0
			var a := Vector3(p.x, gen.get_height(p.x, p.z) + 1.0, p.z)
			var b := Vector3(q.x, gen.get_height(q.x, q.z) + 1.0, q.z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1, [player.get_rid()]))
			if not hit.is_empty() or gen.get_height(q.x, q.z) < 0.5:
				clear = false
				break
			p = q
		if clear:
			return yaw
	return player.rotation.y
