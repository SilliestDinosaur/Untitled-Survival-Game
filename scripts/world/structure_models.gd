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
	if kind == "foundation" or kind == "wall" or kind == "wood_wall":
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


## Building pieces: a stone slab (foundation), brick walls and plank walls, sculpted as solids.
static func _build_piece(kind: String) -> MeshKit:
	var k := MeshKit.new(hash(kind))
	if kind == "foundation":
		# Rounded square slab, 2 x 2 m and half a metre thick, lying flat (outline y -> world z).
		var outline := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			outline.append(Vector2(signf(cos(a)) * pow(absf(cos(a)), 0.25), signf(sin(a)) * pow(absf(sin(a)), 0.25)) * 1.0)
		var stone: Color = Game.palette.rock
		var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		var slab_col := func(p: Vector2, _t: float) -> Color:
			var h := fposmod(sin(floorf(p.x * 2.0) * 12.9 + floorf(p.y * 2.0) * 78.2) * 43758.5, 1.0)
			var seam := fposmod(p.x, 1.0) < 0.03 or fposmod(p.y, 1.0) < 0.03
			return stone.darkened(0.22) if seam else stone.lightened((h - 0.5) * 0.14)
		k.sculpt(outline, xf, func(_p: Vector2) -> float: return 0.5, slab_col, 3, 0.05)
		return k
	# Walls: 2 m long, 2.4 m tall, 0.3 m thick; the wall runs along local x and stands on y = 0.
	var rect := PackedVector2Array([Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 2.4), Vector2(-1.0, 2.4)])
	var brick: Color = ItemDB.info("brick").color
	if kind == "wall":
		var brick_col := func(p: Vector2, _t: float) -> Color:
			var row := floorf(p.y / 0.2)
			var u := fposmod(p.x + (fposmod(row, 2.0) * 0.2), 0.4)
			var mortar := u > 0.385 or fposmod(p.y, 0.2) < 0.022
			return Color(0.66, 0.63, 0.58) if mortar else brick.lightened((fposmod(sin(row * 9.1 + floorf(p.x * 2.5) * 3.7), 1.0) - 0.5) * 0.06)
		k.sculpt(rect, Transform3D(), func(_p: Vector2) -> float: return 0.3, brick_col, 4, 0.05)
	else:   # plank wall: vertical boards with dark seams
		var wood := WOOD.lightened(0.04)
		var board_col := func(p: Vector2, _t: float) -> Color:
			var seam := fposmod(p.x + 1.0, 0.25) < 0.02
			var grain := sin(p.y * 40.0 + floorf((p.x + 1.0) * 4.0) * 2.0) * 0.03
			return WOOD_DARK if seam else wood.lightened(grain)
		k.sculpt(rect, Transform3D(), func(_p: Vector2) -> float: return 0.14, board_col, 4, 0.04)
	return k


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
