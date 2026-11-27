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
var all_frames: Array = []
var busy_proc := 0.0
var busy_phys := 0.0
var busy_n := 0
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
			p.set_physics_process(OS.get_environment("PHYS") != "")
			# OFF=wildlife,ui,caves,atmo,music,structures: switch a system off, to see what it costs per frame.
			for sys in OS.get_environment("OFF").split(","):
				var n: Node = null
				match sys:
					"wildlife": n = main.get_node_or_null("Wildlife")
					"caves": n = main.get_node_or_null("CaveFeatures")
					"atmo": n = main.get_node_or_null("Atmosphere")
					"structures": n = main.get_node_or_null("Structures")
					"music": n = root.get_node_or_null("Music")
					"ui":
						for c in main.get_children():
							if c is CanvasLayer:
								n = c
				if n:
					n.process_mode = Node.PROCESS_MODE_DISABLED
					print("WALK off ", sys)
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
		busy_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		busy_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		busy_n += 1
		var gw = root.get_node("Game").world_gen
		all_frames.append([ms, f, Vector2i(int(pos.x), int(pos.z)), gw.BIOME_NAMES[gw.get_biome(pos.x, pos.z)]])
		if ms > 33.0:
			var g = root.get_node("Game").world_gen
			notes.append("frame %d: %.1f ms at %s (%s%s)" % [f, ms, Vector2i(int(pos.x), int(pos.z)), g.BIOME_NAMES[g.get_biome(pos.x, pos.z)], ", in a cave" if root.get_node("Game").in_cave else ""])
	last_us = now
	# MON=1: leak watch. Activity as in play (hit effects, panels, saves) and counts logged as it goes.
	if OS.get_environment("MON") != "":
		if f % 30 == 0:
			var E = load("res://scripts/gameplay/effects.gd")
			var at := pos + dir * 2.0
			at.y = root.get_node("Game").world_gen.get_height(at.x, at.z) + 1.0
			E.splinters(main, at, Color(0.8, 0.6, 0.4), Color(0.4, 0.3, 0.2), 10, 1.0, pos - at)
			E.shards(main, at, Color(0.6, 0.6, 0.6), 13, pos - at)
		if f % 400 == 0:
			main._toggle_journal(true)
			main._toggle_map(true)
		if f % 400 == 20:
			main._toggle_journal(false)
			main._toggle_map(false)
		if f % 1000 == 0:
			main.save_now()
			print("WALK mon f %d nodes %d orphans %d objects %d resources %d mem %.1f MB animals %d chunks %d" % [f,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, main.get_node("Wildlife")._animals.size(), main.get_node("World").get_chunk_count()])
	if f == 600:
		var t0 := Time.get_ticks_usec()
		main.save_now()
		print("WALK save took %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		last_us = Time.get_ticks_usec()
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
		var pd: Dictionary = Engine.get_meta("prof", {})
		var keys := pd.keys()
		keys.sort_custom(func(a, b) -> bool: return pd[a] > pd[b])
		for k in keys:
			print("WALK prof %-45s %.3f ms/frame" % [k, pd[k] / 1000.0 / maxf(f, 1)])
		print("WALK busy: process %.2f ms  physics %.2f ms (mean per frame)" % [busy_proc / maxf(busy_n, 1), busy_phys / maxf(busy_n, 1)])
		for line: String in notes:
			print("WALK slow ", line)
		all_frames.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for i in mini(15, all_frames.size()):
			print("WALK top %.1f ms frame %d at %s (%s)" % all_frames[i])
		quit()
		return true
	return false
