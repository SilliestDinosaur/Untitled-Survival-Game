class_name StructureModels
extends RefCounted
## Models for placed stations (campfire, workbench, forge), built like the item models from
## lofts, bevelled boards and lumpy faceted stones. Each has a body mesh plus an optional "glow"
## mesh (embers, coals) drawn with an emissive material, and a point for the light.

const WOOD := Color(0.56, 0.41, 0.27)
const WOOD_DARK := Color(0.4, 0.28, 0.18)
const BARK := Color(0.4, 0.29, 0.2)
const ROPE := Color(0.74, 0.64, 0.42)
const IRON := Color(0.32, 0.32, 0.36)
const ASH := Color(0.28, 0.26, 0.25)

static var _cache := {}


static func clear_cache() -> void:
	_cache.clear()


## {body: ArrayMesh, glow: ArrayMesh or null, light: Vector3 (local), radius: float (collision)}
static func get_model(kind: String, material: Material, glow_material: Material) -> Dictionary:
	var key := kind + str(material.get_instance_id())
	if _cache.has(key):
		return _cache[key]
	if GameActions.is_building(kind):
		var bm := _build_piece(kind)
		var piece := {"body": bm.commit(material), "glow": null, "light": Vector3(0, 1, 0), "radius": 1.0}
		_cache[kind + str(material.get_instance_id())] = piece
		return piece
	var k := MeshKit.new(hash(kind))
	var g := MeshKit.new(hash(kind) + 1)
	var light := Vector3(0, 0.5, 0)
	var radius := 0.6
	var stone: Color = Game.palette.rock
	match kind:
		"campfire":
			_campfire(k, g, stone)
			light = Vector3(0, 0.45, 0)
			radius = 0.55
		"workbench":
			_workbench(k)
			light = Vector3.ZERO
			radius = 0.8
		"forge":
			_forge(k, g, stone)
			light = Vector3(0, 0.55, -0.45)
			radius = 0.85
	var out := {"body": k.commit(material), "glow": g.commit(glow_material) if not g.is_empty() else null,
		"light": light, "radius": radius}
	_cache[key] = out
	return out


## A board with bevelled edges: size x (length), y (width), z (thickness), centered on xf.
static func _board(k: MeshKit, size: Vector3, xf: Transform3D, col: Color, wobble := 0.0) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var outline := PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy + wobble), Vector2(hx, hy), Vector2(-hx, hy - wobble)])
	k.extrude(outline, xf, size.z, minf(size.z, size.y) * 0.25, col, col.lightened(0.12), 0.55)


