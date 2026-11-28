class_name DecorModels
extends RefCounted
## Models of the free-standing pieces (GameActions.DECOR): furniture, decor, lights and storage. Made from the same
## parts as the buildings (bevelled boards, rough stone, iron straps, painted cloth), so they sit in the same world.
## Each stands on its origin and faces +Z. Glowing parts (embers, a lantern's glass) go into `glow`.
##
## Parts never share a face or an edge with another (tri_check counts those as non-manifold): where two meet, one
## stands a hair proud of the other.

const WOOD := StructureModels.WOOD
const WOOD_DARK := StructureModels.WOOD_DARK
const IRON := StructureModels.IRON
const CLOTH := Color(0.88, 0.82, 0.68)      ## undyed linen
const RED := Color(0.62, 0.22, 0.18)        ## madder red
const BLUE := Color(0.26, 0.36, 0.52)       ## woad blue
const GOLD := Color(0.86, 0.68, 0.28)
const CLAY := Color(0.72, 0.42, 0.28)       ## terracotta
const EMBER := Color(1.0, 0.5, 0.14)
const FLAT := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   ## a board lying flat (its thickness up)


static func build(kind: String, k: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> void:
	match kind:
		"table": _table(k, rng)
		"chair": _chair(k, rng)
		"bench": _bench(k, rng)
		"bed": _bed(k, rng)
		"shelf": _shelf(k, rng)
		"rug": _rug(k, rng)
		"barrel": _barrel(k, rng)
		"crate": _crate(k, rng)
		"flower_pot": _flower_pot(k, rng)
		"banner": _banner(k, rng)
		"brazier": _brazier(k, glow, rng)
		"lantern_post": _lantern_post(k, glow)
		"standing_torch": _standing_torch(k, glow)
		"wall_torch": _wall_torch(k, glow)
		"wall_lantern": _wall_lantern(k, glow)
		"candle_sconce": _candle_sconce(k, glow, rng)
		"hanging_lantern": _hanging_lantern(k, glow)
		"chest": _chest(k, rng, false)
		"large_chest": _chest(k, rng, true)


static func _wood(rng: RandomNumberGenerator, base := WOOD) -> Color:
	return base.lightened(rng.randf_range(-0.05, 0.06))


## A plank lying flat: length along x, width along z, centred on `at`.
static func _plank(k: MeshKit, length: float, width: float, thick: float, at: Vector3, col: Color, yaw := 0.0) -> void:
	StructureModels._board(k, Vector3(length, width, thick), Transform3D(Basis(Vector3.UP, yaw) * FLAT, at), col, 0.004)


static func _post(k: MeshKit, size: Vector3, at: Vector3, col: Color) -> void:
	k.add_primitive(StructureModels._box(size), Transform3D(Basis(), at), col, 0.0, 0.04)


static func _table(k: MeshKit, rng: RandomNumberGenerator) -> void:
	for i in 3:
		_plank(k, 1.3, 0.255, 0.05, Vector3(0, 0.765, (i - 1) * 0.265), _wood(rng))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(0.08, 0.72, 0.08), Vector3(sx * 0.56, 0.36, sz * 0.3), WOOD_DARK)
	for sz in [-1.0, 1.0]:   # aprons under the top, between the legs
		_post(k, Vector3(1.03, 0.08, 0.04), Vector3(0, 0.68, sz * 0.3), WOOD_DARK.lightened(0.04))
	# A jug and a bowl on top.
	k.loft([Vector3(0.32, 0.791, -0.08), Vector3(0.32, 0.86, -0.08), Vector3(0.32, 0.95, -0.08), Vector3(0.32, 1.0, -0.08)], [0.06, 0.075, 0.05, 0.035], 12, CLAY,
		Callable(), Callable(), true, true)
	k.loft([Vector3(-0.3, 0.791, 0.08), Vector3(-0.3, 0.84, 0.08)], [0.05, 0.11], 14, Color(0.78, 0.7, 0.55), Callable(), Callable(), true, true)


static func _chair(k: MeshKit, rng: RandomNumberGenerator) -> void:
	for i in 2:
		_plank(k, 0.46, 0.225, 0.04, Vector3(0, 0.46, (i - 0.5) * 0.23), _wood(rng))
	for sx in [-1.0, 1.0]:
		_post(k, Vector3(0.05, 0.44, 0.05), Vector3(sx * 0.2, 0.22, 0.19), WOOD_DARK)        # front legs
		_post(k, Vector3(0.05, 0.98, 0.05), Vector3(sx * 0.2, 0.49, -0.19), WOOD_DARK)       # back legs, up into the back
	for i in 3:   # back slats
		_post(k, Vector3(0.07, 0.38, 0.025), Vector3((i - 1) * 0.11, 0.72, -0.2), _wood(rng))
	_post(k, Vector3(0.46, 0.06, 0.035), Vector3(0, 0.94, -0.2), WOOD_DARK.lightened(0.05))   # top rail


