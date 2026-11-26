extends SceneTree
## Walk benchmark: the player runs across the island at sprint speed (no teleports), the way someone exploring does,
## while chunks stream in, animals spawn and the ambience changes. Reports frame times and every frame over 33 ms
## (with what was going on). SEED=, FRAMES= (default 2400), SPEED= m/s (default 9).
var main: Node
var f := 0
var started := false
var last_us := 0
var times: Array = []
var notes: Array = []
var pos := Vector3.ZERO
var dir := Vector3.ZERO
var turn := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	if not started:
		if f == 5:
			main.create_world("Walk", int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 629946553)
		if main.state == main.State.PLAYING:
			started = true
			f = 0
			var p: Node3D = main.player
			p.set_physics_process(false)
			pos = p.global_position
			dir = (Vector3(1024, 0, 1024) - pos)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 1.0 else Vector3(1, 0, 0)
			# Let the start area settle first (as a loading screen would).
			for k in 90:
				pass
		return false
	var now := Time.get_ticks_usec()
	if last_us > 0 and f > 60:
		var ms := (now - last_us) / 1000.0
		times.append(ms)
		if ms > 33.0:
			var g = root.get_node("Game").world_gen
			notes.append("frame %d: %.1f ms at %s (%s%s)" % [f, ms, Vector2i(int(pos.x), int(pos.z)), g.BIOME_NAMES[g.get_biome(pos.x, pos.z)], ", in a cave" if root.get_node("Game").in_cave else ""])
	last_us = now
	# Walk on, wandering a little; turn back in from the coast.
	var speed := float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 9.0
	var g2 = root.get_node("Game").world_gen
	turn = clampf(turn + randf_range(-0.03, 0.03), -0.02, 0.02)
	dir = dir.rotated(Vector3.UP, turn)
	var ahead := pos + dir * 30.0
	if g2.get_height(ahead.x, ahead.z) < 1.0:
		dir = dir.rotated(Vector3.UP, 0.12)
	pos += dir * speed / 60.0
	pos.y = maxf(g2.get_height(pos.x, pos.z), g2.water_level(pos.x, pos.z)) + 1.7
	main.player.global_position = pos
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 2400
	if f >= frames:
		var s := times.duplicate()
		s.sort()
		var n := s.size()
		var mean := 0.0
		for t: float in s:
			mean += t
		mean /= maxf(n, 1)
		print("WALK frames %d  mean %.2f ms  p50 %.2f  p95 %.2f  p99 %.2f  worst %.2f  over 33 ms: %d  over 50 ms: %d" % [n, mean, s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], s.filter(func(t: float) -> bool: return t > 33.0).size(), s.filter(func(t: float) -> bool: return t > 50.0).size()])
		for line: String in notes:
			print("WALK slow ", line)
		quit()
		return true
	return false