## Building pieces at Rust scale: a 3 m square foundation of cut stone blocks, 3 m walls of
## individual bricks (a 1.4 m doorway with a timber frame), plank walls between rails, and tiled roofs.
static func _build_piece(kind: String) -> MeshKit:
	var k := MeshKit.new(hash(kind))
	var brick: Color = ItemDB.info("brick").color
	var mortar := Color(0.7, 0.67, 0.61)
	var stone: Color = Game.palette.rock
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var h := GameActions.CELL * 0.5   # half the cell
	match kind:
		"foundation":
			# Mortar bed, then a 3 x 3 grid of cut blocks with real gaps and slight offsets.
			var bed := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
			k.sculpt(bed, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), func(_p: Vector2) -> float: return 0.42,
				func(_p: Vector2, _t: float) -> Color: return mortar.darkened(0.12), 0, 0.05)
			var step := GameActions.CELL / 3.0
			for iz in 3:
				for ix in 3:
					var bx := -h + step * (ix + 0.5) + rng.randf_range(-0.02, 0.02)
					var bz := -h + step * (iz + 0.5) + rng.randf_range(-0.02, 0.02)
					var hw := step * 0.5 - 0.035 + rng.randf_range(-0.012, 0.012)
					var outline := _rounded_rect(hw, hw, 0.07, 3)
					var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(bx, 0.12, bz))
					var block := stone.lightened(rng.randf_range(-0.07, 0.07))
					var face := func(p: Vector2, _t: float) -> Color:
						return block.darkened(0.1) if fposmod(p.x * 5.0 + p.y * 3.0, 1.0) < 0.04 else block
					k.sculpt(outline, xf, func(_p: Vector2) -> float: return 0.44 + rng.randf_range(-0.01, 0.01), face, 1, 0.04)
		"wall", "doorway":
			# A mortar core and individual bricks in running bond (a doorway leaves the opening clear).
			var door_w := 0.7
			var door_h := 2.3
			var cores := [[Vector2(-h, 0.0), Vector2(h, 0.0), Vector2(h, 3.0), Vector2(-h, 3.0)]]
			if kind == "doorway":
				cores = [
					[Vector2(-h, 0.0), Vector2(-door_w, 0.0), Vector2(-door_w, 3.0), Vector2(-h, 3.0)],
					[Vector2(door_w, 0.0), Vector2(h, 0.0), Vector2(h, 3.0), Vector2(door_w, 3.0)],
					[Vector2(-door_w, door_h), Vector2(door_w, door_h), Vector2(door_w, 3.0), Vector2(-door_w, 3.0)],
				]
			for core: Array in cores:
				k.sculpt(PackedVector2Array(core), Transform3D(), func(_p: Vector2) -> float: return 0.2, func(_p: Vector2, _t: float) -> Color: return mortar, 0, 0.05)
			var bw := 0.5
			var bh := 0.25
			for row in 12:
				var y0 := row * bh
				var offset := bw * 0.5 if row % 2 == 1 else 0.0
				var x := -h - offset
				while x < h:
					var x0 := maxf(x + 0.015, -h)
					var x1 := minf(x + bw - 0.015, h)
					x += bw
					if x1 - x0 < 0.15:
						continue
					var cx := (x0 + x1) * 0.5
					if kind == "doorway" and absf(cx) < door_w + 0.04 and y0 < door_h:
						continue
					var hx := (x1 - x0) * 0.5
					var outline := _rounded_rect(hx, bh * 0.5 - 0.015, 0.025, 2)
					var b := brick.lightened(rng.randf_range(-0.07, 0.05))
					var face := func(p: Vector2, _t: float) -> Color:
						return b.darkened(0.12) if p.y < -bh * 0.5 + 0.045 or p.y > bh * 0.5 - 0.045 else b
					var xf := Transform3D(Basis(), Vector3(cx, y0 + bh * 0.5, 0.07))
					k.sculpt(outline, xf, func(_p: Vector2) -> float: return 0.22, face, 1, 0.03)
			if kind == "doorway":
				# Timber frame around the opening.
				for side in [-1.0, 1.0]:
					k.add_primitive(_box(Vector3(0.12, door_h, 0.26)), Transform3D(Basis(), Vector3(side * door_w, door_h * 0.5, 0.0)), WOOD_DARK, 0.0, 0.03)
				k.add_primitive(_box(Vector3(door_w * 2.0 + 0.24, 0.12, 0.26)), Transform3D(Basis(), Vector3(0.0, door_h, 0.0)), WOOD_DARK, 0.0, 0.03)
		"wood_wall":
			# Boards between a bottom and a top rail, with dark seams and a little grain.
			k.add_primitive(_box(Vector3(3.0, 0.2, 0.26)), Transform3D(Basis(), Vector3(0, 0.1, 0)), WOOD_DARK, 0.0, 0.03)
			k.add_primitive(_box(Vector3(3.0, 0.2, 0.26)), Transform3D(Basis(), Vector3(0, 2.9, 0)), WOOD_DARK, 0.0, 0.03)
			for i in 15:
				var bx := -1.4 + i * 0.2
				var h_off := rng.randf_range(-0.01, 0.01)
				var outline := _rounded_rect(0.092, 1.36, 0.02, 1)
				var board := WOOD.lightened(rng.randf_range(-0.05, 0.06))
				var grain := func(p: Vector2, _t: float) -> Color:
					return board.darkened(0.08) if fposmod(p.y * 6.0 + sin(p.x * 30.0), 1.0) < 0.08 else board
				k.sculpt(outline, Transform3D(Basis(), Vector3(bx, 1.5 + h_off, 0.0)), func(_p: Vector2) -> float: return 0.08, grain, 1, 0.02)
		"roof":
			# Overlapping clay tiles in staggered rows over a 3 m square, with a timber edge.
			var clay := Color(0.62, 0.34, 0.26)
			for row in 10:
				for col in 6:
					var tz := -h + 0.15 + row * 0.3
					var tx := -h + 0.25 + col * 0.5 + (0.25 if row % 2 == 1 else 0.0)
					if tx > h - 0.1:
						continue
					var outline := _rounded_rect(0.24, 0.16, 0.06, 1)
					var t := clay.lightened(rng.randf_range(-0.07, 0.07))
					var tile := func(p: Vector2, _t: float) -> Color: return t.darkened(0.15) if p.y < -0.12 else t
					k.sculpt(outline, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx, 0.03 + row * 0.004, tz)), func(_p: Vector2) -> float: return 0.06, tile, 1, 0.02)
			for side in [-1.0, 1.0]:
				k.add_primitive(_box(Vector3(3.0, 0.16, 0.14)), Transform3D(Basis(), Vector3(0, -0.02, side * h)), WOOD_DARK, 0.0, 0.03)
				k.add_primitive(_box(Vector3(0.14, 0.16, 3.0)), Transform3D(Basis(), Vector3(side * h, -0.02, 0)), WOOD_DARK, 0.0, 0.03)
	return k


