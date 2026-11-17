extends SceneTree
## Benchmark (diagnostic): godot --headless --path . -s tests/tools/bench.gd
## Times world creation, the terrain height lookups and chunk generation at each detail tier.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _t0 := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_t0 = Time.get_ticks_usec()
				_main.create_world("Bench", 629946553)
			if _main.state == _main.State.PLAYING:
				print("WORLD create + load to PLAYING: %.0f ms" % ((Time.get_ticks_usec() - _t0) / 1000.0))
				_step = 1
		1:
			var gen: Object = _game.world_gen
			var n := 20000
			var t := Time.get_ticks_usec()
			var acc := 0.0
			for i in n:
				acc += gen.get_height(float(i % 2000), float(i / 10 % 2000))
			print("get_height: %.1f us per call" % ((Time.get_ticks_usec() - t) / float(n)))
			t = Time.get_ticks_usec()
			for i in n:
				acc += gen.get_normal(float(i % 2000), float(i / 10 % 2000)).y
			print("get_normal: %.1f us per call" % ((Time.get_ticks_usec() - t) / float(n)))
			t = Time.get_ticks_usec()
			for i in n:
				acc += gen.get_base_height(float(i % 2000), float(i / 10 % 2000))
			print("get_base_height: %.1f us per call" % ((Time.get_ticks_usec() - t) / float(n)))
			var cg = load("res://scripts/world/chunk_generator.gd")
			for tier in 3:
				var total := 0
				var count := 0
				for cz in range(10, 16):
					for cx in range(10, 16):
						var job := {"coord": Vector2i(cx, cz), "tier": tier, "gen": gen, "flora": _game.flora, "removed": {}, "grass_density": 0.6}
						var t2 := Time.get_ticks_usec()
						cg.generate(job)
						total += Time.get_ticks_usec() - t2
						count += 1
				print("chunk tier %d: %.1f ms per chunk (%d chunks)" % [tier, total / 1000.0 / count, count])
			print("sink %f" % acc)
			print("RESULT: done")
			return true
	return false
