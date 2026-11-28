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
var draws: Array = []   # DRAW=1 (needs a real render, under xvfb-run): [draw calls, objects, primitives, where] per frame


## Marks taken at the start and end of each frame's process and physics steps (nodes that run first and last), so a
## slow frame shows which part of the frame it was in.
class Mark extends Node:
	var key := ""
	var physics := false
	func _process(_d: float) -> void:
		if not physics:
			Engine.set_meta(key, Time.get_ticks_usec())
	func _physics_process(_d: float) -> void:
		if physics:
			var acc: int = Engine.get_meta(key + "_acc", 0)
			if key.ends_with("end"):
				Engine.set_meta("phys_acc", int(Engine.get_meta("phys_acc", 0)) + Time.get_ticks_usec() - int(Engine.get_meta("phys_start", 0)))
			else:
				Engine.set_meta(key, Time.get_ticks_usec())


func _add_marks() -> void:
	for spec in [["proc_start", false, -100000], ["proc_end", false, 100000], ["phys_start", true, -100000], ["phys_end", true, 100000]]:
		var m := Mark.new()
		m.key = spec[0]
		m.physics = spec[1]
		m.process_priority = spec[2]
		m.process_physics_priority = spec[2]
		root.add_child.call_deferred(m)


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_add_marks()


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
		var proc_ms := (int(Engine.get_meta("proc_end", 0)) - int(Engine.get_meta("proc_start", 0))) / 1000.0
		var phys_ms := int(Engine.get_meta("phys_acc", 0)) / 1000.0
		Engine.set_meta("phys_acc", 0)
		all_frames.append([ms, Engine.get_process_frames(), Vector2i(int(pos.x), int(pos.z)), gw.BIOME_NAMES[gw.get_biome(pos.x, pos.z)], proc_ms, phys_ms])
		if ms > 33.0:
			var g = root.get_node("Game").world_gen
			notes.append("frame %d: %.1f ms at %s (%s%s)" % [f, ms, Vector2i(int(pos.x), int(pos.z)), g.BIOME_NAMES[g.get_biome(pos.x, pos.z)], ", in a cave" if root.get_node("Game").in_cave else ""])
	last_us = now
	if OS.get_environment("DRAW") != "" and f > 60:
		draws.append([Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Vector2i(int(pos.x), int(pos.z))])
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
		if not draws.is_empty():
			var sum := [0.0, 0.0, 0.0]
			for d: Array in draws:
				for k in 3:
					sum[k] += float(d[k])
			print("WALK draw calls mean %.0f  objects %.0f  primitives %.0fk" % [sum[0] / draws.size(), sum[1] / draws.size(), sum[2] / draws.size() / 1000.0])
			draws.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
			for i in mini(5, draws.size()):
				print("WALK most draws %d  objects %d  primitives %dk at %s" % [draws[i][0], draws[i][1], int(draws[i][2] / 1000), draws[i][3]])
			draws.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
			for i in mini(3, draws.size()):
				print("WALK most primitives %dk  draws %d at %s" % [int(draws[i][2] / 1000), draws[i][0], draws[i][3]])
		for line: String in notes:
			print("WALK slow ", line)
		all_frames.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for i in mini(15, all_frames.size()):
			print("WALK top %.1f ms frame %d at %s (%s)  process %.1f  physics %.1f" % all_frames[i])
		quit()
		return true
	return false