## A rounded rectangle outline (half sizes hx, hy; corner radius r; segments per corner).
static func _rounded_rect(hx: float, hy: float, r: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [Vector2(hx - r, hy - r), Vector2(-hx + r, hy - r), Vector2(-hx + r, -hy + r), Vector2(hx - r, -hy + r)]
	for ci in 4:
		var c: Vector2 = corners[ci]
		var a0 := ci * PI * 0.5
		for s in seg + 1:
			var a := a0 + (PI * 0.5) * s / float(seg)
			out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _stone(k: MeshKit, at: Vector3, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var sc := Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.6, 0.85), rng.randf_range(0.9, 1.2))
	k.add_primitive(MeshKit.sphere(r, 9, 6), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(sc), at),
		col.lightened(rng.randf_range(-0.1, 0.12)), r * 0.3, 0.06)


static func _campfire(k: MeshKit, g: MeshKit, stone: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	k.flat_shading = true
	for i in 10:
		var a := TAU * i / 10.0 + rng.randf_range(-0.1, 0.1)
		_stone(k, Vector3(cos(a) * 0.48, 0.05, sin(a) * 0.48), rng.randf_range(0.09, 0.12), stone, rng)
	k.flat_shading = false
	# Ash bed
	k.add_primitive(MeshKit.cylinder(0.38, 0.42, 0.04, 20), Transform3D(Basis(), Vector3(0, 0.0, 0)), ASH, 0.0, 0.08)
	# Teepee of split logs leaning together, charred toward the middle.
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var foot := Vector3(cos(a) * 0.34, 0.02, sin(a) * 0.34)
		var top := Vector3(cos(a) * 0.04, 0.5, sin(a) * 0.04)
		var path := []
		var radii := []
		for s in 6:
			var t := s / 5.0
			path.append(foot.lerp(top, t))
			radii.append(lerpf(0.042, 0.03, t))
		k.loft(path, radii, 9, BARK, func(t: float, _a: float) -> Color: return BARK.lerp(Color(0.12, 0.1, 0.09), smoothstep(0.35, 0.9, t)),
			Callable(), true, true, 0.006)
	# Glowing embers among the logs.
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.18)
		g.add_primitive(MeshKit.sphere(rng.randf_range(0.035, 0.06), 7, 5),
			Transform3D(Basis.from_scale(Vector3(1.2, 0.6, 1.0)), Vector3(cos(a) * r, 0.04, sin(a) * r)),
			Color(1.0, rng.randf_range(0.35, 0.55), 0.15), 0.01, 0.15)


static func _workbench(k: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var top_y := 0.82
	# Tabletop: four planks side by side with slightly different tones.
	for i in 4:
		var z := -0.36 + i * 0.24
		_board(k, Vector3(1.5, 0.22, 0.06), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, top_y, z)),
			WOOD.lightened(rng.randf_range(-0.06, 0.06)), rng.randf_range(-0.01, 0.01))
	# Legs, splayed slightly, with a stretcher frame lower down.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := Vector3(sx * 0.68, 0.0, sz * 0.4)
			var head := Vector3(sx * 0.6, top_y - 0.03, sz * 0.34)
			k.loft([foot, foot.lerp(head, 0.5), head], [0.05, 0.045, 0.045], 8, WOOD_DARK,
				Callable(), func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.8))
	for sz in [-1.0, 1.0]:
		_board(k, Vector3(1.3, 0.08, 0.05), Transform3D(Basis(), Vector3(0, 0.25, sz * 0.38)), WOOD_DARK)
	_board(k, Vector3(0.75, 0.08, 0.05), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.64, 0.25, 0)), WOOD_DARK)
	_board(k, Vector3(0.75, 0.08, 0.05), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.64, 0.25, 0)), WOOD_DARK)
	# Lower shelf with a couple of logs on it.
	_board(k, Vector3(1.2, 0.7, 0.04), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.29, 0)), WOOD_DARK.lightened(0.05))
	for i in 2:
		var z := -0.12 + i * 0.22
		k.loft([Vector3(-0.45, 0.37, z), Vector3(0.45, 0.37, z)], [0.07, 0.07], 12, BARK, Callable(), Callable(), true, true, 0.006)
	# Tools lying on the top: a mallet and a coil of rope.
	var y := top_y + 0.035
	k.loft([Vector3(0.25, y + 0.02, -0.15), Vector3(0.6, y + 0.02, -0.05)], [0.016, 0.014], 8, WOOD)
	k.loft([Vector3(0.6, y + 0.05, -0.13), Vector3(0.6, y + 0.05, 0.03)], [0.05, 0.05], 12, WOOD_DARK.lightened(0.1))
	for i in 3:
		var r := 0.09 - i * 0.012
		var ring := []
		var rr := []
		for s in 17:
			var a := TAU * s / 16.0
			ring.append(Vector3(-0.45 + cos(a) * r, y + 0.015 + i * 0.012, 0.15 + sin(a) * r))
			rr.append(0.014)
		k.loft(ring, rr, 6, ROPE.darkened(i * 0.06), Callable(), Callable(), false, false)
	# A vise block on the front edge.
	_board(k, Vector3(0.16, 0.14, 0.1), Transform3D(Basis(), Vector3(-0.55, top_y + 0.05, 0.5)), WOOD_DARK)
	k.loft([Vector3(-0.55, top_y + 0.05, 0.5), Vector3(-0.55, top_y + 0.05, 0.68)], [0.012, 0.012], 8, IRON)


