extends SceneTree
## Benchmark (diagnostic): where the time goes in world creation and in a near chunk.

var _main: Node
var _game: Node
var _f := 0
var _step := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _ms(t: int) -> String:
	return "%.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0)


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Bench", 629946553)
			if _main.state == _main.State.PLAYING:
				_step = 1
		1:
			var pal = _game.palette
			var t := Time.get_ticks_usec()
			var gen = load("res://scripts/world/world_gen.gd").new(629946553, pal)
			print("WorldGen.new (incl. hydrology + cave plan): ", _ms(t))
			t = Time.get_ticks_usec()
			var h = load("res://scripts/world/hydrology.gd").compute(gen)
			print("  Hydrology.compute alone: ", _ms(t))
			t = Time.get_ticks_usec()
			var plan = load("res://scripts/world/caves.gd").plan(gen)
			print("  Caves.plan alone: ", _ms(t))
			t = Time.get_ticks_usec()
			var fl = load("res://scripts/world/flora_library.gd").new(629946553, pal)
			print("FloraLibrary.new (all meshes): ", _ms(t))
			var cg = load("res://scripts/world/chunk_generator.gd")
			var tv = load("res://scripts/world/terrain_edit.gd")
			var gamegen: Object = _game.world_gen
			var coord := Vector2i(10, 10)
			var origin := Vector3(640, 0, 640)
			var rounds := 3
			var t_terrain := 0
			var t_res := 0
			var t_cover := 0
			var t_buf := 0
			for r in rounds:
				for cz in range(10, 16):
					for cx in range(10, 16):
						var o := Vector3(cx * 64, 0, cz * 64)
						var c := Vector2i(cx, cz)
						var t1 := Time.get_ticks_usec()
						var step := 64.0 / 32.0
						var n := 33
						var heights := PackedFloat32Array()
						heights.resize(n * n)
						for z in n:
							for x in n:
								heights[z * n + x] = gamegen.get_height(o.x + x * step, o.z + z * step)
						t_terrain += Time.get_ticks_usec() - t1
						t1 = Time.get_ticks_usec()
						var res: Array = cg._place_resources(c, o, gamegen, _game.flora, {})
						t_res += Time.get_ticks_usec() - t1
						t1 = Time.get_ticks_usec()
						var mm: Dictionary = cg._resource_buffers(res, o, 0)
						t_buf += Time.get_ticks_usec() - t1
						t1 = Time.get_ticks_usec()
						cg._place_ground_cover(c, o, gamegen, _game.flora, 0.6, mm)
						t_cover += Time.get_ticks_usec() - t1
			var tc := Time.get_ticks_usec()
			var cnt := 0
			for i in 3000:
				gamegen.get_terrain_color(float(i % 60), 0.9, float(i * 7 % 2000), float(i * 13 % 2000))
				cnt += 1
			print("get_terrain_color: %.1f us per call" % ((Time.get_ticks_usec() - tc) / float(cnt)))
			var total := float(rounds * 36)
			print("near chunk average over %d:" % int(total))
			print("  heights grid: %.1f ms" % (t_terrain / 1000.0 / total))
			print("  resource placement: %.1f ms" % (t_res / 1000.0 / total))
			print("  resource buffers: %.1f ms" % (t_buf / 1000.0 / total))
			print("  ground cover (grass etc): %.1f ms" % (t_cover / 1000.0 / total))
			print("RESULT: done")
			return true
	return false