static func _bench(k: MeshKit, rng: RandomNumberGenerator) -> void:
	_plank(k, 1.4, 0.34, 0.06, Vector3(0, 0.45, 0), _wood(rng))
	for sx in [-1.0, 1.0]:
		StructureModels._board(k, Vector3(0.3, 0.41, 0.06), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx * 0.55, 0.205, 0)), WOOD_DARK, 0.004)
	_post(k, Vector3(1.02, 0.06, 0.05), Vector3(0, 0.17, 0), WOOD_DARK.lightened(0.05))


static func _bed(k: MeshKit, rng: RandomNumberGenerator) -> void:
	for sx in [-1.0, 1.0]:   # side rails, and posts at the corners
		_post(k, Vector3(0.07, 0.18, 1.9), Vector3(sx * 0.5, 0.2, 0), WOOD_DARK)
		_post(k, Vector3(0.09, 0.48, 0.09), Vector3(sx * 0.52, 0.24, 0.96), WOOD_DARK.lightened(0.04))
		_post(k, Vector3(0.09, 0.95, 0.09), Vector3(sx * 0.52, 0.475, -0.96), WOOD_DARK.lightened(0.04))
	for i in 4:   # the headboard's planks
		_post(k, Vector3(0.234, 0.62, 0.04), Vector3(-0.36 + i * 0.24, 0.6, -0.97), _wood(rng))
	_post(k, Vector3(0.96, 0.14, 1.82), Vector3(0, 0.33, 0), CLOTH.darkened(0.08))      # mattress (straw ticking)
	k.add_primitive(MeshKit.sphere(0.2, 10, 6), Transform3D(Basis.from_scale(Vector3(1.6, 0.42, 0.9)), Vector3(0, 0.45, -0.7)), CLOTH, 0.01, 0.05)   # pillow
	_post(k, Vector3(1.0, 0.06, 1.2), Vector3(0, 0.42, 0.3), RED)                        # blanket
	_post(k, Vector3(1.02, 0.065, 0.12), Vector3(0, 0.421, -0.253), RED.lightened(0.2))  # its turned-down edge


static func _shelf(k: MeshKit, rng: RandomNumberGenerator) -> void:
	for sx in [-1.0, 1.0]:
		_post(k, Vector3(0.05, 1.8, 0.36), Vector3(sx * 0.575, 0.9, 0), WOOD_DARK)
	for i in 4:
		_post(k, Vector3(1.1, 0.04, 0.34), Vector3(0, 0.12 + i * 0.52, 0), _wood(rng))
	_post(k, Vector3(1.1, 1.74, 0.02), Vector3(0, 0.9, -0.17), WOOD_DARK.darkened(0.15))   # the back
	# On the shelves: jars, pots, a row of books, bundles of herbs.
	for row in 3:
		var y := 0.142 + row * 0.52
		var x := -0.48
		while x < 0.46:
			var pick := rng.randi() % 3
			if pick == 0:
				var r := rng.randf_range(0.05, 0.08)
				var h := rng.randf_range(0.14, 0.24)
				var c: Color = [CLAY, Color(0.4, 0.55, 0.45), Color(0.78, 0.72, 0.6)][rng.randi() % 3]
				k.loft([Vector3(x + r, y, 0.02), Vector3(x + r, y + h * 0.7, 0.02), Vector3(x + r, y + h, 0.02)], [r, r * 1.05, r * 0.7], 10, c, Callable(), Callable(), true, true)
				x += r * 2.0 + 0.04
			elif pick == 1:
				for b in rng.randi_range(3, 5):
					var bw := rng.randf_range(0.035, 0.05)
					var bh := rng.randf_range(0.18, 0.26)
					var bc: Color = [RED, BLUE, Color(0.36, 0.48, 0.3), Color(0.55, 0.4, 0.25)][rng.randi() % 4]
					_post(k, Vector3(bw, bh, 0.2), Vector3(x + bw * 0.5, y + bh * 0.5 + 0.001, 0.02), bc)
					x += bw + 0.004
				x += 0.04
			else:
				k.add_primitive(MeshKit.sphere(0.07, 8, 5), Transform3D(Basis.from_scale(Vector3(1.3, 0.8, 1.0)), Vector3(x + 0.08, y + 0.06, 0.03)),
					Color(0.5, 0.58, 0.32), 0.015, 0.1)
				x += 0.2


