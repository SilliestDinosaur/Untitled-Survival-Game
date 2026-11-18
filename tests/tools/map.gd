extends SceneTree
## Top-down map of one or more islands, written straight to PNG (no Python step).
## Samples the terrain once into a grid, then colours it. Prints timings.
## Environment variables:
##   SEEDS=629946553,777   worlds to draw (default 629946553)
##   RES=160               pixels per side (default 160)
##   OUT=/tmp/map.png      output (one image, islands side by side)

func _initialize() -> void:
	# Load the main scene first, as the other tools do: without it Godot aborts on exit (a double free) after
	# the image is saved.
	root.add_child(load("res://scenes/main.tscn").instantiate())
	var g = root.get_node("Game")
	var seeds: PackedStringArray = OS.get_environment("SEEDS").split(",") if OS.get_environment("SEEDS") != "" else PackedStringArray(["629946553"])
	var res: int = int(OS.get_environment("RES")) if OS.get_environment("RES") != "" else 160
	var out_path: String = OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/map.png"
	var sheet := Image.create(res * seeds.size(), res, false, Image.FORMAT_RGB8)
	for si in seeds.size():
		var t0 := Time.get_ticks_msec()
		g.new_world(int(seeds[si]))
		var wg = g.world_gen
		var t1 := Time.get_ticks_msec()
		var step: float = g.WORLD_SIZE / res
		for j in res:
			for i in res:
				var x: float = (i + 0.5) * step
				var z: float = (j + 0.5) * step
				var h: float = wg.get_height(x, z)
				var c := Color(0.1, 0.25, 0.55)
				if h > -0.5:
					c = Color(0.92, 0.85, 0.6) if h < 2.0 else Color(0.35 + clampf(h / 90.0, 0, 0.5), 0.55 + clampf(h / 200.0, 0, 0.3), 0.25 + clampf(h / 120.0, 0, 0.3))
				sheet.set_pixel(si * res + i, j, c)
		print("seed ", seeds[si], "  world ", t1 - t0, " ms  map ", Time.get_ticks_msec() - t1, " ms")
	sheet.save_png(out_path)
	print("saved ", out_path)
	quit()