static func _forge(k: MeshKit, g: MeshKit, stone: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var mortar := stone.darkened(0.25)
	# Base: a rounded hearth of mortared stone, built up course by course.
	k.add_primitive(MeshKit.cylinder(0.6, 0.72, 0.85, 18), Transform3D(Basis(), Vector3(0, 0.42, 0)), mortar, 0.03, 0.08)
	k.flat_shading = true
	for course in 4:
		var y := 0.1 + course * 0.22
		var r := 0.72 - course * 0.04
		var count := 11 - course
		for i in count:
			var a := TAU * (i + (course % 2) * 0.5) / count
			if course >= 1 and absf(angle_difference(a, -PI * 0.5)) < 0.45:
				continue   # the mouth of the forge faces forward (-Z)
			_stone(k, Vector3(cos(a) * r, y, sin(a) * r), rng.randf_range(0.12, 0.15), stone, rng)
	k.flat_shading = false
	# Chimney: a tapering stone stack with a darker lip.
	var path := []
	var radii := []
	for i in 7:
		var t := i / 6.0
		path.append(Vector3(0, 0.85 + t * 1.15, 0.08 * t))
		radii.append(lerpf(0.5, 0.22, pow(t, 0.7)))
	var chimney_col := func(t: float, a: float) -> Color:
		var band := fposmod(t * 9.0 + sin(a * 3.0) * 0.2, 1.0) < 0.14
		return mortar.darkened(0.15) if band or t > 0.93 else mortar.lightened(0.08 * sin(a * 5.0 + t * 11.0))
	k.loft(path, radii, 14, mortar.lightened(0.05), chimney_col, Callable(), false, true, 0.02)
	# Mouth: dark recess with glowing coals.
	k.add_primitive(MeshKit.sphere(0.3, 14, 8), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.6)), Vector3(0, 0.55, -0.48)), Color(0.16, 0.08, 0.05), 0.0, 0.02)
	for i in 9:
		g.add_primitive(MeshKit.sphere(rng.randf_range(0.05, 0.08), 7, 5),
			Transform3D(Basis(), Vector3(rng.randf_range(-0.18, 0.18), 0.4 + rng.randf_range(0.0, 0.06), -0.66 + rng.randf_range(-0.05, 0.05))),
			Color(1.0, rng.randf_range(0.3, 0.55), 0.1), 0.012, 0.15)
	# Anvil on a stump beside it.
	var ax := Vector3(0.95, 0, -0.2)
	k.loft([ax, ax + Vector3(0, 0.45, 0)], [0.2, 0.18], 14, BARK, func(t: float, _a: float) -> Color: return BARK if t < 0.98 else WOOD, Callable(), true, true, 0.008)
	var anvil := PackedVector2Array([Vector2(-0.24, 0.0), Vector2(-0.1, 0.02), Vector2(-0.08, 0.14), Vector2(-0.22, 0.17), Vector2(-0.3, 0.2),
		Vector2(0.18, 0.2), Vector2(0.3, 0.17), Vector2(0.12, 0.13), Vector2(0.09, 0.02), Vector2(0.2, 0.0)])
	k.extrude(anvil, Transform3D(Basis(Vector3.UP, 0.3), ax + Vector3(0, 0.45, 0)), 0.13, 0.025, IRON, IRON.lightened(0.35), 0.4)
	# Tongs leaning on the hearth.
	for s in [-1.0, 1.0]:
		k.loft([Vector3(-0.75 + s * 0.02, 0.0, -0.15), Vector3(-0.6, 0.75, -0.25)], [0.012, 0.01], 6, IRON)