static func _rug(k: MeshKit, rng: RandomNumberGenerator) -> void:
	var oval := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		oval.append(Vector2(cos(a) * 0.85, sin(a) * 0.55))
	k.extrude(oval, Transform3D(FLAT, Vector3(0, 0.012, 0)), 0.024, 0.008, RED, RED.darkened(0.2))
	for ring in 2:   # woven bands, a hair above the rug
		var s := 0.78 - ring * 0.22
		var band := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			band.append(Vector2(cos(a) * 0.85 * s, sin(a) * 0.55 * s))
		var c := GOLD if ring == 0 else BLUE
		k.extrude(band, Transform3D(FLAT, Vector3(0, 0.026 + ring * 0.004, 0)), 0.006, 0.0, c, c)
		var inner := PackedVector2Array()
		for p in band:
			inner.append(p * 0.86)
		k.extrude(inner, Transform3D(FLAT, Vector3(0, 0.0295 + ring * 0.004, 0)), 0.002, 0.0, RED.lightened(0.05 * ring), RED)


static func _barrel(k: MeshKit, rng: RandomNumberGenerator) -> void:
	var staves := func(_t: float, a: float) -> Color:
		return WOOD.lightened(0.06) if int(floor(a / TAU * 14.0)) % 2 == 0 else WOOD.darkened(0.04)
	var path: Array = []
	var radii: Array = []
	for i in 7:
		var t := i / 6.0
		path.append(Vector3(0, t * 0.88, 0))
		radii.append(0.26 + 0.05 * sin(t * PI))
	k.loft(path, radii, 14, WOOD, staves, Callable(), true, true)
	for y in [0.14, 0.44, 0.74]:   # iron hoops, a hair proud of the staves
		var r := 0.26 + 0.05 * sin(y / 0.88 * PI) + 0.008
		k.add_primitive(MeshKit.cylinder(r, r, 0.04, 16), Transform3D(Basis(), Vector3(0, y, 0)), IRON, 0.0, 0.03)
	k.add_primitive(MeshKit.cylinder(0.22, 0.22, 0.012, 14), Transform3D(Basis(), Vector3(0, 0.886, 0)), WOOD_DARK, 0.0, 0.03)   # the lid


static func _crate(k: MeshKit, rng: RandomNumberGenerator) -> void:
	_post(k, Vector3(0.66, 0.58, 0.66), Vector3(0, 0.3, 0), WOOD.darkened(0.08))
	for face in 4:
		var b := Basis(Vector3.UP, face * PI * 0.5)
		var out := 0.34
		for y in [0.06, 0.54]:   # rails top and bottom, and the corner stiles
			k.add_primitive(StructureModels._box(Vector3(0.62, 0.08, 0.03)), Transform3D(b, b * Vector3(0, y, out)), _wood(rng, WOOD_DARK), 0.0, 0.03)
		# The brace, corner to corner.
		var brace := Basis(Vector3.BACK, atan2(0.4, 0.5))
		k.add_primitive(StructureModels._box(Vector3(0.64, 0.07, 0.025)), Transform3D(b * brace, b * Vector3(0, 0.3, out + 0.004)), _wood(rng, WOOD_DARK), 0.0, 0.03)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(0.07, 0.62, 0.07), Vector3(sx * 0.33, 0.31, sz * 0.33), WOOD_DARK.darkened(0.08))


static func _flower_pot(k: MeshKit, rng: RandomNumberGenerator) -> void:
	k.loft([Vector3(0, 0.0, 0), Vector3(0, 0.26, 0), Vector3(0, 0.3, 0)], [0.13, 0.18, 0.2], 14, CLAY,
		func(t: float, _a: float) -> Color: return CLAY.darkened(0.08) if t > 0.8 else CLAY, Callable(), true, true)
	k.add_primitive(MeshKit.cylinder(0.17, 0.17, 0.02, 12), Transform3D(Basis(), Vector3(0, 0.29, 0)), Color(0.3, 0.22, 0.16), 0.0, 0.03)   # soil
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var top := Vector3(cos(a) * 0.08, 0.48 + rng.randf_range(-0.05, 0.07), sin(a) * 0.08)
		k.loft([Vector3(cos(a) * 0.03, 0.29, sin(a) * 0.03), top], [0.008, 0.006], 5, Color(0.34, 0.52, 0.28))
		var c: Color = [Color(0.92, 0.42, 0.38), Color(0.96, 0.82, 0.38), Color(0.78, 0.55, 0.85), Color(0.96, 0.96, 0.92)][i % 4]
		k.add_primitive(MeshKit.sphere(0.04, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.2)), top + Vector3(0, 0.015, 0)), c, 0.008, 0.1)
		k.add_primitive(MeshKit.sphere(0.012, 5, 3), Transform3D(Basis(), top + Vector3(0, 0.04, 0)), GOLD, 0.0, 0.05)


