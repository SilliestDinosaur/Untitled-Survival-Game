extends SceneTree
## Top-down painted map: the ground's own colours (biomes), hill shading from the north-west, water by depth.
## SEEDS=a,b,c  RES=pixels per side (default 384)  OUT=path.png  LABELS=1 prints the biome share of each world.

func _initialize() -> void:
	root.add_child(load("res://scenes/main.tscn").instantiate())
	var g = root.get_node("Game")
	var seeds: PackedStringArray = OS.get_environment("SEEDS").split(",") if OS.get_environment("SEEDS") != "" else PackedStringArray(["629946553"])
	var res: int = int(OS.get_environment("RES")) if OS.get_environment("RES") != "" else 384
	var out_path: String = OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/biome_map.png"
	var sheet := Image.create(res * seeds.size(), res, false, Image.FORMAT_RGB8)
	for si in seeds.size():
		var t0 := Time.get_ticks_msec()
		g.new_world(int(seeds[si]), float(OS.get_environment("SIZE")) if OS.get_environment("SIZE") != "" else g.NEW_WORLD_SIZE)
		var gen = g.world_gen
		var cell: float = g.WORLD_SIZE / res
		var hs := PackedFloat32Array()
		hs.resize(res * res)
		for j in res:
			for i in res:
				hs[j * res + i] = gen.get_height((i + 0.5) * cell, (j + 0.5) * cell)
		var counts := {}
		var land := 0
		for j in res:
			for i in res:
				var x := (i + 0.5) * cell
				var z := (j + 0.5) * cell
				var h := hs[j * res + i]
				var hx := hs[j * res + mini(i + 1, res - 1)] - hs[j * res + maxi(i - 1, 0)]
				var hz := hs[mini(j + 1, res - 1) * res + i] - hs[maxi(j - 1, 0) * res + i]
				var n := Vector3(-hx, 2.0 * cell, -hz).normalized()
				var col: Color
				var wl: float = gen.water_level(x, z)
				if h < wl:
					var d := wl - h
					col = Color(0.32, 0.62, 0.7).lerp(Color(0.06, 0.16, 0.34), clampf(d / 14.0, 0.0, 1.0))
				else:
					land += 1
					col = gen.get_terrain_color(h, n.y, x, z)
					var b: int = gen.get_biome(x, z)
					counts[b] = int(counts.get(b, 0)) + 1
					var shade := clampf(n.dot(Vector3(-0.6, 0.7, -0.4).normalized()) * 1.25, 0.35, 1.25)
					col = Color(col.r * shade, col.g * shade, col.b * shade)
				sheet.set_pixel(si * res + i, j, col)
		var line := "seed %s  %d ms  land %d%% " % [seeds[si], Time.get_ticks_msec() - t0, land * 100 / (res * res)]
		for b in counts:
			line += " %s %d%%" % [gen.BIOME_NAMES[b], int(counts[b]) * 100 / maxi(land, 1)]
		print(line)
	sheet.save_png(out_path)
	print("saved ", out_path)
	quit()
