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
	k.loft([Vector3(-0.035, 0.1, 0.2), Vector3(0, 0.1, 0.235), Vector3(0.035, 0.1, 0.2), Vector3(0, 0.1, 0.165), Vector3(-0.035, 0.1, 0.2)],
		[0.008, 0.008, 0.008, 0.008, 0.008], 4, IRON.lightened(0.1))
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
		k.loft([Vector3(0, y, 0), b * Vector3(0.018, y - 0.03, 0) + Vector3(0, 0, 0), Vector3(0, y - 0.06, 0), b * Vector3(-0.018, y - 0.03, 0), Vector3(0, y, 0)],
			[0.005, 0.005, 0.005, 0.005, 0.005], 4, IRON)
	_lantern(k, glow, Vector3(0, -0.78, 0), 1.25)


## A chest: planks on a frame, iron straps over it, a lock plate; the large one is longer and taller, iron-bound,
## with studs along its straps.
static func _chest(k: MeshKit, rng: RandomNumberGenerator, large: bool) -> void:
	var w := 1.15 if large else 0.9
	var d := 0.66 if large else 0.56
	var h := 0.5 if large else 0.42
	var lid := 0.22 if large else 0.18
	var wood := WOOD.darkened(0.05) if large else WOOD
	for i in 3:   # the box's planks, front and back, each a shade different
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(w, h / 3.0 - 0.01, 0.05), Vector3(0, h / 6.0 + i * h / 3.0 + 0.005, sz * (d * 0.5 - 0.025)), _wood(rng, wood))
	for sx in [-1.0, 1.0]:
		_post(k, Vector3(0.05, h - 0.004, d - 0.1), Vector3(sx * (w * 0.5 - 0.025), h * 0.5, 0), _wood(rng, wood))
	_post(k, Vector3(w - 0.1, 0.04, d - 0.1), Vector3(0, 0.03, 0), wood.darkened(0.1))   # bottom
	# The lid: a rounded top (a half cylinder of planks along the length).
	var arc: Array = []
	for i in 7:
		var a := PI * i / 6.0
		arc.append(Vector2(cos(a) * d * 0.5, sin(a) * lid))
	for i in 6:
		var p0: Vector2 = arc[i]
		var p1: Vector2 = arc[i + 1]
		var mid := (p0 + p1) * 0.5
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		k.add_primitive(StructureModels._box(Vector3(w + 0.02, 0.035, p0.distance_to(p1) - 0.004)),
			Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(0, h + 0.012 + mid.y, mid.x)), _wood(rng, wood.lightened(0.04)), 0.0, 0.03)
	# Iron straps over the lid and down the front and back.
	var straps := [-0.3, 0.3] if not large else [-0.42, -0.14, 0.14, 0.42]
	for sx: float in straps:
		var x := sx * w / (0.9 if not large else 1.15)
		for i in 6:
			var p0: Vector2 = arc[i]
			var p1: Vector2 = arc[i + 1]
			var mid := (p0 + p1) * 0.5
			var ang := atan2(p1.y - p0.y, p1.x - p0.x)
			var nrm := Vector2(-sin(ang), cos(ang)) * 0.02
			k.add_primitive(StructureModels._box(Vector3(0.06, 0.012, p0.distance_to(p1) + 0.01)),
				Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(x, h + 0.012 + mid.y + nrm.y, mid.x + nrm.x)), IRON, 0.0, 0.03)
		for sz in [-1.0, 1.0]:
			_post(k, Vector3(0.06, h - 0.02, 0.012), Vector3(x, h * 0.5, sz * (d * 0.5 + 0.007)), IRON)
			if large:
				for j in 3:
					k.add_primitive(MeshKit.sphere(0.014, 6, 4), Transform3D(Basis(), Vector3(x, 0.1 + j * (h - 0.2) / 2.0, sz * (d * 0.5 + 0.016))), IRON.lightened(0.3), 0.0, 0.02)
	# The lock plate and its hasp.
	_post(k, Vector3(0.12, 0.14, 0.014), Vector3(0, h - 0.06, d * 0.5 + 0.012), GOLD.darkened(0.15))
	k.add_primitive(MeshKit.sphere(0.018, 6, 4), Transform3D(Basis(), Vector3(0, h - 0.07, d * 0.5 + 0.022)), Color(0.12, 0.1, 0.08), 0.0, 0.02)