static func _banner(k: MeshKit, rng: RandomNumberGenerator) -> void:
	k.loft([Vector3(0, 0, 0), Vector3(0, 2.3, 0)], [0.04, 0.032], 8, WOOD_DARK, Callable(), Callable(), true, true)
	k.loft([Vector3(-0.36, 2.12, 0.05), Vector3(0.36, 2.12, 0.05)], [0.022, 0.022], 6, WOOD_DARK, Callable(), Callable(), true, true)
	# The cloth: a swallow-tailed banner hanging from the crossbar, with a painted sun on it.
	var cloth := PackedVector2Array([Vector2(-0.32, 2.1), Vector2(0.32, 2.1), Vector2(0.32, 1.05), Vector2(0.0, 1.25), Vector2(-0.32, 1.05)])
	k.extrude(cloth, Transform3D(Basis(), Vector3(0, 0, 0.08)), 0.02, 0.0, BLUE, BLUE.darkened(0.2))
	var sun := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		var r := 0.13 if i % 2 == 0 else 0.09
		sun.append(Vector2(cos(a) * r, 1.68 + sin(a) * r))
	k.extrude(sun, Transform3D(Basis(), Vector3(0, 0, 0.093)), 0.006, 0.0, GOLD, GOLD)


static func _brazier(k: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> void:
	var stone: Color = Game.palette.rock if Game.palette else Color(0.55, 0.56, 0.6)
	for i in 3:   # iron legs
		var a := TAU * i / 3.0
		k.loft([Vector3(cos(a) * 0.36, 0.0, sin(a) * 0.36), Vector3(cos(a) * 0.24, 0.6, sin(a) * 0.24)], [0.025, 0.02], 6, IRON)
	# The bowl: a ring of rough stones on an iron dish.
	k.loft([Vector3(0, 0.58, 0), Vector3(0, 0.7, 0)], [0.22, 0.34], 14, IRON.darkened(0.1), Callable(), Callable(), true, true)
	for i in 10:
		var a := TAU * i / 10.0 + rng.randf_range(-0.08, 0.08)
		var s := stone.lightened(rng.randf_range(-0.08, 0.06))
		k.add_primitive(MeshKit.sphere(0.075, 7, 5), Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(0.9, 0.85, 1.25)), Vector3(cos(a) * 0.36, 0.76, sin(a) * 0.36)), s, 0.02, 0.06)
	for i in 9:   # coals
		var p := Vector3(rng.randf_range(-0.17, 0.17), 0.74 + rng.randf_range(0.0, 0.05), rng.randf_range(-0.17, 0.17))
		var r := rng.randf_range(0.04, 0.06)
		if i % 3 == 0:
			k.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), p), Color(0.12, 0.1, 0.09), r * 0.3, 0.1)
		else:
			glow.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), p), EMBER.lightened(rng.randf_range(0.0, 0.2)), r * 0.25, 0.15)


static func _lantern_post(k: MeshKit, glow: MeshKit) -> void:
	StructureModels._board(k, Vector3(0.12, 2.1, 0.12), Transform3D(Basis(), Vector3(0, 1.05, 0)), WOOD_DARK, 0.004)
	k.add_primitive(StructureModels._box(Vector3(0.3, 0.08, 0.3)), Transform3D(Basis(), Vector3(0, 0.04, 0)), WOOD_DARK.darkened(0.15), 0.0, 0.03)   # footing
	# A crook at the top, with the lantern hanging under it on a chain.
	k.loft([Vector3(0, 2.0, 0.02), Vector3(0, 2.12, 0.18), Vector3(0, 2.06, 0.34)], [0.035, 0.03, 0.025], 6, WOOD_DARK)
	k.loft([Vector3(0, 2.04, 0.34), Vector3(0, 1.92, 0.34)], [0.006, 0.006], 4, IRON)
	var c := Vector3(0, 1.78, 0.34)
	k.add_primitive(StructureModels._box(Vector3(0.18, 0.025, 0.18)), Transform3D(Basis(), c + Vector3(0, 0.11, 0)), IRON, 0.0, 0.03)
	k.add_primitive(StructureModels._box(Vector3(0.16, 0.025, 0.16)), Transform3D(Basis(), c - Vector3(0, 0.11, 0)), IRON, 0.0, 0.03)
	k.add_primitive(MeshKit.cylinder(0.0, 0.11, 0.08, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), c + Vector3(0, 0.162, 0)), IRON, 0.0, 0.03)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.add_primitive(StructureModels._box(Vector3(0.018, 0.2, 0.018)), Transform3D(Basis(), c + Vector3(sx * 0.07, 0, sz * 0.07)), IRON, 0.0, 0.02)
	glow.add_primitive(StructureModels._box(Vector3(0.11, 0.17, 0.11)), Transform3D(Basis(), c), Color(1.0, 0.82, 0.5), 0.0, 0.0)


