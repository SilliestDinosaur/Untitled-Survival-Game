extends SceneTree
## Top-down map of one or more islands, written straight to PNG (no Python step).
## Samples the terrain once into a grid, then colours it. Prints timings.
## Environment variables:
##   SEEDS=629946553,777   worlds to draw (default 629946553)
##   RES=160               pixels per side (default 160)
##   OUT=/tmp/map.png      output (one image, islands side by side)
##   RIVERS=1              show the water in blue where it is built: rivers and lakes (default 1)

func _initialize() -> void:
	var g = root.get_node("Game")
	var seeds: PackedStringArray = OS.get_environment("SEEDS").split(",") if OS.get_environment("SEEDS") != "" else PackedStringArray(["629946553"])
	var res: int = int(OS.get_environment("RES")) if OS.get_environment("RES") != "" else 160
	var rivers: bool = OS.get_environment("RIVERS") != "0"
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
					# Water shows where a river has depth here, or a lake's surface stands above the ground.
					if rivers and wg.hydro.water.size() > 0 and (_sample(wg.hydro.water, wg.hydro.n, x, z) > 0.02 or _sample(wg.hydro.lake, wg.hydro.n, x, z) > h + 0.02):
						c = Color(0.2, 0.5, 0.9)
				sheet.set_pixel(si * res + i, j, c)
		print("seed ", seeds[si], "  world ", t1 - t0, " ms  map ", Time.get_ticks_msec() - t1, " ms")
	sheet.save_png(out_path)
	print("saved ", out_path)
	quit()


## Bilinear sample of a per-cell grid (same as Hydrology.sample). Written out here so this script
## does not name any project class, which would compile the game before the autoloads exist.
func _sample(field: PackedFloat32Array, n: int, x: float, z: float) -> float:
	var cell: float = 8.0
	var fx := clampf(x / cell, 0.0, float(n - 1) - 0.001)
	var fz := clampf(z / cell, 0.0, float(n - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := field[j * n + i]
	var b := field[j * n + i + 1]
	var c := field[(j + 1) * n + i]
	var d := field[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