static func _standing_torch(k: MeshKit, glow: MeshKit) -> void:
	k.loft([Vector3(0, 0, 0), Vector3(0.01, 0.8, 0), Vector3(0, 1.4, 0)], [0.04, 0.035, 0.032], 7, WOOD_DARK)
	# The head: rags wrapped round the top, soaked in resin, its middle glowing.
	k.loft([Vector3(0, 1.36, 0), Vector3(0, 1.44, 0), Vector3(0, 1.52, 0)], [0.055, 0.07, 0.06], 9, Color(0.36, 0.26, 0.18),
		func(t: float, a: float) -> Color: return Color(0.42, 0.3, 0.2) if fposmod(a * 2.0 + t * 9.0, 1.0) < 0.5 else Color(0.3, 0.22, 0.15),
		Callable(), true, true)
	glow.add_primitive(MeshKit.sphere(0.05, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), Vector3(0, 1.53, 0)), EMBER, 0.0, 0.05)


# --- Lights on the building: origin on the wall's face (or a ceiling's underside), facing out along +Z -------

## An iron back plate fixed to the wall with two rivets (every wall light starts from one).
static func _wall_plate(k: MeshKit, w: float, h: float, y: float) -> void:
	k.add_primitive(StructureModels._box(Vector3(w, h, 0.02)), Transform3D(Basis(), Vector3(0, y, 0.012)), IRON, 0.0, 0.02)
	for sy in [-1.0, 1.0]:
		k.add_primitive(MeshKit.sphere(0.014, 6, 4), Transform3D(Basis(), Vector3(0, y + sy * (h * 0.5 - 0.03), 0.026)), IRON.lightened(0.25), 0.0, 0.02)


## A lantern: iron top and base, four corner rods, a pyramid cap and a ring, glowing glass between (centred on c).
static func _lantern(k: MeshKit, glow: MeshKit, c: Vector3, s: float) -> void:
	k.add_primitive(StructureModels._box(Vector3(0.18, 0.025, 0.18) * s), Transform3D(Basis(), c + Vector3(0, 0.11 * s, 0)), IRON, 0.0, 0.03)
	k.add_primitive(StructureModels._box(Vector3(0.16, 0.025, 0.16) * s), Transform3D(Basis(), c - Vector3(0, 0.11 * s, 0)), IRON, 0.0, 0.03)
	k.add_primitive(MeshKit.cylinder(0.0, 0.11 * s, 0.08 * s, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), c + Vector3(0, 0.162 * s, 0)), IRON, 0.0, 0.03)
	k.loft([c + Vector3(0, 0.2, -0.018) * s, c + Vector3(0, 0.235, 0) * s, c + Vector3(0, 0.2, 0.018) * s], [0.006, 0.006, 0.006], 4, IRON)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.add_primitive(StructureModels._box(Vector3(0.018, 0.2, 0.018) * s), Transform3D(Basis(), c + Vector3(sx * 0.07, 0, sz * 0.07) * s), IRON, 0.0, 0.02)
	glow.add_primitive(StructureModels._box(Vector3(0.11, 0.17, 0.11) * s), Transform3D(Basis(), c), Color(1.0, 0.82, 0.5), 0.0, 0.0)


## A torch in an iron bracket: a back plate, an arm out to a ring, the torch leaning out through it.
static func _wall_torch(k: MeshKit, glow: MeshKit) -> void:
	_wall_plate(k, 0.09, 0.26, 0.0)
	# The arm: out from the plate and up a little to the ring the torch sits in, and a stay under it.
	k.loft([Vector3(0, 0.04, 0.02), Vector3(0, 0.07, 0.12), Vector3(0, 0.1, 0.19)], [0.012, 0.011, 0.01], 5, IRON)
	k.loft([Vector3(0, -0.09, 0.02), Vector3(0, -0.02, 0.12), Vector3(0, 0.08, 0.19)], [0.009, 0.009, 0.008], 5, IRON)
	# (An open ring, its ends just apart: a loop closed on itself makes edges shared by too many faces.)
	var ring: Array = []
	var rr: Array = []
	for i in 7:
		var a := lerpf(0.35, TAU - 0.35, i / 6.0)
		ring.append(Vector3(sin(a) * 0.035, 0.1, 0.2 - cos(a) * 0.035))
		rr.append(0.008)
	k.loft(ring, rr, 4, IRON.lightened(0.1))
	# The torch: a stick leaning out, a resin-soaked head of wrapped rags, its middle glowing.
	var lean := Vector3(0, 1.0, 0.28).normalized()
	var foot := Vector3(0, 0.1, 0.2) - lean * 0.2
	k.loft([foot, foot + lean * 0.25, foot + lean * 0.42], [0.024, 0.022, 0.02], 7, WOOD_DARK)
	var h0 := foot + lean * 0.4
	k.loft([h0, h0 + lean * 0.07, h0 + lean * 0.14], [0.038, 0.048, 0.04], 9, Color(0.36, 0.26, 0.18),
		func(t: float, a: float) -> Color: return Color(0.42, 0.3, 0.2) if fposmod(a * 2.0 + t * 9.0, 1.0) < 0.5 else Color(0.3, 0.22, 0.15),
		Callable(), true, true)
	glow.add_primitive(MeshKit.sphere(0.034, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), h0 + lean * 0.15), EMBER, 0.0, 0.05)


## A lantern on a hook: a back plate, a curled iron arm out over it, the lantern hanging from its end.
static func _wall_lantern(k: MeshKit, glow: MeshKit) -> void:
	_wall_plate(k, 0.08, 0.24, 0.16)
	k.loft([Vector3(0, 0.2, 0.02), Vector3(0, 0.26, 0.12), Vector3(0, 0.25, 0.24), Vector3(0, 0.21, 0.3)], [0.012, 0.011, 0.01, 0.009], 6, IRON)
	k.loft([Vector3(0, 0.08, 0.02), Vector3(0, 0.14, 0.12), Vector3(0, 0.24, 0.2)], [0.008, 0.008, 0.008], 5, IRON)   # its stay
	k.loft([Vector3(0, 0.2, 0.3), Vector3(0, 0.14, 0.3)], [0.005, 0.005], 4, IRON)   # the short chain
	_lantern(k, glow, Vector3(0, -0.06, 0.3), 1.0)


## A candle sconce: a backboard, a little shelf on a bracket, three candles of different heights burning on it.
static func _candle_sconce(k: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> void:
	_post(k, Vector3(0.36, 0.34, 0.022), Vector3(0, 0.1, 0.012), _wood(rng, WOOD_DARK))
	_post(k, Vector3(0.38, 0.03, 0.14), Vector3(0, -0.005, 0.085), _wood(rng))
	k.loft([Vector3(0, -0.12, 0.026), Vector3(0, -0.06, 0.08), Vector3(0, -0.025, 0.13)], [0.012, 0.011, 0.01], 5, WOOD_DARK)   # bracket
	for i in 3:
		var x := (i - 1) * 0.1 + rng.randf_range(-0.01, 0.01)
		var h := [0.13, 0.19, 0.1][i] as float
		var at := Vector3(x, 0.011, 0.09 + rng.randf_range(-0.01, 0.01))
		k.add_primitive(MeshKit.cylinder(0.03, 0.038, 0.012, 8), Transform3D(Basis(), at + Vector3(0, 0.006, 0)), IRON.lightened(0.15), 0.0, 0.02)   # dish
		k.add_primitive(MeshKit.cylinder(0.024, 0.026, h, 8), Transform3D(Basis(), at + Vector3(0, 0.012 + h * 0.5, 0)), Color(0.93, 0.88, 0.74), 0.0, 0.02)
		# Drips of wax down its side, and the wick's glow.
		k.add_primitive(MeshKit.sphere(0.009, 5, 3), Transform3D(Basis.from_scale(Vector3(1.0, 2.2, 1.0)), at + Vector3(0.022, h * 0.7, 0.006)), Color(0.95, 0.91, 0.78), 0.0, 0.01)
		# The flame itself, a bright teardrop over the wick (an additive flame alone washes out on a lit wall).
		k.add_primitive(MeshKit.cylinder(0.0015, 0.0015, 0.012, 4), Transform3D(Basis(), at + Vector3(0, 0.018 + h, 0)), Color(0.15, 0.12, 0.1), 0.0, 0.0)
		glow.add_primitive(MeshKit.sphere(0.015, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 2.4, 1.0)), at + Vector3(0, 0.05 + h, 0)), Color(1.0, 0.8, 0.4), 0.0, 0.0)


## A lantern hanging on a chain from a ceiling: a ring fixed to the underside, the chain, the lantern below.
static func _hanging_lantern(k: MeshKit, glow: MeshKit) -> void:
	k.add_primitive(MeshKit.cylinder(0.07, 0.07, 0.04, 10), Transform3D(Basis(), Vector3(0, 0.0, 0)), IRON, 0.0, 0.02)
	for i in 8:   # the chain: links turned alternately
		var y := -0.04 - i * 0.07
		var b := Basis(Vector3.UP, PI * 0.5 * (i % 2))
		var link: Array = []
		var lr: Array = []
		for j in 7:   # an open oval (see the torch's ring)
			var a := lerpf(0.4, TAU - 0.4, j / 6.0)
			link.append(b * Vector3(sin(a) * 0.018, 0, 0) + Vector3(0, y - 0.03 + cos(a) * 0.03, 0))
			lr.append(0.005)
		k.loft(link, lr, 4, IRON)
	_lantern(k, glow, Vector3(0, -0.78, 0), 1.25)


## A chest: a box of planks between corner posts, standing on a plinth and four little feet, with a rim round its
## top; a rounded lid of planks closed at both ends by arched end boards; iron corner brackets, straps over the lid
## and down the front and back, hinges behind, a ring handle at each end and a padlock on a hasp in front. The large
## one is bigger, of darker wood, and bound in iron: more straps, studded, with iron bands round its rim and plinth.
static func _chest(k: MeshKit, rng: RandomNumberGenerator, large: bool) -> void:
	var w := 1.16 if large else 0.92    # across (x)
	var d := 0.68 if large else 0.58    # deep (z; it faces +z)
	var h := 0.48 if large else 0.4     # the box's top
	var rise := 0.23 if large else 0.19 # the lid's
	var wood := WOOD.darkened(0.12) if large else WOOD.lightened(0.02)
	var frame := wood.darkened(0.28)
	var iron := Color(0.23, 0.23, 0.25)
	var rivet := iron.lightened(0.35)
	var brass := GOLD.darkened(0.2)
	var foot := 0.035
	var hx := w * 0.5
	var hz := d * 0.5
	# Feet, and the dark core inside the planks (so the gaps between them show shadow, not daylight).
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(0.075, foot + 0.004, 0.075), Vector3(sx * (hx - 0.045), (foot + 0.004) * 0.5, sz * (hz - 0.045)), frame.darkened(0.1))
	_post(k, Vector3(w - 0.07, h - foot - 0.03, d - 0.07), Vector3(0, foot + (h - foot - 0.03) * 0.5 + 0.004, 0), Color(0.12, 0.09, 0.06))
	# The plinth: a band of boards round the foot, a little proud.
	var pl := 0.065
	for sz in [-1.0, 1.0]:
		_post(k, Vector3(w + 0.022, pl, 0.03), Vector3(0, foot + pl * 0.5, sz * (hz + 0.003)), frame)
	for sx in [-1.0, 1.0]:
		_post(k, Vector3(0.03, pl - 0.004, d - 0.026), Vector3(sx * (hx + 0.003), foot + pl * 0.5, 0), frame)
	# Corner posts.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(0.07, h - foot - pl - 0.004, 0.07), Vector3(sx * (hx - 0.03), foot + pl + (h - foot - pl) * 0.5, sz * (hz - 0.03)), frame.lightened(0.05))
	# Plank panels between the posts: three boards a side, each a shade different, with a hair of gap between.
	var y0 := foot + pl + 0.004
	var span := h - 0.045 - y0
	for i in 3:
		var bh := span / 3.0 - 0.008
		var y := y0 + span * (i + 0.5) / 3.0
		for sz in [-1.0, 1.0]:
			StructureModels._board(k, Vector3(w - 0.13, bh, 0.032), Transform3D(Basis(), Vector3(0, y, sz * (hz - 0.022))), _wood(rng, wood), 0.004)
		for sx in [-1.0, 1.0]:
			StructureModels._board(k, Vector3(d - 0.13, bh, 0.032), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx * (hx - 0.022), y, 0)), _wood(rng, wood), 0.004)
	# The rim round the box's top, where the lid comes down on it.
	for sz in [-1.0, 1.0]:
		_post(k, Vector3(w + 0.012, 0.045, 0.032), Vector3(0, h - 0.0225, sz * (hz - 0.006)), frame.lightened(0.08))
	for sx in [-1.0, 1.0]:
		_post(k, Vector3(0.032, 0.041, d - 0.05), Vector3(sx * (hx - 0.006), h - 0.0225, 0), frame.lightened(0.08))
	# The lid: planks along its length round a half-round arch, closed at each end by an arched board.
	var lz := hz + 0.012
	var arc: Array = []
	for i in 9:
		var a := PI * i / 8.0
		arc.append(Vector2(cos(a) * lz, sin(a) * rise))
	var base := h + 0.006
	for i in 8:
		var p0: Vector2 = arc[i]
		var p1: Vector2 = arc[i + 1]
		var mid := (p0 + p1) * 0.5
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		var nrm := Vector2(sin(ang), -cos(ang))   # out from the lid
		var at := mid - nrm * 0.016
		StructureModels._board(k, Vector3(w - 0.07, p0.distance_to(p1) + 0.006, 0.034),
			Transform3D(Basis(Vector3.RIGHT, -ang) * FLAT, Vector3(0, base + at.y, at.x)), _wood(rng, wood.lightened(0.05)), 0.003)
	var cap := PackedVector2Array()
	for i in 13:
		var a := PI * i / 12.0
		cap.append(Vector2(cos(a) * (lz + 0.006), sin(a) * (rise + 0.006)))
	var end_basis := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))
	for sx in [-1.0, 1.0]:
		k.extrude(cap, Transform3D(end_basis, Vector3(sx * (hx - 0.03), base, 0)), 0.05, 0.01, frame, frame.lightened(0.1))
	# Iron straps over the lid, down the front and the back.
	var straps: Array = [-0.34, 0.34] if not large else [-0.4, -0.13, 0.13, 0.4]
	for f: float in straps:
		var x := f * w
		for i in 8:
			var p0: Vector2 = arc[i]
			var p1: Vector2 = arc[i + 1]
			var mid := (p0 + p1) * 0.5
			var ang := atan2(p1.y - p0.y, p1.x - p0.x)
			var nrm := Vector2(sin(ang), -cos(ang))   # out from the lid
			var at := mid + nrm * 0.008
			k.add_primitive(StructureModels._box(Vector3(0.055, 0.01, p0.distance_to(p1) + 0.012)),
				Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(x, base + at.y, at.x)), iron, 0.0, 0.03)
			if large or i % 2 == 1:
				var r := mid + nrm * 0.014
				k.add_primitive(MeshKit.sphere(0.011, 6, 4), Transform3D(Basis(), Vector3(x, base + r.y, r.x)), rivet, 0.0, 0.02)
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(0.055, h - foot - pl - 0.01, 0.01), Vector3(x, foot + pl + (h - foot - pl) * 0.5, sz * (hz + 0.003)), iron)
			for j in (3 if large else 2):
				var ry := foot + pl + 0.05 + j * (h - foot - pl - 0.1) / (2.0 if large else 1.0)
				k.add_primitive(MeshKit.sphere(0.011, 6, 4), Transform3D(Basis(), Vector3(x, ry, sz * (hz + 0.011))), rivet, 0.0, 0.02)
	# Iron corner brackets, top and bottom: an L of plate round each upright corner.
	var bs := 0.1 if large else 0.08
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for cy: float in [foot + pl + 0.05, h - 0.075]:
				_post(k, Vector3(bs, bs, 0.01), Vector3(sx * (hx - bs * 0.5 + 0.004), cy, sz * (hz + 0.006)), iron)
				_post(k, Vector3(0.01, bs - 0.004, bs), Vector3(sx * (hx + 0.006), cy, sz * (hz - bs * 0.5 + 0.004)), iron)
	# The large one: iron bands round its rim and its plinth, and studs along the rim.
	if large:
		for y: float in [h - 0.0225, foot + pl * 0.5]:
			for sz in [-1.0, 1.0]:
				_post(k, Vector3(w + 0.03, 0.03, 0.01), Vector3(0, y, sz * (hz + 0.012)), iron)
			for sx in [-1.0, 1.0]:
				_post(k, Vector3(0.01, 0.026, d + 0.004), Vector3(sx * (hx + 0.012), y, 0), iron)
		for i in 9:
			var x := lerpf(-hx + 0.08, hx - 0.08, i / 8.0)
			for sz in [-1.0, 1.0]:
				k.add_primitive(MeshKit.sphere(0.01, 6, 4), Transform3D(Basis(), Vector3(x, h - 0.0225, sz * (hz + 0.02))), rivet, 0.0, 0.02)
	# Hinges behind: a plate down from the lid's back edge onto the box, round a pin.
	for f in [-0.22, 0.22]:
		_post(k, Vector3(0.06, 0.13, 0.01), Vector3(f * w, h - 0.02, -(lz + 0.008)), iron)
		k.loft([Vector3(f * w - 0.035, h + 0.006, -(lz + 0.012)), Vector3(f * w + 0.035, h + 0.006, -(lz + 0.012))], [0.012, 0.012], 6, iron.lightened(0.1))
	# A ring handle at each end, on a plate.
	var hy := h * 0.62
	for sx in [-1.0, 1.0]:
		_post(k, Vector3(0.01, 0.07, 0.15), Vector3(sx * (hx + 0.012), hy, 0), iron)
		var path: Array = []
		var radii: Array = []
		for i in 9:
			var a := PI * i / 8.0
			path.append(Vector3(sx * (hx + 0.03), hy - 0.012 - sin(a) * 0.055, -cos(a) * 0.065))
			radii.append(0.009)
		k.loft(path, radii, 6, iron.lightened(0.15))
	# The hasp down from the lid over the rim, and a padlock hung through it.
	_post(k, Vector3(0.075, 0.12, 0.012), Vector3(0, h + 0.006, lz + 0.01), iron.lightened(0.05))
	var lock_y := h - 0.09
	k.add_primitive(StructureModels._box(Vector3(0.085, 0.075, 0.032)), Transform3D(Basis(), Vector3(0, lock_y, lz + 0.034)), brass, 0.0, 0.04)
	var shackle: Array = []
	var sr: Array = []
	for i in 9:
		var a := PI * i / 8.0
		shackle.append(Vector3(cos(a) * 0.026, lock_y + 0.036 + sin(a) * 0.035, lz + 0.034))
		sr.append(0.006)
	k.loft(shackle, sr, 6, iron.lightened(0.25))
	k.add_primitive(MeshKit.cylinder(0.008, 0.008, 0.006, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, lock_y - 0.008, lz + 0.052)), Color(0.08, 0.06, 0.04), 0.0, 0.0)
